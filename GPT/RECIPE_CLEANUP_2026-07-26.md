# Recipe & Script Consolidation — 2026-07-26

Session goal: audit the recipe/script corpus and shrink it toward a clean,
minimal, non-redundant set. Done one recipe at a time (describe → decide:
rename / delete / keep / fold). Canonical edits in `~/pipeline`, mirrored to
`~/writediary/node_modules/@jahbini/pipeline`.

## Driving principle (now recorded in GPT/README.md)

`_ite` / `_llm` suffixes are **transitional door-markers**, not a permanent
taxonomy:
- `_ite` = the grandfathered path (Python/mlx-lm spawn via `L.callMLX`)
- `_llm` = the in-process node-mlx door (`L.callLLM`)

Target end-state: every script **dual-aware** (speaks both doors), at which
point the suffix carries no information and drops away. So suffix-less names
(`reset`, `train_lora`, `reembed_clean`, `download_model`, `test`) are the
**direction**, not legacy. Judge a recipe/script by **obsolete** (old-path-only
AND superseded by a live equivalent) vs **live** — never by whether it ends in
`_ite`/`_llm`. Do NOT churn names just to add a suffix.

## Audit method (objective, reusable)

Built a usage/orphan map: parsed every recipe's step `run:` refs across
`~/pipeline/config` + `~/writediary/config`, cross-referenced against scripts on
disk, and flagged scripts referenced by NO recipe. Then grepped each orphan's
basename across all yaml + checked `require()` deps to confirm truly-dead before
recommending removal. (mtime is useless here — every file reads the checkout
date — so "oldest" means legacy-generation, not filesystem age.)

## Changes landed

### Renames
1. **`base_ite` → `reset`.** `config/base_ite.yaml` → `reset.yaml` (both copies),
   title comment updated. It's the bootstrap/reset chain:
   `reset_base_environment_ite → download_model → quantize_model →
   seed_story_sqlite`. Every old-name reference was a comment example (nothing
   did `include:`/`pipeline: base_ite`), so no breakage. Also renamed the two
   pipe overrides `pipes/{test,diary}/override/base_ite.yaml → reset.yaml` and
   fixed their `pipeline: base_ite` → `reset` selectors.

### Merges
2. **`lora_ite` + `diary_full4test` → `train_lora`** (package `config/`, sibling
   of `train_llm`). New `train_lora.yaml` carries the tuned full-corpus params as
   **recipe defaults** (user's choice): rank 8 / alpha 16 (scale 2.0) /
   dropout 0.05 / 8 layers / 300 iters / maxSeqLength 640, `batch_size` 200,
   `max_total_tokens` 400. Same 4 `lora_ite/` scripts. Deleted `lora_ite.yaml`
   (+mirror) and `diary_full4test.yaml`. Rewired all `pipeline: lora_ite`
   selectors → `train_lora`; renamed the per-pipe overrides
   `override/lora_ite.yaml → train_lora.yaml` (diary override slimmed so the new
   defaults aren't clobbered; test override keeps its `batch_size 24` sandbox
   values). Deleted the **obsolete** root `override/lora_ite.yaml` (it wired in
   the dead `build_lora_config_ite` step + the old mlx-lm `--config` path).
   Incremental training is not lost — it's just `batch_size`/`iters` in a pipe
   override.
   - NOTE for the dual-aware pass: `train_lora`'s train step
     (`lora_ite/run_lora_train_ite.coffee`) and `train_llm`'s
     (`train_llm/run_lora_train_llm.coffee`) now BOTH drive the node-mlx
     `trainLoRA` path — a script-merge candidate. Kept both for now (full
     pipeline vs isolated door smoke).

3. **`prompt_rag_llm` → folded into `prompt_llm`.** RAG front-end merged into
   `generate_prompt_llm.coffee`, gated by `rag_top_k` (0 = plain generation, the
   default; >0 = embed query → cosine-rank the clean chunk embeddings → prepend
   the top-K passages as lore context). Kept `prompt_llm`'s superset features
   (legacy mlx-key translation, prompt-echo stripping); carried over all RAG
   helpers, passage logging, and passages-in-diary-record. `prompt_llm.yaml`
   gained `rag_top_k` (UI textarea, default `"0"`) + `clean_embeddings_file`.
   Deleted `prompt_rag_llm.yaml` and `generate_prompt_rag_llm.coffee` (+mirror).
   Test pipe repointed to `prompt_llm` with `rag_top_k: 4`. One recipe now does
   both plain and RAG generation via a single toggle.

### Keepers (reviewed, deliberately kept)
- **`download_model`** — grandfathered. `npm run model` (`bin/model.sh`) writes
  `pipeline: download_model`; `reset` also inlines the same two model scripts.
  Live entry point, just non-`_ite` named.
- **`test`** — kept as a worked example for future pipeline users.
- **`reembed_clean`** — live one-time RAG re-embed (writes
  `build/chunk_embeddings_clean.jsonl`). NOT renamed (suffixes are transitional).
- **`train_llm`** — isolated node-mlx training-door smoke test (1 step, tiny
  fixture, separate `build/adapter_llm`). Distinct from the full `train_lora`.
- **`prompt_ite`** — package minimal reference recipe (smallest `_ite`; already
  on the node door despite its name).

### Retirement
4. **`full_cycle_ite` retired (deleted).** The big inlined end-to-end recipe was
   heavily stale — it referenced pre-reorg script paths
   (`story/reset_base_environment_ite`, `kag_oracle/quantize_model`) that moved
   in the consolidation, and its override still drove the old Python `mlx:`
   training path. Decision: run the individual recipes in sequence instead.
   Deleted `config/full_cycle_ite.yaml` + every override selector (root, test
   pipe, diary pipe) + the stale generated root `experiment.yaml`. No scripts
   orphaned (its step scripts are all shared with live recipes). Doc mentions
   updated; dated `advice/2026-06-26.md` keeps its mention as history.

## Diary pipe finalized (complete, up-to-date set)
`pipes/diary/override/` now selects exactly the production set, in order:
`reset` → `oracle_ite` → `reembed_clean` → `train_lora` → `diary_ite` →
`prompt_llm` → `compare_adapters_ite`. Changes: added `prompt_llm` (adapter +
`rag_top_k: 4`) and `reembed_clean`; retired the `prompt_ite` override (kept as
the package reference recipe) and the `full_cycle_ite` override. User is
verifying each recipe runs + is appropriate. Dependencies: `prompt_llm` RAG
needs `reembed_clean` to have run first (else it falls back to kag_embeddings
with a log warning); `diary_ite` + `prompt_llm` read `build/adapter` from
`train_lora`.

## Current recipe inventory
- Package (`~/pipeline/config`): `chat_llm`, `diary_ite`, `diary_translate_ite`,
  `download_model`, `eval_ite`, `fuse_llm`, `oracle_ite`, `prompt_ite`, `reset`,
  `test`, `train_llm`, `train_lora`
- Project (`~/writediary/config`): `compare_adapters_ite`, `prompt_llm`,
  `reembed_clean`

## Remaining review queue (not yet reviewed, one-at-a-time)
`chat_llm`, `diary_translate_ite`, `eval_ite`, `fuse_llm`. (The diary-set
recipes — `reset`, `oracle_ite`, `reembed_clean`, `train_lora`, `diary_ite`,
`prompt_llm`, `compare_adapters_ite` — are being verified live in the diary
pipe.) **Next up:** the eval pair — `eval_ite` (package) vs `compare_adapters_ite`
(project) — likely the same overlap/merge pattern as the prompt family.

## Pending: dead-scripts deletion (deferred — went recipe-first)
Verified dead (0 recipe refs AND 0 `require()` refs), NOT yet deleted:
- `kag_user_ite/` — whole area (5): `assemble_story_sqlite`,
  `build_kag_prompt_sqlite`, `create_story_parts_sqlite`,
  `expand_story_parts_sqlite`, `select_story_sqlite`. No recipe drives it.
- `story/` legacy originals (2): `assemble_story`, `expand_story_parts`.
- `diary_ite/select_diary_events_ite`
- `kag_oracle_ite/prepare_kag_segments_sqlite`
- `lora_ite/build_lora_config_ite` — now fully orphaned (its only referrer, the
  root `override/lora_ite.yaml`, was deleted). Also remove the stray
  `writediary/params/build_lora_config_ite.yaml`.
- Open question before cutting: is `kag_user_ite/` an abandoned experiment
  (delete) or a reference implementation to keep like `test`?

## Cosmetic loose ends
- The script *directory* `scripts/base_ite/` and a few GPT doc comments still say
  "base_ite" (non-functional; the script namespace wasn't renamed with the
  recipe).
