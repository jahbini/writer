fs   = require 'fs'
path = require 'path'

# ─── State Extractor step (Increment e4) ──────────────────────────────
# After generation, reads the finished chapter text plus the planned
# outline entry, and extracts what ACTUALLY happened. Emits
# chapter_state_json with fields that the NEXT chapter's story_spine
# (already implemented in e3) knows how to consume as inherited state.
#
# Field-name contract with story_spine (e3):
#   actual_ending_state           → next chapter's starting_state
#   actual_questions_opened       → next chapter's inherited_questions
#   actual_obligations_created    → next chapter's inherited_obligations
#   actual_new_protected_facts    → appended to next chapter's protected_facts
#
# Also emits continuity_validation for author review (report-only, not
# gating): {status, drift_notes, missing_beats, extra_events}.

stripMlxFraming = (text) ->
  return '' unless typeof text is 'string'
  text
    .replace(/^={5,}\s*\n/, '')
    .replace(/\n={5,}[\s\S]*$/, '')

findBalancedJson = (text) ->
  start = text.indexOf('{')
  return null if start < 0
  depth = 0
  inString = false
  escape = false
  for i in [start...text.length]
    ch = text[i]
    if escape then escape = false
    else if ch is '\\' and inString then escape = true
    else if ch is '"' then inString = !inString
    else if not inString
      if ch is '{' then depth++
      else if ch is '}'
        depth--
        return { json: text[start..i], truncated: false } if depth is 0
  { json: text[start..], truncated: true }

repairTruncatedJson = (text) ->
  inString = false
  escape = false
  stack = []
  lastSafeEnd = -1
  for i in [0...text.length]
    ch = text[i]
    if escape then escape = false
    else if ch is '\\' and inString then escape = true
    else if ch is '"'
      inString = !inString
      lastSafeEnd = i if not inString
    else if not inString
      if ch is '{' or ch is '[' then stack.push ch
      else if ch is '}' or ch is ']' then stack.pop()
      if /[\s\}\]\d"]/.test(ch) then lastSafeEnd = i
  head = if lastSafeEnd >= 0 then text[..lastSafeEnd] else text
  head = head.replace(/,\s*"?[A-Za-z_]*\s*:?\s*$/, '')
  head = head.replace(/,\s*$/, '')
  stack.reverse().reduce(((acc, open) ->
    acc + (if open is '{' then '}' else ']')), head)

extractJSON = (raw) ->
  return null unless raw?
  cleaned = stripMlxFraming raw
  found = findBalancedJson cleaned
  return null unless found?
  try return JSON.parse found.json catch then null
  return null unless found.truncated
  try return JSON.parse(repairTruncatedJson found.json) catch then null
  null

coerceJSON = (value) ->
  return value unless typeof value is 'string'
  try JSON.parse value catch then value

parseChapterNumber = (raw) ->
  n = parseInt String(raw ? '1').trim(), 10
  throw new Error "[state_extractor] chapter_number must be a positive integer; got '#{raw}'" if isNaN(n) or n < 1
  n

# Read the generated chapter text from whichever generator produced it
# THIS run. The recipe currently gates one of the two generators to
# `depends_on: [never]` via override, so exactly one of the two files
# is present. Prefer the adapter output (higher voice fidelity) when
# both exist. Returns null if neither file is present.
# Read the chapter's finished text via the meta txt device (see
# GPT/CONVENTIONS.md — meta methods for file system access). Meta txt
# returns undefined when the file's absent; treat that like the old
# `fs.existsSync` false branch.
readChapterFromDisk = (L) ->
  candidates = ['out/diary_adapted.txt', 'out/diary_base.txt']
  for key in candidates
    text =
      if L?.theLowdown?
        L.theLowdown(key)?.value
      else
        p = path.join process.cwd(), key
        (if fs.existsSync p then fs.readFileSync p, 'utf8')
    continue unless typeof text is 'string'
    trimmed = text.trim()
    continue unless trimmed.length
    absPath = path.join process.cwd(), key
    return { path: absPath, text: trimmed }
  null

shapeLooksOk = (state) ->
  return false unless state? and typeof state is 'object'
  return false unless state.actual_ending_state?
  return false unless Array.isArray(state.actual_state_changes)
  return false unless Array.isArray(state.actual_questions_answered)
  return false unless Array.isArray(state.actual_questions_opened)
  return false unless Array.isArray(state.actual_obligations_created)
  return false unless Array.isArray(state.actual_new_protected_facts)
  return false unless state.continuity_validation? and state.continuity_validation.status?
  true

buildPrompt = (entry, outline, chapterText) ->
  axis = entry?.chapter_dramatic_axis ? {}
  plannedBeats = (entry?.required_story_beats ? []).map((b) -> "  - #{b}").join('\n')
  plannedStateChanges = (entry?.required_state_changes ? []).map((s) -> "  - #{s}").join('\n')
  plannedQuestionsAnswered = (entry?.questions_answered ? []).map((q) -> "  - #{q}").join('\n')
  plannedNewQuestions = (entry?.new_questions ? []).map((q) -> "  - #{q?.id ? '?'}: #{q?.text ? ''}").join('\n')
  plannedNewObligations = (entry?.new_obligations ? []).map((o) -> "  - #{o?.id ? '?'}: #{o?.text ? ''}").join('\n')
  storyFacts = (outline?.story_protected_facts ? []).map((f) -> "  - #{f}").join('\n')

  # Guard against a runaway prompt: cap chapter text at 6000 chars.
  # A whole diary chapter is typically ~2-4KB; more than 6000 is a
  # truncation risk on the model side.
  MAX_CHARS = 6000
  chText = String(chapterText ? '')
  if chText.length > MAX_CHARS
    chText = chText.slice(0, MAX_CHARS) + "\n[...truncated for state extraction]"

  """
You are the State Extractor for the Writers Guild pipeline.

Your job is to read a chapter that was just written, compare it
against the PLANNED chapter obligations from the story outline,
and produce a structured record of what ACTUALLY happened.

You are NOT judging quality. You are extracting facts.

Later stages depend on your output to carry state into the next
chapter: your `actual_ending_state` becomes the next chapter's
starting state; your `actual_questions_opened` become the next
chapter's inherited questions; your `actual_obligations_created`
become the next chapter's inherited obligations; your
`actual_new_protected_facts` accumulate into the story's running
protected_facts list.

PLANNED CHAPTER (from story_outline.chapter_order)
---------------------------------------------------------------
Chapter id:      #{entry?.chapter_id ? '(none)'}
Chapter number:  #{entry?.chapter_number ? '(none)'}
Chapter title:   #{entry?.chapter_title ? '(none)'}
Chapter purpose: #{entry?.chapter_purpose ? '(none)'}
Inherited state: #{entry?.inherited_state ? '(none)'}
Planned ending state: #{entry?.ending_state ? '(none)'}
Next chapter trigger: #{entry?.next_chapter_trigger ? '(none)'}

Planned dramatic axis:
  external problem:    #{axis.external_problem ? '(none)'}
  internal obstacle:   #{axis.internal_obstacle ? '(none)'}
  missed opportunity:  #{axis.missed_opportunity ? '(none)'}
  primary consequence: #{axis.primary_consequence ? '(none)'}

Planned required beats:
#{if plannedBeats.length then plannedBeats else '  (none)'}

Planned state changes:
#{if plannedStateChanges.length then plannedStateChanges else '  (none)'}

Planned questions to answer this chapter (IDs):
#{if plannedQuestionsAnswered.length then plannedQuestionsAnswered else '  (none)'}

Planned new questions (IDs + text):
#{if plannedNewQuestions.length then plannedNewQuestions else '  (none)'}

Planned new obligations (IDs + text):
#{if plannedNewObligations.length then plannedNewObligations else '  (none)'}

Story-scoped protected facts (immutable across the arc):
#{if storyFacts.length then storyFacts else '  (none)'}

GENERATED CHAPTER TEXT
---------------------------------------------------------------
#{chText}
---------------------------------------------------------------

OUTPUT CONTRACT
---------------------------------------------------------------
Return valid JSON only. No prose outside the JSON. Abstract
language only — no staging. Structure:

{
  "actual_ending_state": "<one-sentence abstract state the chapter actually lands in>",

  "actual_state_changes": [
    "<abstract state shift that actually occurred>"
  ],

  "actual_questions_answered": [
    "<question id or short question text answered by the chapter>"
  ],

  "actual_questions_opened": [
    { "id": "q_<snake>", "text": "<question the chapter opened but did not close>" }
  ],

  "actual_obligations_created": [
    { "id": "o_<snake>", "text": "<promise/debt/arc the chapter established for future chapters>" }
  ],

  "actual_new_protected_facts": [
    "<new immutable fact this chapter established (e.g. 'Tommy owes Southwick a favor')>"
  ],

  "continuity_validation": {
    "status": "matches | drift | conflict",
    "drift_notes":    [ "<obligation from the plan that this chapter did not honor>" ],
    "missing_beats":  [ "<planned beat that never appeared in the chapter>" ],
    "extra_events":   [ "<major event the chapter added that was NOT in the plan; small texture is fine>" ],
    "next_trigger_present": true | false,
    "next_trigger_notes": "<one sentence: is the planned next_chapter_trigger visibly set up by the ending?>"
  }
}

STATUS RULES
- "matches": all planned required beats present, ending_state
  roughly aligns with planned, no obligations dropped, next
  trigger is visibly set up (or n/a for final chapter).
- "drift":   most beats present but the ending or trigger has
  shifted; drift_notes explain how.
- "conflict": a protected fact was contradicted, or a beat that
  the plan required is missing AND the chapter now points somewhere
  incompatible with the outline.

OTHER RULES
- Prefer abstract phrasing throughout. Do not paste dialogue.
- If the chapter is empty or nearly empty, set status to
  "conflict" and note it.
- Facts you extract MUST be visible in the chapter text — do not
  invent state changes the prose does not support.

Return the JSON now.
"""

@step =
  desc: "Extract actual state changes and continuity validation from the generated chapter"

  action: (S) ->
    # Prefer the runner's artifact resolution — the recipe's `needs`
    # entry (diary_adapted_text on the currently-enabled adapter path)
    # is the authoritative way to get the text and doesn't depend on
    # what process.cwd() happens to be. Fall back to disk paths only
    # if S.need returns nothing.
    chapterText = ''
    for artifactName in ['diary_adapted_text', 'diary_base_text']
      try
        v = await S.need artifactName
        if v?
          chapterText = String(v).trim()
          if chapterText.length
            console.log "[state_extractor] read chapter via S.need('#{artifactName}') (#{chapterText.length} chars)"
            break
      catch e then null

    unless chapterText.length
      found = readChapterFromDisk(L)
      if found?
        chapterText = found.text
        console.log "[state_extractor] read chapter from #{found.path} (#{chapterText.length} chars)"

    unless chapterText.length
      throw new Error "[state_extractor] no chapter text: neither S.need('diary_adapted_text'/'diary_base_text') nor out/diary_adapted.txt / out/diary_base.txt yielded content (did generation run?)"

    outline = null
    try outline = await S.need 'story_outline_json' catch e then outline = null
    outline = coerceJSON outline if typeof outline is 'string'

    unless outline? and typeof outline is 'object' and Array.isArray(outline.chapter_order)
      state =
        parse_error: true
        message: "state_extractor: no valid story_outline_json — skip extraction (outline-driven pipeline required)"
        actual_ending_state: null
      S.make 'chapter_state_json', state
      S.done()
      return

    # (e5) chapter_number lives in the chapter_context artifact.
    ctx = null
    try ctx = await S.need 'chapter_context' catch e then ctx = null
    ctx = coerceJSON ctx if typeof ctx is 'string'
    chapterNumber = parseChapterNumber(ctx?.chapter_number ? S.param('chapter_number', '1'))
    unless chapterNumber >= 1 and chapterNumber <= outline.chapter_order.length
      throw new Error "[state_extractor] chapter_number #{chapterNumber} out of range 1..#{outline.chapter_order.length}"
    entry = outline.chapter_order[chapterNumber - 1]

    prompt = buildPrompt entry, outline, chapterText

    modelDir = S.param 'quantized_model_dir', null
    throw new Error "[state_extractor] Missing quantized_model_dir param" unless modelDir?

    llmArgs = op: 'generate', modelDir: modelDir, prompt: prompt
    llmConfig = S.param('llm', null) ? S.param('mlx', null)
    if llmConfig? and typeof llmConfig is 'object' and not Array.isArray(llmConfig)
      for own key, value of llmConfig
        continue unless value?
        camel = switch key
          when 'max-tokens', 'max_tokens' then 'maxTokens'
          when 'temp', 'temperature' then 'temperature'
          when 'top-p', 'top_p' then 'topP'
          when 'system-prompt' then 'systemPrompt'
          else key
        llmArgs[camel] = value

    result = await S.callLLM llmArgs
    raw = String(result?.rawText ? result?.text ? '')
    state = extractJSON raw

    unless shapeLooksOk state
      state =
        parse_error: true
        raw: raw
        message: "state_extractor could not extract a valid state shape (raise llm.maxTokens if the raw output ended mid-object)"
        actual_ending_state: null
        actual_state_changes: []
        actual_questions_answered: []
        actual_questions_opened: []
        actual_obligations_created: []
        actual_new_protected_facts: []
        continuity_validation: { status: 'conflict', drift_notes: ['state_extractor parse_error'], missing_beats: [], extra_events: [], next_trigger_present: false, next_trigger_notes: '(extractor failed)' }

    # Provenance: stamp what was compared. The next chapter's
    # story_spine reads this file and expects actual_* fields.
    state.planned_chapter    = entry
    state.chapter_number     = chapterNumber
    state.generated_chapter  = chapterText
    state.outline_ref =
      story_title:         outline.story_title
      description_hash:    outline._description_hash
      chapter_id:          entry.chapter_id

    console.log "[state_extractor] ch=#{chapterNumber} status=#{state?.continuity_validation?.status ? 'unknown'}"

    S.make 'chapter_state_json', state
    S.done()
    return
