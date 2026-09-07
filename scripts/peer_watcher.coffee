# peer_watcher.coffee — runs on the mini, emits multiplexed change
# events over stdout for a single laptop-side consumer.
#
# Line format (each event is one line, JSON-safe):
#   [UIRUN pipe=<name>] {...ui-run.json contents...}
#   [MANIFEST pipe=<name>] {...recipe_manifest.json contents...}
#   [LOG pipe=<name>] <literal log line from the currently-tailed logdir>
#   [INFO pipe=<name>] <human-readable notice>
#   [ERROR pipe=<name>] <error message>
#   [HEARTBEAT pipe=_watcher] {"t":ISO,"pipes":N,"tails":N}
#
# One consumer subscribes via `ssh peer 'coffee ~/writer/scripts/peer_watcher.coffee'`
# and splits by prefix. Order across streams is preserved because there is
# one stdout — perfect causality for reasoning about "manifest update vs
# ui-run update, which came first?"
#
# 2026-09-07: pilot for the streaming-Memo architecture (per GPT/txtl.md
# design discussion). Replaces polling-based drivers.

fs = require 'fs'
path = require 'path'
{spawn} = require 'child_process'

PIPES_ROOT = path.join process.env.HOME, 'writer', 'pipes'

emit = (kind, pipeName, payload) ->
  body =
    if typeof payload is 'string' then payload
    else
      try JSON.stringify(payload)
      catch then "(unserializable: #{typeof payload})"
  process.stdout.write "[#{kind} pipe=#{pipeName}] #{body}\n"

lastUiRun = {}         # pipe → last-serialized ui-run.json (dedupe)
lastManifest = {}      # pipe → last-serialized recipe_manifest.json
tailProcs = {}         # pipe → {proc, logFile}
watchers = {}          # pipe → [fs watchers]

emitUiRun = (pipeName) ->
  runFile = path.join PIPES_ROOT, pipeName, 'state', 'ui-run.json'
  return unless fs.existsSync runFile
  try
    text = fs.readFileSync runFile, 'utf8'
    return if lastUiRun[pipeName] is text
    lastUiRun[pipeName] = text
    data = JSON.parse text
    emit 'UIRUN', pipeName, data
    # When logdir changes, switch our tail to the new log file.
    if data?.logdir? and data.logdir.length
      switchLogTail pipeName, data.logdir
  catch err
    emit 'ERROR', pipeName, "ui-run read/parse: #{err?.message ? err}"

emitManifest = (pipeName) ->
  mFile = path.join PIPES_ROOT, pipeName, 'recipe_manifest.json'
  return unless fs.existsSync mFile
  try
    text = fs.readFileSync mFile, 'utf8'
    return if lastManifest[pipeName] is text
    lastManifest[pipeName] = text
    data = JSON.parse text
    emit 'MANIFEST', pipeName, data
  catch err
    emit 'ERROR', pipeName, "manifest read/parse: #{err?.message ? err}"

switchLogTail = (pipeName, logdir) ->
  logFile = path.join PIPES_ROOT, pipeName, 'logs', "#{logdir}.log"
  # Wait a beat for the log file to exist if the launch is fresh.
  unless fs.existsSync logFile
    setTimeout (-> switchLogTail pipeName, logdir), 1000
    return
  existing = tailProcs[pipeName]
  return if existing?.logFile is logFile
  if existing?.proc?
    try existing.proc.kill 'SIGTERM'
    delete tailProcs[pipeName]
  proc = spawn 'tail', ['-n', '0', '-F', logFile]
  proc.stdout.setEncoding 'utf8'
  buf = ''
  proc.stdout.on 'data', (chunk) ->
    buf += chunk
    lines = buf.split '\n'
    buf = lines.pop()   # partial trailing line
    for line in lines
      emit 'LOG', pipeName, line
  proc.on 'exit', ->
    delete tailProcs[pipeName] if tailProcs[pipeName]?.logFile is logFile
  tailProcs[pipeName] = {proc, logFile}
  emit 'INFO', pipeName, "tailing #{logdir}.log"

watchPipe = (pipeName) ->
  pipeDir = path.join PIPES_ROOT, pipeName
  return unless fs.existsSync(pipeDir) and fs.statSync(pipeDir).isDirectory()
  return if watchers[pipeName]?
  ws = []
  stateDir = path.join pipeDir, 'state'
  if fs.existsSync stateDir
    try
      w = fs.watch stateDir, {}, (ev, fname) ->
        emitUiRun pipeName if fname is 'ui-run.json'
      ws.push w
    catch err
      emit 'ERROR', pipeName, "watch state/: #{err?.message ? err}"
  try
    w = fs.watch pipeDir, {}, (ev, fname) ->
      emitManifest pipeName if fname is 'recipe_manifest.json'
    ws.push w
  catch err
    emit 'ERROR', pipeName, "watch pipe root: #{err?.message ? err}"
  watchers[pipeName] = ws
  # Emit current state immediately so late subscribers see the baseline.
  emitUiRun pipeName
  emitManifest pipeName

# Initial pass: subscribe to every existing pipe.
scan = ->
  return unless fs.existsSync PIPES_ROOT
  for name in fs.readdirSync PIPES_ROOT
    continue if name.startsWith('.')
    watchPipe name

# Watch PIPES_ROOT for new pipe dirs (create_pipe events).
try
  fs.watch PIPES_ROOT, {}, (ev, fname) ->
    return unless fname and not fname.startsWith('.')
    setTimeout (-> watchPipe fname), 500
catch err
  emit 'ERROR', '_watcher', "watch PIPES_ROOT: #{err?.message ? err}"

emit 'INFO', '_watcher', "starting; PIPES_ROOT=#{PIPES_ROOT}"
scan()

# Heartbeat every 30s. Doubles as liveness probe for the consumer.
setInterval ->
  emit 'HEARTBEAT', '_watcher',
    t: new Date().toISOString()
    pipes: Object.keys(watchers).length
    tails: Object.keys(tailProcs).length
, 30_000

# Graceful shutdown on SIGTERM (ssh disconnect).
process.on 'SIGTERM', ->
  emit 'INFO', '_watcher', 'received SIGTERM; stopping tails'
  for _, entry of tailProcs
    try entry.proc.kill 'SIGTERM'
  process.exit 0
