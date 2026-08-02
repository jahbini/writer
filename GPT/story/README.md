Step memories for the `story` recipe — the four-layer chapter pipeline
in `~/writer`. `writers-guild` is being retired; all future work
happens here.

## Five-layer planning + continuity (2026-08-01, e1–e4 landed)

The full arc is now:

```
free-form description
   ↓
story_outline      whole-story arc + chapter_order[N chapters]         (e1)
   ↓
[per chapter — driven by chapter_number UI knob:]
  story_spine       deterministic transform of outline entry            (e3)
                    + inherited state from ch_<N-1>/chapter_state.json  (e4→e3 loop)
     ↓
  story_beats → scene_planner → build_diary_prompt_ite → generate_diary_*
     ↓
  state_extractor   compares generated chapter vs planned entry;         (e4)
                    emits actual_ending_state / questions_opened /
                    obligations_created / new_protected_facts +
                    continuity_validation
     ↓
  archive_chapter   copies chapter artifacts (incl. chapter_state.json)  (e2)
                    to out/chapters/ch_<N>/
```

### The continuity loop

1. User writes the story description → `story_outline` produces
   `chapter_order[]`.
2. User sets `chapter_number: 1`, runs the pipeline.
   `story_spine` reads the outline (no prior chapter), derives
   chapter 1's spine. Beats/scenes/prose generate. State
   extractor produces `chapter_state.json` with actual outcomes.
   Archiver copies it into `out/chapters/ch_1/`.
3. User sets `chapter_number: 2`, runs again. `story_spine`
   reads outline entry 2 AND `out/chapters/ch_1/chapter_state.json`
   — prefers `actual_ending_state` over the outline's planned
   `inherited_state`. Chapters honor what actually happened, not
   what was hoped.
4. Repeat through the final chapter.

### Report-only continuity validation

`chapter_state_json.continuity_validation.status` is one of
`matches | drift | conflict`. Report-only — the author reads it,
decides whether to regenerate or accept the drift. Nothing
auto-blocks the next chapter.

### Backward compatibility

If the outline is missing / `parse_error`, `story_spine` falls
back to the pre-e3 atom-picker + LLM path. If the outline is
present but `state_extractor` fails, the next chapter's spine
falls back to the outline's planned `inherited_state`. Each layer
degrades gracefully.

See `story/story_outline.md`, `story/story_spine.md`,
`story/state_extractor.md`, `story/archive_chapter.md`,
`story/chapter_context.md`,
`story/collect_diary_kag_ite.md`.

**Also read `story/runner_gotchas.md`** — captures the
`[never]`-gate pruning, `process.cwd()` unreliability, and the
`depends_on` scheduling semantics learned the hard way while
landing e4.

## Four-layer chapter planning

The pipeline separates dramatic obligation from dramatic staging:

```
Premise            (atom picks, immutable)
   ↓
Story Spine        dramatic necessity: axis + facts + three question kinds
   ↓
Story Beats        ordered abstract movements + first-class conflict {need, protection}
   ↓
Scene Planner      concrete Scene Candidates, one selected per beat
   ↓
Prose              build_diary_prompt_ite → generate_diary_*_ite → chapter
```

**Golden rule:** each layer only decides what its layer owns. The
Story Spine must never decide that Southwick is the opportunity or
that Tommy remembers his girlfriend — those are Scene Planner
decisions, downstream. The Spine only asserts "an opportunity to
receive help appears" and "the internal obstacle grows stronger than
the immediate need." Story Beats sharpen those into ordered
movements with explicit need/protection conflicts. Scene Planner
picks the concrete realization.

**Narrative voice at every layer: first-person Jim.** Always. Even
when the dramatic protagonist is Tommy or someone else, Jim narrates
as observer/witness/recounter — the LoRA/base model was trained on
Jim's voice; close-third loses it.

## Recipe and pipe

- Recipe: `<BASE>/config/story.yaml`
- Pipe: `pipes/story/` (activated by `pipes/story/override.yaml`
  → `pipeline: story`)
- Model: `build/model4` symlink chain →
  `~/writediary/pipes/diary/build/model4` (weights not in this repo)

## Current pipeline graph

```
load_library              → story_library
select_story_recipe       → story_recipe          (legacy 5-beat dropdowns)
resolve_story_parts       → story_parts
collect_diary_kag_ite     → diary_kag             (embeddings; ~30s)
story_spine               → story_spine_json      (dramatic necessity)
story_beats               → story_beats_json      (ordered abstract movements)
scene_planner             → scene_plan_json       (concrete staging, one scene per beat)
build_diary_prompt_ite    → diary_prompt_text     (folds spine + beats + scenes → prompt)
generate_diary_without_adapter_ite → diary_base_* (MLX chapter)
generate_diary_with_adapter_ite    → diary_adapted_* (depends_on: [never] until adapter is trained)
```

Increment status:
- (a) 2026-08-01 ✅ — Spine slimmed to dramatic necessity, questions
  split three ways, voice pinned to first-person Jim.
- (b) 2026-08-01 ✅ — Story Beats step landed. Ordered abstract
  movements with first-class `conflict: {need, protection}`. See
  `story/story_beats.md`.
- (c) 2026-08-01 ✅ — Scene Planner step landed. 2–3 candidates per
  beat, one selected. First layer that assigns specific cast to
  beat obligations; cast discipline enforced in code. Prompt
  builder now uses scenes as the concrete backbone. See
  `story/scene_planner.md`. **Note (revised in Increment d): the
  standalone `candidates` array was removed; alternates are now
  captured per-scene in `alternatives_considered: [one-liner,
  one-liner]` to cut generation cost.**
- (d) 2026-08-01 ✅ — Voice fidelity. `build_diary_prompt_ite`
  reframed as a **letter from Jim to Friend**, retelling from
  half-forgotten memory. Adapter carries cadence; the prompt only
  fixes genre/framing/POV. All planner-internal metadata
  (`satisfies_conflict`, `lands_end_state`, `selection_rationale`,
  `alternatives_considered`, `dialogue_beats`, `sensory_grounding`)
  stripped from the generator's prompt to prevent the model from
  parroting dramaturg-speak as narration. Beats block also dropped
  from the generator prompt entirely; only `protected_facts` from
  the Spine survives. Jim's own past RAG passages promoted to top
  of the prompt as register anchor.

## Conventions

- Atoms library at `pipes/story/data/jim_story_library.yaml` carries
  `story_atoms:` (5 axis lists × 10 entries + 4 lenses). Also keeps
  the legacy `library:`, `stories:`, `arc_shapes:`, `time_of_day:`,
  `recipe_defaults:` blocks for `load_library`'s assertions.
- Sacred steps only. `action: (S) ->`, `await S.need`, `S.param`,
  `S.callLLM` (in-process node-mlx — NOT `S.callMLX`, which is the
  Python subprocess path and 10× slower).
- Never Python. Nowhere. Ever.
- Runtime tuning: nested `llm:` block on each MLX step. Keys are
  camelCase (`maxTokens`, `temperature`, `topP`, `systemPrompt`).
  Ledger auto-injects them into the `callLLM` payload.
- Do NOT edit `config/*.yaml` recipes for tuning — use
  `override/<recipe>.yaml`. Exception: adding a new step to a new
  recipe file (like `config/story.yaml` itself) is not tuning.
- Session cache: two `S.callLLM` steps on the same `modelDir` MUST
  have an explicit `depends_on` edge. See `story_spine.md` for
  chapter and verse.
