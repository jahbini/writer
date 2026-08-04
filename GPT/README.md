This directory is assistant-owned working memory for recipe and step contracts.

Purpose:
- keep step-local memory outside the transient conversation
- record proven contracts and costly failure modes
- help trace downstream failures back to upstream causes
- preserve current pipe/workspace assumptions so future sessions do not drift back to older top-level-only behavior

**Read this first when starting a session on anything DAG-shaped:
[`pipeline_architecture.md`](pipeline_architecture.md)** — the framework is
the universal starting point for notebook conversion / batch automation.
When work is ambiguous, separate "framework orbit" from "domain orbit"
before acting.

Rules:
- keep files short and factual
- update a step memory when its contract changes
- prefer one file per important step
- record inputs, outputs, invariants, and pitfalls
- if a stale bug is diagnosed from logs, update the affected step memory so the failure mode is explicit
- do not use this directory for general notes or speculation

## Current repository assumptions worth preserving

- The repo is **pipe-centric**; active workspaces live under `pipes/<pipe>/`.
- **The runner's `CWD` is the pipe directory, `pipes/<pipe>/`. Run-state
  and run-config files are resolved relative to `CWD`, NOT the repo
  base.** So the operative files are:
  - `pipes/<pipe>/override.yaml` and `pipes/<pipe>/override/<recipe>.yaml`
  - `pipes/<pipe>/experiment.yaml`
  - `pipes/<pipe>/control_override.yaml`
  - `pipes/<pipe>/{state,out,params,data,runtime}/`
- **npm-extracted layout**: the runner + bundled recipes/scripts live under
  `node_modules/@jahbini/pipeline/` (the runner calls this `EXEC`). It is
  wiped by `npm install`. The project root — `BASE` — is the dir that
  contains that `node_modules/`. The runner resolves scripts as
  `[CWD, BASE, EXEC]/scripts/<ref>` and recipes as
  `[BASE, EXEC]/config/<name>.yaml` (project shadows package). `ui_server`
  mirrors this for its own asset lookups (`resolveUiAsset` adds the BASE
  tier, `PIPES_ROOT = BASE/pipes`).
- The BASE shared set (committed unless noted): `config/` (project recipe
  overrides), `scripts/` (project-shared step scripts not bundled in the
  package), `ui_server.coffee`, `ui/`, `merge_sqlite_dbs.coffee`, `bin/`,
  `run-first.sh`, `package.json`, `.gitignore`, `GPT/`. Gitignored shared
  (regenerable but lives at BASE): `.venv/`, `build/` (shared model),
  `node_modules/`.
- `pipes/*` is fully ephemeral and gitignored — `data/`, `state/`, `out/`,
  `logs/`, `params/`, `override.yaml`, `override/<recipe>.yaml`,
  `experiment.yaml`, `control_override.yaml`, `pipeline.json`, plus any
  pipe-local `scripts/` override seam. Nothing under `pipes/` is retained
  in git. A keeper experiment graduates into a `BASE/config/` recipe
  rather than being kept as a pipe override.
- The same-named files in the repo BASE directory (`BASE/override.yaml`,
  `BASE/experiment.yaml`) — when they appear — are stale leftovers from
  temporary bootstrapping writes. Recipes that run inside pipes must not
  read them.

## Recipe / notebook contract

- Each recipe is a 1:1 conversion of one Python notebook. Each step/script
  in a recipe is the direct equivalent of one notebook step. The DAG
  runner adds dependency edges (`needs` / `makes`), reactivity (the memo),
  and restartability on top of that notebook structure.
- `test` is kept deliberately as a worked example for future pipeline users.

## Persistence layers (by lifetime)

- **Long-term, cross-run**: per-pipe SQLite. New steps that produce
  reusable structured data should land it in SQLite.
- **Transient, single-run**: `out/`, `data/`, `params/`, `state/`.
  Scratch space for one pipeline run.
- **Crash-resume**: when a recipe dies mid-DAG, `state/` and `params/`
  together let the runner pick up at the dead step on next launch.
  That is why the UI prominently features the `Pipeline Death` pane and
  the `Erase pipeline.json` button.

## Override chain

- Overrides are recipe-scoped: prefer `override/<pipeline>.yaml` for
  human overrides associated with a selected config recipe.
- Legacy `override.yaml` remains a fallback/bootstrap file for older pipes
  and initial pipeline/model inference; when used for a selected pipeline
  it should be materialized into `override/<pipeline>.yaml` for future runs.
- `control_override.yaml` is UI-owned run control, not a replacement for
  recipe-scoped human overrides.
- **`experiment.yaml` is the materialized effective config of a run** —
  the fully-merged result of recipe + override + control_override with
  UI directives stripped, exactly what the runner consumed. When the
  human posts an `experiment.yaml`, treat it as the authoritative, exact
  source of what that run entailed. Do NOT speculate about
  recipe-vs-override provenance or "where a value came from" — the
  merged file IS the answer. It is per-run.
- A `config/*.yaml` recipe block, an `override.yaml`, or any single
  pre-merge file is NOT the experiment.yaml. Only the merged
  `pipes/<pipe>/experiment.yaml` is authoritative for what a run did.

## Working discipline

- **HARD RULE: the assistant does NOT edit `config/*.yaml` recipe files
  for tuning.** Recipes are the stable baseline. Every parameter change
  goes in `override.yaml` (or `override/<recipe>.yaml`). Creating a
  brand-new recipe file when the human explicitly asks for one is
  allowed; editing an existing recipe's values is not. If a recipe value
  looks wrong, express the correction as an override entry and tell the
  human — do not reach into the recipe.
- Do not build opinions or assert conclusions from partial, pre-merge, or
  possibly-stale data. If a fact depends on a file the assistant cannot
  see, ASK for it. Do not theorize a value and then carry that theory
  forward as established fact.
- When the human tries to stop or redirect, stop immediately. Do not
  keep executing on input that is being retracted or corrected.

## UI conventions

- The UI drives recipe fields through recipe-declared directives, currently
  `UI_dropdown`, `UI_checkbox`, and `UI_textarea`.
- The UI layout is intentionally split into:
  - left column for death/output/step/log visibility
  - right column for one merged controls pane
- The UI should not poll every 2 seconds all the time; it polls
  continuously while EITHER a pipeline run OR a merge job is active, and
  stops otherwise so the user can edit fields without the UI yanking
  values back from disk (see `GPT/ui/ui_server.md` for the full polling
  gate rule).

## Suggested use

- When a step fails, inspect its memory file first.
- If the real cause is upstream, follow the listed dependency chain.
- When code changes invalidate a memory file, update it in the same work.
