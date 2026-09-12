#!/usr/bin/env coffee
fs = require 'fs'
path = require 'path'
http = require 'http'
yaml = require 'js-yaml'
{ spawn } = require 'child_process'
{ DatabaseSync } = require 'node:sqlite'

CWD = process.env.CWD ? process.cwd()
PORT = Number(process.env.UI_PORT ? 4311)
UI_BIND_MODE = String(process.env.UI_BIND_MODE ? (if process.argv[2] is 'net' then 'net' else 'local'))
HOST = if UI_BIND_MODE is 'net' then '0.0.0.0' else '127.0.0.1'
repeatLoop =
  enabled: false
  payload: null
  timer: null
  next_launch_at: null
  delay_seconds: 60
UI_CONTROL_PATH = path.join(CWD, 'state', 'ui-control.json')
CONTROL_OVERRIDE_PATH = path.join(CWD, 'control_override.yaml')
OVERRIDE_PATH = path.join(CWD, 'override.yaml')
OVERRIDE_DIR = path.join(CWD, 'override')
MERGE_RUN_PATH = path.join(CWD, 'state', 'merge-run.json')

readJson = (p, fallback = null) ->
  return fallback unless fs.existsSync(p)
  try JSON.parse(fs.readFileSync(p, 'utf8')) catch then fallback

readText = (p, fallback = '') ->
  return fallback unless fs.existsSync(p)
  try fs.readFileSync(p, 'utf8') catch then fallback

writeText = (p, text) ->
  fs.mkdirSync path.dirname(p), { recursive: true }
  fs.writeFileSync p, text, 'utf8'

looksLikeExecRoot = (candidate) ->
  return false unless typeof candidate is 'string' and candidate.length
  # **Project-owned UI fix — keep this comment.**
  # We used to require `ui/index.html` here too, but the UI can
  # live at the *project* root if the project copies it there
  # (e.g. `cp -r node_modules/@jahbini/pipeline/ui ./ui`). EXEC_ROOT
  # is identified by runner-shipped assets only: `pipeline_runner.coffee`
  # + `meta/`. The static UI is resolved separately, project-first
  # with EXEC_ROOT fallback (see resolveUiAsset below).
  try
    fs.existsSync(path.join(candidate, 'pipeline_runner.coffee')) and
      fs.existsSync(path.join(candidate, 'meta'))
  catch
    false

resolveExecRoot = ->
  candidates = []
  seen = new Set()

  pushCandidate = (candidate) ->
    return unless typeof candidate is 'string' and candidate.length
    absolute = path.resolve(candidate)
    return if seen.has(absolute)
    seen.add absolute
    candidates.push absolute

  pushCandidate process.env.EXEC if process.env.EXEC?

  # **Read env/EXEC stamped by the runner.**
  # On every run, pipeline_runner.coffee saves `env/EXEC` (and
  # `env/CWD`, `env/PYTHON`, …) into the project via the slash
  # meta device. That's the authoritative project record of where
  # the runner code lives, so we honor it before any heuristic
  # guess. The file is JSON-encoded (the slash meta does
  # JSON.stringify on string values), hence the parse.
  try
    envExecPath = path.join(CWD, 'env', 'EXEC')
    if fs.existsSync(envExecPath)
      raw = fs.readFileSync(envExecPath, 'utf8').trim()
      parsed = null
      try parsed = JSON.parse(raw) catch then parsed = raw
      pushCandidate parsed if typeof parsed is 'string'
  catch
    null

  pushCandidate path.dirname(__filename)
  pushCandidate process.cwd()
  pushCandidate CWD
  pushCandidate path.dirname(CWD)
  pushCandidate path.dirname(path.dirname(CWD))

  for candidate in candidates when looksLikeExecRoot(candidate)
    return candidate

  candidates[0] ? path.dirname(__filename)

EXEC_ROOT = resolveExecRoot()
RUNNER = path.join(EXEC_ROOT, 'pipeline_runner.coffee')
# merge_sqlite_dbs.coffee is project-owned (it pulls LoRA results from the
# remote training box into THIS project's pipes/build). Prefer the BASE copy;
# fall back to the package only if a project copy isn't present. (BASE is
# defined just below — resolved the same way; compute it inline here.)
MERGE_SCRIPT = do ->
  marker = "#{path.sep}node_modules#{path.sep}"
  idx = EXEC_ROOT.indexOf(marker)
  base = if idx isnt -1 then EXEC_ROOT.slice(0, idx) else EXEC_ROOT
  baseCopy = path.join(base, 'merge_sqlite_dbs.coffee')
  if fs.existsSync(baseCopy) then baseCopy else path.join(EXEC_ROOT, 'merge_sqlite_dbs.coffee')

# BASE — the consuming project's root (mirrors the runner's BASE). When
# installed as an npm package, EXEC_ROOT is `<base>/node_modules/@jahbini/
# pipeline`; the pipes live at `<base>/pipes`, NOT inside node_modules. So
# resolve PIPES_ROOT against the project base, falling back to EXEC_ROOT for
# the monolith layout (runner at the base, no node_modules ancestor).
BASE = do ->
  marker = "#{path.sep}node_modules#{path.sep}"
  idx = EXEC_ROOT.indexOf(marker)
  if idx isnt -1 then EXEC_ROOT.slice(0, idx) else EXEC_ROOT

PIPES_ROOT = path.join(BASE, 'pipes')

# --- Panel registry (2026-09-09) ----------------------------------------
# Plugin surface for project + framework UI sections. See
# ~/pipeline/GPT/ui/panels.md. Each panel is a coffee file in
# <BASE|EXEC>/panels/<name>.coffee (BASE wins on conflict). No CWD
# tier: pipes in a project share one UI by design. `CWD` is still
# passed through the ctx so panels can read pipe-local disk state.
# Helpers get folded into every panel's ctx so panels don't each
# redeclare listFiles/describeOutputFile/readJson.
panelRegistry = null
initPanelRegistry = ->
  return panelRegistry if panelRegistry?
  try
    {load} = require path.join(EXEC_ROOT, 'panels')
    panelRegistry = load
      CWD:  CWD
      BASE: BASE
      EXEC: EXEC_ROOT
      helpers:
        listFiles:          listFiles
        describeOutputFile: describeOutputFile
        readJson:           readJson
        readText:           readText
    # Audit: dump the resolution table to params/_panels.yaml so a
    # human sees which tier supplied each panel this session.
    try
      resolveRows = panelRegistry.resolution()
      if resolveRows.length
        yml = ({name, tier, path}) -> "- name: #{name}\n  tier: #{tier}\n  path: #{path}"
        fs.mkdirSync path.join(CWD, 'params'), {recursive: true}
        fs.writeFileSync path.join(CWD, 'params', '_panels.yaml'),
          "# panel resolution table — CWD ↠ BASE ↠ EXEC\n#{(yml(r) for r in resolveRows).join('\n')}\n"
    catch
      null
    console.log "[panels] registered #{panelRegistry.list().length} panel(s)"
  catch err
    console.error "[panels] registry init failed: #{String(err?.message ? err)}"
    panelRegistry =
      list: -> []
      get: -> null
      data: -> null
      eager: -> {}
      resolution: -> []
  panelRegistry
DEFAULT_KAG_KEYWORDS = [
  'joy'
  'contentment'
  'sadness'
  'grief'
  'fear'
  'anxiety'
  'anger'
  'frustration'
  'disgust'
  'shame'
  'surprise'
  'neutral'
]

isProcessAlive = (pid) ->
  num = Number(pid)
  return false unless Number.isFinite(num) and num > 0
  try
    process.kill num, 0
    true
  catch
    false

normalizeUiRun = (run) ->
  current = if run? and typeof run is 'object' and not Array.isArray(run) then Object.assign({}, run) else {}
  pid = Number(current.pid ? 0)
  alive = isProcessAlive(pid)

  if alive and current.status in ['launching', 'running', 'skipped', 'killing']
    current.status = if current.status is 'killing' then 'killing' else 'running'
    current.pid = pid
    current.is_attached = true
    current.is_process_alive = true
    return current

  current.is_attached = false
  current.is_process_alive = alive
  current

normalizeMergeRun = (run) ->
  current = if run? and typeof run is 'object' and not Array.isArray(run) then Object.assign({}, run) else {}
  pid = Number(current.pid ? 0)
  alive = isProcessAlive(pid)

  if alive and current.status in ['launching', 'running']
    current.status = 'running'
    current.pid = pid
    current.is_process_alive = true
    return current

  current.is_process_alive = alive
  current

readMergeRun = ->
  normalizeMergeRun readJson(MERGE_RUN_PATH, {})

resolveCoffeeBin = ->
  # pnpm currently ships a broken shim at
  #   <base>/node_modules/@jahbini/pipeline/node_modules/.bin/coffee
  # that exec's `node "<basedir>/../../../../../../coffeescript@X/…/coffee"`
  # — that's six `..` levels up from `.bin`, landing at $HOME, then
  # appending `coffeescript@X/…`. Result: `/Users/<you>/coffeescript@X/…`
  # which doesn't exist. When we spawn the shim, Node dies with
  # `Cannot find module '/Users/<you>/coffeescript@X/…/coffee'`.
  #
  # Bypass strategy: look under the project's `.pnpm/` store for the
  # real coffee entry point (`.pnpm/coffeescript@*/node_modules/coffeescript/bin/coffee`)
  # and, when found, return it directly. Node treats a file path as a
  # script to run, so `spawn(nodePath, [coffeePath, script, args...])`
  # is the cleanest form — but existing callers spawn a single bin.
  # So we return the absolute path to that entry point; Node's shebang
  # `#!/opt/homebrew/opt/node/bin/node` (or similar) makes it directly
  # executable IF the file is +x. When it isn't, fall through to the
  # PATH-resolved `coffee` (Homebrew's system install).
  pnpmRoot = path.join(BASE, 'node_modules', '.pnpm')
  if fs.existsSync(pnpmRoot)
    try
      for entry in fs.readdirSync(pnpmRoot) when entry.startsWith('coffeescript@')
        realCoffee = path.join(pnpmRoot, entry, 'node_modules', 'coffeescript', 'bin', 'coffee')
        continue unless fs.existsSync realCoffee
        # Only return it if it's executable. Otherwise Node has to be
        # invoked with the file as its argv, which the caller isn't set
        # up for — cleaner to fall through to `coffee` on PATH.
        try
          fs.accessSync realCoffee, fs.constants.X_OK
          return realCoffee
        catch
          null
    catch
      null

  # Fallback #1: the (possibly-broken) local shim. Kept for the older
  # monolith layout where the shim IS correct — an npm install without
  # pnpm produces a working shim here.
  localCoffee = path.join(EXEC_ROOT, 'node_modules', '.bin', 'coffee')
  return localCoffee if fs.existsSync(localCoffee) and not fs.existsSync(pnpmRoot)

  # Fallback #2: system coffee via PATH (Homebrew's install).
  'coffee'

workspacePipeName = (workspacePath = CWD) ->
  rel = path.relative(PIPES_ROOT, workspacePath)
  return null if not rel? or rel.startsWith('..') or path.isAbsolute(rel) or rel is ''
  rel.split(path.sep)[0] ? null

inferModelIdFromPipeName = (pipeName) ->
  # Guard: only infer for TRULY BARE pipes — those with no legacy
  # override.yaml that already pins run.model. Pipes created via
  # /api/create_pipe or bin/pipe-new.sh always set run.model in the
  # legacy file, and the runner's deep-merge delivers it. Inferring
  # from a name like `q35_4` yields nonsense (`q35/4`), so any caller
  # that runs the inference without this guard silently corrupts the
  # recipe-scoped override. Folded into the helper so future callers
  # can't skip the check.
  legacyModel = try
    String(readLegacyOverride()?.run?.model ? '').trim()
  catch
    ''
  return '' if legacyModel.length
  name = String(pipeName ? '').trim()
  return '' unless name.length
  underscoreIndex = name.indexOf('_')
  return '' unless underscoreIndex > 0 and underscoreIndex < name.length - 1
  organization = name.slice(0, underscoreIndex).trim()
  modelName = name.slice(underscoreIndex + 1).trim()
  return '' unless organization.length and modelName.length
  "#{organization}/#{modelName}"

listPipeDirectories = ->
  return [] unless fs.existsSync(PIPES_ROOT)
  names = fs.readdirSync(PIPES_ROOT).filter (name) ->
    full = path.join(PIPES_ROOT, name)
    try
      fs.statSync(full).isDirectory()
    catch
      false
  names.sort (a, b) -> String(a).localeCompare String(b)

buildPipeSummary = ->
  current = workspacePipeName(CWD)
  pipes = (name: name, is_active: name is current for name in listPipeDirectories())
  {
    root: PIPES_ROOT
    current: current
    workspace: CWD
    # Basename of the project root — feeds the window/page title
    # "Pipeline Monitor for <base_dir> <current>" in the client.
    base_dir: path.basename(BASE)
    pipes: pipes
  }

writeUiRunPatch = (patch) ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  current = readJson(runPath, {})
  current = {} unless current? and typeof current is 'object' and not Array.isArray(current)
  next = Object.assign {}, current, patch
  writeText runPath, JSON.stringify(next, null, 2)
  next

readUiControl = ->
  current = readJson(UI_CONTROL_PATH, {})
  current = {} unless current? and typeof current is 'object' and not Array.isArray(current)
  current

writeUiControl = (patch) ->
  current = readUiControl()
  next = Object.assign {}, current, patch
  writeText UI_CONTROL_PATH, JSON.stringify(next, null, 2)
  next

normalizeCooldownSeconds = (value, fallback = 60) ->
  num = Number(value)
  return 20 if num is 20
  return 60 if num is 60
  fallback

dumpYaml = (value) ->
  yaml.dump value,
    lineWidth: 120
    noRefs: true

getByPath = (root, dottedPath) ->
  return undefined unless root? and typeof dottedPath is 'string' and dottedPath.length
  node = root
  for part in dottedPath.split('.')
    return undefined unless node? and typeof node is 'object'
    node = node[part]
  node

setByPath = (root, dottedPath, value) ->
  return root unless root? and typeof root is 'object' and typeof dottedPath is 'string' and dottedPath.length
  parts = dottedPath.split('.')
  node = root
  for part, index in parts
    if index is parts.length - 1
      node[part] = value
    else
      node[part] ?= {}
      node = node[part]
  root

deleteByPath = (root, dottedPath) ->
  return root unless root? and typeof root is 'object' and typeof dottedPath is 'string' and dottedPath.length
  parts = dottedPath.split('.')
  chain = []
  node = root
  for part in parts
    return root unless node? and typeof node is 'object'
    chain.push [node, part]
    node = node[part]

  [leafParent, leafKey] = chain[chain.length - 1]
  delete leafParent[leafKey]

  for index in [(chain.length - 2)..0]
    [parent, key] = chain[index]
    child = parent[key]
    break unless child? and typeof child is 'object' and not Array.isArray(child) and Object.keys(child).length is 0
    delete parent[key]

  root

loadDropdownOptions = (specPath) ->
  return [] unless typeof specPath is 'string' and specPath.length
  # `adapters` — list the LoRA adapters available in this pipe's build/ dir
  # (any `adapter` / `adapter_*` subdir holding an adapter_config.json), plus
  # a base (no-adapter) option. Powers the adapter-picker dropdown; the chosen
  # value is written to the step's `adapter_path` override.
  if specPath is 'adapters'
    buildDir = path.join CWD, 'build'
    rows = [{ key: '', label: '(base — no adapter)' }]
    if fs.existsSync buildDir
      for name in fs.readdirSync(buildDir).sort() when /^adapter($|_)/.test(name)
        full = path.join buildDir, name
        continue unless fs.statSync(full).isDirectory() and fs.existsSync(path.join(full, 'adapter_config.json'))
        dirLabel = if name is 'adapter' then 'adapter (current)' else name
        rows.push { key: "build/#{name}", label: dirLabel }
        # Also surface each saved checkpoint (NNNNNNN_adapters.safetensors) as a
        # selectable option so a specific training step can be compared. The
        # loader (session_api) loads the file against the dir's adapter_config.
        base = if name is 'adapter' then 'adapter' else name
        for ckpt in fs.readdirSync(full).sort() when /^\d+_adapters\.safetensors$/.test(ckpt)
          rows.push { key: "build/#{name}/#{ckpt}", label: "#{base} @#{parseInt(ckpt, 10)}" }
    # Append saved good adapters from this pipe's build/good_adapters/
    # dir — see GPT/ui/save_good_adapter.md.
    goodDir = path.join buildDir, 'good_adapters'
    if fs.existsSync goodDir
      for name in fs.readdirSync(goodDir).sort()
        full = path.join goodDir, name
        continue unless fs.statSync(full).isDirectory() and fs.existsSync(path.join(full, 'adapter_config.json'))
        rows.push { key: "build/good_adapters/#{name}", label: "★ good: #{name}" }
    return rows
  if specPath is 'db/grammars'
    # Grammar names from data/dramatic_grammars.yaml — one row per
    # top-level grammar key (jim_tragedy, spy, …). Label = the key
    # verbatim; a short desc from the YAML would be nicer but the UI's
    # dropdown renderer shows the label only.
    grammarsPath = resolveDataAsset 'dramatic_grammars.yaml'
    return [] unless fs.existsSync grammarsPath
    try
      doc = readYaml grammarsPath
      return ({ key: String(name), label: String(name) } for name of (doc?.grammars ? {}))
    catch
      return []
  if specPath is 'db/iching_situations'
    # 64 canonical situations from data/iching_situations.yaml. Key =
    # the id as a string; label = "N — <situation string, truncated>"
    # so the human can eyeball what they're picking. HYGIENE: label
    # renders the RENDER-SAFE `situation` field, never name_internal
    # or glyph_binary.
    sitPath = resolveDataAsset 'iching_situations.yaml'
    return [] unless fs.existsSync sitPath
    try
      doc = readYaml sitPath
      rows = []
      for entry in (doc?.situations ? []) when Number.isInteger(entry?.id)
        situationText = String(entry?.situation ? '').replace(/\s+/g, ' ').trim()
        short = if situationText.length > 60 then situationText[0...57] + '…' else situationText
        rows.push { key: String(entry.id), label: "#{entry.id} — #{short}" }
      return rows
    catch
      return []
  if specPath is 'db/moving_line_counts'
    # Small fixed dropdown: blank = seeded default, else 3/4/5.
    return [
      { key: '',  label: '(seeded 3–5)' }
      { key: '3', label: '3' }
      { key: '4', label: '4' }
      { key: '5', label: '5' }
    ]
  if specPath is 'db/story_titles'
    # Populated by the storacle recipe's `story_id` dropdown so a human
    # can pick any story present in the pipe's runtime.sqlite. key =
    # story_id (kebab-cased), label = title. Ordered by title. Empty
    # list if the sqlite is missing or the stories table is empty —
    # the UI will just render "(default)" and the step will throw on
    # empty story_id.
    dbPath = path.join CWD, 'runtime.sqlite'
    return [] unless fs.existsSync dbPath
    db = null
    try
      db = new DatabaseSync dbPath
      rows = db.prepare("""
        SELECT story_id, title
        FROM stories
        WHERE story_id IS NOT NULL AND TRIM(story_id) != ''
        ORDER BY title ASC
      """).all()
      return ({
        key: String(row.story_id)
        label: String(row.title ? row.story_id)
      } for row in rows when row?.story_id?)
    catch
      return []
    finally
      try db?.close() catch then null
  if specPath is 'db/kag_keywords'
    dbPath = path.join CWD, 'runtime.sqlite'
    fallbackRows = ({ key, label: key } for key in DEFAULT_KAG_KEYWORDS)
    return fallbackRows unless fs.existsSync dbPath
    db = null
    try
      db = new DatabaseSync dbPath
      rows = db.prepare("""
        SELECT DISTINCT keyword
        FROM kag_entries
        WHERE keyword IS NOT NULL AND TRIM(keyword) != ''
        ORDER BY keyword ASC
      """).all()
      mapped = ({
        key: String(row.keyword)
        label: String(row.keyword)
      } for row in rows when row?.keyword?)
      return mapped if mapped.length
      return fallbackRows
    catch
      return fallbackRows
    finally
      try db?.close() catch then null
  parts = specPath.split('/')
  return [] unless parts.length >= 3
  filePath = path.join CWD, parts[0], parts[1]
  keyParts = parts.slice(2)
  doc = readYaml filePath
  node = doc
  for key in keyParts
    return [] unless node? and typeof node is 'object'
    node = node[key]
  return [] unless node? and typeof node is 'object'
  rows = []
  preserveOrder = false
  if Array.isArray(node)
    # Ordered list. Entries may be bare strings (key == label) or objects
    # with {id|key, label, ...} — the latter preserves author-curated order.
    for v in node
      if typeof v is 'string'
        rows.push { key: v, label: v }
      else if v? and typeof v is 'object'
        key = v.id ? v.key
        continue unless key?
        label = v.label ? v.text ? v.character ? v.desc ? key
        rows.push { key: String(key), label: String(label) }
        preserveOrder = true
  else
    for own key, value of node
      label = value?.text ? value?.character ? value?.label ? key
      rows.push { key, label }
  rows.sort (a, b) -> String(a.label).localeCompare String(b.label) unless preserveOrder
  rows

scanUiFields = (recipe, valueSource, uiControl, extraDirectiveSources = []) ->
  # `valueSource` supplies CURRENT VALUES via getByPath (controlOverride
  # for the render pass, the recipe-scoped override for the save-handler
  # pass). `extraDirectiveSources` is a list of additional objects to
  # walk for `UI_checkbox` / `UI_dropdown` / `UI_textarea` directives —
  # this is what lets steps registered via override (SKYGUY's
  # situation_caster, LEPA's cast_genesis, etc.) declare their own
  # directives without editing the recipe. Recipe wins on path
  # collision (recipe is canonical); extras only add new paths.
  pendingUi = uiControl?.ui_values ? {}
  rows = []
  seenPaths = new Set()

  # Historical arg name inside the function body — keep it named
  # `override` locally so the value-lookup calls below still read.
  override = valueSource

  buildLabel = (pathText) ->
    parts = String(pathText ? '').split('.')
    return pathText unless parts.length
    if parts.length >= 2
      stepName = parts[0]
      keyName = parts[parts.length - 1]
      return "#{stepName}: #{keyName}"
    pathText

  pushRow = (row) ->
    return if seenPaths.has row.path
    seenPaths.add row.path
    rows.push row

  walk = (node, prefix = '') ->
    return unless node? and typeof node is 'object'
    if Array.isArray(node)
      directive = String(node[0] ? '')
      if directive is 'UI_checkbox'
        defaultValue = node[1] is true
        chosenValue = if Object::hasOwnProperty.call(pendingUi, prefix)
          pendingUi[prefix] is true
        else
          overrideValue = getByPath override, prefix
          if typeof overrideValue is 'boolean' then overrideValue else defaultValue
        pushRow
          path: prefix
          label: buildLabel(prefix)
          type: 'checkbox'
          default_value: defaultValue
          value: chosenValue
      else if directive is 'UI_dropdown'
        sourcePath = String(node[1] ? '')
        defaultValue = String(node[2] ? '')
        chosenValue = if Object::hasOwnProperty.call(pendingUi, prefix)
          String(pendingUi[prefix] ? '')
        else
          overrideValue = getByPath override, prefix
          if typeof overrideValue is 'string' then overrideValue else defaultValue
        sourceParts = sourcePath.split('/')
        pushRow
          path: prefix
          label: buildLabel(prefix)
          type: 'dropdown'
          default_value: defaultValue
          value: chosenValue
          source_path: sourcePath
          options: loadDropdownOptions(sourcePath)
      else if directive is 'UI_textarea'
        defaultValue = if node.length >= 2 then String(node[1] ? '') else ''
        chosenValue = if Object::hasOwnProperty.call(pendingUi, prefix)
          String(pendingUi[prefix] ? '')
        else
          overrideValue = getByPath override, prefix
          if typeof overrideValue is 'string' then overrideValue else defaultValue
        pushRow
          path: prefix
          label: buildLabel(prefix)
          type: 'textarea'
          default_value: defaultValue
          value: chosenValue
      return

    return unless not Array.isArray(node)
    for own key, value of node
      currentPath = if prefix.length then "#{prefix}.#{key}" else key
      walk value, currentPath

  walk recipe
  for src in (extraDirectiveSources ? [])
    walk src

  # Group diary event fields by event kind so each event renders as
  # `select_story_recipe.<kind>` immediately followed by
  # `collect_diary_kag_ite.<kind>_emotion` (recipe-declared step order is
  # `select_story_recipe` before `collect_diary_kag_ite`, so within a kind
  # the story selection naturally precedes the emotion). Non-event fields
  # render first in their original recipe order. Mirrors writeStory's
  # scanUiFields ordering — this is the documented diary control layout.
  eventOrder = ['scene', 'arrival', 'disturbance', 'reflection', 'realization']
  kindFor = (rowPath) ->
    tail = String(rowPath ? '').split('.').pop() ? ''
    for kind in eventOrder
      return kind if tail is kind or tail is "#{kind}_emotion"
    null

  unkinned = []
  kinned = []
  for row, idx in rows
    kind = kindFor row.path
    if kind?
      kinned.push { row, idx, kindIndex: eventOrder.indexOf(kind) }
    else
      unkinned.push row
  kinned.sort (a, b) ->
    if a.kindIndex isnt b.kindIndex then a.kindIndex - b.kindIndex else a.idx - b.idx
  unkinned.concat(entry.row for entry in kinned)

# Resolve a recipe's config file BASE-first, then EXEC — same precedence as
# the runner's resolveConfigPath, so the UI reads the SAME recipe the runner
# will run (a project config/<name>.yaml shadows the package copy).
resolveConfigPath = (name) ->
  for root in [BASE, EXEC_ROOT]
    p = path.join(root, 'config', "#{name}.yaml")
    return p if fs.existsSync(p)
  path.join(EXEC_ROOT, 'config', "#{name}.yaml")

# Enumerate every pipeline recipe visible in the UI dropdown by scanning
# three tiers in precedence order:
#   pipe    - <CWD>/config/*.yaml    (pipe-local, highest priority)
#   project - <BASE>/config/*.yaml   (project-shared)
#   shipped - <EXEC_ROOT>/config/*.yaml (bundled with @jahbini/pipeline)
# Matches `resolveConfigPath`'s CWD > BASE > EXEC precedence. When a
# recipe name exists in multiple tiers, the highest-priority source wins.
#
# `discoverPipelines()` returns [{name, source}]. The UI uses `source`
# to italicize non-shipped entries so the human can see at a glance
# which are local overlays. `discoverRecipes()` remains for callers
# that only need the string list.
discoverPipelines = ->
  bySource = {}
  for [source, root] in [['pipe', CWD], ['project', BASE], ['shipped', EXEC_ROOT]]
    dir = path.join(root, 'config')
    continue unless fs.existsSync(dir)
    try
      for f in fs.readdirSync(dir) when f.endsWith('.yaml')
        name = f.slice(0, -('.yaml'.length))
        bySource[name] ?= source   # first writer wins → precedence order
    catch
      null
  ({name, source: bySource[name]} for name in Object.keys(bySource).sort())

discoverRecipes = -> p.name for p in discoverPipelines()

readRecipe = (pipeline) ->
  return {} unless typeof pipeline is 'string' and pipeline.length
  readYaml resolveConfigPath(pipeline)

pad2 = (n) ->
  text = String(Number(n) ? 0)
  if text.length < 2 then "0#{text}" else text

safeStem = (s) ->
  # Filesystem-friendly: strip anything not alnum / dash / underscore.
  String(s ? '').replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '') or 'pipe'

buildRunTag = (recipe = null) ->
  now = new Date()
  hhmm = "#{pad2(now.getHours())}_#{pad2(now.getMinutes())}"
  prefix = if recipe? and String(recipe).length then safeStem(recipe) else 'pipe'
  {
    hh_mm: hhmm
    logdir: "#{prefix}_#{hhmm}"
  }

tailText = (p, maxLines = 120) ->
  text = readText(p, '')
  lines = text.split /\r?\n/
  lines.slice(Math.max(lines.length - maxLines, 0)).join "\n"

listFiles = (dir) ->
  return [] unless fs.existsSync(dir)
  names = fs.readdirSync(dir).sort()
  out = []
  for name in names
    full = path.join(dir, name)
    stat = fs.statSync(full)
    out.push
      name: name
      path: full
      is_dir: stat.isDirectory()
      size: stat.size
      mtime: stat.mtime.toISOString()
  out

readJsonlTail = (p, maxRows = 80) ->
  return [] unless fs.existsSync(p)
  text = fs.readFileSync(p, 'utf8')
  rows = []
  for line in text.split(/\r?\n/) when line.trim().length
    try rows.push JSON.parse(line) catch then null
  rows.slice Math.max(rows.length - maxRows, 0)

latestLogStem = ->
  logDir = path.join(CWD, 'logs')
  return null unless fs.existsSync(logDir)
  # Accept both legacy pipe_HH_MM and new <recipe>_HH_MM basenames.
  names = fs.readdirSync(logDir).filter (name) -> /^[A-Za-z0-9_-]+_\d{2}_\d{2}\.(log|err)$/.test(name)
  return null unless names.length
  stems = {}
  for name in names
    stem = name.replace /\.(log|err)$/, ''
    stems[stem] = true
  ordered = Object.keys(stems).sort()
  ordered[ordered.length - 1]

# collectStepStates removed 2026-09-10 — migrated to
# ~/pipeline/panels/steps.coffee (framework tier). The rich row shape
# is preserved so ui/index.html's renderSteps + refreshPipelineGraph
# work unchanged via the PANEL_CUSTOM_RENDERERS.steps hook.

overridePathForPipeline = (pipelineName) ->
  name = String(pipelineName ? '').trim()
  return OVERRIDE_PATH unless name.length
  path.join OVERRIDE_DIR, "#{name}.yaml"

readLegacyOverride = ->
  parsed = if fs.existsSync(OVERRIDE_PATH)
    try yaml.load(fs.readFileSync(OVERRIDE_PATH, 'utf8')) ? {} catch then {}
  else
    {}
  parsed = {} unless parsed? and typeof parsed is 'object' and not Array.isArray(parsed)
  parsed

readOverride = (pipelineName = null) ->
  foundational = {}
  pipeName = workspacePipeName(CWD)
  legacy = readLegacyOverride()
  inferredModel = inferModelIdFromPipeName(pipeName)
  selectedPipeline = String(pipelineName ? '').trim()
  selectedPipeline = String(legacy.pipeline ? '').trim() unless selectedPipeline.length
  selectedPath = overridePathForPipeline selectedPipeline

  # Only seed a new recipe-scoped override from the legacy override.yaml when
  # the legacy file is actually for THIS recipe (or names no pipeline). The
  # legacy file holds one pipeline's config; seeding an unrelated recipe from
  # it would copy e.g. diary_ite's overrides into prompt_ite on a recipe switch.
  legacyPipeline = String(legacy.pipeline ? '').trim()
  legacyMatchesSelection = legacyPipeline.length is 0 or legacyPipeline is selectedPipeline

  materializedFromLegacy = false
  parsed = if fs.existsSync(selectedPath)
    try yaml.load(fs.readFileSync(selectedPath, 'utf8')) ? {} catch then {}
  else if fs.existsSync(OVERRIDE_PATH) and legacyMatchesSelection
    materializedFromLegacy = selectedPipeline.length > 0
    Object.assign {}, legacy
  else
    {}

  parsed = {} unless parsed? and typeof parsed is 'object' and not Array.isArray(parsed)
  needsWrite = false

  if inferredModel.length
    parsed.run = {} unless parsed.run? and typeof parsed.run is 'object' and not Array.isArray(parsed.run)
    currentModel = String(parsed.run.model ? '').trim()
    if currentModel.length is 0
      parsed.run.model = inferredModel
      needsWrite = true

  if selectedPipeline.length and not parsed.pipeline?
    parsed.pipeline = selectedPipeline
    needsWrite = true

  if materializedFromLegacy or needsWrite or (inferredModel.length and not fs.existsSync(selectedPath))
    writeText selectedPath, dumpYaml(parsed)

  parsed

readControlOverride = ->
  return {} unless fs.existsSync CONTROL_OVERRIDE_PATH
  try yaml.load(fs.readFileSync(CONTROL_OVERRIDE_PATH, 'utf8')) ? {} catch then {}

readYaml = (p) ->
  target = p
  if not fs.existsSync(target) and typeof p is 'string'
    rel = path.relative(CWD, p)
    if rel? and not rel.startsWith('..') and not path.isAbsolute(rel)
      fallback = path.join(EXEC_ROOT, rel)
      target = fallback if fs.existsSync(fallback)
  return {} unless fs.existsSync target
  try yaml.load(fs.readFileSync(target, 'utf8')) ? {} catch then {}

buildControls = ->
  controlOverride = readControlOverride()
  uiControl = readUiControl()
  pending = uiControl.pending ? {}
  legacyOverride = readLegacyOverride()
  pipelineName = pending.pipeline ? controlOverride.pipeline ? legacyOverride.pipeline ? ''
  override = readOverride(pipelineName)
  recipe = readRecipe(pipelineName)
  # The story library is per-pipe data: prefer the active pipe's data/ (CWD),
  # fall back to EXEC_ROOT for older layouts. (The package has no data/, so a
  # plain EXEC_ROOT read leaves the scene/arrival dropdowns empty.)
  libraryPath = resolveDataAsset('jim_story_library.yaml')
  libraryDoc = readYaml libraryPath
  library = libraryDoc?.library ? {}
  recipeStoryStep = recipe?.select_story_recipe ? {}
  controlStoryStep = controlOverride?.select_story_recipe ? {}

  makeOptions = (shelfName) ->
    shelf = library?[shelfName] ? {}
    rows = []
    for own key, value of shelf
      label = value?.text ? value?.character ? key
      rows.push { key, label }
    rows.sort (a, b) -> String(a.label).localeCompare String(b.label)
    rows

  overrideObject = buildOverrideObject
    pipeline: pipelineName
    scene: pending.scene ? controlStoryStep.scene ? recipeStoryStep.scene ? ''
    arrival: pending.arrival ? controlStoryStep.arrival ? recipeStoryStep.arrival ? ''
    disturbance: pending.disturbance ? controlStoryStep.disturbance ? recipeStoryStep.disturbance ? ''
    reflection: pending.reflection ? controlStoryStep.reflection ? recipeStoryStep.reflection ? ''
    realization: pending.realization ? controlStoryStep.realization ? recipeStoryStep.realization ? ''
    ui_values: Object.assign {}, (uiControl.ui_values ? {})

  controlOverrideText = if typeof uiControl.control_override_text is 'string' and uiControl.control_override_text.trim().length
    uiControl.control_override_text
  else
    dumpYaml overrideObject
  recipeText = if pipelineName.length then dumpYaml(recipe) else ''
  humanOverridePath = overridePathForPipeline pipelineName
  humanOverrideText = if fs.existsSync(humanOverridePath)
    readText humanOverridePath, ''
  else if fs.existsSync(OVERRIDE_PATH)
    readText OVERRIDE_PATH, ''
  else
    ''
  experimentText = if fs.existsSync(path.join(CWD, 'experiment.yaml')) then readText(path.join(CWD, 'experiment.yaml'), '') else ''
  # Values come from controlOverride (UI-managed per-run state);
  # directives can live in the recipe OR in the recipe-scoped override
  # (override/<recipe>.yaml). This lets steps registered via override
  # attach UI_checkbox / UI_dropdown / UI_textarea directives without
  # editing the recipe.
  uiFields = scanUiFields recipe, controlOverride, uiControl, [override]

  {
    pipeline: pipelineName
    scene: pending.scene ? controlStoryStep.scene ? recipeStoryStep.scene ? ''
    arrival: pending.arrival ? controlStoryStep.arrival ? recipeStoryStep.arrival ? ''
    disturbance: pending.disturbance ? controlStoryStep.disturbance ? recipeStoryStep.disturbance ? ''
    reflection: pending.reflection ? controlStoryStep.reflection ? recipeStoryStep.reflection ? ''
    realization: pending.realization ? controlStoryStep.realization ? recipeStoryStep.realization ? ''
    continuous: uiControl.continuous is true
    continuous_delay_seconds: normalizeCooldownSeconds(uiControl.continuous_delay_seconds, 60)
    # Discovered from config/ (project BASE ∪ package EXEC) — every recipe that
    # actually exists is selectable; no hardcoded list to drift out of sync.
    pipelines: discoverRecipes()
    # Enriched form: [{name, source}] with source ∈
    # {'pipe','project','shipped'}. UI italicizes non-shipped entries.
    pipelines_enriched: discoverPipelines()
    scene_options: makeOptions 'scenes'
    arrival_options: makeOptions 'characters'
    disturbance_options: makeOptions 'disturbances'
    reflection_options: makeOptions 'reflections'
    realization_options: makeOptions 'realizations'
    ui_fields: uiFields
    control_override_text: controlOverrideText
    human_override_text: humanOverrideText
    recipe_text: recipeText
    experiment_text: experimentText
  }

describeOutputFile = (relativePath, runStart = null) ->
  fullPath = path.join(CWD, relativePath)
  exists = fs.existsSync(fullPath)
  stat = if exists then fs.statSync(fullPath) else null
  mtime = if stat? then stat.mtime.toISOString() else null
  fresh = false
  if stat? and runStart?
    started = new Date(runStart)
    fresh = not Number.isNaN(started.getTime()) and stat.mtime.getTime() >= started.getTime()

  {
    name: path.basename(relativePath)
    path: relativePath
    exists: exists
    size: stat?.size ? null
    mtime: mtime
    is_fresh: fresh
  }

collectExpectedOutputs = (run) ->
  # Returns only `out_files` (recipe-declared `target:` artifacts).
  # Diary files moved to the panel registry (2026-09-10) —
  # ~/writer/panels/diary_files.coffee.
  controlOverride = readControlOverride()
  legacyOverride = readLegacyOverride()
  pipeline = controlOverride.pipeline ? legacyOverride.pipeline ? run?.pipeline ? null
  override = readOverride(pipeline)
  return { out_files: [] } unless pipeline?

  configPath = resolveConfigPath(pipeline)
  recipe = readYaml(configPath)
  artifacts = recipe?.artifacts ? {}
  runStart = run?.started_at ? null

  outFiles = []
  seen = new Set()

  for own artifactKey, spec of artifacts
    continue unless spec? and typeof spec is 'object' and typeof spec.target is 'string'
    target = String(spec.target)
    continue if seen.has(target)
    seen.add target
    row = describeOutputFile target, runStart
    continue if /^diary\//.test(target)
    outFiles.push row

  outFiles.sort (a, b) -> String(a.path).localeCompare String(b.path)

  { out_files: outFiles }

# collectDiaryFiles, collectLogFiles removed 2026-09-10 — migrated to
# ~/writer/panels/diary_files.coffee and ~/pipeline/panels/log_files.coffee.
# The panel registry (initPanelRegistry) populates data.panels_data.*
# and renderDynamicPanels() in ui/index.html builds the UI section
# from that. log_files uses render_hint 'custom' so its
# "Delete Log Files" button is preserved via a PANEL_CUSTOM_RENDERERS
# hook. See ~/pipeline/GPT/ui/panels.md.

buildStatus = ->
  # Async because panel endpoints may be async. The single caller
  # (/api/status handler) awaits.
  run = normalizeUiRun readJson path.join(CWD, 'state', 'ui-run.json'), {}
  mergeRun = readMergeRun()
  pipelineState = readJson path.join(CWD, 'pipeline.json'), null
  expectedOutputs = collectExpectedOutputs(run)
  pipeSummary = buildPipeSummary()
  loraRemaining = readJson path.join(CWD, 'out', 'lora_remaining_count.json'), null
  oracleRemaining = readJson path.join(CWD, 'out', 'oracle_remaining_count.json'), null
  storiesRemaining = if oracleRemaining? then oracleRemaining else loraRemaining
  events = readJsonlTail path.join(CWD, 'state', 'ui-events.jsonl')
  # steps moved to panel registry (2026-09-10) — data.panels_data.steps.rows.
  # Per-pipe env overrides (SESSION_API_MEM_CEIL_MB, etc). Written
  # by puppeteer's raise-ceiling action; applied by startRunner at
  # every subsequent spawn. Surface to the UI so humans can see
  # what env vars this pipe carries.
  envOverrides = {}
  try envOverrides = readJson(path.join(CWD, 'env_overrides.json'), {}) catch
  stem = if run?.logdir? then String(run.logdir) else latestLogStem()
  latestLog = if stem? then readText(path.join(CWD, 'logs', "#{stem}.log")) else ''
  latestErr = if stem? then readText(path.join(CWD, 'logs', "#{stem}.err")) else ''

  # Panel registry — declaration list + eager-panel data. Legacy
  # top-level fields (diary_files, log_files, out_files, …) stay
  # populated during migration so existing HTML keeps rendering; each
  # will move to panels_data.<name> in a later pass.
  registry = initPanelRegistry()
  panels = registry.list()
  panels_data = await registry.eager {run}

  {
    run: run
    merge_run: mergeRun
    pipeline_state: pipelineState
    pipe: pipeSummary
    lora_remaining_count: loraRemaining
    oracle_remaining_count: oracleRemaining
    stories_remaining_count: storiesRemaining
    controls: buildControls()
    # steps: removed 2026-09-10 — see panels_data.steps.rows
    events: events
    latest_log_stem: stem
    latest_log: latestLog
    latest_err: latestErr
    out_files: expectedOutputs.out_files
    env_overrides: envOverrides
    panels: panels
    panels_data: panels_data
  }

isAllowedFilePath = (relativePath) ->
  return false unless typeof relativePath is 'string' and relativePath.length
  normalized = path.normalize(relativePath)
  return false if normalized.startsWith('..') or path.isAbsolute(normalized)
  /^logs\//.test(normalized) or /^out\//.test(normalized) or /^diary\//.test(normalized) or /^build\//.test(normalized) or /^tested\//.test(normalized)

readViewerFile = (relativePath) ->
  return null unless isAllowedFilePath(relativePath)
  fullPath = path.join(CWD, relativePath)
  return null unless fs.existsSync(fullPath)
  stat = fs.statSync(fullPath)
  return null unless stat.isFile()
  {
    path: relativePath
    size: stat.size
    mtime: stat.mtime.toISOString()
    text: readText(fullPath, '')
  }

sendJson = (res, code, payload) ->
  body = JSON.stringify(payload, null, 2)
  res.writeHead code,
    'Content-Type': 'application/json; charset=utf-8'
    'Content-Length': Buffer.byteLength(body)
    'Cache-Control': 'no-store'
  res.end body

sendHtml = (res, p) ->
  body = readText p, ''
  if not body.length
    console.error "[ui_server] missing html:", p
    console.error "[ui_server] EXEC_ROOT:", EXEC_ROOT
    console.error "[ui_server] CWD:", CWD
    console.error "[ui_server] __filename:", __filename
    res.writeHead 404, 'Content-Type': 'text/plain; charset=utf-8'
    res.end 'ui/index.html not found'
    return
  res.writeHead 200,
    'Content-Type': 'text/html; charset=utf-8'
    'Content-Length': Buffer.byteLength(body)
    'Cache-Control': 'no-store'
  res.end body

readRequestBody = (req) ->
  new Promise (resolve, reject) ->
    chunks = []
    req.on 'data', (chunk) -> chunks.push chunk
    req.on 'end', ->
      text = Buffer.concat(chunks).toString('utf8')
      resolve text
    req.on 'error', reject

clearStepState = ->
  stateDir = path.join(CWD, 'state')
  return unless fs.existsSync stateDir
  for name in fs.readdirSync(stateDir) when /^step-.*\.json$/.test(name) or /^ui-run\.(json|jsonl)$/.test(name) or /^ui-events\.(json|jsonl)$/.test(name)
    fs.unlinkSync path.join(stateDir, name)

  pipelinePath = path.join(CWD, 'pipeline.json')
  fs.unlinkSync(pipelinePath) if fs.existsSync(pipelinePath)

seedUiRun = (launch, override) ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  current = readJson(runPath, {})
  current = {} unless current? and typeof current is 'object' and not Array.isArray(current)

  seeded =
    pipeline: current.pipeline ? override.pipeline ? null
    pid: current.pid ? launch.pid
    cwd: current.cwd ? CWD
    hh_mm: current.hh_mm ? launch.hh_mm
    logdir: current.logdir ? launch.logdir
    status: current.status ? 'launching'
    started_at: current.started_at ? new Date().toISOString()
    finished_at: current.finished_at ? null

  writeText runPath, JSON.stringify(seeded, null, 2)

findActiveWorkspaceRun = ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  run = normalizeUiRun readJson(runPath, {}), {}
  return null unless run.is_process_alive is true and Number(run.pid ? 0) > 0
  run

markUiRunExited = (launch, patch = {}) ->
  runPath = path.join(CWD, 'state', 'ui-run.json')
  current = readJson(runPath, {})
  return unless current? and typeof current is 'object' and not Array.isArray(current)
  return unless current.pid is launch.pid
  return unless current.status in ['launching', 'running']

  next = Object.assign {}, current,
    status: patch.status ? 'exited'
    finished_at: patch.finished_at ? new Date().toISOString()
  , patch

  writeText runPath, JSON.stringify(next, null, 2)

markMergeRunExited = (launch, patch = {}) ->
  current = readJson(MERGE_RUN_PATH, {})
  return unless current? and typeof current is 'object' and not Array.isArray(current)
  return unless current.pid is launch.pid
  return unless current.status in ['launching', 'running']

  next = Object.assign {}, current,
    status: patch.status ? 'exited'
    finished_at: patch.finished_at ? new Date().toISOString()
  , patch

  writeText MERGE_RUN_PATH, JSON.stringify(next, null, 2)

stopRepeatLoop = ->
  if repeatLoop.timer?
    clearTimeout repeatLoop.timer
  repeatLoop.enabled = false
  repeatLoop.payload = null
  repeatLoop.timer = null
  repeatLoop.next_launch_at = null
  repeatLoop.delay_seconds = 60
  writeUiControl continuous: false

buildLaunchPayloadFromControl = ->
  uiControl = readUiControl()
  pending = uiControl.pending ? {}
  controlOverride = readControlOverride()
  legacyOverride = readLegacyOverride()
  payload =
    pipeline: pending.pipeline ? controlOverride.pipeline ? legacyOverride.pipeline ? ''
    continuous: uiControl.continuous is true
    continuous_delay_seconds: normalizeCooldownSeconds(uiControl.continuous_delay_seconds, 60)

  for key in ['scene', 'arrival', 'disturbance', 'reflection', 'realization']
    payload[key] = pending[key] if pending[key]?
  payload.ui_values = Object.assign {}, (uiControl.ui_values ? {})

  payload

buildOverrideObject = (payload) ->
  override = {}
  pipelineName = String(payload.pipeline ? readLegacyOverride().pipeline ? '')
  recipe = readRecipe(pipelineName)
  recipeStory = recipe?.select_story_recipe ? {}
  override.pipeline = pipelineName
  diaryPipelines = ['diary_ite', 'diary_translate_ite']

  if override.pipeline in diaryPipelines
    override.select_story_recipe ?= {}

  if override.pipeline in diaryPipelines
    for key in ['scene', 'arrival', 'disturbance', 'reflection', 'realization']
      value = String(payload[key] ? '').trim()
      recipeValue = String(recipeStory[key] ? '')
      if value.length and value isnt recipeValue
        override.select_story_recipe[key] = value
      else
        delete override.select_story_recipe[key]

    delete override.select_story_recipe if Object.keys(override.select_story_recipe).length is 0
  else
    delete override.select_story_recipe

  uiFields = scanUiFields recipe, override, { ui_values: payload.ui_values ? {} }, [override]
  for field in uiFields
    chosenValue = if payload?.ui_values? and Object::hasOwnProperty.call(payload.ui_values, field.path)
      payload.ui_values[field.path]
    else
      field.value

    if chosenValue is field.default_value
      deleteByPath override, field.path
    else
      setByPath override, field.path, chosenValue

  override

writeControlOverrideText = (text) ->
  writeText CONTROL_OVERRIDE_PATH, text
  parsed = readYaml CONTROL_OVERRIDE_PATH
  throw new Error 'control_override.yaml must parse to an object' unless parsed? and typeof parsed is 'object' and not Array.isArray(parsed)
  throw new Error 'control_override.yaml must include pipeline' unless typeof parsed.pipeline is 'string' and parsed.pipeline.trim().length
  parsed

writeHumanOverrideText = (text, pipelineOverride = null) ->
  trimmed = String(text ? '').trim()
  controlOverride = readControlOverride()
  uiControl = readUiControl()
  # An explicit pipeline lets the UI save the OLD recipe's override while
  # switching away from it (before control_override flips to the new one).
  explicit = String(pipelineOverride ? '').trim()
  pipelineName = if explicit.length
    explicit
  else
    String(controlOverride.pipeline ? uiControl?.pending?.pipeline ? readLegacyOverride().pipeline ? '').trim()
  targetPath = overridePathForPipeline pipelineName
  if trimmed.length is 0
    parsed = readOverride(pipelineName)
    return parsed

  writeText targetPath, text
  parsed = readYaml targetPath
  throw new Error "#{path.relative(CWD, targetPath)} must parse to an object" unless parsed? and typeof parsed is 'object' and not Array.isArray(parsed)
  pipeName = workspacePipeName(CWD)
  inferredModel = inferModelIdFromPipeName(pipeName)
  if inferredModel.length
    parsed.run = {} unless parsed.run? and typeof parsed.run is 'object' and not Array.isArray(parsed.run)
    currentModel = String(parsed.run.model ? '').trim()
    if currentModel.length is 0
      parsed.run.model = inferredModel
      writeText targetPath, dumpYaml(parsed)
  parsed

scheduleRepeatLaunch = ->
  return unless repeatLoop.enabled

  pipelineState = readJson path.join(CWD, 'pipeline.json'), null
  if pipelineState?.status is 'shutdown'
    stopRepeatLoop()
    writeUiRunPatch
      loop_enabled: false
      countdown_seconds: null
      next_launch_at: null
    return

  delaySeconds = normalizeCooldownSeconds(repeatLoop.delay_seconds, 60)
  delayMs = delaySeconds * 1000
  repeatLoop.next_launch_at = new Date(Date.now() + delayMs).toISOString()
  writeUiRunPatch
    status: 'cooldown'
    loop_enabled: true
    countdown_seconds: delaySeconds
    next_launch_at: repeatLoop.next_launch_at

  repeatLoop.timer = setTimeout ->
    return unless repeatLoop.enabled
    pipelineStateNow = readJson path.join(CWD, 'pipeline.json'), null
    if pipelineStateNow?.status is 'shutdown'
      stopRepeatLoop()
      writeUiRunPatch
        loop_enabled: false
        countdown_seconds: null
        next_launch_at: null
      return

    uiControl = readUiControl()
    launchPayload = buildLaunchPayloadFromControl()
    overrideText = if typeof uiControl.control_override_text is 'string' and uiControl.control_override_text.trim().length
      uiControl.control_override_text
    else
      dumpYaml buildOverrideObject(launchPayload)
    override = writeControlOverrideText overrideText
    clearStepState()
    launch = startRunner()
    seedUiRun launch, override
    writeUiRunPatch
      loop_enabled: true
      countdown_seconds: null
      next_launch_at: null
  , delayMs

startRunner = ->
  # Read the active pipeline from control_override.yaml so the log
  # basename is <recipe>_HH_MM.log instead of the opaque pipe_HH_MM.
  recipeForTag = null
  try recipeForTag = readControlOverride()?.pipeline catch then null
  runTag = buildRunTag(recipeForTag)
  logDir = path.join(CWD, 'logs')
  fs.mkdirSync logDir, { recursive: true }
  logPath = path.join(logDir, "#{runTag.logdir}.log")
  errPath = path.join(logDir, "#{runTag.logdir}.err")
  fs.writeFileSync logPath, '', 'utf8'
  fs.writeFileSync errPath, '', 'utf8'
  outFd = fs.openSync logPath, 'a'
  errFd = fs.openSync errPath, 'a'

  # Read per-pipe env overrides from `env_overrides.json` — a simple
  # key/value map written by the puppeteer's "raise ceiling" action
  # (and any other per-pipe env-tuning UI). Values here override any
  # process.env inherited from our own environment.
  envOverrides = {}
  overridePath = path.join(CWD, 'env_overrides.json')
  if fs.existsSync overridePath
    try
      envOverrides = JSON.parse fs.readFileSync(overridePath, 'utf8')
    catch err
      console.error "[startRunner] env_overrides.json parse failed: #{err?.message ? err}"

  child = spawn 'coffee', [RUNNER],
    cwd: CWD
    detached: true
    stdio: ['ignore', outFd, errFd]
    env: Object.assign {}, process.env, envOverrides,
      EXEC: EXEC_ROOT
      CWD: CWD
      PWD: CWD
      HH_MM: runTag.hh_mm
      LOGDIR: runTag.logdir

  child.unref()
  child.on 'error', (err) ->
    markUiRunExited {
      pid: child.pid
      hh_mm: runTag.hh_mm
      logdir: runTag.logdir
    },
      status: 'failed'
      error: String(err?.message ? err)

  child.on 'exit', (code, signal) ->
    status = if code is 0 then 'done' else 'failed'
    markUiRunExited {
      pid: child.pid
      hh_mm: runTag.hh_mm
      logdir: runTag.logdir
    },
      status: status
      exit_code: code
      signal: signal ? null

    if repeatLoop.enabled
      if status is 'done'
        scheduleRepeatLaunch()
      else
        stopRepeatLoop()
        writeUiRunPatch
          loop_enabled: false
          countdown_seconds: null
          next_launch_at: null

  {
    pid: child.pid
    hh_mm: runTag.hh_mm
    logdir: runTag.logdir
  }

startMerge = (pipeName) ->
  stamp = buildRunTag()
  logDir = path.join(CWD, 'logs')
  fs.mkdirSync logDir, { recursive: true }
  logStem = "merge_#{stamp.hh_mm}"
  logPath = path.join(logDir, "#{logStem}.log")
  errPath = path.join(logDir, "#{logStem}.err")
  fs.writeFileSync logPath, '', 'utf8'
  fs.writeFileSync errPath, '', 'utf8'
  outFd = fs.openSync logPath, 'a'
  errFd = fs.openSync errPath, 'a'

  # merge_sqlite_dbs takes exactly `--pipe NAME` (and optionally
  # `--dry-run`); everything else is derived from BASE + pipeName.
  # Trainer is always `theaiguy@mac-mini.local:~/<project>/pipes/<pipe>`.
  child = spawn resolveCoffeeBin(), [MERGE_SCRIPT, '--pipe', pipeName],
    cwd: EXEC_ROOT
    detached: true
    stdio: ['ignore', outFd, errFd]
    env: Object.assign {}, process.env,
      EXEC: EXEC_ROOT
      CWD: CWD
      PWD: EXEC_ROOT

  payload =
    pipe: pipeName
    pid: child.pid
    status: 'launching'
    started_at: new Date().toISOString()
    finished_at: null
    logdir: logStem
    log_path: path.relative(CWD, logPath)
    err_path: path.relative(CWD, errPath)

  writeText MERGE_RUN_PATH, JSON.stringify(payload, null, 2)

  child.unref()
  child.on 'error', (err) ->
    markMergeRunExited {
      pid: child.pid
      logdir: logStem
    },
      status: 'failed'
      error: String(err?.message ? err)

  child.on 'exit', (code, signal) ->
    status = if code is 0 then 'done' else 'failed'
    markMergeRunExited {
      pid: child.pid
      logdir: logStem
    },
      status: status
      exit_code: code
      signal: signal ? null

  payload

handleLaunch = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  # 2026-09-11: `continue: true` means "resume where we left off" —
  # do NOT clobber step-*.json / pipeline.json / control_override.yaml.
  # The runner picks the current on-disk pipeline + step state as-is,
  # which lets a failed step retry without redoing the whole recipe.
  # Pending UI edits are IGNORED in continue mode: the button is for
  # resuming, not for applying new params.
  continueMode = payload.continue is true or payload.resume is true

  pipeline = String(payload.pipeline ? '').trim()
  # In continue mode, allow an empty pipeline — the on-disk override
  # already names the recipe. Otherwise, pipeline is required.
  return sendJson(res, 400, { ok: false, error: 'pipeline is required' }) unless continueMode or pipeline.length

  unless continueMode
    writeUiControl
      pending:
        pipeline: pipeline
        scene: payload.scene ? ''
        arrival: payload.arrival ? ''
        disturbance: payload.disturbance ? ''
        reflection: payload.reflection ? ''
        realization: payload.realization ? ''
      ui_values: if payload.ui_values? and typeof payload.ui_values is 'object' then payload.ui_values else {}

    if payload.continuous is true
      repeatLoop.enabled = true
      repeatLoop.payload = Object.assign {}, payload
      repeatLoop.delay_seconds = normalizeCooldownSeconds(payload.continuous_delay_seconds, 60)
      writeUiControl
        continuous: true
        continuous_delay_seconds: repeatLoop.delay_seconds
    else
      stopRepeatLoop()

  # In continue mode, don't rewrite control_override — reuse the
  # existing file so the runner reads the exact same recipe/params
  # the previous attempt used.
  override =
    if continueMode
      # Read what's already there so the response can report it.
      try
        text = fs.readFileSync(CONTROL_OVERRIDE_PATH, 'utf8')
        writeUiControl control_override_text: text
        yaml.load(text) ? {}
      catch
        {}
    else
      overrideText = if typeof payload.control_override_text is 'string' and payload.control_override_text.trim().length
        payload.control_override_text
      else
        dumpYaml buildOverrideObject(payload)
      writeUiControl control_override_text: overrideText
      writeControlOverrideText overrideText
  attachedRun = findActiveWorkspaceRun()
  if attachedRun?
    writeUiRunPatch
      status: 'running'
      pid: attachedRun.pid
      loop_enabled: repeatLoop.enabled
      countdown_seconds: null
      next_launch_at: null
    return sendJson res, 200,
      ok: true
      attached: true
      pid: attachedRun.pid
      hh_mm: attachedRun.hh_mm ? null
      logdir: attachedRun.logdir ? null
      override: override

  # In continue mode, preserve step-*.json + pipeline.json so the
  # runner resumes at the first not-done step.
  clearStepState() unless continueMode
  launch = startRunner()
  seedUiRun launch, override
  writeUiRunPatch
    loop_enabled: repeatLoop.enabled
    countdown_seconds: null
    next_launch_at: null

  sendJson res, 200,
    ok: true
    pid: launch.pid
    hh_mm: launch.hh_mm
    logdir: launch.logdir
    override: override

handleKill = (req, res) ->
  stopRepeatLoop()
  runPath = path.join(CWD, 'state', 'ui-run.json')
  run = readJson(runPath, {})
  pid = Number(run?.pid ? 0)
  targetKind = 'run'

  if Array.isArray(run?.other_runners) and run.other_runners.length > 0
    first = run.other_runners[0]
    if typeof first?.pid is 'number' and first.pid > 0
      pid = Number(first.pid)
      targetKind = 'blocking_runner'
    else
      firstText = String(first ? '')
      match = firstText.match(/^\s*(\d+)\b/)
      if match?
        pid = Number(match[1])
        targetKind = 'blocking_runner'

  return sendJson(res, 400, { ok: false, error: 'no active run pid recorded' }) unless pid > 0

  # 2026-09-07: SIGKILL immediately. Kill button = user's decision
  # that this run is done, no grace period needed. The prior
  # SIGTERM→SIGKILL escalation added 1s of latency and was moot
  # anyway — during in-process native MLX generation the main
  # thread is inside a C++ call and the JS SIGTERM handler can't
  # spin, so SIGTERM never landed cleanly. Skip the ritual: SIGKILL
  # the whole process group (negative pid — kills detached children:
  # git-lfs, python subprocs, MLX workers).
  killGroup = (target, sig) ->
    try
      process.kill -target, sig
    catch
      process.kill target, sig

  try
    killGroup pid, 'SIGKILL'
    console.log "[kill] SIGKILL sent to process group #{pid} (immediate kill -9)"
  catch err
    return sendJson res, 500,
      ok: false
      error: String(err?.message ? err)

  next = Object.assign {}, run,
    status: 'killing'
    kill_requested_at: new Date().toISOString()
    loop_enabled: false
    countdown_seconds: null
    next_launch_at: null
  writeText runPath, JSON.stringify(next, null, 2)

  sendJson res, 200,
    ok: true
    pid: pid
    target_kind: targetKind

# Stop the UI server process itself. A relaunched (Switch Pipe) server is
# detached + unref'd, so the browser is the only way to reach it; this is the
# kill switch. Respond first, then exit so the port is freed.
handleShutdownUi = (req, res) ->
  stopRepeatLoop()
  sendJson res, 200,
    ok: true
    pid: process.pid
    shutting_down: true
  setTimeout((-> process.exit(0)), 150)

# Save the current pipe's adapter to pipes/good_adapters/<name>/ so
# it can be compared with future training runs. Reads adapter_path
# from the active pipe's experiment.yaml (first step that has one),
# copies the .safetensors file + adapter_config.json + a small
# provenance metadata json.
handleCreatePipe = (req, res) ->
  # POST /api/create_pipe  body: {name, model, pipeline?}
  # Scaffolds pipes/<name>/ with an override.yaml pinning pipeline +
  # run.model (per model_identity.md — recipes MUST NOT default it),
  # plus empty state/, logs/, data/, out/ dirs and a README.md.
  # Returns {ok, name, cwd, cwd_relative} on success; the client is
  # responsible for calling /api/switch_pipe next if it wants to
  # switch the UI to the new pipe.
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  name  = String(payload.name ? '').trim()
  model = String(payload.model ? '').trim()
  pipelineName = String(payload.pipeline ? 'reset').trim() or 'reset'

  return sendJson(res, 400, { ok: false, error: 'name required' }) unless name.length
  return sendJson(res, 400, { ok: false, error: 'model (HuggingFace org/name) required' }) unless model.length
  # Safe pipe name: same rules as workspacePipeName / handleSwitchPipe.
  return sendJson(res, 400, { ok: false, error: "invalid name: use letters, digits, _, -, . only" }) unless /^[A-Za-z0-9._-]+$/.test(name)
  return sendJson(res, 400, { ok: false, error: "invalid name" }) if name in ['.', '..']
  # Model shape: <org>/<name> — permissive; ui_server doesn't reach
  # HF, download_model.coffee does. Reject only obviously bad shapes.
  return sendJson(res, 400, { ok: false, error: "invalid pipeline name" }) unless /^[A-Za-z0-9._-]+$/.test(pipelineName)

  pipeDir = path.join(PIPES_ROOT, name)
  return sendJson(res, 409, { ok: false, error: "pipes/#{name} already exists" }) if fs.existsSync(pipeDir)

  try
    fs.mkdirSync pipeDir, { recursive: true }
    # No per-pipe data/ dir — data files live at project BASE
    # (writer/data/) and resolve via the CWD→BASE→EXEC walk. A pipe
    # can shadow later by creating data/<file> under the pipe dir.
    for sub in ['state', 'logs', 'out']
      fs.mkdirSync path.join(pipeDir, sub), { recursive: true }

    overrideText = """
      # pipes/#{name}/override.yaml — created by /api/create_pipe
      # Pipeline selector + model identity. See GPT/model_identity.md.
      pipeline: #{pipelineName}

      run:
        model: #{model}
    """
    fs.writeFileSync path.join(pipeDir, 'override.yaml'), overrideText + '\n', 'utf8'

    # Pre-create the recipe-scoped override (the "human override" the
    # UI displays) with pipeline + run.model. Two reasons:
    #   1. Kills the readOverride() race — the file exists on first
    #      /api/status, no lazy materialization from legacy needed.
    #   2. UI's Human Override display shows the model.
    #
    # Yes, this duplicates run.model with legacy override.yaml. The
    # drift concern (from GPT/model_identity.md) has always been about
    # HUMAN edits diverging; a single writer here writes identical
    # values so there's no drift at creation. If a user later edits
    # one file's model, our readOverride fix (2026-08-26) no longer
    # infers from pipe name, so no automatic corruption path either.
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
    ok:            true
    name:          name
    cwd:           pipeDir
    cwd_relative:  path.relative(BASE, pipeDir)
    pipeline:      pipelineName
    model:         model

handleSaveGoodAdapter = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try payload = JSON.parse(bodyText ? '{}') catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }
  name = String(payload?.name ? '').trim()
  return sendJson(res, 400, { ok: false, error: 'name required' }) unless name.length
  # Safe-name check: letters, digits, _, -, . only. No slashes, no ..
  return sendJson(res, 400, { ok: false, error: "invalid name: use letters, digits, _, -, . only" }) unless /^[A-Za-z0-9._-]+$/.test(name)
  return sendJson(res, 400, { ok: false, error: "invalid name" }) if name in ['.', '..']

  expPath = path.join(CWD, 'experiment.yaml')
  return sendJson(res, 400, { ok: false, error: "no experiment.yaml — run the pipeline once first" }) unless fs.existsSync expPath
  experiment = null
  try
    experiment = yaml.load fs.readFileSync(expPath, 'utf8')
  catch err
    return sendJson res, 500, { ok: false, error: "cannot parse experiment.yaml: #{err?.message ? err}" }

  # Find first step with adapter_path set.
  RESERVED = ['run', 'artifacts', 'pipeline']
  sourceStep = null
  sourcePath = null
  for own k, v of experiment when k not in RESERVED and v? and typeof v is 'object' and v.run?
    ap = v.adapter_path
    if typeof ap is 'string' and ap.trim().length
      sourceStep = k
      sourcePath = ap.trim()
      break
  return sendJson(res, 400, { ok: false, error: "no step in experiment.yaml has adapter_path set" }) unless sourcePath?

  # Resolve to absolute path under the pipe's CWD.
  absSource = if path.isAbsolute(sourcePath) then sourcePath else path.join(CWD, sourcePath)
  return sendJson(res, 404, { ok: false, error: "adapter file not found: #{path.relative(CWD, absSource)}" }) unless fs.existsSync absSource

  # adapter_config.json sits alongside the adapter file (or IS the dir).
  sourceIsFile = fs.statSync(absSource).isFile()
  configDir = if sourceIsFile then path.dirname(absSource) else absSource
  weightsSource = if sourceIsFile then absSource else path.join(absSource, 'adapters.safetensors')
  configSource = path.join(configDir, 'adapter_config.json')
  return sendJson(res, 404, { ok: false, error: "adapter weights not found: #{path.relative(CWD, weightsSource)}" }) unless fs.existsSync weightsSource
  return sendJson(res, 404, { ok: false, error: "adapter_config.json not found in #{path.relative(CWD, configDir)}" }) unless fs.existsSync configSource

  # Refuse to overwrite an existing good adapter.
  destDir = path.join(CWD, 'build', 'good_adapters', name)
  if fs.existsSync destDir
    return sendJson res, 409, { ok: false, error: "a good adapter named '#{name}' already exists (#{path.relative(CWD, destDir)}). Pick a different name or delete the existing one." }

  fs.mkdirSync destDir, { recursive: true }
  destWeights = path.join(destDir, 'adapters.safetensors')
  destConfig = path.join(destDir, 'adapter_config.json')
  fs.copyFileSync weightsSource, destWeights
  fs.copyFileSync configSource, destConfig
  # Provenance: which pipe, which step, which checkpoint file, when.
  meta =
    saved_at: new Date().toISOString()
    saved_as: name
    source_pipe: path.basename(CWD)
    source_step: sourceStep
    source_adapter_path: sourcePath
    source_weights_abs: weightsSource
    source_config_abs: configSource
  fs.writeFileSync path.join(destDir, 'meta.json'), JSON.stringify(meta, null, 2), 'utf8'

  sendJson res, 200,
    ok: true
    name: name
    source: "step #{sourceStep}: #{sourcePath}"
    destination: path.relative(CWD, destDir)

handleControl = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  pipeline = String(payload.pipeline ? '').trim()
  current = readUiControl()
  controlOverride = readControlOverride()
  legacyOverride = readLegacyOverride()
  next =
    continuous: if payload.continuous is true then true else false
    continuous_delay_seconds: normalizeCooldownSeconds(payload.continuous_delay_seconds, normalizeCooldownSeconds(current?.continuous_delay_seconds, 60))
    pending:
      pipeline: if pipeline.length then pipeline else (current?.pending?.pipeline ? controlOverride.pipeline ? legacyOverride.pipeline ? '')
      scene: String(payload.scene ? '')
      arrival: String(payload.arrival ? '')
      disturbance: String(payload.disturbance ? '')
      reflection: String(payload.reflection ? '')
      realization: String(payload.realization ? '')
    ui_values: if payload.ui_values? and typeof payload.ui_values is 'object'
      Object.assign {}, (current?.ui_values ? {}), payload.ui_values
    else
      (current?.ui_values ? {})
    control_override_text: if typeof payload.control_override_text is 'string' then payload.control_override_text else null

  unless typeof payload.control_override_text is 'string'
    next.control_override_text = dumpYaml buildOverrideObject
      pipeline: next.pending.pipeline
      scene: next.pending.scene
      arrival: next.pending.arrival
      disturbance: next.pending.disturbance
      reflection: next.pending.reflection
      realization: next.pending.realization
      ui_values: next.ui_values

  writeUiControl next
  controlOverride = writeControlOverrideText next.control_override_text
  if next.continuous is true
    repeatLoop.enabled = true
    repeatLoop.delay_seconds = next.continuous_delay_seconds
  else
    stopRepeatLoop()
    writeUiRunPatch
      loop_enabled: false
      countdown_seconds: null
      next_launch_at: null

  sendJson res, 200,
    ok: true
    control: next
    control_override: controlOverride

handleHumanOverride = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  text = if typeof payload.human_override_text is 'string' then payload.human_override_text else ''
  pipelineTarget = if typeof payload.pipeline is 'string' and payload.pipeline.trim().length then payload.pipeline else null
  override = writeHumanOverrideText text, pipelineTarget
  sendJson res, 200,
    ok: true
    override: override

handleClearPipelineState = (req, res) ->
  pipelinePath = path.join(CWD, 'pipeline.json')
  removed = false
  if fs.existsSync(pipelinePath)
    fs.unlinkSync pipelinePath
    removed = true

  sendJson res, 200,
    ok: true
    removed: removed

# Delete the accumulated per-run log files (pipe_HH_MM.log/.err) from the
# pipe's logs/ dir. logs/ is transient single-run scratch, so this is safe;
# it just keeps the Logs panel from growing without bound.
handleClearLogs = (req, res) ->
  logDir = path.join(CWD, 'logs')
  removed = 0
  if fs.existsSync(logDir)
    for name in fs.readdirSync(logDir) when /^[A-Za-z0-9_-]+_\d{2}_\d{2}\.(log|err)$/.test(name)
      try
        fs.unlinkSync path.join(logDir, name)
        removed += 1
      catch
        null
  sendJson res, 200,
    ok: true
    removed: removed

# Delete the contents of the pipe's out/ dir (top-level files and subdirs like
# out/eval/). out/ is transient single-run scratch — the next run regenerates
# what it needs — so this just clears the Outputs panel's accumulated files.
handleClearOutput = (req, res) ->
  outDir = path.join(CWD, 'out')
  removed = 0
  if fs.existsSync(outDir)
    for name in fs.readdirSync(outDir)
      try
        fs.rmSync path.join(outDir, name), { recursive: true, force: true }
        removed += 1
      catch
        null
  sendJson res, 200,
    ok: true
    removed: removed

handleSwitchPipe = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  pipeName = String(payload.pipe ? '').trim()
  if pipeName.length
    return sendJson(res, 400, { ok: false, error: 'invalid pipe name' }) if pipeName.includes('/') or pipeName.includes(path.sep) or pipeName is '.' or pipeName is '..'
    targetCwd = path.join(PIPES_ROOT, pipeName)
    return sendJson(res, 404, { ok: false, error: 'pipe directory not found' }) unless fs.existsSync(targetCwd) and fs.statSync(targetCwd).isDirectory()
  else
    targetCwd = CWD          # empty pipe => restart current workspace in place

  fs.mkdirSync path.join(targetCwd, 'state'), { recursive: true }
  fs.mkdirSync path.join(targetCwd, 'logs'), { recursive: true }

  sendJson res, 200,
    ok: true
    pipe: pipeName
    cwd: targetCwd
    restarting: true

  # Relaunch a ui_server.coffee, preferring the most project-owned one so the
  # project's UI fixes survive a pipe switch:
  #   1. the pipe's own ui_server.coffee (rare), then
  #   2. the project BASE ui_server.coffee (this file — the customized one), then
  #   3. the shipped package copy under EXEC_ROOT (last resort).
  # Falling straight to EXEC_ROOT (the old behavior) silently swapped in the
  # package's stock UI after every switch, dropping all project customizations.
  uiServerPath = path.join(targetCwd, 'ui_server.coffee')
  uiServerPath = path.join(BASE, 'ui_server.coffee') unless fs.existsSync(uiServerPath)
  uiServerPath = path.join(EXEC_ROOT, 'ui_server.coffee') unless fs.existsSync(uiServerPath)

  # Re-assert the critical env vars INSIDE the exec, via `env VAR=val …`. The
  # `-l` login shell re-sources the user's profile, which can export its own
  # EXEC (e.g. a dev pipeline checkout) and clobber the env passed to spawn —
  # that would misresolve EXEC_ROOT/BASE on the relaunched UI. Setting them on
  # the exec'd process happens AFTER profile sourcing, so they win.
  reassert = [
    "EXEC=#{JSON.stringify(EXEC_ROOT)}"
    "CWD=#{JSON.stringify(targetCwd)}"
    "UI_PORT=#{JSON.stringify(String(PORT))}"
    "UI_BIND_MODE=#{JSON.stringify(UI_BIND_MODE)}"
  ].join(' ')
  launchArgs = ['-lc', "sleep 1; exec env #{reassert} coffee #{JSON.stringify(uiServerPath)}"]
  child = spawn 'bash', launchArgs,
    cwd: targetCwd
    detached: true
    stdio: 'ignore'
    env: Object.assign {}, process.env,
      EXEC: EXEC_ROOT
      CWD: targetCwd
      UI_PORT: String(PORT)
      UI_BIND_MODE: UI_BIND_MODE

  child.unref()
  setTimeout((-> process.exit(0)), 150)

handleMergePipe = (req, res) ->
  bodyText = await readRequestBody req
  payload = {}
  try
    payload = JSON.parse(bodyText ? '{}')
  catch
    return sendJson res, 400, { ok: false, error: 'invalid json body' }

  pipeName = workspacePipeName(CWD)
  return sendJson(res, 400, { ok: false, error: 'current workspace is not under pipes/' }) unless pipeName?

  mergeRun = readMergeRun()
  if mergeRun.is_process_alive is true and Number(mergeRun.pid ? 0) > 0 and mergeRun.status in ['launching', 'running']
    return sendJson res, 200,
      ok: true
      attached: true
      merge_run: mergeRun

  launch = startMerge pipeName
  sendJson res, 200,
    ok: true
    merge_run: launch

# Resolve the static UI: project-owned `CWD/ui/` wins; fall back to
# the runner-shipped `EXEC_ROOT/ui/` if the project hasn't run
# `pipeline ui:init` yet. This is what makes the UI a
# project-customizable surface.
resolveUiAsset = (rel) ->
  # CWD/ui (pipe-local override) → BASE/ui (project-owned UI) → EXEC/ui (package).
  # The BASE tier is what serves the project's own ui/ after a pipe switch, when
  # CWD is a pipe dir with no ui/ of its own — without it, resolution skipped
  # straight to the package copy under node_modules (and 404'd if absent).
  for root in [CWD, BASE, EXEC_ROOT]
    candidate = path.join(root, 'ui', rel)
    return candidate if fs.existsSync(candidate)
  path.join(EXEC_ROOT, 'ui', rel)

# Mirror of resolveUiAsset for data/. Lets shared data files (story
# libraries, dramatic grammars, i-ching tables, jim.md) live at the
# project BASE — /writer/data/ — instead of duplicating per-pipe. A
# pipe can still shadow by dropping its own <pipe>/data/<file> in.
resolveDataAsset = (rel) ->
  for root in [CWD, BASE, EXEC_ROOT]
    candidate = path.join(root, 'data', rel)
    return candidate if fs.existsSync(candidate)
  path.join(EXEC_ROOT, 'data', rel)

server = http.createServer (req, res) ->
  url = req.url ? '/'

  # Deep-link URL to jump to a specific pipe.
  #   http://mac-mini.local:4311/pipe/<pipe-name>
  #   http://mac-mini.local:4311/?pipe=<pipe-name>
  # Both perform the same in-place ui_server respawn as
  # POST /api/switch_pipe, then send an HTML page that reloads
  # after 3s so the browser picks up the fresh workspace UI.
  pipeName = null
  if url.startsWith '/pipe/'
    pipeName = decodeURIComponent(url.slice('/pipe/'.length).split('?')[0].split('#')[0])
  else if url.startsWith '/?pipe='
    pipeName = decodeURIComponent(url.slice('/?pipe='.length).split('&')[0].split('#')[0])
  if pipeName?
    pipeName = String(pipeName).trim()
    if not pipeName.length or pipeName.includes('/') or pipeName.includes(path.sep) or pipeName is '.' or pipeName is '..'
      res.writeHead 400, {'Content-Type': 'text/html; charset=utf-8'}
      return res.end "<h3>bad pipe name: <code>#{pipeName}</code></h3><p><a href='/'>home</a></p>"
    targetCwd = path.join(PIPES_ROOT, pipeName)
    unless fs.existsSync(targetCwd) and fs.statSync(targetCwd).isDirectory()
      res.writeHead 404, {'Content-Type': 'text/html; charset=utf-8'}
      return res.end "<h3>pipe not found: <code>#{pipeName}</code></h3><p><a href='/'>home</a></p>"
    # Reuse the switch machinery — build a fake req + res.
    fakeReq =
      on: (evt, cb) -> cb(Buffer.from(JSON.stringify({pipe: pipeName}))) if evt is 'data'
      _emitEnd: null
    fakeReq.on = (evt, cb) ->
      if evt is 'data' then cb(Buffer.from(JSON.stringify({pipe: pipeName})))
      else if evt is 'end' then setImmediate(cb)
    fakeRes =
      writeHead: -> null
      end: -> null
      _fake: true
    # Kick off the switch (async, fire-and-forget).
    Promise.resolve(handleSwitchPipe(fakeReq, fakeRes)).catch (err) ->
      console.error "[deep-link switch] #{err?.message ? err}"
    # Send the user a "hang on, switching" page that reloads to `/`.
    res.writeHead 200, {'Content-Type': 'text/html; charset=utf-8'}
    res.end """
      <!doctype html><meta charset="utf-8">
      <title>switching to #{pipeName}…</title>
      <meta http-equiv="refresh" content="3;url=/">
      <style>body{font-family:-apple-system,sans-serif;padding:40px;color:#333}</style>
      <h3>Switching workspace to <code>#{pipeName}</code>…</h3>
      <p>UI is respawning. This page reloads in ~3 seconds.</p>
      <p><a href="/">Go now</a></p>
    """
    return

  if url is '/' or url is '/index.html'
    return sendHtml res, resolveUiAsset('index.html')
  if url is '/api/status'
    return Promise.resolve(buildStatus()).then (status) ->
      sendJson res, 200, status
    .catch (err) ->
      sendJson res, 500, { ok: false, error: String(err?.message ? err) }
  if url.startsWith '/api/panel/'
    name = decodeURIComponent(url.slice('/api/panel/'.length).split('?')[0])
    return Promise.resolve(initPanelRegistry().data(name, {run: normalizeUiRun(readJson(path.join(CWD, 'state', 'ui-run.json'), {}))})).then (data) ->
      if data is null
        sendJson res, 404, { ok: false, error: "panel not found or endpoint failed: #{name}" }
      else
        sendJson res, 200, { ok: true, name: name, data: data }
    .catch (err) ->
      sendJson res, 500, { ok: false, error: String(err?.message ? err) }
  if url.startsWith('/api/step_detail?')
    # Return the state file and params file for one step so the SVG
    # click-popup can show status + inputs and offer a restart button.
    query = new URL(url, 'http://127.0.0.1').searchParams
    name = String(query.get('name') ? '').trim()
    return sendJson(res, 400, { ok: false, error: 'name required' }) unless name.length
    return sendJson(res, 400, { ok: false, error: "invalid step name: #{name}" }) if name.includes('/') or name.includes(path.sep) or name in ['.', '..']
    stateFile = path.join(CWD, 'state', "step-#{name}.json")
    paramsFile = path.join(CWD, 'params', "#{name}.yaml")
    state = null
    stateErr = null
    if fs.existsSync stateFile
      try
        state = JSON.parse fs.readFileSync(stateFile, 'utf8')
      catch err
        stateErr = String(err?.message ? err)
    params_text = null
    paramsErr = null
    if fs.existsSync paramsFile
      try
        params_text = fs.readFileSync paramsFile, 'utf8'
      catch err
        paramsErr = String(err?.message ? err)
    # 2026-09-07: liveness override. step-<name>.json is only rewritten
    # when the runner exits cleanly. If the runner crashed / was killed
    # mid-step, the file is left with status: 'running' forever. The
    # UI keeps showing "running" even though the process is dead. Fix:
    # check the parent runner's pid (from state/ui-run.json). If the
    # pid is not alive and the step file says 'running', override the
    # returned state to 'crashed_stale' so the UI is truthful. Leaves
    # the on-disk file alone — the startup sweep in pipeline_runner
    # will rewrite it to 'crashed' next run.
    if state?.status is 'running'
      try
        runFile = path.join(CWD, 'state', 'ui-run.json')
        if fs.existsSync runFile
          runData = JSON.parse fs.readFileSync(runFile, 'utf8')
          runPid = Number(runData?.pid ? 0)
          if runPid > 0 and not isProcessAlive(runPid)
            state = Object.assign {}, state,
              status: 'crashed_stale'
              liveness_override: true
              liveness_note: "runner pid #{runPid} is dead; step file says 'running' but no process is alive. On-disk file will be rewritten on next run by startup sweep."
              runner_pid: runPid
      catch
        null
    return sendJson res, 200,
      ok: true
      name: name
      state: state
      state_error: stateErr
      state_path: path.relative(CWD, stateFile)
      params_text: params_text
      params_error: paramsErr
      params_path: path.relative(CWD, paramsFile)
  if url is '/api/step_restart' and req.method is 'POST'
    # Restart via the runner's `restart_here` protocol
    # (pipeline_runner.coffee §6). Set restart_here=true on the
    # target step's state file — the runner picks that up at
    # startup, deletes state for that step + every DOWNSTREAM step,
    # clears the flag, and runs. **ONLY the target step is marked.**
    # Upstream state, params, and control_override are left exactly
    # as-is. If an upstream step's declared output file is missing
    # on disk the runner may block waiting for it — that's the
    # operator's problem to resolve (delete its state, then trigger
    # a full launch, or restart that upstream step directly). We
    # deliberately do NOT cascade upstream: previous auto-cascade
    # behavior led to confusion about which prior steps got
    # regenerated silently.
    bodyText = await readRequestBody req
    payload = {}
    try payload = JSON.parse(bodyText ? '{}') catch
      return sendJson res, 400, { ok: false, error: 'invalid json body' }
    name = String(payload?.name ? '').trim()
    return sendJson(res, 400, { ok: false, error: 'name required' }) unless name.length
    return sendJson(res, 400, { ok: false, error: "invalid step name: #{name}" }) if name.includes('/') or name.includes(path.sep) or name in ['.', '..']

    attachedRun = findActiveWorkspaceRun()
    if attachedRun?
      return sendJson res, 200,
        ok: true
        attached: true
        pid: attachedRun.pid
        note: "a runner is already alive; restart_here NOT set (would race with the running pipeline). Kill the run first, then retry."

    # Load experiment.yaml only to validate the target step exists.
    experimentPath = path.join(CWD, 'experiment.yaml')
    unless fs.existsSync experimentPath
      return sendJson res, 400, { ok: false, error: "no experiment.yaml — run the pipeline once before using restart" }
    experiment = null
    try
      experiment = yaml.load fs.readFileSync(experimentPath, 'utf8')
    catch err
      return sendJson res, 500, { ok: false, error: "cannot parse experiment.yaml: #{err?.message ? err}" }

    RESERVED = ['run', 'artifacts', 'pipeline']
    hasStep = false
    for own k, v of experiment when k not in RESERVED and v? and typeof v is 'object' and v.run?
      hasStep = true if k is name
    return sendJson(res, 404, { ok: false, error: "step '#{name}' not found in experiment.yaml" }) unless hasStep

    # Mark ONLY the target step with restart_here=true.
    marked = false
    stateFile = path.join(CWD, 'state', "step-#{name}.json")
    if fs.existsSync stateFile
      try
        st = JSON.parse fs.readFileSync(stateFile, 'utf8')
      catch err
        return sendJson res, 500, { ok: false, error: "cannot read #{path.relative(CWD, stateFile)}: #{err?.message ? err}" }
      st.restart_here = true
      st.updated_at = new Date().toISOString()
      fs.writeFileSync stateFile, JSON.stringify(st, null, 2), 'utf8'
      marked = true
    # If no state file, the step is already unmarked in the runner's
    # eyes and will run on launch — no write needed.

    # pipeline.json is the "we crashed last time" gate — its presence
    # causes the runner to exit at startup. Remove so restart can run.
    pipelinePath = path.join(CWD, 'pipeline.json')
    removedPipelineJson = false
    if fs.existsSync pipelinePath
      fs.unlinkSync pipelinePath
      removedPipelineJson = true

    launch = startRunner()
    seedUiRun launch, readControlOverride()
    return sendJson res, 200,
      ok: true
      name: name
      restart_here_marked: (if marked then [name] else [])
      already_unmarked: (if marked then [] else [name])
      removed_pipeline_json: removedPipelineJson
      pid: launch.pid
      hh_mm: launch.hh_mm
      logdir: launch.logdir
  if url is '/api/pipeline_svg' or url.startsWith('/api/pipeline_svg?')
    # Render a recipe's DAG SVG using pipeline_svg.coffee.
    # Default: read the CURRENT pipe's experiment.yaml (last-run
    # config). With ?pipeline=<name>, load that recipe's config
    # directly (config/<name>.yaml + expandIncludes). Lets the UI
    # preview a different recipe's graph BEFORE running it.
    query = new URL(url, 'http://127.0.0.1').searchParams
    requestedPipeline = String(query.get('pipeline') ? '').trim()
    doc = null
    try
      if requestedPipeline.length
        configPath = resolveConfigPath(requestedPipeline)
        unless configPath? and fs.existsSync(configPath)
          res.writeHead 404, { 'Content-Type': 'text/plain; charset=utf-8' }
          return res.end "no config for recipe '#{requestedPipeline}'"
        # Preview: just read the recipe file. Includes are not
        # expanded here; the graph will show the recipe's direct
        # structure. Good enough for "what steps does this recipe
        # run" without needing full runner semantics.
        doc = readYaml(configPath)
      else
        expPath = path.join(CWD, 'experiment.yaml')
        unless fs.existsSync expPath
          res.writeHead 404, { 'Content-Type': 'text/plain; charset=utf-8' }
          return res.end 'no experiment.yaml yet — run the pipeline once, then reload.'
        doc = yaml.load fs.readFileSync(expPath, 'utf8')
      scriptPath = path.join(BASE, 'pipeline_svg.coffee')
      delete require.cache[require.resolve(scriptPath)] if require.cache[require.resolve(scriptPath)]?
      { renderSvg } = require scriptPath
      svg = renderSvg doc
      res.writeHead 200,
        'Content-Type': 'image/svg+xml; charset=utf-8'
        'Cache-Control': 'no-store'
      return res.end svg
    catch err
      res.writeHead 500, { 'Content-Type': 'text/plain; charset=utf-8' }
      return res.end "[pipeline_svg] #{err?.message ? err}"
  if url.startsWith('/api/file?')
    query = new URL(url, 'http://127.0.0.1').searchParams
    relativePath = query.get('path')
    payload = readViewerFile(relativePath)
    return sendJson(res, 404, { ok: false, error: 'file not found' }) unless payload?
    return sendJson res, 200, { ok: true, file: payload }
  if url is '/api/launch' and req.method is 'POST'
    return Promise.resolve(handleLaunch(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/control' and req.method is 'POST'
    return Promise.resolve(handleControl(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/human_override' and req.method is 'POST'
    return Promise.resolve(handleHumanOverride(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/clear_pipeline_state' and req.method is 'POST'
    return Promise.resolve(handleClearPipelineState(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/clear_logs' and req.method is 'POST'
    return Promise.resolve(handleClearLogs(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/clear_output' and req.method is 'POST'
    return Promise.resolve(handleClearOutput(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/create_pipe' and req.method is 'POST'
    return Promise.resolve(handleCreatePipe(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/switch_pipe' and req.method is 'POST'
    return Promise.resolve(handleSwitchPipe(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/merge_pipe' and req.method is 'POST'
    # Feature-gate: `merge_sqlite_dbs.coffee` is a writeStory-specific
    # helper not shipped with the runner. Projects that need it can
    # drop it next to `pipeline_runner.coffee` and the endpoint
    # activates automatically.
    unless fs.existsSync(MERGE_SCRIPT)
      return sendJson res, 501,
        ok: false
        error: 'merge feature not available — merge_sqlite_dbs.coffee not present'
    return Promise.resolve(handleMergePipe(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/kill' and req.method is 'POST'
    return Promise.resolve(handleKill(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/save_good_adapter' and req.method is 'POST'
    return Promise.resolve(handleSaveGoodAdapter(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  if url is '/api/shutdown_ui' and req.method is 'POST'
    return Promise.resolve(handleShutdownUi(req, res)).catch (err) ->
      sendJson res, 500,
        ok: false
        error: String(err?.message ? err)
  res.writeHead 404, 'Content-Type': 'text/plain; charset=utf-8'
  res.end 'not found'

server.listen PORT, HOST, ->
  console.log "[ui_server] listening on http://#{HOST}:#{PORT}"

setInterval ->
  return unless repeatLoop.enabled and repeatLoop.next_launch_at?
  run = readJson path.join(CWD, 'state', 'ui-run.json'), {}
  return unless run?.status is 'cooldown'
  remainingMs = Math.max(0, new Date(repeatLoop.next_launch_at).getTime() - Date.now())
  seconds = Math.ceil(remainingMs / 1000)
  writeUiRunPatch
    loop_enabled: true
    countdown_seconds: seconds
    next_launch_at: repeatLoop.next_launch_at
, 1000
