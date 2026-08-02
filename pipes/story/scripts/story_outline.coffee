fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

# ─── Story Outline step (Increment e1) ───────────────────────────────
# TOP layer of the chapter pipeline. Reads a free-form story
# description (UI textarea) plus the atoms library, and emits a
# whole-story outline: title, premise, protagonist, states, story
# questions/obligations, and an ordered chapter_order[] that
# downstream chapter planning will consume one entry at a time.
#
# This step is a SIDECAR in (e1) — nothing downstream reads it yet.
# (e3) will rewire story_spine to pick chapter_order[chapter_number-1]
# as its dramatic necessity, replacing the raw atom-picking flow.

readAtomsLibrary = ->
  libPath = path.join process.cwd(), 'data', 'jim_story_library.yaml'
  yaml.load fs.readFileSync(libPath, 'utf8')

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

shapeLooksOk = (outline) ->
  return false unless outline? and typeof outline is 'object'
  return false unless outline.story_title? and outline.premise? and outline.protagonist?
  return false unless outline.central_conflict?
  return false unless outline.starting_state? and outline.intended_terminal_state?
  return false unless Array.isArray(outline.major_story_questions)
  return false unless Array.isArray(outline.major_story_obligations)
  return false unless Array.isArray(outline.story_protected_facts)
  return false unless outline.cast? and typeof outline.cast is 'object'
  return false unless outline.cast.protagonist_label?
  return false unless outline.lens_label?
  # Single-chapter outlines are legal — many of Jim's short stories are
  # one-piece pieces with a turn (e.g. "Day of the Miser"). Only require
  # at least one chapter.
  return false unless Array.isArray(outline.chapter_order) and outline.chapter_order.length >= 1
  for ch, i in outline.chapter_order
    return false unless ch?.chapter_id? and ch?.chapter_number?
    return false unless ch?.chapter_purpose? and ch?.ending_state?
    # next_chapter_trigger MAY be null on the final chapter (that's
    # the spec: only the final chapter is exempt from the trigger
    # requirement). Only require it for non-final chapters.
    isFinal = i is outline.chapter_order.length - 1
    return false unless isFinal or ch?.next_chapter_trigger?
    return false unless ch?.chapter_dramatic_axis?
    axis = ch.chapter_dramatic_axis
    return false unless axis.external_problem? and axis.internal_obstacle?
    return false unless axis.missed_opportunity? and axis.primary_consequence?
  true

summarizeAtomList = (list, limit = 10) ->
  return '(none)' unless Array.isArray(list) and list.length
  entries = list.slice(0, limit).map (a) ->
    label = a?.label ? '(unlabeled)'
    id = a?.id ? '?'
    "    - #{label} (id: #{id})"
  entries.join('\n')

buildPrompt = (description, atoms) ->
  characters      = summarizeAtomList atoms?.characters
  externals       = summarizeAtomList atoms?.external_problems
  internals       = summarizeAtomList atoms?.internal_obstacles
  missed          = summarizeAtomList atoms?.missed_opportunities
  consequences    = summarizeAtomList atoms?.primary_consequences
  lenses          = summarizeAtomList atoms?.lenses

  """
You are the Story Outline Generator for the Writers Guild pipeline.

Your job is to convert a free-form story description into a
STRUCTURED WHOLE-STORY OUTLINE that later stages will use to plan
chapters one at a time.

You are NOT writing prose. You are architecting the arc.

FREE-FORM STORY DESCRIPTION (from the author)
---------------------------------------------------------------
#{description}
---------------------------------------------------------------

ATOM LIBRARY (reference — canonical labels the author might invoke)
---------------------------------------------------------------
Characters:
#{characters}

External problems:
#{externals}

Internal obstacles:
#{internals}

Missed opportunities:
#{missed}

Primary consequences:
#{consequences}

Interpretive lenses:
#{lenses}

RULES
---------------------------------------------------------------
- Preserve the author's story. Never invent a different premise.
  Never invent characters, settings, or events the description
  does not name.

- IF THE DESCRIPTION IS ONE OF JIM'S LETTERS — first person, opens
  with an address like "Hi, Friend" or uses second-person direct
  address, wanders between topics, is signed with a wry aphorism,
  runs 200-1500 words — then:
    * protagonist_label = "Jim"
    * witness_label     = "Friend"
    * antagonist_label  = null (unless the letter names a specific
                          adversary; a difficult client or an
                          absent institution is NOT an antagonist)
    * chapter_order MUST have exactly ONE chapter. Do NOT invent a
      multi-chapter arc. The letter is one piece with one turn.
    * The chapter's required_story_beats trace the beats of the
      letter itself: setup → the miserly/greedy/anxious/etc.
      justification → the mid-paragraph turn where Jim catches
      himself → the reframe → the sign-off.
    * next_chapter_trigger = null (the letter is self-contained).

- For genuinely multi-chapter descriptions (a synopsis spanning
  multiple scenes across time, or the user explicitly says "arc"
  or "chapters"), produce 2-6 chapters with continuity.

- Choose chapter count based on what the description actually
  contains — do not invent chapters to pad.
- Each chapter must inherit unfinished business from the previous
  chapter, advance at least one major_story_question or
  major_story_obligation, change the story state, and create a
  concrete next_chapter_trigger. Only the final chapter is exempt
  from the trigger requirement (it may resolve).
- next_chapter_trigger MUST be specific. Examples of ACCEPTABLE
  triggers: "a promise must be kept", "an object must be
  recovered", "a character must respond", "a relationship has
  changed", "a consequence is now unavoidable". Examples of
  UNACCEPTABLE triggers: "the journey continues", "more remains
  to be seen", "the story goes on".
- Chapter 1's inherited_state / inherited_questions /
  inherited_obligations may be empty arrays or match the story's
  starting_state — that is fine.
- ending_state of chapter N MUST match inherited_state of chapter
  N+1 (planned continuity).
- questions_answered ⊆ inherited_questions ∪ new_questions from
  earlier chapters. questions_left_open + questions_answered
  covers the inherited set plus this chapter's new_questions.
- The final chapter should resolve most major_story_questions and
  most major_story_obligations. Its next_chapter_trigger may be
  null.

OUTPUT CONTRACT
---------------------------------------------------------------
Return valid JSON only. No prose outside the JSON. Structure:

{
  "story_title":               "<short title>",
  "premise":                   "<one-sentence premise>",
  "central_conflict":          "<the load-bearing tension of the whole story>",
  "protagonist":               "<protagonist label>",
  "starting_state":            "<abstract state at story open>",
  "intended_terminal_state":   "<abstract state at story close>",
  "story_protected_facts":     [ "<3-8 premise-level facts NO chapter may contradict>" ],

  "cast": {
    "protagonist_label":  "<label of one character atom>",
    "antagonist_label":   "<label of one character atom, or null if none>",
    "witness_label":      "<label of one character atom, or null if none>"
  },
  "lens_label":                "<label of one lens atom>",

  "major_story_questions":     [ { "id": "q_<snake>", "text": "<question>" } ],
  "major_story_obligations":   [ { "id": "o_<snake>", "text": "<promise, debt, or arc the story must land>" } ],
  "chapter_order": [
    {
      "chapter_id":             "ch_1",
      "chapter_number":         1,
      "chapter_title":          "<short>",
      "chapter_purpose":        "<one line: this chapter's role in the arc>",
      "inherited_state":        "<abstract; empty or matches starting_state for ch_1>",
      "inherited_questions":    [ "q_<id>", ... ],
      "inherited_obligations":  [ "o_<id>", ... ],

      "chapter_dramatic_axis": {
        "external_problem":    "<external problem in play THIS chapter; echo an atom's canonical phrasing when applicable>",
        "internal_obstacle":   "<internal obstacle THIS chapter>",
        "missed_opportunity":  "<the opportunity that appears and is missed / taken THIS chapter>",
        "primary_consequence": "<what physically happens by chapter close>"
      },

      "required_story_beats":   [ "<3-5 abstract movements this chapter must contain>" ],
      "required_state_changes": [ "<what abstract states must shift>" ],
      "questions_answered":     [ "q_<id>", ... ],
      "questions_left_open":    [ "q_<id>", ... ],
      "new_questions":          [ { "id": "q_<snake>", "text": "<...>" } ],
      "new_obligations":        [ { "id": "o_<snake>", "text": "<...>" } ],
      "ending_state":           "<abstract state at chapter close>",
      "next_chapter_trigger":   "<specific reason chapter N+1 must occur; null only for final chapter>"
    }
  ]
}

CAST + LENS RULES
- `cast` and `lens_label` are STORY-scoped. Protagonist stays
  constant across chapters. Antagonist and witness may be null.
- All four labels MUST be exact `label` strings from the atom
  library above. Do NOT invent new names.
- Do NOT put a character in the cast unless the description
  actually names them. If the description does not name an
  antagonist, `antagonist_label` MUST be null. Same for witness.
  A "stranger at the bar," "the ex-partner," "the neighbor" —
  none of these belong in the cast unless the description names
  them.
- If the description names a lens/motif explicitly ("today's story
  is based on the 5 of Cups", "tarot", "mind-worm", "I Ching",
  "the four forces"), use that as lens_label — do NOT pick a
  different lens.

CHAPTER_DRAMATIC_AXIS RULES
- Every chapter has its OWN axis — the whole-arc axis changes
  shape across chapters. Chapter 1 might introduce the external
  problem; chapter 3's axis might emphasize the internal obstacle
  strengthening, etc.
- No staging. Abstract movement only. WRONG: "Southwick appears
  at the roadside." RIGHT: "An opportunity to receive help
  appears."

Return the JSON now.
"""

@step =
  desc: "Convert a free-form story description into a structured whole-story outline"

  action: (S) ->
    description = String(S.param('story_description', '') ? '').trim()
    throw new Error "[story_outline] story_description is empty; enter a story description in the UI textarea" unless description.length

    lib = readAtomsLibrary()
    atoms = lib?.story_atoms ? {}

    prompt = buildPrompt description, atoms

    modelDir = S.param 'quantized_model_dir', null
    throw new Error "[story_outline] Missing quantized_model_dir param" unless modelDir?

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
    outline = extractJSON raw

    unless shapeLooksOk outline
      outline =
        parse_error: true
        raw: raw
        message: "story_outline could not extract a valid outline (raise llm.maxTokens if raw ended mid-object; check that chapter_order[] has 3+ chapters and required fields)"

    # Stamp source hash + description for provenance. Downstream steps
    # (e3) can compare hashes to detect stale outlines when the user
    # edits the description mid-arc.
    outline._source_description = description
    outline._description_hash = require('crypto').createHash('sha1').update(description).digest('hex').slice(0, 12)

    S.make 'story_outline_json', outline
    S.done()
    return
