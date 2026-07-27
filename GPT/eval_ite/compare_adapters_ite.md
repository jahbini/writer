Step: `compare_adapters_ite`  (writediary project step + recipe)
Recipe: `compare_adapters_ite`  (config/compare_adapters_ite.yaml, shadows package)

Purpose: rank a LIST of LoRA adapters (incl. base) on a FROZEN held-out
prompt set with PINNED sampling, writing a ranked comparison to disk — the
yardstick that makes the training-fix changes verifiable instead of eyeballed.

Files (all in the writediary project, committable; no package edits):
- `eval/heldout_prompts.json` — frozen spec: 5 neutral prompts (verified
  absent from data/jim.md, 2026-07-25) + pinned sampling (temperature 0 =
  deterministic greedy/argmax; max_tokens 256). Changing it changes the
  comparability of results — treat as pinned.
- `scripts/eval_ite/compare_adapters_ite.coffee` — the step.
- `config/compare_adapters_ite.yaml` — the recipe.

Metrics per adapter (over the frozen prompts):
- termination_rate / runaway_rate — from `generated_tokens < max_tokens`
  (stopped on EOS vs hit the cap). THE metric for Change 1 (EOS supervision).
- distinct2_mean / distinct4_mean / top4_repeat_max — repetition. A loop shows
  as low distinct-n and a large top-4-gram count.
- voice_cosine_mean — cosine of each completion's embedding vs the Jim centroid
  (mean of kag_embeddings), same signal judge_run_ite ranks on. PRIMARY rank key.
- sentence_ending_rate, word_count_mean — shape.

Run it: point the pipe at the recipe (control_override.yaml or override.yaml
`pipeline: compare_adapters_ite`), set `compare_adapters` to the A/B you want,
`npx pipeline` from the pipe dir. Paths (build/model4, build/adapter) are
relative to the pipe CWD; eval spec is `{BASE}/eval/heldout_prompts.json`.

MEMORY: L.callLLM caches one loaded model per modelDir::adapter
(mlx/llm_dispatch.coffee getSession). base + N adapters = N+1 resident models.
Keep the list to 2-3 on this laptop.

First run (2026-07-25, base vs current no-EOS sweep adapter):
- **0% termination for BOTH** — every generation ran to max_tokens (256).
  Expected: with raw:true (no chat template) and NO EOS supervision, nothing
  learns to stop. This is exactly the baseline Change 1 must move.
- base stays diverse (distinct2 0.775) but never stops.
- **current adapter has COLLAPSED into a prompt-independent repetition loop**:
  distinct2 0.024, a single 4-gram repeated 43×, IDENTICAL output (wc 214)
  across all 5 prompts — it ignores the input. Red flag on the recent sweep
  adapter (rank 4 / effective scale 2.0). Treat this adapter as degenerate.

KNOWN BUG surfaced by the harness (blocks the voice metric project-wide):
- `voice_cosine` came back null for every completion —
  `mlx/session_api.coffee` `embed()` throws
  `[slice] Start indices must be integers, got type float32` at
  `mx.slice(valuesTensor, [0], [2], [keep])`. @frost-beta/mlx 0.4.0 requires
  integer slice start indices; the `[0]` JS array is inferred float32. This
  same embed path backs `voice_similarity_ite`, so voice is broken across the
  whole eval on this stack (likely the real cause of judge_run_ite's
  "voice_similarity unavailable" fallback, not only a judge bug). Fix:
  pass int32 start indices. Until fixed, the harness ranks on
  termination/repetition only (sufficient for Change 1; voice needed for 2-3
  and parameter search).
- Open question (not asserted — evidence mixed): does `session_api.generate`
  reset `llm.kvCache` between independent prompts? It clears in `embed()` and
  `dispose()` but not visibly in `generate()`. base outputs varied cleanly
  across prompts, arguing against contamination, but verify before trusting
  per-prompt cross-comparison.
