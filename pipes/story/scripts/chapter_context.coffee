# ─── Chapter Context step (Increment e5) ──────────────────────────────
# Single source of truth for `chapter_number`. Emits `chapter_context`
# artifact so downstream steps (story_spine, state_extractor,
# archive_chapter) read from ONE UI slot instead of duplicating the
# textarea across three places.
#
# No LLM call. No file I/O. Just parses the UI param and stamps it.

@step =
  desc: "Hoist chapter_number into a single artifact all chapter-scoped steps read"

  action: (S) ->
    raw = String(S.param('chapter_number', '1') ? '1').trim()
    n = parseInt raw, 10
    throw new Error "[chapter_context] chapter_number must be a positive integer; got '#{raw}'" if isNaN(n) or n < 1

    console.log "[chapter_context] chapter_number = #{n}"
    S.make 'chapter_context', { chapter_number: n }
    S.done()
    return
