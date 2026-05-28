#!/usr/bin/env coffee
# =====================================================================
#   merge_sqlite_dbs.coffee  —  pull LoRA training results from a remote
#   (the mac-mini training box) into this project.
# =====================================================================
#   Layout (asymmetric, by design):
#     server (trainer, e.g. mac-mini)  — PER-PIPE: pipes/<pipe>/runtime.sqlite,
#       pipes/<pipe>/build/adapter. The trainer pipe owns its training output.
#     receiver (laptop)  — PROJECT-LEVEL SHARED: BASE/runtime.sqlite and
#       BASE/build/adapter. All pipes on the receiver share these common
#       resources (different algorithms, same db + adapter).
#     BASE (the project root, where pipes/ and build/ live) is resolved from
#       the EXEC env the UI passes, NOT process.cwd() (the UI spawns this
#       with cwd = EXEC_ROOT under node_modules).
#
#   Authority policy (unchanged): the local machine is authoritative for
#   stories / KAG; the remote contributes ONLY the lora_* tables and the
#   trained build/adapter.
#
fs = require 'fs'
os = require 'os'
path = require 'path'
{ execFileSync } = require 'child_process'
{ DatabaseSync } = require 'node:sqlite'

# --- BASE resolution: same rule as the runner/UI. EXEC is the runner dir
#     (…/node_modules/@jahbini/pipeline when installed); BASE is the dir
#     that contains that node_modules. Standalone (no node_modules
#     ancestor), BASE == the script's own dir.
EXEC = process.env.EXEC ? __dirname
BASE = do ->
  marker = "#{path.sep}node_modules#{path.sep}"
  idx = EXEC.indexOf(marker)
  if idx isnt -1 then EXEC.slice(0, idx) else __dirname

printUsage = ->
  console.log """
usage:
  coffee merge_sqlite_dbs.coffee [options]

layout:
  server (trainer)  — PER-PIPE:    <remote-base>/pipes/<pipe>/{runtime.sqlite, build/adapter}
  receiver (laptop) — PROJECT-LEVEL SHARED: <BASE>/{runtime.sqlite, build/adapter}
  pipes on the receiver consume the shared db + adapter (different algorithms,
  same common resources).

optional:
  --pipe NAME                      pipe name on the server (trainer side)
  --local-pipe NAME                ignored; local is always shared at BASE
  --remote-pipe NAME               remote pipe name under <remote-base>/pipes
  --remote-host HOST               default: mac-mini.local
  --remote-user USER               default: theaiguy
  --remote-base PATH               remote project root (default: /Users/<user>/writediary)
  --remote-db PATH                 default: <remote-base>/pipes/<pipe>/runtime.sqlite
  --remote-adapter-dir PATH        default: <remote-base>/pipes/<pipe>/build/adapter
  --local-db PATH                  default: <BASE>/runtime.sqlite  (SHARED)
  --local-adapter-dir PATH         default: <BASE>/build/adapter   (SHARED)
  --dry-run

authority policy:
  receiver keeps: stories, story_parts, expanded_story_parts, kag_entries
  server contributes only: lora_story_usage, lora_training_runs,
  lora_training_run_stories, lora_trained_stories, and build/adapter
"""

args = process.argv.slice 2
opts =
  pipe: null
  localPipe: null
  remotePipe: null
  remoteHost: 'mac-mini.local'
  remoteUser: 'theaiguy'
  remoteBase: null            # set after parsing, derived from remoteUser
  remoteDb: null              # derived from remoteBase + pipe unless overridden
  remoteAdapterDir: null      # derived from remoteBase unless overridden
  localDb: null               # derived from BASE + pipe unless overridden
  localAdapterDir: null       # defaults to shared <BASE>/build/adapter
  dryRun: false

i = 0
while i < args.length
  arg = args[i]
  if arg is '--pipe'
    i += 1; opts.pipe = args[i]
  else if arg is '--local-pipe'
    i += 1; opts.localPipe = args[i]
  else if arg is '--remote-pipe'
    i += 1; opts.remotePipe = args[i]
  else if arg is '--remote-host'
    i += 1; opts.remoteHost = args[i]
  else if arg is '--remote-user'
    i += 1; opts.remoteUser = args[i]
  else if arg is '--remote-base'
    i += 1; opts.remoteBase = args[i]
  else if arg is '--remote-db'
    i += 1; opts.remoteDb = args[i]
  else if arg is '--remote-adapter-dir'
    i += 1; opts.remoteAdapterDir = args[i]
  else if arg is '--local-db'
    i += 1; opts.localDb = args[i]
  else if arg is '--local-adapter-dir'
    i += 1; opts.localAdapterDir = args[i]
  else if arg is '--dry-run'
    opts.dryRun = true
  else if arg in ['-h', '--help']
    printUsage(); process.exit 0
  else
    throw new Error "Unknown arg #{arg}"
  i += 1

pipeName = if opts.pipe? and String(opts.pipe).trim().length then String(opts.pipe).trim() else null
localPipeName = if opts.localPipe? and String(opts.localPipe).trim().length then String(opts.localPipe).trim() else pipeName
remotePipeName = if opts.remotePipe? and String(opts.remotePipe).trim().length then String(opts.remotePipe).trim() else pipeName

validatePipeName = (label, value) ->
  return null unless value?
  throw new Error "Invalid #{label}: #{value}" if value.includes('/') or value.includes(path.sep) or value in ['.', '..']
  value

localPipeName = validatePipeName 'local pipe name', localPipeName
remotePipeName = validatePipeName 'remote pipe name', remotePipeName

# --- LOCAL (receiver) paths: PROJECT-LEVEL SHARED.
#     One project = one runtime.sqlite + one build/adapter, both at BASE.
#     All pipes consume these common resources (recipes read CWD/runtime.sqlite
#     via a pipe-local symlink → ../../runtime.sqlite; the diary recipe loads
#     ../../build/adapter). The merge target is the shared pair, NOT per-pipe.
opts.localDb ?= path.join BASE, 'runtime.sqlite'
opts.localAdapterDir ?= path.join BASE, 'build', 'adapter'

# --- REMOTE (server / trainer) paths: PER-PIPE.
#     The trainer pipe (e.g. mac-mini's pipes/diary) produces its own
#     runtime.sqlite (lora_* rows) and build/adapter under itself; the merge
#     ferries them to the receiver's shared spots.
opts.remoteBase ?= "/Users/#{opts.remoteUser}/writediary"
if remotePipeName?
  opts.remoteDb ?= path.join opts.remoteBase, 'pipes', remotePipeName, 'runtime.sqlite'
  opts.remoteAdapterDir ?= path.join opts.remoteBase, 'pipes', remotePipeName, 'build', 'adapter'
throw new Error 'no --remote-db and no --remote-pipe to derive it from' unless opts.remoteDb?
throw new Error 'no --remote-adapter-dir and no --remote-pipe to derive it from' unless opts.remoteAdapterDir?

remoteSpec = if opts.remoteUser? then "#{opts.remoteUser}@#{opts.remoteHost}" else opts.remoteHost
localDbPath = path.resolve opts.localDb
localAdapterDir = path.resolve opts.localAdapterDir

throw new Error "Local DB not found at #{localDbPath}" unless fs.existsSync localDbPath

console.log "[merge_sqlite_dbs] BASE:", BASE
console.log "[merge_sqlite_dbs] local DB:", localDbPath
console.log "[merge_sqlite_dbs] local adapter dir (shared):", localAdapterDir
console.log "[merge_sqlite_dbs] remote:", "#{remoteSpec}:#{opts.remoteDb}"
console.log "[merge_sqlite_dbs] remote adapter dir:", "#{remoteSpec}:#{opts.remoteAdapterDir}"

tmpRoot = fs.mkdtempSync path.join(os.tmpdir(), 'merge-sqlite-dbs-')
remoteDbCopy = path.join tmpRoot, 'remote-runtime.sqlite'
remoteAdapterCopy = path.join tmpRoot, 'remote-adapter'

tablesToMerge = [
  'lora_story_usage'
  'lora_training_runs'
  'lora_training_run_stories'
  'lora_trained_stories'
]

countRows = (db, tableName) ->
  row = db.prepare("SELECT COUNT(*) AS n FROM #{tableName}").get()
  row?.n ? 0

run = (cmd, args) ->
  console.log "[merge_sqlite_dbs] exec:", cmd, args.join(' ')
  execFileSync cmd, args, stdio: 'inherit'

capture = (cmd, args) ->
  try
    execFileSync cmd, args, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8'
  catch err
    String(err?.stdout ? err?.stderr ? '').trim()

copyRemoteFile = ->
  console.log "[merge_sqlite_dbs] copying remote DB from #{remoteSpec}:#{opts.remoteDb}"
  run 'scp', ["#{remoteSpec}:#{opts.remoteDb}", remoteDbCopy]

copyRemoteAdapter = ->
  fs.mkdirSync remoteAdapterCopy, recursive: true
  console.log "[merge_sqlite_dbs] syncing remote adapter from #{remoteSpec}:#{opts.remoteAdapterDir}/"
  run 'rsync', ['-a', '--delete', "#{remoteSpec}:#{opts.remoteAdapterDir}/", "#{remoteAdapterCopy}/"]

backupLocalDb = ->
  stamp = new Date().toISOString().replace(/[:.]/g, '-')
  backupPath = "#{localDbPath}.backup-#{stamp}"
  fs.copyFileSync localDbPath, backupPath
  console.log "[merge_sqlite_dbs] local DB backup:", backupPath

replaceLocalAdapter = ->
  stamp = new Date().toISOString().replace(/[:.]/g, '-')
  backupDir = "#{localAdapterDir}.backup-#{stamp}"
  if fs.existsSync localAdapterDir
    fs.renameSync localAdapterDir, backupDir
    console.log "[merge_sqlite_dbs] adapter backup:", backupDir
  fs.mkdirSync path.dirname(localAdapterDir), recursive: true
  run 'rsync', ['-a', '--delete', "#{remoteAdapterCopy}/", "#{localAdapterDir}/"]
  console.log "[merge_sqlite_dbs] adapter copied into:", localAdapterDir

summarize = (db, label) ->
  console.log "[merge_sqlite_dbs] #{label}"
  for tableName in tablesToMerge
    console.log "  #{tableName}: #{countRows(db, tableName)}"

isSqliteLockedError = (err) ->
  text = String(err?.message ? err ? '')
  /database is locked|SQLITE_BUSY|SQLITE_LOCKED/i.test text

describePhaseError = (phase, err) ->
  return unless isSqliteLockedError err
  console.error "[merge_sqlite_dbs] SQLITE LOCKED during #{phase}"
  console.error "[merge_sqlite_dbs] local DB:", localDbPath
  console.error "[merge_sqlite_dbs] local pipe:", localPipeName ? '(none)'
  console.error "[merge_sqlite_dbs] remote DB copy:", remoteDbCopy
  console.error "[merge_sqlite_dbs] note: another local process may have runtime.sqlite open for writing"
  lsofText = capture 'lsof', [localDbPath]
  if lsofText.length
    console.error "[merge_sqlite_dbs] lsof #{localDbPath}:"
    console.error lsofText
  else
    console.error "[merge_sqlite_dbs] lsof found no current holder for #{localDbPath}"

copyRemoteFile()
copyRemoteAdapter()

localDb = new DatabaseSync localDbPath
remoteDb = new DatabaseSync remoteDbCopy

try
  try
    summarize localDb, 'local before merge'
    summarize remoteDb, 'remote snapshot'
  catch err
    describePhaseError 'summary', err
    throw err

  if opts.dryRun
    console.log "[merge_sqlite_dbs] dry-run only, no merge performed"
    process.exit 0

  backupLocalDb()

  try
    localDb.exec "ATTACH DATABASE '#{remoteDbCopy.replace(/'/g, "''")}' AS remote_db"
    localDb.exec 'BEGIN IMMEDIATE'
  catch err
    describePhaseError 'begin merge transaction', err
    throw err

  try
    # Local DB is authoritative for stories/KAG tables.
    # Only merge LoRA-family tables from the remote machine.
    localDb.exec """
	    INSERT INTO lora_story_usage (story_id, use_count, last_trained_at, last_run_id)
	    SELECT story_id, use_count, last_trained_at, last_run_id
	    FROM remote_db.lora_story_usage
	    WHERE 1=1
	    ON CONFLICT(story_id) DO UPDATE SET
	      use_count = excluded.use_count,
	      last_trained_at = excluded.last_trained_at,
	      last_run_id = excluded.last_run_id;

	    INSERT INTO lora_training_runs (
	      run_id, started_at, finished_at, status, model_dir, adapter_path,
	      resume_adapter_file, training_dir, stdout_text, train_rows_count,
	      valid_rows_count, test_rows_count, checkpoint_path
	    )
	    SELECT
	      run_id, started_at, finished_at, status, model_dir, adapter_path,
	      resume_adapter_file, training_dir, stdout_text, train_rows_count,
	      valid_rows_count, test_rows_count, checkpoint_path
	    FROM remote_db.lora_training_runs
	    WHERE 1=1
	    ON CONFLICT(run_id) DO UPDATE SET
	      started_at = excluded.started_at,
	      finished_at = excluded.finished_at,
	      status = excluded.status,
	      model_dir = excluded.model_dir,
	      adapter_path = excluded.adapter_path,
	      resume_adapter_file = excluded.resume_adapter_file,
	      training_dir = excluded.training_dir,
	      stdout_text = excluded.stdout_text,
	      train_rows_count = excluded.train_rows_count,
	      valid_rows_count = excluded.valid_rows_count,
	      test_rows_count = excluded.test_rows_count,
	      checkpoint_path = excluded.checkpoint_path;

	    INSERT OR IGNORE INTO lora_training_run_stories (run_id, story_id)
	    SELECT run_id, story_id
	    FROM remote_db.lora_training_run_stories;

	    INSERT INTO lora_trained_stories (story_id, trained_at)
	    SELECT story_id, trained_at
	    FROM remote_db.lora_trained_stories
	    WHERE 1=1
	    ON CONFLICT(story_id) DO UPDATE SET
	      trained_at = excluded.trained_at;
    """

    localDb.exec 'COMMIT'
  catch err
    describePhaseError 'merge transaction', err
    localDb.exec 'ROLLBACK'
    throw err
  finally
    localDb.exec 'DETACH DATABASE remote_db'

  summarize localDb, 'local after merge'
  replaceLocalAdapter()
  console.log "[merge_sqlite_dbs] merge complete"
finally
  try localDb?.close() catch then null
  try remoteDb?.close() catch then null
