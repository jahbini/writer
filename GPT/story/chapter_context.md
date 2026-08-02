Step: `chapter_context`
Recipe: `story`
Script: `pipes/story/scripts/chapter_context.coffee`
Repo of record: `~/writer`

## Purpose

Increment e5. Single source of truth for `chapter_number`. Before
e5 the number lived on three separate UI textareas (`story_spine`,
`state_extractor`, `archive_chapter`) — easy to mismatch, and
mismatching meant chapter N's plan got archived as chapter M.

This step has ONE UI textarea. It emits a
`chapter_context` artifact holding the parsed integer, and all
downstream chapter-scoped steps read from that artifact via
`S.need`.

## Inputs

UI:
- `chapter_number` — free-form textarea. Users type `"1"`, `"2"`,
  etc. Parsed to int; rejects non-positive.

No artifact inputs. No dependencies. Runs first among
chapter-scoped steps.

## Output

Artifact `chapter_context` → `out/chapter_context.json`:

```
{ "chapter_number": 3 }
```

## Consumers

- `story_spine` reads `ctx.chapter_number` to pick
  `story_outline_json.chapter_order[N-1]`.
- `state_extractor` reads it to look up the planned entry for
  comparison against the generated chapter.
- `archive_chapter` reads it to decide the target
  `out/chapters/ch_<N>/` directory.

All three read it via `S.need 'chapter_context'` with an
`S.param('chapter_number', '1')` fallback (backward-compat if
someone runs the recipe without wiring the artifact).

## Not automatic-incrementing

The step does NOT scan `out/chapters/` for the highest existing
ch_<N> and auto-increment. Users control the number so they can
regenerate a specific chapter (e.g. re-run ch_2 without
overwriting ch_3). Auto-increment would foreclose that.

If you want the archiver to warn when a target dir already has
files, that's a small addition to `archive_chapter` — deferred.
