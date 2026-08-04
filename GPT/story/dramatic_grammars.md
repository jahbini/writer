# dramatic_grammars — externalized dramatic vocabulary

Session: 2026-08-04.

## What moved into data

`pipes/story/data/dramatic_grammars.yaml` now owns three prompt pieces
that used to be hardcoded across the `story` recipe:

- The **dramatic_function enum** in the OUTPUT CONTRACT of
  `story_beats.coffee` — sourced from
  `grammars.<g>.dramatic_functions` (key order, joined with ` | `).
- The **RIGHT / WRONG abstraction examples** — from
  `grammars.<g>.abstraction_examples.{right,wrong}`.
- The **BACKBONE TARGET block** — from `grammars.<g>.backbone`
  (`note` + numbered `beats[].gloss`) plus `beat_count` for the
  trailing "(N–M) number of beats" clause.

And it owns the **beat → KAG-emotion map** consumed by
`collect_diary_kag_ite.coffee`. Old hardcoded `BEAT_EMOTION` constant
deleted; the map is now built from
`grammars.<g>.dramatic_functions.<fn>.kag_emotion`. Unknown/missing
function still falls back to `'neutral'`.

`spy_story_library.yaml` was also copied into `pipes/story/data/` for
a future `pipes/spy` pipe. No code reads it yet.

## Selector

`grammar:` key on the two consuming steps. Lives in
`pipes/story/override/story.yaml`:

```yaml
story_beats:
  grammar: jim_tragedy
collect_diary_kag_ite:
  grammar: jim_tragedy
```

Absent selector defaults to `jim_tragedy` in code (`S.param('grammar',
'jim_tragedy')`) so the pre-externalization no-config path is
preserved.

## Axis field names

The four axis field names (`external_problem`, `internal_obstacle`,
`missed_opportunity`, `primary_consequence`) are still hard-required
everywhere (`story_outline.shapeLooksOk`, `state_extractor` prompt).
Grammars re-caption them via `axis_gloss` but do not rename them.
Making axis fields grammar-variable is a later, separate change.

## jim_tragedy as regression baseline

The `jim_tragedy` grammar is a field-for-field transcription of the
pre-externalization behavior. Two spots needed the shipped grammar
to be extended to be a true transcription:

- `abstraction_examples.wrong` extended from 2 → 3 items, `.right`
  extended from 2 → 4 items, to include the exact quoted examples
  the old prompt carried.
- `backbone.note` uses a double-quoted string with an embedded `\n`
  so the wrapped-line break in the old heredoc is preserved.

## Regression probe

`test/dramatic_grammars_probe.coffee` (gitignored scratch).

Compares the OLD `buildPrompt(spine)` (from
`test/old_story_beats.coffee`, snapshotted from `HEAD` pre-change)
against the NEW `buildPrompt(spine, jim_tragedy_grammar)` on a
canned spine — asserts byte-identical output. Also asserts the
grammar-derived `beatEmotionMap` matches the old `BEAT_EMOTION`
constant key-for-key.

Run:

```
cd pipes/story && npx coffee ../../test/dramatic_grammars_probe.coffee
```

Current result:

```
PASS: story_beats prompt identical for grammar=jim_tragedy (5234 chars)
PASS: BEAT_EMOTION identical for grammar=jim_tragedy (8 keys)
OK
```

## Contract for module exports

Both refactored scripts expose their helpers as module attributes so
the probe can call them without spinning the DAG runner:

- `pipes/story/scripts/story_beats.coffee` — `@buildPrompt`,
  `@readGrammar`
- `pipes/story/scripts/collect_diary_kag_ite.coffee` — `@readGrammar`,
  `@buildBeatEmotionMap`

## `build_diary_prompt_ite`

Task allowed an optional emotional-cues addition here for a beat's
`surface`/`undercurrent` pair. Not done in this pass — kept scope
minimal, and retrieval behavior (which is what matters) is unchanged
because retrieval reads only `kag_emotion`.

## Error guard

Per `GPT/CONVENTIONS.md` (no parameter prescreens), the only guard
added is `readGrammar` throwing a contextual error naming the missing
grammar key and the file path — that's the "cross-artifact
consistency" exception, because downstream code can't produce that
message.
