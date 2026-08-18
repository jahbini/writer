# simplify_chunks_ite

**File**: `pipes/story/scripts/simplify_chunks_ite.coffee`
**Recipe**: `config/simplify.yaml`
**Meta backend**: `meta/hfchat.coffee` in `@jahbini/pipeline` (see
`~/pipeline/GPT/hfchat_meta.md`)

## Purpose

Produces a plain-English paraphrase for every KAG chunk
(`kag_entries.chunk_index`) that doesn't already have one, and stores
the paraphrase in the `chunk_simplifications` sqlite table (managed by
the pipeline's sqlite meta).

Paired with the Jim-style original at LoRA training time, these give
the adapter a supervised style-transfer signal (simple → Jim).

## Inputs

- `chunkSimplificationsMissing.jsonl` (sqlite meta request key,
  routed via the `chunk_simplifications_missing` source-only artifact)
  — rows: `{story_id, chunk_index, title, story_text}` for every
  distinct kag-chunk pair with no simplification row yet.

## Outputs

- Per-chunk: writes `chunkSimplification{sid|idx}.json` → one row in
  `chunk_simplifications` (idempotent upsert).
- Step-level: makes `simplify_report` — `{processed, failed, failures,
  remaining, completed_at}`.

## Invariants and pitfalls

- **Chunking must match `collect_diary_kag_ite`**. Both scripts split
  `stories.text` into 5 equal paragraph groups via `buildStoryGroups`.
  If you change the formula in one place, change it in the other —
  otherwise the simplified text won't align with the Jim-style chunk
  the KAG entries point at.
- **Model comes from `run.hfchat_default_model`** in the recipe. Do
  not pin a model in step params. The provider policy suffix
  (`:cheapest` / `:fastest` / a named provider) belongs in the same
  place — meta/hfchat reads it every dispatch, so a config change
  takes effect without a runner restart.
- **HF_TOKEN required** in env. Missing → step throws at first hfchat
  write.
- **Iterative**. `batch_size` (default 25) chunks per invocation. Re-run
  picks up whatever remains. Safe to `restart_here` mid-batch — a chunk
  with a persisted row is skipped next time.
- **Admission control is optional**. If the recipe declares
  `run.resources.hf-api`, the step gates each hfchat call through a
  local `ResourceLedger` (see [`GPT/resource_ledger.md`](../resource_ledger.md)).
  Without that block, the step behaves as it did before admission
  control landed. When enabled, expect log lines like
  `[simplify_chunks_ite] simplify.<sid>.<idx>.hfchat queued by resource ledger`
  for calls that got queued.

## Failure modes

- Non-2xx HF response → `meta/hfchat` rejects the notifier; step logs
  the error and records `{story_id, chunk_index, reason}` in
  `simplify_report.failures`. Row not written; a re-run retries it.
- Bad chunk (out-of-range `chunk_index`, empty text) → same failure
  path, never hits HF.
- Ledger rejection (unknown owner, impossible needs, duplicate id) →
  same failure path. Duplicate id shouldn't happen — the memo key is
  unique per (story_id, chunk_index) — but if it does, the throw makes
  the bug loud.
