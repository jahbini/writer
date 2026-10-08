# pipeline-pipes

A multi-pipe starter for [`@jahbini/pipeline`](https://github.com/jahbini/pipeline).
Sister project to [`pipeline-demo`](https://github.com/jahbini/pipeline-demo):
where pipeline-demo is one project = one pipeline, **pipeline-pipes is
one project with a shared model + many applications**.

```
pipeline-pipes/
  build/           ← shared model lives here (downloaded once, quantized once)
  .venv/           ← shared Python venv (created once)
  pipes/
    sample/        ← one application — its own override, state, logs
      override.yaml
      .venv → ../../.venv
    my_lora_run/   ← another application — its own override, etc.
      ...
  ui/index.html    ← project-owned UI frontend
  ui/project.coffee ← project-specific plugin (routes + panels)
```

The UI server itself lives in `@jahbini/pipeline` and is launched via
`pnpm run ui`. The plugin at `ui/project.coffee` adds this project's
routes (`/api/create_pipe`, `/api/storacle_observation(s)`,
`/pipe/<name>` deep-link) and panel registry on top. See
`pipeline/GPT/ui/plugin_system.md`.

Each pipe is its own working directory: separate `state/`, `logs/`,
`out/`. The model in `build/` is shared. The Python venv in `.venv/`
is shared (each pipe symlinks to it).

## Prerequisites

- **Node 20+**
- **Python 3.10+** (for MLX)
- **macOS with Apple Silicon** (MLX is ARM-only)
- **git** and **git-lfs** (`brew install git-lfs && git lfs install`) — the
  model download step (`@jahbini/pipeline`'s `model/download_model.coffee`)
  clones the HF repo via git + LFS.
- **~10 GB free disk** if you'll download a real model

## First run, in two commands

```sh
git clone https://github.com/jahbini/pipeline-pipes my-project
cd my-project
./run-first.sh
```

`run-first.sh` installs the runner package, creates the shared
`.venv` with MLX, and scaffolds `pipes/sample/` (a working
application that runs the shipped `test` pipeline). After the
script finishes, four entry points are available:

| command | what it does |
|--|--|
| `npm run model -- Qwen/Qwen3-4B-Instruct-2507` | Activates the shipped `download_model` recipe: fetches the model + quantizes it into `build/model/` and `build/model4/`. The quantized output is self-contained — no further HF traffic to use it. |
| `cd pipes/sample && npx pipeline` | Runs the sample pipe — the 9-step test pipeline, no model required. Ends with the `step9_handoff` welcome banner. |
| `npm run pipe:new my_experiment [pipeline-name]` | Scaffolds a new pipe under `pipes/<name>/` with a symlink to the shared venv and a fresh `override.yaml`. Default pipeline is `test`. |
| `npm run ui` | Starts the local UI on `http://127.0.0.1:4311`. The UI's pipe-switcher lists every pipe under `pipes/`; clicking one re-launches the UI with that pipe as the working directory. |

## Workflow

A typical session:

```sh
# 1. Bootstrap once.
./run-first.sh

# 2. Set MODELS to the shared model cache root.
export MODELS=$HOME/models

# 3. Spin up an application.
npm run pipe:new diary_experiment diary_ite
# (creates pipes/diary_experiment/override.yaml with pipeline: diary_ite)

# 4. Set the pipe's model + paths in pipes/diary_experiment/override.yaml
#    (see "Model paths" below), then run it — first run downloads +
#    quantizes into $MODELS; subsequent runs are idempotent-skipped.
cd pipes/diary_experiment && npx pipeline

# 5. Spin up another, in parallel — different model, same $MODELS cache.
cd ../..
npm run pipe:new lora_experiment lora_ite
cd pipes/lora_experiment && npx pipeline
```

Each pipe accumulates its own `state/`, `logs/`, `out/`, `runtime.sqlite`
— all gitignored. The pipe directory (`pipes/<name>/override.yaml`) is
the one thing worth committing per pipe, alongside any pipe-specific
scripts you write.

## Model paths ($MODELS shared cache)

Models are loaded as steps inside a pipe's recipe (there is no
separate `npm run model` bootstrap). Set `MODELS` in your shell to
the shared cache root; each pipe's `override.yaml` pins its
download + quantize paths under it:

```yaml
pipeline: story

run:
  model: Qwen/Qwen3-4B-Instruct-2507

# Layout: $MODELS/<org>/<name>[-mlx<bits>]/
download_model:
  download_dir: ${MODELS}/Qwen/Qwen3-4B-Instruct-2507

quantize_model:
  src_dir:       ${MODELS}/Qwen/Qwen3-4B-Instruct-2507
  quantized_dir: ${MODELS}/Qwen/Qwen3-4B-Instruct-2507-mlx4
```

Multiple pipes using different base models coexist in one `$MODELS`
tree. Both `download_model` and `quantize_model` are idempotent:
once the weights are present and match the recorded provenance,
subsequent runs skip.

Downstream steps that need the quantized model reference
`quantized_dir` via their own params (typically
`quantized_model_dir`) — again pinned in the pipe's override.yaml.

## Project-owned UI plugin is yours to hack

The UI server (`ui_server.coffee`) lives in `@jahbini/pipeline` and
is shared across projects. What you customize is the **plugin** at
`ui/project.coffee` plus the static frontend at `ui/index.html` —
both at the project root. The plugin adds this project's routes
(`/api/create_pipe`, `/api/storacle_observation(s)`, `/pipe/<name>`
deep-link) and threads project-specific helpers into the panel
registry. The library auto-loads it by walking up from `process.cwd()`.

The UI's pipe-switcher calls the library's `handleSwitchPipe`
endpoint: it creates `pipes/<name>/{state,logs}/` if missing, then
re-launches the library server with the pipe as the working
directory. The plugin walk-up re-resolves to this project's
`ui/project.coffee` so customizations survive the relaunch.

See `pipeline/GPT/ui/plugin_system.md` for the plugin contract.

## Resetting

```sh
npm run clean    # wipes .venv, build/*, every pipe's runtime artifacts
./run-first.sh
```

Note that `npm run clean` does NOT remove `pipes/<name>/override.yaml`
or any custom scripts you've put in `pipes/<name>/scripts/` — those
are content, not cache.

## Relation to pipeline-demo

| | pipeline-demo | pipeline-pipes |
|--|--|--|
| Shape | one project, one pipeline | one project, many applications |
| Model | not required | shared `build/`, downloaded once |
| State | at project root | per-pipe under `pipes/<name>/` |
| Use case | "kick the tires" on the runner | iterate on multiple experiments against one model |

Start with pipeline-demo if you're new to the runner; graduate to
pipeline-pipes when you have a model and want to run several
experiments side-by-side.

## License

ISC.
