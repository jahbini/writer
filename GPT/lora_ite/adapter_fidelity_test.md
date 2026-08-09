# Adapter fidelity test — proving save/load isn't the bug

Shipped 2026-08-09 during the amplitude-diagnosis session. Verifies
that a `.safetensors` checkpoint written by the trainer reproduces
its training-time validation loss when loaded through the
inference-time seam. Rules out "save/load defect" as a candidate
for empty-generation problems.

## The seam this test exercises

An adapter checkpoint is written by the trainer with weights live
in memory. Later, inference loads that file via `applyLoRA` +
`loadAdapter` (`~/pipeline/mlx/lora/wrap.coffee`). If ANYTHING
between the two (transposed A/B matrices, silent parameter-name
mismatch defaulting to init, dtype cast, scale double-applied)
mangles the round-trip, the reloaded adapter is not the one the
trainer measured.

Val loss at train time proves nothing about the on-disk file. It
proves the trainer's in-memory weights predict validation well.
The fidelity test bridges the gap.

## How the test works

`scripts/adapter_fidelity.coffee`:

1. Loads base model via the same seam session_api uses (config →
   `resolveModelClass` → `loadWeights` → quantize predicate →
   `model.loadWeights` → `Tokenizer`).
2. Runs 25 validation batches through `makeLossFn` from the
   trainer. Reports **BASE LOSS**.
3. Loads a FRESH copy of the base model. Applies `applyLoRA` with
   the adapter's `adapter_config.json` params. Calls `loadAdapter`
   on the safetensors file — this is the exact production seam.
4. Runs the same 25 validation batches (same seed → same batches)
   through the same `makeLossFn`. Reports **ADAPTER LOSS**.

Difference between the two is the adapter's on-disk effect on
loss. Compare `ADAPTER LOSS` against the trainer's reported
val_loss at that iter.

## Runner

`test.sh` at repo root. Handles coffee-shim brokenness (falls back
to pnpm store copy), preflight-checks all inputs exist, saves
timestamped output to `test/fidelity_<tag>_<stamp>.log` +
`.summary`, and mirrors to `test/latest.*` for shell-friendly
access.

Usage:

    ./test.sh          # defaults to checkpoint 0000100
    ./test.sh 500      # shorthand for 0000500 checkpoint
    ./test.sh path/to/adapter.safetensors

## Interpreting the numbers

Assume rank-8 style adapter on a Jim corpus. Baseline expectations:

- **base loss** typically 3.5–4.5 for Qwen3-4B on prose.
- **adapter loss** should be **lower than base** by 0.3–0.8 for a
  well-trained adapter. Confirmed 2026-08-09: BASE 4.2262 vs
  ADAPTER 3.7624, delta −0.4638, matches trainer's reported ~3.72.

Branches:

- **adapter ≈ trainer-reported val_loss** → checkpoint is faithful.
  Save/load is not the bug. Look elsewhere.
- **adapter ≈ base loss** (no improvement) → adapter is a no-op
  after load. Almost certainly parameter-name mismatch in
  `loadAdapter` silently defaulting to init. Inspect
  `wrap.coffee:134-149`.
- **adapter >> base loss** → weights loaded but corrupt (transpose,
  dtype cast, double-scale). Same file to inspect.
- **loaded 16/16 tensors but adapter ≈ base** → names match at
  load time but values aren't taking effect at forward time.
  Check whether forward reads from the same attribute name that
  loadAdapter writes to.

## When to run this

- Any new "empty generation" report BEFORE spending time on
  runtime plumbing. It's decisive and cheap (~30s per adapter).
- After any change to `wrap.coffee` (`applyLoRA` /
  `loadAdapter` / `adapterKeys`), as a smoke test.
- After adopting a new mlx-lm version — if the framework changes
  parameter names, the safetensors keys we wrote won't match what
  it now expects, and the test will catch it.

## What this test does NOT prove

- **The adapter generates coherently on OOD prompts.** For that,
  see [[checkpoint_selection]] — a generation probe against the
  real ChatML+directive prompt.
- **The adapter isn't over-amplitude.** Val loss can be healthy
  while OOD behavior is collapsed. See [[overtraining_notes]].

The fidelity test rules ONE thing in or out: the on-disk file is
what the trainer meant to write. Everything else needs its own
test.

## Guardrails

- **Don't delete** `scripts/adapter_fidelity.coffee` or `test.sh`.
  They are the record of how to answer "did I break the trainer's
  save format" in future sessions.
- **Do keep** `test/latest.summary` around — it's the
  most-recent-run pointer.
- Regenerating `test/` files on each run is fine; the timestamped
  logs are the diagnostic trail.
