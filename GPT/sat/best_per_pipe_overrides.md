# Best-per-pipe SAT overrides (locked 2026-09-19)

Decision: **each pipe's `override/sat_ladder.yaml` points at that
pipe's best-tested adapter checkpoint**, not at a common default.
The pipe's SAT grade reflects the model's *achievable* quality with
its best-known configuration, per the grading-at-best principle
recorded in `size_scaled_lora.md` and `puppeteer/GPT/design/sat_matrix.md`.

## The four locked overrides

| Pipe | `sat_diary_ite.adapter_dir` | Best score seen | Config |
|---|---|---|---|
| **hf__qwen__qwen3-0-6b** | `build/adapter` | adapted 5/6 vs base 3/6, Δ=+2 | v4: rank=8 α=16 layers=8 lr=7e-6 iters=300 |
| **hf__qwen__qwen3-1-7b** | `build/adapter` | adapted 2/6 vs base 1/6, Δ=+1 | v4: rank=8 α=16 layers=8 lr=7e-6 iters=300 |
| **hf__qwen__qwen3-4b** | `build/adapter.pre-scaled-2026-09-18/0000100_adapters.safetensors` | adapted 6/6 vs base 4/6, Δ=+2 | original: rank=8 α=16 layers=8 lr=1e-5, checkpoint 100 (pre-retrain, backed up) |
| **hf__qwen__qwen3-4b-instruct-2507** | `build/adapter` | adapted 4/6 vs base 2/6, Δ=+2 (base only wrote "Jim") | v4: rank=8 α=16 layers=8 lr=7e-6 iters=300 |

Other knobs (uniform across the four pipes):
- Elementary: `temperature=0.15`, `top_p=0.8`, `with_judge=true`
- Diary: `temperature=0.75`, `top_p=0.9`, `max_tokens=3000`
- Story: `temperature=0.85`, `top_p=0.9`, `max_tokens=5000`, `min_words=300`, `max_words=1200`

## Why these are locked, not "final"

The choices above use only the temperatures we happened to test
(0.75 for diary, 0.85 for story). We have NOT swept temperature ×
adapter-checkpoint per pipe — the puppeteer-side parameter-sweep
capability (P2 in `puppeteer/GPT/rules/route_runs_through_puppeteer.md`)
doesn't exist yet. Each pipe's true peak may sit at a different
temperature; that'll be tested once P2 lands.

For 4B specifically: the pre-scaled ckpt-100 is a **historical
peak from before the LR-halving retrain**. The current
`build/adapter/` on that pipe is the SCALED-LR retrain (final),
which grades 5/6 — worse than the original ckpt-100. If a future
retrain matches or beats 6/6, this pointer moves.

For the other three pipes: `build/adapter/` is the v4 retrain
result (lr=7e-6). Those are the highest-scoring configs each has
produced so far.

## What this changes about the SAT matrix

- Every ingested `sat_verdicts` row records the exact
  `sat_diary_ite.adapter_dir` (and other knobs) so the matrix can
  distinguish "verdict at best config" from "verdict at some other
  config." See the `knobs_json` field in the matrix schema.
- Any change to `override/sat_ladder.yaml` invalidates the pipe's
  current matrix row until the next SAT run (or the matrix
  displays a "stale" flag until re-ingested).
- The matrix is now a claim about *these specific overrides* — the
  overrides file becomes part of the answer, not just the input.

## Backup adapter locations (audit trail)

Each pipe has adapter backups so we can revert or compare:

- **0.6B**: `build/adapter.scaled-v1-2026-09-18` (v1 too-soft), `build/adapter.v2-lr5e6-300iters`
- **1.7B**: `build/adapter.scaled-v1-2026-09-18` (rank=4 config, was Δ=−1)
- **4B**: `build/adapter.pre-scaled-2026-09-18` (three checkpoints from 1e-5 training — 100/200/final)
- **4B-Instruct-2507**: `build/adapter.scaled-v1-2026-09-18` (rank=4 config, was Δ=0)

## When to revisit

- After the puppeteer's per-pipe parameter sweep capability (P2)
  lands and runs a real (temp × adapter × top_p) grid per pipe.
- After the LR-decay training experiment (see
  `writer/GPT/sat/next_experiments.md` Arc A2) — if that produces
  a higher-scoring adapter, its checkpoint file becomes the new
  pointer.
- After 8B and Qwen2.5-0.5B get their `-mlx4` quantizations built —
  those pipes join the matrix and need their own overrides tuned.
