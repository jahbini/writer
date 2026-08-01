Step: `story_spine`
Recipe: `story`
Script: `pipes/story/scripts/story_spine.coffee`
Repo of record: `~/writer` (writers-guild is retired)

## Purpose

Sacred dramaturg. The Story Spine is the SECOND of four planning
layers and captures **dramatic necessity only**:

```
Premise (atom picks)
   ↓
Story Spine        ← this step
   ↓
Story Beats        ← next increment
   ↓
Scene Planner      ← later increment
   ↓
Prose (build_diary_prompt_ite → generate_diary_*_ite)
```

The Spine describes WHAT MUST HAPPEN, never HOW. It never decides:

- which specific character embodies the missed opportunity
- where anyone stands or how they arrive
- what anyone says or remembers
- weather, setting choreography, sensory staging

Those are Scene Planner decisions. The Spine only asserts that the
dramatic axis must move and that certain premise facts must hold.

## Inputs

Artifact:
- `story_parts` — `await S.need`'d for artifact wiring only. Never
  embedded in the prompt (doing so caused 34-item required_events
  pollution before 2026-08-01).

UI dropdowns (8), all backed by `data/jim_story_library.yaml/story_atoms/*`:

- `protagonist` (required), `antagonist`, `witness` — characters list
- `external_problem`, `internal_obstacle`, `missed_opportunity`,
  `primary_consequence` — dramatic axis, one atom from each list
- `lens` — one of `mind_worm | tarot_major_arcana | four_forces | i_ching_hexagram`

Runtime config (nested `llm:` block on the step):
```yaml
quantized_model_dir: build/model4
llm:
  maxTokens: 4000
  temperature: 0.05     # NOT 0 — see "Sampler gotcha"
  topP: 0.95
```

## Output

Artifact `story_spine_json` → `out/story_spine.json`. **Two top-level
sections only** (as of 2026-08-01):

```
{
  "story": {
    "title": "...",
    "premise": "...",              // one sentence, abstract
    "protagonist": "...",           // label (a fact, not staging)
    "dramatic_axis": {
      "external_problem": "...",
      "internal_obstacle": "...",
      "missed_opportunity": "...",
      "primary_consequence": "..."
    },
    "starting_state": "...",        // abstract dramatic state
    "terminal_state": "...",        // abstract dramatic state
    "protected_facts": [ ... ],     // 3–6 premise facts, no staging
    "generation_freedoms": [ ... ]  // 3–6 things later stages may invent
  },
  "questions": {
    "story":              [ { id, text }, ... ],  // 1–3, primary; drive plot
    "reader_curiosities": [ { id, text }, ... ],  // 0–3, secondary
    "symbolic":           [ { id, text }, ... ]   // 0–2, optional, non-driving
  }
}
```

Plus deterministically-injected `cast` and `lens` blocks (from the
raw atom picks, never LLM-generated):

```
"cast":   { "protagonist": {id, label}, "antagonist": {...}, "witness": {...} },
"lens":   { id, label }
```

**Explicitly removed** (2026-08-01): `causal_spine`, `scenes`,
`required_story_events`. Those were the source of premature staging
(the model decided Southwick was the opportunity because the spine
schema forced it to pick a scene realization). They belong to Story
Beats and Scene Planner, not here.

## Prompt

Built inline in `buildPrompt(picks)`. Structure:

1. "Story Spine Generator" role — dramaturg, not novelist, not
   director.
2. The eight atoms formatted with id / label / canonical_phrasing /
   tags / role_hints. Lens `interpretive_note` included as its own line.
3. FULL CAST list (names for reference, not for role assignment at
   this layer).
4. Explicit **WRONG vs RIGHT** examples of abstraction level:
   - WRONG: "Southwick appears at the roadside."
   - RIGHT: "A genuine opportunity to receive help appears."
   - WRONG: "Tommy remembers his old girlfriend."
   - RIGHT: "The internal obstacle grows stronger than the immediate need."
5. Output contract (JSON shape shown above, question kinds split).
6. Rules: exactly one primary story question minimum; symbolic
   questions must not drive plot; protected_facts are premise-only,
   never staging.

`story_parts` is NEVER embedded in the prompt.

## JSON extraction

Reused from earlier `oracle_brief.coffee`:

- `stripMlxFraming` — drops mlx_lm's `===` framing bracket.
- `findBalancedJson` — walks brace depth ignoring string content;
  returns `{json, truncated}`.
- `repairTruncatedJson` — closes open strings, trims dangling
  keys/commas, closes stacked braces/brackets in reverse order.
- `extractJSON` — straight parse; if that fails and truncated, tries
  repair; otherwise `null`.

## Sampler gotcha

`temperature: 0` triggers division-by-zero deep in `@frost-beta/llm`'s
sampler → `Error converting "this" to mx.array` at `token.tolist()`.
Use `0.05` (near-greedy, no numerical edge case). `topP: 1.0` also
misbehaves; `0.95` is safe.

## Session sharing (critical)

`mlx/llm_dispatch.coffee` caches LLM sessions by
`modelDir::adapterPath`. `story_spine` and
`generate_diary_without_adapter_ite` both use `build/model4` with no
adapter, so they share the same LLM object. Two consequences:

**(a) kvCache stays populated across calls.** Shipped
`session_api.coffee` `generate()` did NOT reset it; consecutive
generations index against stale KV → crash.

Fix in `node_modules/@jahbini/pipeline/mlx/session_api.coffee`:
`mx.dispose?(llm.kvCache) if llm.kvCache; llm.kvCache = null` at the
top of `generate()`, matching `embed()`. **Evaporates on
`pnpm install`** — needs upstream.

**(b) Concurrent generators on the same session race.** Serialize via
DAG. Current wiring:
`build_diary_prompt_ite.depends_on: [collect_diary_kag_ite, story_spine]`
and `generate_diary_without_adapter_ite.depends_on: [build_diary_prompt_ite]`
force serialization naturally.

Rule for future MLX steps: **any two steps that `S.callLLM` on the
same `modelDir` MUST have an explicit `depends_on` edge.**

## What consumes this (Increment d, revised)

Only `story.protected_facts` is folded into the generator's prompt
(as "Things that must stay true (from the premise)"). Everything
else in the Spine — `dramatic_axis`, `starting_state`,
`terminal_state`, `generation_freedoms`, `questions.*` — is
planner-internal, consumed only by `story_beats` and (indirectly
through beats) by `scene_planner`. It never reaches the generator.

Reason: exposing axis / questions / abstract states to the
generator caused it to parrot dramaturg language as narration.
The Spine's role at generation time is a **guardrail** (via
`protected_facts`), not a scaffold.

Cast and lens are carried forward: `story_beats_json` carries them
from here; `scene_plan_json` carries them from beats; and
`build_diary_prompt_ite` reads cast from `story_spine_json.cast`
to build the "People in the story" block.

## What comes next (roadmap)

Increment (a) — this one — landed 2026-08-01. The Spine now describes
dramatic necessity only.

Increment (b): add `story_beats` step. Reads `story_spine_json`,
emits `story_beats_json` — an ordered list of abstract dramatic
movements. Each beat:

```
{
  id, purpose, dramatic_function,
  required_transition, required_end_state,
  conflict: { need, protection },          // first-class object
  required_story_events, generation_freedoms
}
```

Beats still never name Southwick, never stage memory. Tommy's
backbone should read: "Breakdown creates dependence." → "Opportunity
to receive help appears." → "Pride defeats need." → "Consequence
becomes physical."

Increment (c): add `scene_planner` step. Per beat, emit N Scene
Candidates that stage the same dramatic obligation differently, pick
the strongest. Only here does the cast get assigned to dramatic
roles ("old girlfriend embodies the opportunity for Tommy"). Emits
`scene_plan_json`.

Increment (d): rewire `build_diary_prompt_ite` to consume
`scene_plan_json` (concrete staging) instead of the current spine
fold-through.

Narrative voice at every layer: **first-person Jim, always.** Even
when protagonist ≠ Jim, Jim narrates as observer/witness/recounter.
The LoRA/base model was trained on Jim's voice; close-third loses it.
Do NOT bind voice to `spine.cast.protagonist.label`.
