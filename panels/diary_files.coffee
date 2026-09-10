###
  panels/diary_files.coffee  —  writer's Diary Files panel
  ========================================================

  First migration to the panel-registry pattern (see GPT/ui/panels.md).
  Behaviour is identical to the legacy `collectDiaryFiles(run)` that
  lived in ui_server.coffee — lists everything under `<CWD>/diary/`,
  marks entries with mtime ≥ run.started_at as `is_fresh: true`, sorts
  alphabetically.

  `applies` gates the panel out entirely when the pipe has no
  `diary/` subdir. That way pipes that don't produce diary output
  (most of them) don't show an empty Diary Files section.
###

exports.panel =
  title:       'Diary Files'
  render_hint: 'file_list'
  # 'after-outputs' places it between Outputs and Run History.
  column:      'after-outputs'
  eager:       true          # legacy /api/status included this; keep it hot
  poll_seconds: 5

  applies: (ctx) ->
    ctx.fs.existsSync(ctx.path.join(ctx.CWD, 'diary'))

  endpoint: (ctx) ->
    {fs, path, CWD, helpers} = ctx
    diaryDir = path.join(CWD, 'diary')
    return [] unless fs.existsSync(diaryDir)

    runStart = ctx.run?.started_at ? null
    rows = []
    for entry in (helpers.listFiles?(diaryDir) ? [])
      continue unless entry? and entry.is_dir isnt true
      rows.push helpers.describeOutputFile? "diary/#{entry.name}", runStart
    rows.sort (a, b) -> String(a.path).localeCompare String(b.path)
    rows
