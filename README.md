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
  ui_server.coffee ← project-owned UI server (PIPES_ROOT → ./pipes)
```

Each pipe is its own working directory: separate `state/`, `logs/`,
`out/`. The model in `build/` is shared. The Python venv in `.venv/`
is shared (each pipe symlinks to it).

## Prerequisites

- **Node 20+**
- **Python 3.10+** (for MLX)
- **macOS with Apple Silicon** (MLX is ARM-only)
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

# 2. Get a model into shared build/ (one-time, ~5 min for a 4B model).
npm run model -- Qwen/Qwen3-4B-Instruct-2507

# 3. Spin up an application.
npm run pipe:new diary_experiment diary_ite
# (creates pipes/diary_experiment/override.yaml with pipeline: diary_ite)

# 4. Run it.
cd pipes/diary_experiment && npx pipeline

# 5. Spin up another, in parallel — uses the same model & venv.
cd ../..
npm run pipe:new lora_experiment lora_ite
cd pipes/lora_experiment && npx pipeline
```

Each pipe accumulates its own `state/`, `logs/`, `out/`, `runtime.sqlite`
— all gitignored. The pipe directory (`pipes/<name>/override.yaml`) is
the one thing worth committing per pipe, alongside any pipe-specific
scripts you write.

## How `npm run model` actually works

`npm run model -- <org/name>` is a thin shell wrapper. It writes
`override.yaml` at the project root selecting `pipeline: download_model`
and then runs `npx pipeline`. The actual work happens inside the
runner's shipped `download_model` recipe (two steps:
`download_model` → `quantize_model`).

The recipe-based approach matters because:

1. **No HF-cache surprises.** A raw `huggingface-cli download` can
   leave the local directory holding cache symlinks that need network
   to resolve later. The recipe's `quantize_model` step runs
   `mlx_lm.convert`, which produces a self-contained MLX directory
   (`build/model4`) with real weight files — load it offline forever.
2. **Customizable via override.yaml.** Open the generated
   `override.yaml` after the wrapper writes it; tweak `q_bits`,
   `download_dir`, `quantized_dir`, or set `skip_quantize: true` if
   you want the raw download only.
3. **Restartable.** If the download is interrupted, `restart_here`
   works just like for any other pipeline step.

If you'd rather skip the wrapper, do the same thing by hand:

```sh
cat > override.yaml <<EOF
pipeline: download_model
download_model:
  model: Qwen/Qwen3-4B-Instruct-2507
EOF
npx pipeline
```

Any existing project-root `override.yaml` gets backed up to
`override.yaml.YYYY-MM-DD_HH-MM-SS.bak` before the wrapper replaces
it. Per-pipe override files under `pipes/*/` are untouched.

## Using the shared model in a pipe

Pipes are working dirs *under* the project root. Inside
`pipes/<name>/override.yaml`, a relative path to the quantized
model looks like:

```yaml
pipeline: diary_ite

# In an _ite recipe, the quantized model is typically referenced
# via the `quantized_model_dir` param. Make it relative to the
# pipe's CWD (which is pipes/<name>/).
quantize_model:
  quantized_model_dir: ../../build/model4
```

The `../../` walks up out of `pipes/<name>/` to the project root,
then into `build/model4/`. Every pipe sees the same model.

## Project-owned UI is yours to hack

The starter ships the entire UI stack — `ui_server.coffee` and
`ui/index.html` — at the project root, not buried in
`node_modules/`. Edit them freely; the runner package's defaults
won't overwrite your changes. If you ever want to start over from
the package's current defaults: `npm run ui:reset`.

The UI's pipe-switcher uses the runner's existing `handleSwitchPipe`
endpoint: it creates `pipes/<name>/{state,logs}/` if missing, then
re-launches the *project-owned* UI server (this file) with the pipe
as the working directory. Customizations survive the relaunch.

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
