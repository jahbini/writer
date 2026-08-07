# Merge tool (pull LoRA training from the mac-mini)

Session: 2026-08-07.

## What the merge button does

The UI's "Merge Adapter And SQLite From Other Machine" button pulls
LoRA training results from the trainer box (`mac-mini.local`) into
the currently-active local pipe. It's `POST /api/merge_pipe` in
`ui_server.coffee` → `startMerge(pipeName)` → spawns
`coffee merge_sqlite_dbs.coffee --pipe <pipeName>`.

## Layout invariant (post-2026-08-07 simplification)

**Same layout on both sides.** Trainer is always `theaiguy@mac-mini.local`.
For a local pipe at `~/<project>/pipes/NAME`, the trainer's copy MUST
be at `~/<project>/pipes/NAME` on the mac-mini — same project dir
name, same pipe name.

`<project>` = `path.basename(BASE)` (for this repo: `writer`).

That's the whole contract. The merge script derives everything:

```
local  DB      = <BASE>/pipes/<pipe>/runtime.sqlite
local  adapter = <BASE>/pipes/<pipe>/build/adapter
remote DB      = theaiguy@mac-mini.local:/Users/theaiguy/<project>/pipes/<pipe>/runtime.sqlite
remote adapter = theaiguy@mac-mini.local:/Users/theaiguy/<project>/pipes/<pipe>/build/adapter
```

## What the merge script accepts

Just `--pipe NAME [--dry-run]`. Every other flag errors out with
`Unknown arg …`. Do NOT re-add options; the historical set
(`--remote-base`, `--remote-pipe`, `--local-db`, `--remote-user`,
`--remote-host`, etc.) accreted for a different, "shared receiver
at BASE" era and was mostly dead. The current shape enforces the
"same layout on both sides" invariant by making any other pattern
un-expressible.

If the trainer moves off `mac-mini.local` or the user isn't
`theaiguy`, edit `REMOTE_USER` / `REMOTE_HOST` constants in
`merge_sqlite_dbs.coffee` directly. No CLI knob.

## Authority policy (unchanged)

Receiver keeps: `stories`, `story_parts`, `expanded_story_parts`,
`kag_entries`.
Server contributes only: `lora_story_usage`, `lora_training_runs`,
`lora_training_run_stories`, `lora_trained_stories`, and
`build/adapter`.

## Two recent bug fixes (2026-08-07)

**(1) Wrong remote root.** The old default was
`/Users/<user>/writediary` — a name from a former incarnation of the
project. Now derived from `path.basename(BASE)`, so for the writer
repo the trainer path is `~/writer/…` on both machines.

**(2) Local DB defaulted to `<BASE>/runtime.sqlite`.** That was the
old "shared receiver" convention. Writer pipes are per-pipe: each
carries its own `runtime.sqlite`. Local DB now always resolves to
`<BASE>/pipes/<pipe>/runtime.sqlite`.

Both live in `merge_sqlite_dbs.coffee` at BASE (project-owned copy).
The runner picks up the BASE copy in preference to the package copy
via `ui_server.coffee`'s `MERGE_SCRIPT` resolution (line 99-104):
BASE first, EXEC fallback.

## `resolveCoffeeBin()` — broken pnpm shim workaround

Also 2026-08-07. `ui_server.coffee:174-208` (function
`resolveCoffeeBin`).

pnpm currently generates a broken shim at
`writer/node_modules/@jahbini/pipeline/node_modules/.bin/coffee`
that exec's `node "<basedir>/../../../../../../coffeescript@X/…/coffee"`
— six `..` from `.bin` reaches `$HOME`, then appends
`coffeescript@X/…`, producing the bogus
`/Users/jahbini/coffeescript@2.7.0/…` (no `writer` in the middle).
Node dies with `Cannot find module …`.

`resolveCoffeeBin()` now bypasses the shim entirely and looks
directly under `writer/node_modules/.pnpm/coffeescript@*/node_modules/coffeescript/bin/coffee`,
returning that path if it exists and is executable. Falls through
to the shim (for classic-npm installs where it's correct), then to
system `coffee` on PATH.

If a future `pnpm install` re-breaks the shim: no action needed —
`resolveCoffeeBin` prefers the `.pnpm` store copy which is always
intact.

## Do NOT re-add

- `--remote-base`, `--remote-pipe`, `--local-db`, `--remote-db`,
  `--remote-adapter-dir`, `--local-adapter-dir`, `--local-pipe`,
  `--remote-user`, `--remote-host` — all removed 2026-08-07. The
  simpler shape is deliberate; the removed options can't co-exist
  with the "same layout on both sides" invariant.
- A "remote pipe name" text input on the merge button. Was briefly
  added the same day and immediately removed when the invariant
  was made explicit. If the trainer has a differently-named pipe,
  rename the pipe (either side); do not re-add the input.
