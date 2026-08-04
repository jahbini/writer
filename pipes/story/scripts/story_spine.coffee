fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

# ─── Story Spine step (post-e7 cleanup) ───────────────────────────────
# DETERMINISTIC transform of story_outline_json[chapter_number-1] into
# the spine shape downstream steps consume. NO LLM CALL. NO UI KNOBS.
#
# The legacy atom-picker + LLM fallback was removed 2026-08-02 (e7).
# When it existed, an outline shape-check failure would silently
# degrade to picking atoms from UI dropdowns — which meant a broken
# outline produced a plausible Tommy story instead of an error. Bad.
# Now: broken outline → hard throw.

readAtomsLibrary = ->
  libPath = path.join process.cwd(), 'data', 'jim_story_library.yaml'
  yaml.load fs.readFileSync(libPath, 'utf8')

coerceJSON = (value) ->
  return value unless typeof value is 'string'
  try JSON.parse value catch then value

parseChapterNumber = (raw) ->
  n = parseInt String(raw ? '1').trim(), 10
  throw new Error "[story_spine] chapter_number must be a positive integer; got '#{raw}'" if isNaN(n) or n < 1
  n

outlineIsUsable = (outline) ->
  return false unless outline? and typeof outline is 'object'
  return false if outline.parse_error
  return false unless Array.isArray(outline.chapter_order) and outline.chapter_order.length
  return false unless outline.cast?.protagonist_label? and outline.lens_label?
  true

readPriorChapterState = (chapterNumber) ->
  return null unless chapterNumber > 1
  filePath = path.join process.cwd(), 'out', 'chapters', "ch_#{chapterNumber - 1}", 'chapter_state.json'
  return null unless fs.existsSync filePath
  try JSON.parse fs.readFileSync(filePath, 'utf8') catch e then null

findAtomByLabel = (list, label) ->
  return null unless label? and Array.isArray(list)
  target = String(label).trim().toLowerCase()
  for a in list
    return a if a? and String(a.label ? '').trim().toLowerCase() is target
  null

# Merge cast_supplement sheets into the spine as LABEL-ONLY entries
# under spine.cast.supplemental. LEAKAGE LAW: archetype / court_role
# / primary_energy / distortion / typical_imbalance stay in the
# cast_supplement artifact and are DROPPED before entering the spine
# — nothing downstream needs those fields, and build_diary_prompt's
# prompt must never carry them.
mergeSupplementalCast = (outline, supplementDoc) ->
  sheets = supplementDoc?.sheets ? []
  # An unresolved character whose name exactly fills one of the
  # outline's atom-only cast slots (antagonist_label / witness_label)
  # goes IN THAT SLOT instead of into supplemental[]. In practice the
  # outline generator will not label an unresolved character into a
  # slot (see the UNRESOLVED_CAST rule), so this branch is defensive:
  # slot assignment only happens when the outline explicitly requests it.
  slotFor = (name) ->
    return 'antagonist' if outline?.cast?.antagonist_label? and outline.cast.antagonist_label is name
    return 'witness'    if outline?.cast?.witness_label?    and outline.cast.witness_label    is name
    null
  supplemental = []
  slotAssignments = {}
  for s in sheets
    entry = { id: s.id, label: s.label }
    slot = slotFor s.label
    if slot?
      slotAssignments[slot] = entry
    else
      supplemental.push entry
  { supplemental, slotAssignments }

# Deterministic transform: outline entry + top-level cast/lens →
# spine JSON with the shape downstream steps already consume.
deriveSpineFromOutline = (outline, entry, priorState, lib, supplementDoc) ->
  atoms = lib?.story_atoms ? {}
  cast =
    protagonist: null
    antagonist:  null
    witness:     null

  pAtom = findAtomByLabel atoms.characters, outline.cast?.protagonist_label
  aAtom = findAtomByLabel atoms.characters, outline.cast?.antagonist_label
  wAtom = findAtomByLabel atoms.characters, outline.cast?.witness_label
  cast.protagonist = { id: pAtom.id, label: pAtom.label } if pAtom?
  cast.antagonist  = { id: aAtom.id, label: aAtom.label } if aAtom?
  cast.witness     = { id: wAtom.id, label: wAtom.label } if wAtom?

  # Fallback: if label lookup missed, still name the character so
  # downstream cast blocks work.
  unless cast.protagonist?
    lbl = outline.cast?.protagonist_label ? outline.protagonist
    cast.protagonist = { id: null, label: String(lbl) } if lbl?
  unless cast.antagonist?
    lbl = outline.cast?.antagonist_label
    cast.antagonist = { id: null, label: String(lbl) } if lbl? and String(lbl) isnt 'null'
  unless cast.witness?
    lbl = outline.cast?.witness_label
    cast.witness = { id: null, label: String(lbl) } if lbl? and String(lbl) isnt 'null'

  # Merge in genesis characters from cast_supplement (Phase 1 LEPA).
  # Only labels cross the leakage boundary; full sheets stay in the
  # cast_supplement artifact.
  { supplemental, slotAssignments } = mergeSupplementalCast outline, supplementDoc
  cast.antagonist = slotAssignments.antagonist if slotAssignments.antagonist? and not cast.antagonist?
  cast.witness    = slotAssignments.witness    if slotAssignments.witness?    and not cast.witness?
  cast.supplemental = supplemental if supplemental.length

  lensAtom = findAtomByLabel atoms.lenses, outline.lens_label
  lens =
    if lensAtom? then { id: lensAtom.id, label: lensAtom.label }
    else if outline.lens_label? then { id: null, label: String(outline.lens_label) }
    else null

  # Inherited state / questions come from priorState if we have it
  # (chapter N > 1 and state_extractor archived a chapter_state.json).
  # Otherwise use the outline's planned inherited fields.
  inheritedState        = priorState?.actual_ending_state ? entry.inherited_state
  inheritedQuestions    = priorState?.actual_questions_opened ? entry.inherited_questions ? []
  inheritedObligations  = priorState?.actual_obligations_created ? entry.inherited_obligations ? []

  # Story protected_facts: story-scoped from outline, plus any facts
  # the previous chapter created that are still in force.
  storyFacts     = outline.story_protected_facts ? []
  inheritedFacts = priorState?.actual_new_protected_facts ? []
  protectedFacts = storyFacts.concat inheritedFacts

  # Story questions for THIS chapter: inherited + this chapter's new.
  storyQuestions = []
  majorById = {}
  for q in (outline.major_story_questions ? []) when q?.id?
    majorById[q.id] = q
  for qid in inheritedQuestions
    q = majorById[qid]
    storyQuestions.push { id: q.id, text: q.text } if q?
  for q in (entry.new_questions ? []) when q?.id? and q?.text?
    storyQuestions.push { id: q.id, text: q.text }

  spine =
    story:
      title:               entry.chapter_title ? outline.story_title
      premise:             entry.chapter_purpose ? outline.premise
      protagonist:         cast.protagonist?.label ? outline.protagonist
      dramatic_axis:       entry.chapter_dramatic_axis ? {}
      starting_state:      inheritedState
      terminal_state:      entry.ending_state
      protected_facts:     protectedFacts
      generation_freedoms: []
    questions:
      story:              storyQuestions
      reader_curiosities: []
      symbolic:           []
    cast:                 cast
    lens:                 lens
    _outline_ref:
      chapter_id:           entry.chapter_id
      chapter_number:       entry.chapter_number
      next_chapter_trigger: entry.next_chapter_trigger
    _prior_state_used:    priorState?
  spine

@deriveSpineFromOutline = deriveSpineFromOutline

@step =
  desc: "Deterministic transform of story_outline_json[chapter_number-1] into spine"

  action: (S) ->
    lib = readAtomsLibrary()
    unless lib?.story_atoms?
      throw new Error "[story_spine] atoms library missing story_atoms block at data/jim_story_library.yaml"

    outline = null
    try outline = await S.need 'story_outline_json' catch e then outline = null
    outline = coerceJSON outline if typeof outline is 'string'

    unless outlineIsUsable outline
      msg = if outline?.parse_error
        "[story_spine] story_outline_json is a parse_error blob — fix the outline before running the chapter. Message: #{outline.message}"
      else if not outline?.cast?.protagonist_label?
        "[story_spine] story_outline_json missing cast.protagonist_label — outline schema is incomplete"
      else if not Array.isArray(outline?.chapter_order) or not outline.chapter_order.length
        "[story_spine] story_outline_json has no chapter_order entries"
      else
        "[story_spine] story_outline_json is not usable (shape check failed)"
      throw new Error msg

    ctx = null
    try ctx = await S.need 'chapter_context' catch e then ctx = null
    ctx = coerceJSON ctx if typeof ctx is 'string'
    chapterNumber = parseChapterNumber(ctx?.chapter_number ? '1')

    chapters = outline.chapter_order
    unless chapterNumber >= 1 and chapterNumber <= chapters.length
      throw new Error "[story_spine] chapter_number #{chapterNumber} out of range 1..#{chapters.length}"
    entry = chapters[chapterNumber - 1]

    priorState = readPriorChapterState chapterNumber

    supplementDoc = null
    try supplementDoc = await S.need 'cast_supplement' catch e then supplementDoc = null
    supplementDoc = coerceJSON supplementDoc

    spine = deriveSpineFromOutline outline, entry, priorState, lib, supplementDoc
    supN = (supplementDoc?.sheets ? []).length
    console.log "[story_spine] outline-driven (ch=#{chapterNumber}, prior_state=#{if priorState? then 'yes' else 'no'}, supplemental=#{supN})"

    S.make 'story_spine_json', spine
    S.done()
    return
