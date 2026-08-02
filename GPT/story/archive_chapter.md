Step: `archive_chapter`
Recipe: `story`
Script: `pipes/story/scripts/archive_chapter.coffee`
Repo of record: `~/writer`

## Purpose

LAST step in the DAG (Increment e2). Copies this run's
chapter-specific artifacts from `out/` into
`out/chapters/ch_<N>/`, then updates the `out/latest` symlink to
point at the new dir.

The pipeline overwrites `out/` on every run. Without archival we
lose chapter 1's state before chapter 2 can inherit it. This step
is where per-chapter history persists.

## Inputs

UI:
- `chapter_number` — free-form textarea (no numeric widget in the
  UI yet). Users type `"1"`, `"2"`, etc. Parsed to int; must be
  positive.

Artifact:
- `diary_base_text` — awaited only to gate on generation
  completion. The file's content is not read.

## Output

Artifact `archived_chapter` → `out/archived_chapter.json`.

```
{
  "chapter_number":  3,
  "target_dir":      "out/chapters/ch_3",
  "files_copied":    [ ... ],
  "files_skipped":   [ ... ],
  "latest_symlink":  "out/latest -> chapters/ch_3"
}
```

## Files archived

Chapter-scoped only:

- `story_spine.json`
- `story_beats.json`
- `scene_plan.json`
- `diary_prompt.txt`
- `diary_base_raw.txt`, `diary_base_meta.json`, `diary_base.txt`
- `diary_adapted_raw.txt`, `diary_adapted_meta.json`, `diary_adapted.txt`
- `diary_kag.json`
- `story_parts.json`

Missing files are silently skipped (partial run still archives
what exists).

## Files NOT archived

- **`story_outline.json`** — story-scoped, not chapter-scoped.
  Stays at `out/story_outline.json` so every chapter run of the
  same arc reads the same outline.
- **`archived_chapter.json`** — the stamp lives in `out/`, one
  per run, overwritten each time.

## What consumes this

Nothing yet (e2). In (e4), `state_extractor` will produce a
`chapter_state.json` that is also archived here (add to
`CHAPTER_FILES`), and future chapter runs' `story_spine` step
will read `out/chapters/ch_<N-1>/chapter_state.json` for
inherited state.

## Behavior notes

- The symlink is relative (`chapters/ch_<N>`), so
  `out/latest/diary_base.txt` resolves correctly.
- If the symlink pre-exists, it's replaced. If a REAL FILE named
  `out/latest` exists, the `fs.unlinkSync` still works; but a
  directory in that path will crash — user should not manually
  create `out/latest/`.
- No cleanup of prior archives. `out/chapters/` grows monotonically
  across runs; the user is expected to clear stale chapter dirs
  manually if they want a fresh arc.

## Increment path

- (e2) ✅ 2026-08-01 — this step; sidecar for state extraction to
  hook into later.
- (e3) planned — `story_spine` reads `chapter_number` and picks
  `chapter_order[N-1]` from `story_outline_json` as its dramatic
  necessity, replacing the atom-picker inputs.
- (e4) planned — `state_extractor` step produces
  `chapter_state.json`, added to this step's archive list.
