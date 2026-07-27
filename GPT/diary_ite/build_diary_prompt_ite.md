Step: `build_diary_prompt_ite`
Recipe: `diary_ite`

> ⚠ IMPORTANT (2026-07-27): in the production recipe, BOTH generate steps run
> `generate_diary_event_ordered_ite`, which builds its OWN per-event prompt and
> does NOT consume `diary_prompt_text`. So this step's output — and the chunk
> passages described below — are **dormant** unless the recipe is switched to the
> simpler `generate_diary_{with,without}_adapter` scripts. The LIVE chunk tactic
> (and its `include_chunk_passages` / `chunk_excerpt_chars` knobs) is on the
> generate steps, implemented in `generate_diary_event_ordered_ite` — see that
> step's doc. The passage support below is kept for the simple-generator path.

Purpose:
- build the final diary generation prompt from the story event scaffold, the
  matched KAG cues, AND the per-event story chunks (Jim's own passages)

Inputs:
- artifact `story_parts`
- artifact `diary_kag`  (its `events[kind].matches[].chunk_text` carries the passages)

Outputs:
- artifact `diary_prompt_text`

Params:
- `include_chunk_passages` (default `true`) — fold each event's matched
  `chunk_text` into the prompt as a "Reference passages … by event" section.
  Set `false` for the pre-2026-07-27 behaviour (cues only, no passages).
- `chunk_excerpt_chars` (default `700`, `0` = full) — per-passage char cap so
  5 events × `per_event_match_limit` chunks stay bounded.

Current event source:
- `story_parts` is the current valid event object
- it comes from `load_library -> select_story_recipe -> resolve_story_parts`

Invariants:
- `diary_prompt_text` must be produced before either diary generator runs
- `generate_diary_with_adapter_ite` and `generate_diary_without_adapter_ite` are sibling consumers
- chunk passages are keyed off the diary steps (scene/arrival/disturbance/
  reflection/realization) — one group per event, from that event's matches
- passages are REFERENCE (voice + concrete detail), not plot: the prompt rule
  tells the model to echo cadence, borrow phrasing sparingly, never copy whole
  sentences or their plots
- prompt should not expose retrieval bookkeeping like source `story_id` or `chunk` labels
- `Diary story id:` is obsolete and should not appear in the prompt

DESIGN NOTE (2026-07-27) — reversal of a prior invariant:
- Through 2026-07-26 this step deliberately did NOT paste raw `chunk_text` (kept
  the prompt compact, cues only) because heavy raw passages made the adapter
  bloviate. That rule was intentionally reversed: the user asked for the chunks
  and the diary ablations improved with them.
- The original bloviation concern is mitigated by `chunk_excerpt_chars` (bounded
  excerpts) + the `include_chunk_passages` toggle for A/B, not by omitting them.
  If bloviation returns, LOWER `chunk_excerpt_chars` or `per_event_match_limit`
  (in `collect_diary_kag_ite`) before considering turning passages off entirely.

Known pitfalls:
- if downstream sees bad `diary_prompt_text`, inspect merged graph in `experiment.yaml`
- invalid override semantics can break this step indirectly
- passages appear only for events with a selected `*_emotion` (that drives
  `collect_diary_kag_ite`'s matching); no emotion → that event renders `- none`
- repeated reuse of one source story can bend the diary too hard toward one image cluster
