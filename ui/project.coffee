# writer/ui/project.coffee — project plugin for the library ui_server.
#
# Loaded by pipeline/ui_server.coffee when a project ships this file
# at `${CWD}/ui/project.coffee`. Carries the writer-specific routes:
#   - /api/create_pipe
#   - /api/storacle_observation(s)
#   - /api/panel/* (with writer's listFiles helper injection)
#   - /pipe/<name> deep-link that puppeteer's peer_pipes panel uses
#
# Thin plugin — no SSH divergence, no sticky-pipe chdir. Writer binds
# the canonical port 4311.

fs   = require 'fs'
path = require 'path'

init = (ctx) ->
  {CWD, EXEC_ROOT, BASE_ROOT, sendJson, readRequestBody, readJson, readText, writeText, listFiles, describeOutputFile, normalizeUiRun} = ctx
  {DatabaseSync} = require 'node:sqlite'
  {spawn} = require 'child_process'

  PIPES_ROOT = path.join(BASE_ROOT, 'pipes')
  # Must come from ctx — the library binds to argv[2]='net' but doesn't
  # export process.env.UI_BIND_MODE, so reading the env directly here
  # returns 'local' and the respawn would silently drop to 127.0.0.1.
  UI_BIND_MODE = String(ctx.UI_BIND_MODE ? process.env.UI_BIND_MODE ? 'local')

  # ── /pipe/<name> and /?pipe=<name> deep links ───────────────
  # Puppeteer's peer_pipes panel links to writer pipes via these URLs.
  # Returns a "switching..." HTML page that reloads to `/` after 3s,
  # while the server respawns in the target pipe's CWD.
  handleDeepLinkPipe = (req, res) ->
    url = req.url ? ''
    pipeName = null
    if url.startsWith '/pipe/'
      pipeName = decodeURIComponent(url.slice('/pipe/'.length).split('?')[0].split('#')[0])
    else if url.startsWith '/?pipe='
      pipeName = decodeURIComponent(url.slice('/?pipe='.length).split('&')[0].split('#')[0])
    return sendBadDeepLink(res, 'no pipe in URL') unless pipeName?
    pipeName = String(pipeName).trim()
    if not pipeName.length or pipeName.includes('/') or pipeName.includes(path.sep) or pipeName in ['.', '..']
      return sendBadDeepLink(res, "bad pipe name: #{pipeName}")
    targetCwd = path.join(PIPES_ROOT, pipeName)
    unless fs.existsSync(targetCwd) and fs.statSync(targetCwd).isDirectory()
      res.writeHead 404, {'Content-Type': 'text/html; charset=utf-8'}
      return res.end "<h3>pipe not found: <code>#{pipeName}</code></h3><p><a href='/'>home</a></p>"

    # Send the "switching..." HTML now, then respawn.
    html = """
      <!doctype html><meta charset="utf-8">
      <title>switching to #{pipeName}…</title>
      <meta http-equiv="refresh" content="3;url=/">
      <style>body{font-family:-apple-system,sans-serif;padding:40px;color:#333}</style>
      <h3>Switching workspace to <code>#{pipeName}</code>…</h3>
      <p>UI is respawning. This page reloads in ~3 seconds.</p>
      <p><a href="/">Go now</a></p>
    """
    res.writeHead 200, {'Content-Type': 'text/html; charset=utf-8'}
    res.end html

    # Respawn the same ui_server entry at the target CWD. Mirrors the
    # library's handleSwitchPipe (coffee <main> net, sleep 1 in a bash
    # wrapper so the port window closes cleanly, UI_PORT propagated).
    fs.mkdirSync path.join(targetCwd, 'state'), { recursive: true }
    fs.mkdirSync path.join(targetCwd, 'logs'),  { recursive: true }
    uiServerPath =
      if typeof require.main?.filename is 'string' and require.main.filename.length
        require.main.filename
      else
        path.join(EXEC_ROOT, 'ui_server.coffee')
    port    = Number(process.env.UI_PORT ? module.exports.portDefault)
    netArg  = if UI_BIND_MODE is 'net' then ' net' else ''
    launchArgs = ['-lc', "sleep 1 && exec coffee #{JSON.stringify(uiServerPath)}#{netArg}"]
    child = spawn 'bash', launchArgs,
      cwd:      targetCwd
      detached: true
      stdio:    'ignore'
      env: Object.assign {}, process.env,
        EXEC:         EXEC_ROOT
        CWD:          targetCwd
        UI_PORT:      String(port)
        UI_BIND_MODE: UI_BIND_MODE
    child.unref()
    setTimeout((-> process.exit(0)), 150)

  sendBadDeepLink = (res, msg) ->
    res.writeHead 400, {'Content-Type': 'text/html; charset=utf-8'}
    res.end "<h3>#{msg}</h3><p><a href='/'>home</a></p>"

  # ── /api/create_pipe (POST) ─────────────────────────────────
  # Scaffolds pipes/<name>/ with override.yaml, state/, logs/, out/,
  # and a recipe-scoped human override under override/<pipeline>.yaml.
  handleCreatePipe = (req, res) ->
    bodyText = await readRequestBody req
    payload = {}
    try payload = JSON.parse(bodyText ? '{}') catch
      return sendJson res, 400, { ok: false, error: 'invalid json body' }

    name  = String(payload.name ? '').trim()
    model = String(payload.model ? '').trim()
    pipelineName = String(payload.pipeline ? 'reset').trim() or 'reset'

    return sendJson(res, 400, { ok: false, error: 'name required' }) unless name.length
    return sendJson(res, 400, { ok: false, error: 'model (HuggingFace org/name) required' }) unless model.length
    return sendJson(res, 400, { ok: false, error: 'invalid name: use letters, digits, _, -, . only' }) unless /^[A-Za-z0-9._-]+$/.test(name)
    return sendJson(res, 400, { ok: false, error: 'invalid name' }) if name in ['.', '..']
    return sendJson(res, 400, { ok: false, error: 'invalid pipeline name' }) unless /^[A-Za-z0-9._-]+$/.test(pipelineName)

    pipeDir = path.join(PIPES_ROOT, name)
    return sendJson(res, 409, { ok: false, error: "pipes/#{name} already exists" }) if fs.existsSync(pipeDir)

    try
      fs.mkdirSync pipeDir, { recursive: true }
      for sub in ['state', 'logs', 'out']
        fs.mkdirSync path.join(pipeDir, sub), { recursive: true }

      modelsRoot = process.env.MODELS ? path.join(process.env.HOME, 'models')
      baseModelPath      = path.join(modelsRoot, model)
      quantizedModelPath = path.join(modelsRoot, "#{model}-mlx4")
      overrideText = """
        # pipes/#{name}/override.yaml — created by /api/create_pipe
        # Pipeline selector + pipe foundation (identity + model paths).
        # See writer/MORNING.md for the recipe/foundation contract.
        pipeline: #{pipelineName}

        run:
          model:         #{model}
          loraLand:      #{baseModelPath}
          quantized_dir: #{quantizedModelPath}
      """
      fs.writeFileSync path.join(pipeDir, 'override.yaml'), overrideText + '\n', 'utf8'

      humanOverrideDir  = path.join(pipeDir, 'override')
      humanOverridePath = path.join(humanOverrideDir, "#{pipelineName}.yaml")
      humanOverrideText = """
        # pipes/#{name}/override/#{pipelineName}.yaml — created by /api/create_pipe
        # Recipe-scoped human override (higher precedence than legacy
        # override.yaml). run.model duplicated here on purpose so the UI
        # shows model identity in the Human Override panel.
        pipeline: #{pipelineName}

        run:
          model: #{model}
      """
      fs.mkdirSync humanOverrideDir, { recursive: true }
      fs.writeFileSync humanOverridePath, humanOverrideText + '\n', 'utf8'

      readmeText = """
        # #{name}

        Created via the UI on #{new Date().toISOString()}.

        - **Base model**: `#{model}`
        - **Starting recipe**: `#{pipelineName}`

        Launch: switch the UI to this pipe from the "Switch UI To Pipe"
        dropdown and press "Write Override And Run", or from a shell:
        `cd pipes/#{name} && npx pipeline`.
      """
      fs.writeFileSync path.join(pipeDir, 'README.md'), readmeText + '\n', 'utf8'
    catch err
      return sendJson res, 500, { ok: false, error: "scaffold failed: #{err?.message ? err}" }

    sendJson res, 200,
      ok:           true
      name:         name
      cwd:          pipeDir
      cwd_relative: path.relative(BASE_ROOT, pipeDir)
      pipeline:     pipelineName
      model:        model

  # ── Storacle observations (sqlite table lives on per-pipe runtime.sqlite) ──
  ensureStoracleObservationsTable = (db) ->
    db.exec """
      CREATE TABLE IF NOT EXISTS storacle_observations (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        observed_at       TEXT NOT NULL,
        updated_at        TEXT NOT NULL,
        storacle_logdir   TEXT,
        adapter_path      TEXT,
        lora_run_id       TEXT,
        adapter_mtime     TEXT,
        story_id          TEXT,
        prompt_text       TEXT,
        think_prefill     TEXT,
        use_kag           INTEGER,
        use_chunks        INTEGER,
        rag_top_k         INTEGER,
        llm_config_json   TEXT,
        generated_text    TEXT,
        notes             TEXT,
        noted_by          TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_storacle_observations_observed_at
        ON storacle_observations (observed_at);
    """

  handleStoracleObservationsList = (req, res) ->
    dbPath = path.join CWD, 'runtime.sqlite'
    return sendJson(res, 200, { ok: true, observations: [] }) unless fs.existsSync(dbPath)
    db = null
    try
      db = new DatabaseSync dbPath
      ensureStoracleObservationsTable db
      rows = db.prepare("""
        SELECT id, observed_at, updated_at, storacle_logdir,
               adapter_path, lora_run_id, adapter_mtime, story_id,
               prompt_text, think_prefill, use_kag, use_chunks,
               rag_top_k, llm_config_json, generated_text, notes,
               noted_by
        FROM storacle_observations
        ORDER BY observed_at DESC
      """).all()
      observations = rows.map (row) ->
        llmConfig = null
        try llmConfig = JSON.parse(row.llm_config_json ? 'null') catch then null
        id:              row.id
        observed_at:     row.observed_at
        updated_at:      row.updated_at
        storacle_logdir: row.storacle_logdir
        adapter_path:    row.adapter_path
        lora_run_id:     row.lora_run_id
        adapter_mtime:   row.adapter_mtime
        story_id:        row.story_id
        prompt_text:     row.prompt_text
        think_prefill:   row.think_prefill
        use_kag:         row.use_kag is 1
        use_chunks:      row.use_chunks is 1
        rag_top_k:       row.rag_top_k
        llm_config:      llmConfig
        generated_text:  row.generated_text
        notes:           row.notes
        noted_by:        row.noted_by
      sendJson res, 200, { ok: true, observations: observations }
    catch err
      sendJson res, 500, { ok: false, error: String(err?.message ? err) }
    finally
      try db?.close() catch then null

  handleStoracleObservationUpsert = (req, res) ->
    bodyText = await readRequestBody req
    payload = try JSON.parse(bodyText) catch then {}
    dbPath = path.join CWD, 'runtime.sqlite'
    return sendJson(res, 400, { ok: false, error: 'runtime.sqlite missing on this pipe' }) unless fs.existsSync(dbPath)
    db = null
    try
      db = new DatabaseSync dbPath
      ensureStoracleObservationsTable db

      # UPDATE branch
      if payload.id?
        id = Number(payload.id)
        return sendJson(res, 400, { ok: false, error: 'invalid id' }) unless Number.isFinite(id) and id > 0
        now = new Date().toISOString()
        info = db.prepare("""
          UPDATE storacle_observations
          SET notes = ?, noted_by = ?, updated_at = ?
          WHERE id = ?
        """).run(
          String(payload.notes ? '')
          payload.noted_by ? null
          now
          id
        )
        return sendJson res, 200, { ok: true, id: id, changes: info.changes, updated_at: now }

      # CREATE branch — read provenance from out/
      outDir   = path.join CWD, 'out'
      metaPath = path.join outDir, 'storacle_meta.json'
      textPath = path.join outDir, 'storacle.txt'
      return sendJson(res, 400, { ok: false, error: 'no storacle_meta.json in out/ — run storacle first' }) unless fs.existsSync(metaPath)
      meta = null
      try meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'))
      return sendJson(res, 400, { ok: false, error: 'storacle_meta.json unreadable' }) unless meta? and typeof meta is 'object'
      generatedText = try fs.readFileSync(textPath, 'utf8') catch then ''

      adapterPath  = meta.adapter_path ? ''
      adapterMtime = null
      loraRunId    = null
      if adapterPath and typeof adapterPath is 'string' and adapterPath.length
        adapterAbs = path.join(CWD, adapterPath, 'adapters.safetensors')
        if fs.existsSync(adapterAbs)
          try adapterMtime = fs.statSync(adapterAbs).mtime.toISOString()
          try
            row = db.prepare("""
              SELECT run_id FROM lora_training_runs
              WHERE adapter_path = ? AND status = 'done'
                AND (finished_at IS NULL OR finished_at <= ?)
              ORDER BY finished_at DESC LIMIT 1
            """).get(adapterPath, adapterMtime ? new Date().toISOString())
            loraRunId = row?.run_id ? null

      llmConfig = meta.llm_config ? {}
      llmConfigJson = try JSON.stringify(llmConfig) catch then '{}'

      now = new Date().toISOString()
      info = db.prepare("""
        INSERT INTO storacle_observations
          (observed_at, updated_at, storacle_logdir, adapter_path,
           lora_run_id, adapter_mtime, story_id, prompt_text,
           think_prefill, use_kag, use_chunks, rag_top_k,
           llm_config_json, generated_text, notes, noted_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """).run(
        now
        now
        payload.storacle_logdir ? null
        adapterPath ? null
        loraRunId
        adapterMtime
        meta.story_id ? null
        meta.template_text ? null
        llmConfig?.think_prefill ? null
        (if meta.use_kag then 1 else 0)
        (if meta.use_chunks then 1 else 0)
        meta.rag_top_k ? null
        llmConfigJson
        generatedText
        ''
        payload.noted_by ? null
      )
      sendJson res, 200, { ok: true, id: Number(info.lastInsertRowid), observed_at: now }
    catch err
      sendJson res, 500, { ok: false, error: String(err?.message ? err) }
    finally
      try db?.close() catch then null

  # ── /api/panel/* — writer panel loader ─────────────────────
  # Writer panels (steps, log_files, pipeline_death from the library)
  # expect `listFiles` and `describeOutputFile` helpers; thread them
  # from ctx so the library panel index gets what it needs.
  panelRegistry = null
  initPanelRegistry = ->
    return panelRegistry if panelRegistry?
    try
      {load} = require path.join(EXEC_ROOT, 'panels')
      panelRegistry = load
        CWD:  CWD
        BASE: BASE_ROOT
        EXEC: EXEC_ROOT
        helpers:
          listFiles:          listFiles
          describeOutputFile: describeOutputFile
          readJson:           readJson
          readText:           readText
      console.log "[writer-panels] registered #{panelRegistry.list().length} panel(s)"
    catch err
      console.error "[writer-panels] registry init failed: #{String(err?.message ? err)}"
      panelRegistry =
        list: -> []
        get:  -> null
        data: -> null
        eager: -> {}
        resolution: -> []
    panelRegistry

  handlePanel = (req, res) ->
    url  = req.url ? ''
    name = decodeURIComponent url.slice('/api/panel/'.length).split('?')[0]
    runPath = path.join(CWD, 'state', 'ui-run.json')
    run = normalizeUiRun(readJson(runPath, {}))
    data = await initPanelRegistry().data(name, {run: run})
    if data is null
      return sendJson res, 404, { ok: false, error: "panel not found or endpoint failed: #{name}" }
    sendJson res, 200, { ok: true, name: name, data: data }

  # Eager panel snapshot — writer's panels (steps, log_files,
  # pipeline_death from the library) populate /api/status.panels_data
  # just like puppeteer's.
  augmentStatus = (status) ->
    registry = initPanelRegistry()
    status.panels = registry.list()
    try
      status.panels_data = await registry.eager {run: status.run}
    catch err
      console.error "[writer-project] eager panels failed: #{err?.message ? err}"
      status.panels_data = {}
    return

  routes: [
    {method: 'POST', path: '/api/create_pipe',             handler: handleCreatePipe}
    {method: 'GET',  path: '/api/storacle_observations',   handler: handleStoracleObservationsList}
    {method: 'POST', path: '/api/storacle_observation',    handler: handleStoracleObservationUpsert}
    {method: 'GET',  pathPrefix: '/api/panel/',            handler: handlePanel}
    # Deep-link /pipe/<name> — puppeteer's peer_pipes panel links to
    # writer pipes via this URL. Must match before the library's
    # catch-all so the HTML switcher page is served.
    {method: 'GET',  pathPrefix: '/pipe/',                  handler: handleDeepLinkPipe}
  ]
  augmentStatus: augmentStatus

module.exports =
  # No preStartup — writer has no sticky-pipe chdir.
  portDefault: 4311
  init:        init
