Step: `state_extractor`
Recipe: `story`
Script: `pipes/story/scripts/state_extractor.coffee`
Repo of record: `~/writer`

## Purpose

Runs AFTER generation, BEFORE archival (Increment e4). Reads the
finished chapter text plus the planned outline entry and produces
a structured `chapter_state.json` describing what ACTUALLY
happened, compared against what was planned.

Two roles:

1. **Feed the next chapter.** Emits `actual_ending_state`,
   `actual_questions_opened`, `actual_obligations_created`,
   `actual_new_protected_facts`. These field names match what
   `story_spine` (e3) already knows how to read as inherited
   state when `chapter_number > 1`.
2. **Report continuity to the author.** Emits
   `continuity_validation: {status, drift_notes, missing_beats,
   extra_events, next_trigger_present, next_trigger_notes}`.
   Report-only — nothing auto-blocks the next chapter.

## Inputs

Artifacts:
- `story_outline_json` — planned entry is looked up by
  `chapter_number`.

Disk read (in the script; recipe still declares one via needs):
- `out/diary_adapted.txt` OR `out/diary_base.txt` — the script
  prefers the adapter output, falling back to base. **Why disk?**
  The recipe's override gates ONE of the two generators to
  `depends_on: [never]`, and the runner prunes those steps AND
  their artifacts from the DAG. That means we can't have a single
  `needs:` line that works under both configurations.

  Compromise: the recipe declares `depends_on` and `needs` for
  the currently-enabled generator by name (as of 2026-08-01, the
  adapter path — see the recipe comment). If you flip the
  override, update those two recipe lines; the script itself
  reads whichever text file exists on disk, so it needs no
  change.

  Ideal fix (deferred): the pipeline would benefit from either a
  canonical `chapter_text` artifact both generators produce, or a
  runner feature that treats needs on a pruned artifact as
  "satisfied by absence." Neither exists today.

UI:
- `chapter_number` — must match the value used on `story_spine`
  and `archive_chapter` (see recipe note).

Runtime config:
```yaml
quantized_model_dir: build/model4
llm:
  maxTokens: 3000       # output arrays are compact but prompt embeds full text
  temperature: 0.05
  topP: 0.95
```

Chapter text is capped at 6000 chars in the prompt to prevent
runaway token count on the model side.

## Output

Artifact `chapter_state_json` → `out/chapter_state.json`.
Archived to `out/chapters/ch_<N>/chapter_state.json` by
`archive_chapter`.

```
{
  "actual_ending_state":       "...",                 // becomes ch_<N+1>'s starting_state
  "actual_state_changes":      [ "..." ],
  "actual_questions_answered": [ "..." ],
  "actual_questions_opened":   [ { id, text } ],       // ch_<N+1>'s inherited_questions
  "actual_obligations_created":[ { id, text } ],       // ch_<N+1>'s inherited_obligations
  "actual_new_protected_facts":[ "..." ],              // appended to story protected_facts
  "continuity_validation": {
    "status":               "matches | drift | conflict",
    "drift_notes":          [ "..." ],
    "missing_beats":        [ "..." ],
    "extra_events":         [ "..." ],
    "next_trigger_present": true | false,
    "next_trigger_notes":   "..."
  },
  "planned_chapter":   { ... },   // provenance: the entry that was compared against
  "chapter_number":    N,
  "generated_chapter": "<full chapter text>",
  "outline_ref": {
    "story_title":      "...",
    "description_hash": "...",
    "chapter_id":       "ch_N"
  }
}
```

## Prompt

Structure:

1. Role: state extractor, not judge — extract facts, don't rate
   quality.
2. Planned chapter block: id / number / title / purpose / inherited
   state / planned ending state / dramatic axis / required beats /
   required state changes / planned questions answered / planned
   new questions + obligations / story-scoped protected facts.
3. Generated chapter text (capped at 6000 chars).
4. Output contract with abstract-language-only rule.
5. Status rules for `matches / drift / conflict`.
6. "Facts you extract MUST be visible in the chapter text" — no
   hallucination.

## Failure modes

- **No outline**: emits `{parse_error, message, actual_ending_state: null}`
  and completes; next chapter's `story_spine` will fall through
  to the outline's planned inherited_state, so the pipeline
  degrades gracefully.
- **Bad JSON**: emits `parse_error` with a `continuity_validation`
  block flagged as `status: "conflict"` so the author sees it.

## Where it sits in the DAG

```
generate_diary_without_adapter_ite
   ↓
state_extractor
   ↓
archive_chapter
```

`archive_chapter` now has `chapter_state.json` in its
`CHAPTER_FILES` list — the file gets copied to
`out/chapters/ch_<N>/chapter_state.json` for the next run to
read via `story_spine`'s prior-state loader (already implemented
in e3).

## Session sharing

Same rule as the other MLX steps: uses `build/model4` with no
adapter, shares the getSession LLM cache. The DAG naturally
serializes it after generation.
