###
  panels/sat_buckets.coffee — three-tier SAT bucket dashboard
  ============================================================

  Shows this pipe's placement in the three-tier ladder:

    Tier 1: elementary reading    (elementary_verdict.bucket)
                                     → can_read | cannot_read
    Tier 2: diary (fixed spine)   (sat_verdict_<adapted|base>.pass)
                                     → can_diary | cannot_diary
    Tier 3: story (fixed spine)   (sat_story_verdict.bucket)
                                     → can_story | cannot_story

  Applies whenever any of those artifact files exist on disk. Each tier
  block renders empty (— pending) until the corresponding step has run,
  so this panel is safe to show as soon as any tier's recipe has fired.

  Reads live artifacts from <CWD>/params/*.yaml — matches the
  data-source convention the user pinned 2026-09-18.
###

yaml = require 'js-yaml'

FILES = [
  { tier: 'elementary', label: 'Tier 1 — Elementary Reading',
    files: [{key: 'elementary', file: 'elementary_verdict.yaml'}] }
  { tier: 'diary',      label: 'Tier 2 — Diary (fixed spine)',
    files: [
      {key: 'adapted', file: 'sat_verdict_adapted.yaml'}
      {key: 'base',    file: 'sat_verdict_base.yaml'}
    ] }
  { tier: 'story',      label: 'Tier 3 — Story (fixed spine)',
    files: [{key: 'story', file: 'sat_story_verdict.yaml'}] }
]

exports.panel =
  title:        'SAT Buckets'
  render_hint:  'custom'
  column:       'after-outputs'
  eager:        true
  poll_seconds: 15

  applies: (ctx) ->
    {fs, path, CWD} = ctx
    for tier in FILES
      for f in tier.files
        p = path.join(CWD, 'params', f.file)
        return true if fs.existsSync(p)
    false

  endpoint: (ctx) ->
    {fs, path, CWD} = ctx
    tiers = []
    for tier in FILES
      entries = []
      for f in tier.files
        p = path.join(CWD, 'params', f.file)
        entry = { key: f.key, verdict: null, mtime: null, missing: true }
        if fs.existsSync(p)
          entry.missing = false
          try
            raw = fs.readFileSync(p, 'utf8')
            entry.verdict = yaml.load(raw)
            stat = fs.statSync(p)
            entry.mtime = stat.mtime?.toISOString?() ? null
          catch err
            entry.error = String(err?.message ? err)
        entries.push entry
      tiers.push { tier: tier.tier, label: tier.label, entries }
    {tiers: tiers}
