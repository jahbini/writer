Step: `download_model`
Recipes: `reset` (PROJECT `config/reset.yaml`) and the shipped
`download_model` (package `config/download_model.yaml`). The step
runs as part of a pipe's normal recipe chain — there is no separate
bootstrap command.

Run script: `model/download_model.coffee` (shipped in the pipeline
package). Uses **git + git-lfs** only; no HF CLI, no Python, no API
tokens.

Inputs (params):
- `model` — HF repo id, e.g. `Qwen/Qwen3-4B-Instruct-2507`. Pulled from
  the step's `model` param if set, else `run.model`.
- `download_dir` — target directory where the model is cloned. Pin
  it in the pipe's `override.yaml` using the shared cache layout:
    `${MODELS}/<org>/<name>/`
  When omitted, the script derives that same path from `$MODELS` +
  `model`. Legacy fallback: `build/model` (used when `$MODELS`
  unset). `loraLand` is still accepted as an alias for backward
  compatibility.

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
- `quantize_model` reads its own `src_dir` (pinned to the same
  `${MODELS}/<org>/<name>/` in the pipe's override.yaml) and writes
  MLX 4-bit weights to `${MODELS}/<org>/<name>-mlx4/`.
- `lora_ite` reads the raw download path as the base model for training.

Known pitfalls:
- If `git-lfs` is missing, the safetensors files are LFS pointer stubs;
  downstream `quantize_model` will fail with "source model invalid".
- The raw clone (~16 GB for a 4B model) is required by `lora_ite`
  (which trains against the raw model, not the quantized derivative).
  Do not `rm -rf ${MODELS}/<org>/<name>/` after quantization if LoRA
  training is on the table.
