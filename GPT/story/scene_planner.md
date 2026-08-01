Step: `scene_planner`
Recipe: `story`
Script: `pipes/story/scripts/scene_planner.coffee`
Repo of record: `~/writer`

## Purpose

Fourth of the four planning layers:

```
Premise → Story Spine → Story Beats → Scene Planner ← this step → Prose
```

Reads `story_beats_json` and emits `scene_plan_json` — one concrete
scene per beat, plus the alternate candidates that were considered.

**This is the first layer allowed to make concrete decisions:**
- assign a specific cast member to embody a beat's obligation
  (e.g. "Tommy's old girlfriend is who embodies the missed opportunity")
- pick location, time of day, weather, props
- describe physical action and what is said or remembered
- add sensory grounding

Everything upstream (Spine, Beats) is abstract. Everything downstream
(the prose generator) faithfully renders what this layer chose.

## Inputs

Artifact:
- `story_beats_json` — must not be `parse_error`; must have a
  non-empty `beats` array. Includes carried `cast`, `lens`, and
  `spine_ref` from the Spine.

Runtime config:
```yaml
quantized_model_dir: build/model4
llm:
  maxTokens: 5000        # candidates × beats is verbose; keep object whole
  temperature: 0.1       # a touch more variety than spine/beats (which are 0.05)
  topP: 0.95
```

Scene Planner has no UI knobs. It is a pure function of the Beats.

## Output

Artifact `scene_plan_json` → `out/scene_plan.json`.

```
{
  "scenes": [                       // one selected scene per beat, IN ORDER
    {
      "id":       "s1",
      "beat_id":  "b1",
      "setting":  "concrete location + time of day + weather",
      "present_cast": [ "Tommy", ... ],   // only cast-block names
      "catalyst": "what starts the scene",
      "action":   "what happens; concrete but brief",
      "dialogue_beats":    [ ... ],       // optional
      "sensory_grounding": [ ... ],       // 1-3 details
      "outcome":  "physical/emotional state at scene close",
      "satisfies_conflict": {
        "how_need_is_at_stake":    "...",
        "how_protection_manifests":"..."
      },
      "lands_end_state":     "...",
      "selection_rationale": "one sentence: why this over alternates"
    }
  ],
  "candidates": [                   // provenance — all considered, marked selected/not
    { "beat_id": "b1", "id": "cand_1_1", "setting": ..., "why_not_selected": "..." }
  ],
  "cast":      { ... },             // carried from beats/spine
  "lens":      { ... },             // carried
  "beats_ref": [ { id, purpose, dramatic_function }, ... ]
}
```

## Cast discipline (enforced in code)

The prompt tells the model: "The Cast list is the ONLY named
characters you may use. Do NOT invent new named characters. Unnamed
passersby are fine."

After the LLM call, the step also **filters `present_cast`** on every
scene and candidate down to labels that exist in the spine's cast
block. If the model tries to smuggle in a name, it silently drops
out of `present_cast`. Unnamed passersby that live in the free-text
`action` or `setting` fields survive intact.

## Prompt

Structure:

1. Role: Scene Planner; concrete decisions expected.
2. Story context: title / premise / protagonist / terminal_state / lens.
3. **Cast block** — the ONLY names allowed, spelled out with role.
   "Do NOT invent new named characters."
4. Beats to realize, one at a time, showing id / purpose /
   dramatic_function / conflict {need, protection} / required
   transition / required end state / obligations.
5. Rules:
   - 2–3 candidates per beat, staged differently
   - select one per beat, explain rationale
   - candidates must satisfy the beat's conflict
   - candidates must land in the beat's required_end_state
   - chapter voice is first-person Jim (planner is describing
     staging, not writing prose)
6. Full JSON output contract.

## What consumes this (Increment d, revised)

`build_diary_prompt_ite` folds `scene_plan_json` as the concrete
backbone, but **only these fields per scene reach the generator's
prompt**:

- `setting`         → "setting: …"
- `present_cast`    → "who's involved: …"
- `catalyst`        → "what starts it: …"
- `action`          → "what happens: …"
- `outcome`         → "how it lands: …"

Everything else — `satisfies_conflict`, `lands_end_state`,
`selection_rationale`, `alternatives_considered`, and (if the
model still emits them) `dialogue_beats` and `sensory_grounding`
— stays in `scene_plan_json` as planner-internal audit trail. It
NEVER reaches the generator.

Reason: the pre-(d) run showed the model treating those meta
fields as prose material and reproducing them verbatim in the
chapter ("The opportunity to restart the car is now physically
available"). Stripping them was the biggest single lever for
voice.

The generator's final instruction:
> "Write ONE letter from Jim to Friend, retelling what happened
> below. Cover the moments in order, but not as scene headers —
> as a single piece of writing. Do NOT copy the phrasing of the
> 'what happened' notes below; those are notes, not prose. Do NOT
> narrate abstract obligations ('the need is now at stake', 'the
> opportunity appears') — just tell what happened."

Also revised in (d): the standalone `candidates` array was
removed from Scene Planner's output contract; the model was
collapsing to 1 candidate per beat at low temperature anyway,
paying the token cost for no exploration. Alternates are now
per-scene one-liners in `alternatives_considered`.

## Session sharing

Same rule as the other MLX steps: `scene_planner`, `story_beats`,
and `story_spine` all use `build/model4` with no adapter, sharing
the getSession LLM cache. The DAG serializes them:

```
story_spine → story_beats → scene_planner → build_diary_prompt_ite → generate_diary_without_adapter_ite
```

## Failure mode

If the model returns something that doesn't pass `shapeLooksOk`
(scenes covering every beat_id, each with a non-empty
`present_cast`, `setting`, `action`), the artifact is saved as
`{parse_error: true, raw, message}`. `build_diary_prompt_ite`
gracefully falls back to beats (or the spine) as backbone.

## Roadmap position

Increment (c) — this step — is where the "same Story Spine supports
multiple scene realizations" principle from the four-layer spec
becomes real. Rerun the recipe with the same atoms twice, and the
Spine + Beats will be near-identical; the Scene Plan will differ.

Increment (d) is a further refinement of what this step feeds into
`build_diary_prompt_ite`. As of 2026-08-01 the fold-through is
already scene-primary, so (d) is scope for later polish — richer
sensory rendering, per-scene KAG passage matching, etc.
