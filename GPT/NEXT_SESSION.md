# NEXT SESSION — read this first (handoff 2026-08-02 afternoon)

## Where we are (2026-08-02 afternoon)

**Increments e5, e6, e7 all landed today.** e1–e4 shipped
yesterday. The full arc is now:

- **e5** — Hoisted `chapter_number` to a single UI knob
  (`chapter_context` step). Was previously duplicated across three
  steps.
- **e6** — KAG emotion selection now DERIVED from beats. Local
  fork of `collect_diary_kag_ite` at `pipes/story/scripts/`. Each
  beat's `dramatic_function` maps to a KAG keyword; five UI
  dropdowns become manual overrides. Mapping table in
  `GPT/story/collect_diary_kag_ite.md`.
- **e7** — DELETED the legacy fallback path. `story_spine.coffee`
  is now a pure deterministic transform (170 lines, was 456); no
  more LLM path or atom-picker fallback. `select_story_recipe` +
  `resolve_story_parts` steps gone. `story_parts` now stubbed
  empty by a new `stub_story_parts` step just to satisfy the
  vendored `generate_diary_*_ite` steps' `S.need 'story_parts'`
  check. All 8 atom dropdowns removed from `story_spine`, all 5
  legacy diary dropdowns removed from `select_story_recipe`.

**Final UI knobs** (this is now the whole surface):

| Step | Knob |
|---|---|
| `chapter_context` | `chapter_number` |
| `story_outline` | `story_description` (textarea) |
| `collect_diary_kag_ite` | 5 optional `<kind>_emotion` overrides |
| `build_diary_prompt_ite` | `include_chunk_passages`, `chunk_excerpt_chars` |
| `generate_diary_with_adapter_ite` | `adapter_path` |

## What we learned in the Miser's Day debugging (READ THIS)

Spent hours here. The lessons matter more than the fix list.

1. **A shape-check bug in the outline generator silently degraded
   the whole pipeline.** `shapeLooksOk` in `story_outline.coffee`
   required `next_chapter_trigger?` truthy on every chapter —
   but the final chapter's trigger is (correctly) `null` per
   spec. Every valid outline was rejected, marked as
   `parse_error`, and downstream fell back to the legacy
   atom-picker path. Fix: `isFinal or ch?.next_chapter_trigger?`.

2. **`chapter_order.length >= 2` was too strict.** Jim's letters
   are single-piece pieces with a mid-paragraph turn. Enforced
   multi-chapter minimum forced the model to invent multi-chapter
   arcs where a single-letter description was the right thing.
   Fix: `>= 1`.

3. **Jim and Friend weren't in the character atoms.** The atom
   library was designed for the Tommy-shaped stories. When the
   outline generator saw "the description is a Jim letter" it
   couldn't put Jim in the cast — Jim wasn't a valid atom label.
   Result: Tommy was cast as protagonist, "the_stranger" was
   invented as witness, the story drifted to a bar-meeting arc
   completely unrelated to the source. Fix: added `Jim` and
   `Friend` to `story_atoms.characters` at the top of the list
   with narrator/addressee `role_hints`.

4. **The four-layer pipeline (outline → beats → scenes → prose)
   is designed for stories that ARE dramatic scenes.** A Jim
   letter is one voice, one mid-paragraph turn, no scenes, no
   props. Feeding a Jim letter through beats + scene_planner
   translates specific irritants (hacked-website client, lost
   cellphone, "castles yet to build") into abstract obligations
   ("the emotional signal is interpreted as a threat"), then into
   invented props (a paper crane in a garden cafe). The user's
   feedback: "reads very well but has no essence of the original
   story." This is a **real limitation** — the current pipeline
   cannot preserve a single-letter's essence because the source
   text vanishes after the outline step. **Deferred.** Candidate
   fix (e8 or later): "letter mode" that detects
   `cast.protagonist_label === "Jim"` + 1-chapter outline and
   bypasses beats + scene_planner, feeding the outline's beats
   directly to the generator. Or: carry `source_excerpt` through
   the pipeline as an anchor.

5. **The user distinguished KAG from RAG.** Don't conflate them.
   KAG = keyword-anchor-guide, a curated SQLite table mapping
   emotion keywords → pre-tagged Jim chunks. RAG (embedding-based
   semantic retrieval) does NOT exist in this pipeline. Both
   yesterday's docs and today's early discussion drifted; the
   `runner_gotchas.md` and `collect_diary_kag_ite.md` are clean
   now.

## Rough edges accepted for later (real ones)

- **KAG has emotion tags but not theme tags.** Selecting
  emotion=frustration returns chunks that share the emotional
  tag but not the topic of the target story. For a
  miserliness-themed piece, we'd want chunks tagged (e.g.)
  "money" or "generosity" — not there. Would require corpus-level
  re-tagging or adding a real RAG layer.
- **Letter-mode bypass** (item 4 above). The single biggest
  quality lever if you're generating Jim letters. Beats +
  scene_planner are actively harmful for that case.
- **The vendored `generate_diary_*_ite` steps still `S.need
  'story_parts'`.** We stub it with `{}`, which works but is a
  smell. Fork them locally next time we touch them.
- **kvCache patch in `node_modules`** still fragile (evaporates on
  `pnpm install`). Send upstream.

## Where files live (post-e7)

| Purpose | Path |
|---|---|
| Recipe | `~/writer/config/story.yaml` |
| Outline generator | `pipes/story/scripts/story_outline.coffee` |
| Spine (deterministic) | `pipes/story/scripts/story_spine.coffee` |
| Beats | `pipes/story/scripts/story_beats.coffee` |
| Scene planner | `pipes/story/scripts/scene_planner.coffee` |
| KAG collector (forked) | `pipes/story/scripts/collect_diary_kag_ite.coffee` |
| Prompt builder (forked) | `pipes/story/scripts/build_diary_prompt_ite.coffee` |
| State extractor | `pipes/story/scripts/state_extractor.coffee` |
| Archiver | `pipes/story/scripts/archive_chapter.coffee` |
| Chapter context | `pipes/story/scripts/chapter_context.coffee` |
| Stub story_parts | `pipes/story/scripts/stub_story_parts.coffee` |
| Atoms library (Jim + Friend added) | `pipes/story/data/jim_story_library.yaml` |

## Resume here (next session)

The user is running Miser's Day chapters through the pipeline
and evaluating output quality. The pipeline runs clean now. The
open question: **is the four-layer chapter pipeline the right
architecture for Jim letters, or should we add a letter-mode
bypass?** Every generated chapter so far has read well but lost
the source's essence. If they say "it's still not the source" —
propose the letter-mode bypass (item 4 in "what we learned").

---

# Prior handoff (2026-08-01 evening)

## Where we are (2026-08-01 evening)

Increments **e1 through e4** all landed:

- **e1** — Story Outline step above the chapter pipeline
- **e2** — `archive_chapter` step + per-chapter output dirs
- **e3** — `story_spine` becomes a deterministic transform when
  the outline is present; extended outline schema to carry
  story-scoped `cast` / `lens_label` / `story_protected_facts`
  and per-chapter `chapter_dramatic_axis`
- **e4** — `state_extractor` step closes the continuity loop

**Full DAG (adapter path enabled):**
```
load_library → story_outline
             ↘
               select_story_recipe → resolve_story_parts →
                 story_spine → story_beats → scene_planner →
                 collect_diary_kag_ite → build_diary_prompt_ite →
                 generate_diary_with_adapter_ite →
                 state_extractor → archive_chapter
```

## What's tested and what isn't

**Tested end-to-end** (through last generation):
- Outline → spine (deterministic transform) → beats → scenes →
  prompt → diary_adapted.txt. Output "looked good" per user.

**NOT YET tested** (bugfixes landed this session, no rerun yet):
- The state_extractor `S.need` + disk fallback fix. Last three
  attempts errored: (1) undefined depends_on ref, (2) parallel
  scheduling before generator finished, (3) disk read didn't
  find file. Current fix uses `S.need('diary_adapted_text')`
  first, falls back to `S.need('diary_base_text')`, then to
  disk. Compiled clean; needs a live run to confirm.
- `archive_chapter` copying `chapter_state.json` into
  `out/chapters/ch_N/`.
- The full continuity loop (chapter 2 reading chapter 1's
  actual state).

## Resume here (2026-08-02 morning)

1. **Verify the fix.** Rerun the pipe with the same story
   description and `chapter_number: 1`. Expect log line
   `[state_extractor] read chapter via S.need('diary_adapted_text')`
   and `out/chapter_state.json` to appear with a valid
   continuity_validation block. Then `[archive_chapter]` should
   copy everything into `out/chapters/ch_1/`, including
   `chapter_state.json`.
2. **Try chapter 2.** Set `chapter_number: 2`, rerun. Expect
   `[story_spine] outline-driven (ch=2, prior_state=yes)` —
   confirming the loop closed. The generated chapter 2 should
   open from what actually happened in chapter 1, not from the
   outline's planned inherited_state (if they diverged).
3. **If both work, commit.** The user planned to commit at
   end-of-day but hit the state_extractor bugs; commit
   deferred to morning.

## Rough edges we accepted (candidates for later polish)

- **`chapter_number` lives on three steps** (`story_spine`,
  `state_extractor`, `archive_chapter`). Recipe comments call
  it out. Hoist to a single UI param via a shared step or a
  `run:`-block global next.
- **`state_extractor.depends_on` names the enabled generator
  by hand** (`generate_diary_with_adapter_ite`). The pipeline
  runner prunes `[never]`-gated steps AND their artifacts from
  the DAG entirely, so we can't list both. If the override is
  flipped to the base path, both `depends_on:` and `needs:`
  lines must flip. Ideal fix: a canonical `chapter_text`
  artifact both generators produce, or a runner feature that
  treats needs on a pruned artifact as "satisfied by absence."
  Deferred.
- **Legacy 5-beat subgraph** (`select_story_recipe`,
  `resolve_story_parts`, `collect_diary_kag_ite`) still runs
  and feeds atmosphere into the prompt. Could be removed now
  that outline+spine are authoritative.
- **kvCache patch in node_modules** still lives outside the
  repo. Send upstream to `@jahbini/pipeline`.

---

# Prior handoff (2026-08-01 mid-day)

> **Canonical repo is now `~/writer`. `~/writers-guild` is being retired.**
> All future edits, notes, and memories belong here. If a memory or
> doc still references `writers-guild`, treat it as archival and
> update it when you touch it.

## Today (2026-08-01): Story Spine → four-layer split — see `story/story_spine.md`, `story/README.md`

The chapter pipeline is being restructured into four independent
planning layers:

```
Premise  →  Story Spine  →  Story Beats  →  Scene Planner  →  Prose
```

Golden rule: each layer decides only what its layer owns. The Story
Spine describes **dramatic necessity** ("an opportunity to receive
help appears") — it never stages ("Southwick appears at the
roadside"). Story Beats sharpen necessity into ordered abstract
movements with a first-class `conflict: {need, protection}`. Scene
Planner is the only layer that assigns concrete cast to dramatic
roles (Tommy's old girlfriend embodies the opportunity, etc.).

**Narrative voice at every layer: first-person Jim, always.** Even
when the dramatic protagonist is Tommy or someone else, Jim narrates
as observer/witness/recounter. Do NOT bind voice to
`spine.cast.protagonist.label`. The LoRA/base was trained on Jim's
voice; close-third loses it.

### Increment status
- (a) ✅ 2026-08-01 — Story Spine slimmed to dramatic necessity only.
  Removed `causal_spine`, `scenes`, `required_story_events`. Split
  `questions` into `story` / `reader_curiosities` / `symbolic`.
  Prompt now includes explicit WRONG/RIGHT examples of the
  abstraction level. `build_diary_prompt_ite` fork updated: voice
  pinned to first-person Jim; renders axis + protected_facts +
  three question kinds instead of walking scenes.
- (b) ✅ 2026-08-01 — Story Beats step landed at
  `pipes/story/scripts/story_beats.coffee`. Emits `story_beats_json`
  with 3–5 ordered abstract movements, each carrying a first-class
  `conflict: {need, protection}`. Cast + lens + spine_ref carried
  forward from spine so Scene Planner has one artifact to read.
  `build_diary_prompt_ite` fork now folds beats as the PRIMARY
  backbone, with the spine kept as "must-not-contradict" context.
  Serialized via DAG: `story_spine → story_beats →
  build_diary_prompt_ite → generate_diary_without_adapter_ite`.
  See `story/story_beats.md`.
- (c) ✅ 2026-08-01 — Scene Planner step landed at
  `pipes/story/scripts/scene_planner.coffee`. Emits `scene_plan_json`:
  one selected concrete scene per beat plus 2–3 candidates per beat
  for provenance. First layer allowed to assign specific cast to
  beat obligations, pick locations, describe physical action.
  **Cast discipline enforced in code**: `present_cast` filtered
  post-LLM to labels that exist in the spine's cast block; unnamed
  passersby survive in the free-text `action`/`setting` fields.
  `build_diary_prompt_ite` fork now folds scenes as the CONCRETE
  backbone (one paragraph per scene, in order); beats become the
  abstract dramatic obligation each scene must land; spine stays as
  "must-not-contradict". Serialized via DAG: `story_spine →
  story_beats → scene_planner → build_diary_prompt_ite →
  generate_diary_without_adapter_ite`. See `story/scene_planner.md`.
- (d) ✅ 2026-08-01 — Voice fidelity. `build_diary_prompt_ite`
  reframed as a **letter from Jim to Friend**, retelling something
  that happened to Tommy from half-forgotten memory. Adapter
  carries cadence; prompt only fixes genre/framing/POV.

  Planner-internal metadata stripped from the generator prompt:
  `satisfies_conflict`, `lands_end_state`, `selection_rationale`,
  `alternatives_considered`, `dialogue_beats`, `sensory_grounding`.
  The pre-(d) run had the model **parroting those lines as
  narration** ("The opportunity to restart the car is now
  physically available"), which killed the voice. Beats block also
  dropped from the generator prompt entirely — beats are useful for
  Scene Planner input; scaffolding by generation time. Only
  `protected_facts` from the Spine survive to the generator.
  Jim's own past RAG passages promoted to the top of the prompt as
  a register anchor (no "match cadence" instruction — that's the
  adapter's job).

  New voice-line text (in `build_diary_prompt_ite.coffee`):
  > "You are Jim from St. John's, writing to a friend. This is a
  > letter, not a chapter. Open with an address ('Hi, Friend' or
  > similar). Warm, wry, digressive. Gossipy. It happened to
  > `#{protagonist}`. You (Jim) were not the center of the action
  > — you're retelling it the way you heard it, or half-remember
  > it, or pieced it together after. Jim tells stories from
  > half-forgotten memories. Details are hazy in places. Some
  > things are third-hand. Jim wanders — a small unrelated
  > observation or aside somewhere is welcome. Jim is never inside
  > another character's head."

  Confirmed working on the Tommy premise: chapter opens as a
  letter, references Southwick and Tommy without immersing in
  either, retells the roadside beats from third-hand memory.

### Resume here (next session)

The core four-layer split shipped and produced a good chapter.
Nothing urgent left. Optional follow-ups in rough payoff order:

1. **Kill the legacy 5-beat subgraph** —
   `select_story_recipe` / `resolve_story_parts` / the
   `story_parts`-fed atmosphere lines in the prompt. The four
   layers are now authoritative; the legacy branch is atmosphere
   only. Removing it simplifies both the UI and the prompt.
2. **Per-scene KAG matching** — `collect_diary_kag_ite` still
   matches Jim's own passages against the legacy 5-beat picks.
   Rewire it to match against each `scene.action` /
   `scene.outcome` instead, so the voice reference passages
   actually align with the chosen staging.
3. **Upstream the kvCache patch** — currently lives in
   `~/writer/node_modules/@jahbini/pipeline/mlx/session_api.coffee`
   and evaporates on `pnpm install`. Send to `@jahbini/pipeline`.
4. **JSON Schema validation with ajv** — replace `shapeLooksOk`
   in each planner step with real schemas, so failures produce
   actionable messages instead of a `parse_error` blob.

### One thing to double-check next session

The user's run report mentioned `generate_diary_with_adapter_ite`
ran for 248s, but its recipe entry has `depends_on: [never]`. Two
possibilities: the UI is overriding `depends_on`, or the user
manually switched it. Either way — worth confirming the recipe is
being honored before assuming a report of `_with_adapter_` timings
means the adapter path is active.

### Landmines (unchanged from 2026-07-31)

- `mlx/session_api.coffee` `generate()` needs the in-process
  `mx.dispose?(llm.kvCache); llm.kvCache = null` patch at the top,
  matching what `embed()` already does. `@frost-beta/llm` reuses
  `this.kvCache` otherwise → mx.array crash. Patch lives in
  `node_modules/` and **evaporates on `pnpm install`** — send
  upstream.
- Two `S.callLLM` steps on the same `modelDir` share the getSession
  cache. They MUST have an explicit `depends_on` edge. Current DAG
  serializes `story_spine` → `build_diary_prompt_ite` →
  `generate_diary_without_adapter_ite`.
- `temperature: 0` triggers div-by-zero in `@frost-beta/llm`'s
  sampler. Use `0.05`.

## Archived: 2026-07-31 handoff — Story Spine, Phase 1 (superseded)

The Phase 1 spine emitted `story/questions/causal_spine/scenes` and
was consumed by the prompt builder as a scene walk. That coupling
was what produced the wrong story (Southwick prematurely staged as
the opportunity when Tommy's old girlfriend was the premise atom).
The four-layer split above is the fix. Historical Phase 1 details
kept below for reference; do not use them as a spec.

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
