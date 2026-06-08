Step: `build_lora_config_ite`
Recipe: `lora_ite` (added via override; not in the package recipe)
Script: `scripts/lora_ite/build_lora_config_ite.coffee` (project-shared, BASE tier)

Purpose:
- write the YAML file consumed by `mlx_lm.lora`'s `-c/--config` flag so
  the LoRA `rank` / `scale` / `dropout` parameters — which have no
  argparse flag in `mlx_lm.lora` — can be tuned per pipe.

Why this exists:
- `mlx_lm.lora` exposes most training knobs (`--num-layers`,
  `--learning-rate`, `--batch-size`, `--iters`, …) as CLI flags but
  intentionally keeps `lora_parameters` out of argparse — it's only
  reachable through the config file at `mlx_lm/lora.py:74` (default
  `{rank: 8, scale: 20.0, dropout: 0.0}`), consumed by
  `tuner/utils.py:60-82`.
- the GPT/README HARD RULE says "lora `rank`/`scale`/`dropout` are NOT
  CLI flags, so they ride mlx-lm defaults" — this step is the
  deliberate exception: communication with `mlx_lm` is unavoidable
  Python anyway, so the project channels its `--config` mechanism
  through a proper DAG step rather than a bespoke wrapper.

Inputs (params):
- `rank` (default 8) — LoRA rank.
- `scale` (default 20.0) — multiplier inside the LoRA layer (NOT
  PEFT alpha/rank; do not "fix" to 2.0).
- `dropout` (default 0.0) — adapter dropout, must be in [0, 1).

Outputs:
- Memo artifact `lora_config` — the YAML object
  `{lora_parameters: {rank, scale, dropout}}`.
- The recipe's `artifacts.lora_config.target` is the file the runner
  serializes it to. Convention: `data/lora_config.yaml` (CWD-relative,
  pipe-local).

Wiring (in `pipes/<pipe>/override/lora_ite.yaml` on the trainer):
- add the artifact, the step block, and the path under `run_lora_train_ite.mlx.config`.
  The path appears in two places (artifact target + mlx config value)
  and must agree.

Invariants:
- step only sets the three keys with no CLI flag; everything else
  (num-layers, learning-rate, iters, batch-size, max-seq-length,
  optimizer, fine-tune-type, grad-checkpoint, etc.) stays in
  `run_lora_train_ite.mlx:` and is passed as `--key value`.
- params validated: rank > 0 integer, scale > 0 number, dropout in
  `[0, 1)`. The step throws loudly on bad input rather than silently
  passing garbage to mlx-lm.
- the saved adapter at `pipes/<pipe>/build/adapter/adapter_config.json`
  will record the values used (mlx_lm writes the config back). After
  the trained adapter is merged to `BASE/build/adapter` on the
  receiver, the inference-side gypsy `generation_adapter_scale` may
  need to be reconciled with the trained `scale`.

Known pitfalls:
- forgetting the `mlx: config: <path>` entry in `run_lora_train_ite`
  silently reverts to mlx-lm defaults; the file is written but mlx
  never reads it.
- placing `lora_parameters: {…}` directly in `run_lora_train_ite.mlx:`
  (instead of via this step) yields the `--lora_parameters [object Object]`
  argparse rejection — that is what this step exists to replace.
- the path string is duplicated (artifact target + mlx config value);
  keep them in sync. A future runner enhancement could let `mlx:`
  values reference an artifact name; until then, the duplication is
  intentional and visible.
