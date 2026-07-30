# NEXT SESSION — read this first (handoff 2026-07-31)

## Today (2026-07-31): Story Spine, Phase 1 — see `story/story_spine.md`

Built the `story` recipe — a fork of `diary_ite` with a new
`story_spine` step that reads eight atom dropdowns
(protagonist/antagonist/witness + 4-axis dramatic atoms + interpretive
lens) and emits `out/story_spine.json`: a strict JSON structural plan
(story/questions/causal_spine/scenes) that a future prose stage will
expand into one chapter. Recipe at `<BASE>/config/story.yaml`, atoms
library at `pipes/story/data/jim_story_library.yaml` under
`story_atoms:`, schema at `pipes/story/schemas/story_spine.schema.json`,
step implementation at `pipes/story/scripts/story_spine.coffee`. Sacred
style (`action: (S) ->`), uses `S.callLLM` (in-process node-mlx), NOT
`S.callMLX` (Python subprocess).

Confirmed working: "The Road That Flickers" — 4 scenes, 8 causal steps,
3 central questions, tarot lens applied to premise.

**Two landmines documented in `story/story_spine.md`, worth the second
read:**
- `mlx/session_api.coffee` `generate()` got an in-process patch that
  disposes `llm.kvCache` before each call (`@frost-beta/llm` reuses it
  otherwise → position-index confusion → mx.array crash). The patch
  lives in `node_modules/` and **evaporates on `pnpm install`** — needs
  upstream and re-application until it lands.
- Two steps that call `S.callLLM` on the same `modelDir` share the
  cached LLM object via `getSession`, so they must have an explicit
  `depends_on` edge. Currently `story_spine.depends_on:
  [resolve_story_parts, generate_diary_without_adapter_ite]` — the
  latter forces serialization.

**Resume here — Phase 2:** wire `story_spine_json` into
`build_diary_prompt_ite` so the diary generator actually produces a
chapter shaped by the structural plan (not just the current diary
entry). Right now the spine is a sidecar; nothing consumes it. Also
worth: convert the JSON-shape check into full JSON Schema validation
against `pipes/story/schemas/story_spine.schema.json` (would need
`ajv` as a dep) — but skip it while the model output is consistent.

## Previous handoff (2026-07-26): recipe & script consolidation — see `RECIPE_CLEANUP_2026-07-26.md`
Shrank the recipe corpus one recipe at a time. Renamed `base_ite → reset`;
merged `lora_ite`+`diary_full4test` → **`train_lora`** (tuned full-corpus params
as recipe defaults); folded `prompt_rag_llm` into **`prompt_llm`** behind a
`rag_top_k` toggle. Kept `download_model`, `test`, `reembed_clean`, `train_llm`,
`prompt_ite` (with reasons). Recorded the guiding principle in `README.md`:
`_ite`/`_llm` suffixes are **transitional door-markers** — judge by
obsolete-vs-live, not by suffix; suffix-less names are the direction.

**Resume here:** continue the recipe review (next: the eval pair `eval_ite` vs
`compare_adapters_ite`), then delete the verified-dead scripts (`kag_user_ite/`
whole area, `story/` originals, `build_lora_config_ite`, etc.) — full list +
rationale in `RECIPE_CLEANUP_2026-07-26.md`.

---

## Previous handoff (2026-07-25 evening)

Diary LoRA work. Big infra wins today; one open question on the adapter.
**Headline: a 24-story / 300-iter LoRA now trains in ~4–5 min with FLAT memory.**

## Where things stand
- Sandbox pipe: `pipes/test` (clone of `diary`: cloned corpus DB 169 stories /
  825 embeddings, symlinked shared model, isolated adapter). Run everything there.
- Current `pipes/test/build/adapter` = a **200-iter v2 adapter** (it's fine to
  keep; the full run died at the step-200 eval BEFORE the eval leak was fixed —
  see below). Config: rank 8 / alpha 16 (scale 2.0) / dropout 0.05 / num_layers 8.

## Fixes landed today (canonical in ~/pipeline, mirrored to writediary node_modules)
1. **`num_layers` wired end-to-end** — was a silent no-op (wrapped all 36 blocks);
   now restricts LoRA to top N. Files: `mlx/lora/wrap.coffee` (restrict + record
   in adapter_config), `mlx/lora/train.coffee`, `mlx/session_api.coffee` (inference
   wraps same N), `scripts/lora_ite/run_lora_train_ite.coffee` +
   `scripts/train_llm/run_lora_train_llm.coffee`.
2. **EOS supervision** — `scripts/lora_ite/build_lora_dataset_ite.coffee` appends
   the model's EOT (`<|im_end|>`, read from tokenizer_config) to every row.
3. **THE memory fix** — `train.coffee` leaked ~1.3 GB/step (OOM'd ~step 20; the old
   sweep could only do ~10-iter batches). Fixed by scoping the step in `mx.tidy`
   (return loss + model params + optimizer state; frees the rest). Applied to BOTH
   the training loop AND `evaluate()` (the eval leak was the "memory hog" at
   stepsPerEval=200). Plus cache limit + per-step `clearCache` + per-step memory
   logging (`mem active=/peak=`). Memory is now flat ~2.1 GB.
4. **Voice fixed** — `session_api.embed` `mx.slice` threw on node-mlx 0.4.0; replaced
   with `mx.take(…, mx.arange(keep).astype(int32), 2)`. This also repairs
   `voice_similarity_ite` / the full-cycle judge.
5. **Builder knobs** — `max_total_tokens` param + graceful skip (was a hard throw);
   `tokenizeCorpus` forces EOT onto the last token when a row IS truncated.
6. **Eval harness** (writediary project): `scripts/eval_ite/compare_adapters_ite.coffee`
   + `config/compare_adapters_ite.yaml` + frozen `eval/heldout_prompts.json`
   (temp 0, now max_tokens 512) and `eval/heldout_prompts_t07.json` (temp 0.7, 512).
   Ranks a list of adapters on frozen prompts: termination / repetition (distinct2,
   top-4-gram) / voice-cosine.
7. **UI**: added "Delete Log Files" / "Delete Output Files" buttons (left column) —
   `ui_server.coffee` + `ui/index.html` (writediary-local). Needs UI restart to load.

## Eval findings (the open question)
- **v1** (truncation, maxSeqLen 512, 300 iters): collapsed to **immediate EOS →
  empty**. Cause: head-truncation forced EOT mid-word → "EOS follows anything".
- **v2** (natural rows: max_total_tokens 400 / maxSeqLength 640, 200 iters):
  **voice WIN** (0.717–0.733 vs base 0.699–0.703), coherent evocative Jim-voiced
  prose — but **does NOT terminate** (0% even at 512 cap; base terminates ~20%) and
  rambles/repeats somewhat over length (distinct2 0.51 @512).
- Greedy (temp 0) exaggerates both loops and EOS-collapse; **temp 0.7 is the honest
  read**. At 0.7 the v2 loop was an artifact (distinct2 0.08→0.77).
- **Conclusion so far: EOS-append improved voice but did NOT teach stopping.**
  v1 over-corrected, v2 under-corrected.

## Open LoRA-eval track (recipe names updated 2026-07-26 — the `*4test` recipes were deleted in the consolidation)
1. Clear the partial adapter and run the **full clean 300-iter v2** (eval-safe now):
   `rm -f pipes/test/build/adapter/*`, then user runs **`train_lora`** (select it in
   the UI dropdown — that's what sets control_override). It now carries exactly the
   v2 sweet-spot params as defaults (rank 8 / alpha 16 / dropout 0.05 / 8 layers /
   300 iters / maxSeqLength 640). ~4–5 min.
2. Then user runs **`compare_adapters_ite`** against the frozen prompt sets
   `eval/heldout_prompts.json` (temp 0, 512) and `eval/heldout_prompts_t07.json`
   (temp 0.7, 512). I read `pipes/test/eval_out/adapter_comparison.json`.
   Question: does 300 iters (vs 200) terminate any better?
3. If still 0% termination, DECIDE direction:
   - (a) Accept the voice win; handle length via generation config (the diary
     generator already runs structured per-event sections with its own max-tokens,
     so whole-entry self-stop may not matter).
   - (b) Push termination: shorter training rows (~150 tok → more EOS density per
     token trained), and/or weight the EOS token in the loss. Risk: re-collapse to empty.
   - Also worth trying: eval prompts are instructions but training prompts are story
     FRAGMENTS (OOD) — fragment-style eval prompts may be more representative.

## Working rules (don't forget)
- I do NOT run the pipeline / tests. User runs; I read results from disk
  (filesystem access) or they paste. See memory `no-running-tests`.
- I do NOT touch git. User commits.
- Edit surface: canonical edits in `~/pipeline`, then MIRROR to
  `~/writediary/node_modules/@jahbini/pipeline/...`. Recipes/eval/config live in
  the writediary project.
- `*4test` recipes = "the exact thing Claude wants run" (self-contained, no override
  ambiguity). But the UI dropdown must have it SELECTED before Run.
