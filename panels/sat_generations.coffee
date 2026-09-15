###
  panels/sat_generations.coffee — writer's SAT Generations panel
  ==============================================================

  Shows the text outputs of ~/writer/bin/run_sat.sh: one file per
  (config, prompt) combination, organized by timestamped run dir.

  A pipe is `applies` for this panel iff it has a `sat/` subdir with
  at least one .txt file. Newborn pipes see a single file per run
  (baseline __ A_retell); elementary pipes see up to 8 (baseline / kag /
  adapter / adapter_chunks × B / D).

  File layout on disk:
    <CWD>/sat/YYYY-MM-DD_HH_MM/<config>__<prompt>.txt

  Filename encodes the (config, prompt) pair — the client renderer
  splits on `__` to display side-by-side.

  Kept small so the panel refresh is cheap. Only reads the first
  MAX_PREVIEW_BYTES of each file (the model's `maxTokens` cap tops
  out around 800 chars in practice; a 4 KB cap is plenty).
###

MAX_PREVIEW_BYTES = 8192  # 4× typical output, leaves headroom for future
MAX_RUNS_SHOWN    = 8     # newest N — older runs stay on disk but not in UI

exports.panel =
  title:        'SAT Generations'
  render_hint:  'custom'   # sat_generations client-side renderer below
  column:       'after-outputs'
  # 2026-09-14 rev: eager so /api/status pre-fetches the data and the
  # client's custom renderer receives it on every refresh. Lazy panels
  # need their hooks to fetch their own data; keeping it eager here
  # since the payload is bounded (max ~8 runs × ~8 files, few KB each).
  eager:        true
  poll_seconds: 30

  applies: (ctx) ->
    satDir = ctx.path.join(ctx.CWD, 'sat')
    return false unless ctx.fs.existsSync(satDir)
    # Only show if there's at least one run dir with at least one .txt
    try
      for entry in ctx.fs.readdirSync(satDir)
        runPath = ctx.path.join(satDir, entry)
        continue unless ctx.fs.statSync(runPath).isDirectory()
        for f in ctx.fs.readdirSync(runPath)
          return true if f.endsWith '.txt'
    catch
      return false
    false

  endpoint: (ctx) ->
    {fs, path, CWD} = ctx
    satDir = path.join(CWD, 'sat')
    return {runs: []} unless fs.existsSync(satDir)

    # Enumerate run dirs, newest first (timestamp string sort works
    # for our YYYY-MM-DD_HH_MM format).
    runNames = []
    for entry in fs.readdirSync(satDir)
      full = path.join(satDir, entry)
      try
        continue unless fs.statSync(full).isDirectory()
      catch
        continue
      runNames.push entry
    runNames.sort()
    runNames.reverse()
    runNames = runNames.slice(0, MAX_RUNS_SHOWN)

    runs = []
    for runName in runNames
      runPath = path.join(satDir, runName)
      files = []
      try
        for f in fs.readdirSync(runPath)
          continue unless f.endsWith '.txt'
          filePath = path.join(runPath, f)
          stat = fs.statSync(filePath)
          # Parse `<config>__<prompt>.txt`; fall back to raw name if
          # the double-underscore convention isn't followed.
          base = f.replace(/\.txt$/, '')
          [config, promptKey] =
            if base.indexOf('__') >= 0 then base.split('__', 2) else [base, '']
          content = ''
          try
            content = fs.readFileSync(filePath, 'utf8').slice(0, MAX_PREVIEW_BYTES)
          catch
            content = '(read failed)'
          files.push {
            label:     f
            config:    config
            prompt:    promptKey
            size:      stat.size
            mtime:     stat.mtime?.toISOString?() ? null
            content:   content
            truncated: stat.size > MAX_PREVIEW_BYTES
          }
      catch
        continue
      files.sort (a, b) -> String(a.label).localeCompare String(b.label)
      runs.push {timestamp: runName, files: files}

    {runs: runs}
