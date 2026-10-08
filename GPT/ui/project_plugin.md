# writer/ui/project.coffee — the plugin

**Introduced**: 2026-10-08 as part of the UI unification cutover
(see `pipeline/GPT/ui/plugin_system.md`). Writer no longer runs its
own `ui_server.coffee`; the library ui_server auto-loads this plugin
when launched from `~/writer`.

## Cutover status

- **Writer plugin is tiny** by comparison to puppeteer — ~380 LOC
  carrying 4 unique routes. No SSH divergence, no sticky-pipe chdir.
- **Mini**: not yet launchd-managed. Launch manually with
  `cd ~/writer && coffee ~/pipeline/ui_server.coffee net`.
  Serves 4311 (`portDefault`). Previously tested at 4401 side-by-side.
- **Old file**: `~/writer/ui_server.coffee` is still on disk pending
  deletion. No launcher references it after the cutover.

## What the plugin exports

```coffee
preStartup   # none — writer has no sticky-pipe chdir
portDefault  # 4311. Flipped to 4401 during side-by-side testing.
init(ctx)    # returns {routes: [...], augmentStatus}
```

## Routes (4)

Project-unique only. The ~20 shared endpoints (launch, kill, status,
manifest, sqlite, pipeline_svg, step_restart, control, overrides,
switch_pipe, merge_pipe, adapters, clear_*, etc.) come from the
library.

```
POST  /api/create_pipe              scaffold pipes/<name>/
GET   /api/storacle_observations    list observations from per-pipe runtime.sqlite
POST  /api/storacle_observation     create (reads out/storacle_meta.json for
                                    provenance) or update (notes/noted_by only)
GET   /api/panel/*                  dynamic panel loader
```

## `augmentStatus`

Same as puppeteer's — eager-runs the panel registry and injects
`panels` + `panels_data` into `/api/status`. Writer's panels today:
`steps`, `log_files`, `pipeline_death` from the library; no
writer-shipped panel files yet (`~/writer/panels/` is empty).

## create_pipe details

Writes `pipes/<name>/override.yaml` with the pinned `pipeline:` +
`run: {model, loraLand, quantized_dir}` block (per
`writer/MORNING.md` — recipes MUST NOT default `run.model`), plus
pre-creates `override/<pipeline>.yaml` so `readOverride()` finds a
file on first `/api/status` (no lazy legacy materialization).

Model paths derive at creation time from `${MODELS:-${HOME}/models}`:

```
run.loraLand      = ${MODELS}/<model>
run.quantized_dir = ${MODELS}/<model>-mlx4
```

Human edits the file after creation for non-standard layouts.

## storacle_observations

Captures a single storacle run's provenance into
`<pipe>/runtime.sqlite` so the human can note what worked. Table
auto-created on first write (CREATE IF NOT EXISTS). Create branch
reads `out/storacle_meta.json` + `out/storacle.txt` once and freezes
provenance — only `notes` and `noted_by` are editable thereafter.

Adapter mtime + `lora_run_id` are captured by matching
`adapter_path` to the most recent `lora_training_runs` row.

## Panel registry

Same shape as puppeteer's, with `listFiles`, `describeOutputFile`,
`readJson`, `readText` injected as helpers. No `buildPeerPipes` —
writer doesn't have SSH fan-out.

## Related

- `[[plugin_system]]` — the plugin loader contract.
- `[[ipc]]` — broker and memo modules.
- `~/writer/GPT/ui/ui_server.md` — pre-plugin notes, still accurate for
  shared behavior (launch, kill, switch_pipe mechanics).
- `~/writer/GPT/ui/ui_restart_on_switch_pipe.md` — restart semantics.
