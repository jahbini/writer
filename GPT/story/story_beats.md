Step: `story_beats`
Recipe: `story`
Script: `pipes/story/scripts/story_beats.coffee`
Repo of record: `~/writer`

## Purpose

Third of the four planning layers:

```
Premise → Story Spine → Story Beats ← this step → Scene Planner → Prose
```

Reads `story_spine_json` (dramatic necessity) and emits
`story_beats_json` — an **ordered sequence of abstract dramatic
movements**, 3–5 beats total. Each beat carries a first-class
`conflict: {need, protection}` object.

Beats sharpen the Spine's axis into ordered movement. They never
stage: no specific cast names in obligations, no locations, no
dialogue, no memory contents, no sensory detail. Scene Planner
(Increment c) is the layer that assigns cast to obligations.

## Tommy backbone target

```
b1  establish_need           Breakdown creates dependence.
b2  introduce_opportunity    Opportunity to receive help appears.
b3  force_a_decision         Pride defeats need.
b4  make_consequence_physical Consequence becomes physical.
```

Every beat: abstract, one dramatic movement, non-empty conflict.

## Inputs

Artifact:
- `story_spine_json` — must be a good spine (`parse_error` triggers a
  hard throw; there is nothing to plan from).

Runtime config:
```yaml
quantized_model_dir: build/model4
llm:
  maxTokens: 3000
  temperature: 0.05
  topP: 0.95
```

Beats have NO UI knobs. They are a pure function of the Spine.

## Output

Artifact `story_beats_json` → `out/story_beats.json`.

```
{
  "beats": [
    {
      "id": "b1",
      "purpose": "<one-line role in the arc>",
      "dramatic_function":  "establish_need | introduce_opportunity |
                             escalate_pressure | force_a_decision |
                             reveal_information | lose_an_opportunity |
                             make_consequence_physical | resolve_a_question",
      "required_transition": "<abstract state shift>",
      "required_end_state":  "<abstract state at beat close>",
      "conflict": {
        "need":       "<what the protagonist requires>",
        "protection": "<what the protagonist is defending against>"
      },
      "required_story_events": [ "<1-3 abstract movements>" ],
      "generation_freedoms":   [ "<1-3 things Scene Planner may invent>" ]
    }
  ],
  "cast":       { ...carried from spine... },
  "lens":       { ...carried from spine... },
  "spine_ref":  { title, premise, protagonist, terminal_state }
}
```

The `cast` and `lens` blocks are carried forward from the spine so
Scene Planner has one artifact to read. Beats themselves must not
name cast in their obligations.

## Prompt

Structure:

1. Role: dramaturg marking beats, not director blocking scenes.
2. The Spine payload: title / premise / protagonist / axis /
   starting_state / terminal_state / protected_facts /
   generation_freedoms / three question kinds.
3. Explicit **WRONG vs RIGHT** examples of the abstraction level.
4. First-class `conflict: {need, protection}` explanation with
   examples.
5. The Tommy backbone as a target cadence (3–5 beats, that level of
   abstraction, that pace of movement).
6. Output contract with `dramatic_function` enum.
7. Rules: 3–5 beats; end-state of N is start-state of N+1; final
   beat's end state matches spine terminal_state; axis moves
   visibly; conflict fields non-empty and opposed; symbolic
   questions must not drive beats.

## What consumes this (Increment d, revised)

`scene_planner` ONLY. Beats are NOT folded into the generator's
prompt anymore.

The Increment (b) wiring rendered beats to the generator as the
"primary backbone". Increment (c) added scenes as a competing
backbone. Increment (d) dropped the beats block from the
generator prompt entirely — once concrete scenes exist, beats are
scaffolding, and their abstract phrasing ("the internal obstacle
grows stronger than the immediate need") ended up as parroted
narration in the last pre-(d) run.

Beats live in `story_beats_json` for provenance and as the input
`scene_planner` reads. Nothing else consumes them at generation
time.

## Session sharing

Same rule as `story_spine`: both use `build/model4` with no adapter,
so they share the getSession LLM cache. The DAG serializes them:
`story_beats.depends_on: [story_spine]`, and
`build_diary_prompt_ite.depends_on: [collect_diary_kag_ite,
story_beats]`. No two S.callLLM steps on the same modelDir run in
parallel.

## Failure mode

If the model returns something that doesn't pass `shapeLooksOk` (3+
beats, each with id / purpose / dramatic_function / conflict.need /
conflict.protection / required_end_state), the artifact is saved as
`{parse_error: true, raw, message}`. `build_diary_prompt_ite`
gracefully falls back to the spine-only backbone in that case.
