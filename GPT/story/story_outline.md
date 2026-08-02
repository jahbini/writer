Step: `story_outline`
Recipe: `story`
Script: `pipes/story/scripts/story_outline.coffee`
Repo of record: `~/writer`

## Purpose

TOP layer of the chapter pipeline. Converts a free-form author
description into a **whole-story outline** with an ordered
`chapter_order[]` — each entry contains the inherited state,
required beats, and next_chapter_trigger for one chapter.

Increment status:
- **(e1) ✅ 2026-08-01** — Sidecar. Emits `story_outline_json`.
- **(e2) ✅ 2026-08-01** — Per-chapter archival step
  `archive_chapter` copies chapter artifacts to
  `out/chapters/ch_<N>/`; `chapter_number` UI knob on the
  archiver.
- **(e3) ✅ 2026-08-01** — `story_spine` reads
  `story_outline_json` + `chapter_number` and derives the spine
  **deterministically** from the chapter entry (no LLM call in
  the outline-driven path). Extended outline schema to carry
  story-scoped `cast`, `lens_label`, `story_protected_facts`,
  and per-chapter `chapter_dramatic_axis`. Atom dropdowns kept
  on `story_spine` as fallback when the outline is missing.
- **(e4) ✅ 2026-08-01** — `state_extractor` runs after
  generation, produces `chapter_state.json` with
  `actual_ending_state`, `actual_questions_opened`,
  `actual_obligations_created`, `actual_new_protected_facts`,
  and `continuity_validation: {status, drift_notes,
  missing_beats, extra_events, next_trigger_present,
  next_trigger_notes}`. `archive_chapter` now copies it into
  `out/chapters/ch_<N>/chapter_state.json`; `story_spine`'s
  prior-state reader (already in e3) picks it up for chapter
  N+1. Continuity loop closed.

## Inputs

UI:
- `story_description` — free-form textarea. User types a paragraph
  or two describing the arc, characters, and end state they want.

Artifact:
- `story_library` — atoms library loaded by `load_library`; passed
  in for the model to see canonical labels (characters,
  external_problems, internal_obstacles, missed_opportunities,
  primary_consequences, lenses).

Runtime config:
```yaml
quantized_model_dir: build/model4
llm:
  maxTokens: 5000       # 3-6 chapters × ~14 fields each is verbose
  temperature: 0.05
  topP: 0.95
```

## Output

Artifact `story_outline_json` → `out/story_outline.json`.

```
{
  "story_title":              "...",
  "premise":                  "...",
  "central_conflict":         "...",
  "protagonist":              "...",
  "starting_state":           "...",
  "intended_terminal_state":  "...",
  "story_protected_facts":    [ "..." ],           // e3: premise-level, no chapter contradicts
  "cast": {                                        // e3: story-scoped cast
    "protagonist_label": "...",
    "antagonist_label":  "..." or null,
    "witness_label":     "..." or null
  },
  "lens_label":               "...",               // e3: story-scoped lens
  "major_story_questions":    [ { id: "q_...", text: "..." } ],
  "major_story_obligations":  [ { id: "o_...", text: "..." } ],
  "chapter_order": [
    {
      "chapter_id":            "ch_1",
      "chapter_number":        1,
      "chapter_title":         "...",
      "chapter_purpose":       "...",
      "inherited_state":       "...",              // empty or = starting_state for ch_1
      "inherited_questions":   [ "q_..." ],
      "inherited_obligations": [ "o_..." ],
      "chapter_dramatic_axis": {                    // e3: per-chapter axis
        "external_problem":    "...",
        "internal_obstacle":   "...",
        "missed_opportunity":  "...",
        "primary_consequence": "..."
      },
      "required_story_beats":  [ "...", "..." ],
      "required_state_changes":[ "..." ],
      "questions_answered":    [ "q_..." ],
      "questions_left_open":   [ "q_..." ],
      "new_questions":         [ { id, text } ],
      "new_obligations":       [ { id, text } ],
      "ending_state":          "...",
      "next_chapter_trigger":  "specific reason next chapter must occur; null for final"
    }
  ],
  "_source_description": "<verbatim textarea input>",
  "_description_hash":   "<12-char sha1 prefix>"
}
```

The `_source_description` and `_description_hash` fields are
provenance stamps. When (e3) lands, downstream chapter planning
will hash the current UI description and refuse to run if the
outline on disk was generated from a different description
(preventing chapter 4 from being planned against a stale chapter 1
outline).

## Prompt

Structure:

1. Role: story architect, not novelist.
2. The free-form description verbatim.
3. Atoms library summary (labels + ids) so the model can invoke
   the author's canonical vocabulary.
4. Rules — 3-6 chapters, inherited/ending state continuity,
   specific next_chapter_triggers with acceptable/unacceptable
   examples, final-chapter exemption for the trigger.
5. Full JSON output contract.

The prompt does NOT constrain chapter length, POV, or voice —
that's downstream. The outline is pure structure.

## Failure mode

If `shapeLooksOk` fails (chapter_order < 2 entries, missing
required fields per chapter, missing top-level fields), the
artifact is saved as `{parse_error: true, raw, message}` with a
hint to raise `maxTokens` or inspect the raw output.

## Session sharing

Same rule as the other MLX steps: uses `build/model4` with no
adapter, so it shares the getSession LLM cache. In (e1) the only
`depends_on` is `[load_library]`; when (e3) rewires downstream,
`story_spine.depends_on` will include `story_outline` and the
serialization will be:

```
story_outline → story_spine → story_beats → scene_planner → build_diary_prompt_ite → generate_diary_without_adapter_ite → state_extractor
```
