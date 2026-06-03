Step: `download_model`
Recipes:
- `base_ite` (PROJECT `config/base_ite.yaml`, restored 2026-05-27 with the
  proven 4-step writeStory chain)
- `download_model` (PROJECT `config/download_model.yaml`, the recipe
  `npm run model` selects)

Both project recipes shadow the package via `resolveConfigPath`
(`BASE/config` wins over `EXEC/config`). DO NOT use the package's
`download_model.yaml` — its `model/download_model.coffee` is HuggingFace
API + Python and has hit `401 Unauthorized` on the trainer.

Run script: `story/hf_download.coffee` (resolves from `BASE/scripts/story/`).
Uses **git + git-lfs** only; no HF CLI, no Python, no API tokens.

Inputs (params):
- `model` — HF repo id, e.g. `Qwen/Qwen3-4B-Instruct-2507`. Pulled from
  the step's `model` param if set, else `run.model`.
- `loraLand` — target directory where the model is cloned.
  - In `download_model.yaml` (invoked at project root by `npm run model`):
    `build/model` → `BASE/build/model`.
  - In `base_ite.yaml` (invoked inside a pipe): `../../build/model` →
    `BASE/build/model` (the shared model location every pipe references).

Outputs:
- Directory at `loraLand` containing the cloned model (`config.json`,
  `model.safetensors*`, tokenizer files, etc.) plus a
  `.model_provenance.json` written by the script with `{model_id, repo_url, ...}`.
- No Memo artifact; the artifact is the on-disk directory.

Invariants:
- **Idempotent**: re-running with the same `model` and provenance match
  skips the clone (`isModelAlreadyDownloaded`).
- **Retry-hardened**: 3 attempts with a 10-minute backoff between failures.
- **Restart-safe**: a partial clone is stripped (`.git` removed) and
  re-attempted on next invocation.
- **Stripped of `.git`** after a successful clone — the working tree is
  retained but the repo metadata is removed.

Host prerequisites:
- `git` and **`git-lfs`** installed on the host. The clone will fail or
  download placeholder pointers if `git-lfs` isn't installed and
  initialized (`git lfs install` once per user).

Downstream consumers:
- `quantize_model` reads `source_model_dir: build/model` (or
  `../../build/model`) and writes the MLX 4-bit quantized model to
  `build/model4` (or `../../build/model4`).
- `lora_ite` reads `run.loraLand` as the base model for training.

Why this exists separately from the package's `model/download_model.coffee`:
- avoids HuggingFace API auth (no `HF_TOKEN`, no `huggingface-cli login`).
- avoids Python and the `mlx_lm.convert` cache-symlink behavior the
  package recipe relies on.
- preserves the original writeStory provenance + retry policy.

Known pitfalls:
- If invoked at the project root (e.g. via `npm run model`), `model.sh`
  writes a `BASE/override.yaml` selecting `pipeline: download_model`. That
  file is a transient driver, not a per-recipe override; per `README.md`
  pipe-recipes must not read `BASE/override.yaml`.
- If `git-lfs` is missing, the safetensors files are LFS pointer stubs;
  downstream `quantize_model` will fail with "source model invalid".
- `build/model` (the raw clone, ~16 GB for a 4B model) is required by
  `lora_ite` (which trains against the raw model, not `build/model4`).
  Do not `rm -rf build/model` after quantization if LoRA training is on
  the table.
