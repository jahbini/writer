Step memories for the `story` recipe — the four-layer chapter pipeline
in `~/writer`. `writers-guild` is being retired; all future work
happens here.

## Four-layer planning (2026-08-01)

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
