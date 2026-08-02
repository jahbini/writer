fs   = require 'fs'
path = require 'path'

# ─── Archive Chapter step (Increment e2) ─────────────────────────────
# Runs LAST in the DAG. Reads the UI `chapter_number` param, copies the
# chapter-specific artifacts from out/ into out/chapters/ch_<N>/, and
# updates the out/latest symlink to point at the new dir.
#
# Rationale: the pipeline overwrites out/ on every run. Without this
# archival, we lose the previous chapter's state before the next
# chapter can inherit from it. The archive dir is where (e4)'s
# state_extractor and future runs will look for prior chapter state.
#
# story_outline_json is STORY-scoped, not chapter-scoped, and is
# deliberately not archived — it stays at out/story_outline.json so
# each chapter run reads the same global outline.

# Files copied per chapter run. Keep this in sync with the artifacts
# each planning + generation step produces. Missing files are
# silently skipped so a partial run still archives what it has.
CHAPTER_FILES = [
  'story_spine.json'
  'story_beats.json'
  'scene_plan.json'
  'diary_prompt.txt'
  'diary_base_raw.txt'
  'diary_base_meta.json'
  'diary_base.txt'
  'diary_adapted_raw.txt'
  'diary_adapted_meta.json'
  'diary_adapted.txt'
  'diary_kag.json'
  'story_parts.json'
  'chapter_state.json'  # (e4) state_extractor output — carries the actual
                        # ending_state / questions_opened / obligations for
                        # the NEXT chapter's story_spine to inherit from.
]

@step =
  desc: "Copy this run's chapter artifacts to out/chapters/ch_<N>/ and update out/latest"

  action: (S) ->
    # Gate on state extraction only. The generator output artifact
    # name varies (adapter vs base path); state_extractor already
    # reads whichever exists from disk and its completion is a
    # sufficient gate.
    await S.need 'chapter_state_json'

    # (e5) chapter_number lives in the chapter_context artifact.
    coerceJSON = (v) -> if typeof v is 'string' then (try JSON.parse v catch then v) else v
    ctx = null
    try ctx = await S.need 'chapter_context' catch e then ctx = null
    ctx = coerceJSON ctx
    raw = String(ctx?.chapter_number ? S.param('chapter_number', '1') ? '1').trim()
    n = parseInt raw, 10
    throw new Error "[archive_chapter] chapter_number must be a positive integer; got '#{raw}'" if isNaN(n) or n < 1

    outDir = path.join process.cwd(), 'out'
    chDir  = path.join outDir, 'chapters', "ch_#{n}"
    fs.mkdirSync chDir, recursive: true

    copied = []
    skipped = []
    for f in CHAPTER_FILES
      src = path.join outDir, f
      unless fs.existsSync src
        skipped.push f
        continue
      dst = path.join chDir, f
      fs.copyFileSync src, dst
      copied.push f

    # out/latest → chapters/ch_<N>  (relative symlink survives the
    # dir being moved as long as the parent stays put). Replace any
    # existing symlink; ignore if it wasn't there.
    latest = path.join outDir, 'latest'
    try fs.unlinkSync latest catch e then null
    fs.symlinkSync path.join('chapters', "ch_#{n}"), latest

    stamp =
      chapter_number: n
      target_dir: "out/chapters/ch_#{n}"
      files_copied: copied
      files_skipped: skipped
      latest_symlink: "out/latest -> chapters/ch_#{n}"

    console.log "[archive_chapter] ch_#{n}: archived #{copied.length} files, skipped #{skipped.length}"

    S.make 'archived_chapter', stamp
    S.done()
    return
