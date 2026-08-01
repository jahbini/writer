fs   = require 'fs'
path = require 'path'

# ─── Scene Planner step ───────────────────────────────────────────────
# Fourth planning layer. Reads story_beats_json (ordered abstract
# movements + first-class conflicts + carried cast/lens) and emits
# scene_plan_json — one CONCRETE scene per beat, plus the alternate
# candidates that were considered.
#
# This is the FIRST layer allowed to:
#   - name specific cast members in dramatic roles
#   - place them somewhere
#   - describe what is said, remembered, or physically happens
#   - assign a specific character to embody a beat's opportunity
#
# The Scene Planner is bound by the Cast block (from spine). It may
# NEVER invent named cast the premise did not provide.

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

shapeLooksOk = (plan, expectedBeatIds) ->
  return false unless plan? and typeof plan is 'object'
  return false unless Array.isArray(plan.scenes) and plan.scenes.length >= 1
  # Every expected beat must have at least one selected scene.
  seen = new Set()
  for sc in plan.scenes
    return false unless sc?.beat_id? and sc?.setting? and sc?.action?
    return false unless Array.isArray(sc.present_cast) and sc.present_cast.length
    seen.add sc.beat_id
  for id in expectedBeatIds
    return false unless seen.has id
  true

castNamesList = (cast) ->
  names = []
  names.push cast.protagonist.label if cast?.protagonist?.label?
  names.push cast.antagonist.label  if cast?.antagonist?.label?
  names.push cast.witness.label     if cast?.witness?.label?
  names

formatBeatForPrompt = (b, i) ->
  lines = []
  lines.push "  Beat #{i+1} (id: #{b.id ? "b#{i+1}"}) — #{b.dramatic_function ? 'beat'}"
  lines.push "    purpose:              #{b.purpose ? '(none)'}"
  if b.conflict?
    lines.push "    conflict.need:        #{b.conflict.need ? '(none)'}"
    lines.push "    conflict.protection:  #{b.conflict.protection ? '(none)'}"
  lines.push "    required_transition:  #{b.required_transition ? '(none)'}"
  lines.push "    required_end_state:   #{b.required_end_state ? '(none)'}"
  if Array.isArray(b.required_story_events) and b.required_story_events.length
    lines.push "    obligations:"
    lines.push "      - #{e}" for e in b.required_story_events
  lines.join "\n"

buildPrompt = (beatsDoc) ->
  beats = beatsDoc?.beats ? []
  cast = beatsDoc?.cast ? {}
  lens = beatsDoc?.lens ? null
  spineRef = beatsDoc?.spine_ref ? {}
  castNames = castNamesList cast
  castLine = if castNames.length then castNames.join(', ') else '(no cast)'
  beatBlock = (formatBeatForPrompt(b, i) for b, i in beats).join('\n\n')

  """
You are the Scene Planner for the Writers Guild pipeline.

Your job is to convert each abstract Story Beat into a CONCRETE scene
that a first-person Jim narrator could later render into prose.

Unlike the Spine and Beats layers, YOU are allowed — and required —
to make concrete decisions:

  - which specific character embodies each beat's obligation
  - where the scene takes place (location, time of day, weather)
  - what happens physically and what is said or remembered
  - which small props, gestures, and sensory details ground the scene

STORY CONTEXT
---------------------------------------------------------------
Title:         #{spineRef.title ? '(untitled)'}
Premise:       #{spineRef.premise ? '(none)'}
Protagonist:   #{spineRef.protagonist ? '(none)'}
Terminal:      #{spineRef.terminal_state ? '(none)'}
Lens:          #{lens?.label ? '(none)'}

CAST (the ONLY named characters you may use)
---------------------------------------------------------------
Protagonist: #{cast.protagonist?.label ? '(none)'}
Antagonist:  #{cast.antagonist?.label  ? '(none — omit if none)'}
Witness:     #{cast.witness?.label     ? '(none — omit if none)'}

Cast list: #{castLine}

You MUST NOT invent new named characters. Unnamed passersby are fine
if the scene needs a bystander. If a beat's obligation cannot be
plausibly embodied by any cast member as-provided, embody it through
an unnamed passerby or a physical circumstance instead — never
introduce a new name.

BEATS TO REALIZE (in order)
---------------------------------------------------------------
#{if beatBlock.length then beatBlock else '  (no beats)'}

RULES
---------------------------------------------------------------
- Produce ONE selected scene per beat, in beat order.
- Before committing to a scene, mentally consider 2 alternate stagings
  (different cast assignment, different setting or catalyst) and
  record them as short one-liners in `alternatives_considered`.
  Choose the strongest as the selected scene.
- Every selected scene must:
    * name at least one specific cast member OR describe how an
      unnamed circumstance embodies the beat
    * establish the beat's conflict.need vs conflict.protection
      tension physically or through action (not narration alone)
    * end in a state that matches the beat's required_end_state
- Chapter voice is first-person Jim. You are NOT writing prose —
  you are describing the staging Jim will later narrate. Keep each
  field TIGHT: 1–2 sentences max per field.

OUTPUT CONTRACT
---------------------------------------------------------------
Return valid JSON only. No prose outside the JSON. Structure:

{
  "scenes": [
    {
      "id":       "s<beat-index>",
      "beat_id":  "<beat id, e.g. b1>",
      "setting":  "<location + time of day + weather; ONE sentence>",
      "present_cast": [ "<cast label>", ... ],
      "catalyst": "<what starts the scene; ONE sentence>",
      "action":   "<who does what; 1-2 sentences, concrete but brief>",
      "outcome":  "<physical/emotional state at scene close; ONE sentence>",
      "satisfies_conflict": {
        "how_need_is_at_stake":    "<one clause>",
        "how_protection_manifests":"<one clause>"
      },
      "lands_end_state":        "<one clause: how the scene lands the beat's required_end_state>",
      "alternatives_considered":[ "<one-liner alt staging>", "<one-liner alt staging>" ],
      "selection_rationale":    "<ONE sentence: why this over the alternates>"
    }
  ]
}

Return the JSON now.
"""

@step =
  desc: "Convert story_beats_json into concrete Scene Candidates and select one per beat"

  action: (S) ->
    beatsDoc = await S.need 'story_beats_json'
    beatsDoc = coerceJSON beatsDoc
    if beatsDoc?.parse_error
      throw new Error "[scene_planner] upstream story_beats returned parse_error; cannot plan scenes"
    unless Array.isArray(beatsDoc?.beats) and beatsDoc.beats.length
      throw new Error "[scene_planner] story_beats_json has no beats to plan"

    expectedBeatIds = (b.id ? "b#{i+1}" for b, i in beatsDoc.beats)

    prompt = buildPrompt beatsDoc

    modelDir = S.param 'quantized_model_dir', null
    throw new Error "[scene_planner] Missing quantized_model_dir param" unless modelDir?

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
    plan = extractJSON raw

    unless shapeLooksOk plan, expectedBeatIds
      plan =
        parse_error: true
        raw: raw
        message: "scene_planner could not extract a valid scenes array covering all beats (raise llm.maxTokens; check that beats have ids and cast is present)"

    # Enforce cast discipline: strip any names from present_cast that
    # are not in the provided cast. Unnamed passersby stay as free text
    # in `action`/`setting`, but present_cast must reference only
    # premise-provided names.
    allowed = new Set(castNamesList(beatsDoc?.cast ? {}))
    if Array.isArray plan.scenes
      for sc in plan.scenes when Array.isArray(sc.present_cast)
        sc.present_cast = sc.present_cast.filter (n) -> allowed.has(n)

    # Carry forward the cast / lens / beats reference so the prompt
    # builder can render everything from one artifact.
    plan.cast = beatsDoc.cast if beatsDoc?.cast?
    plan.lens = beatsDoc.lens if beatsDoc?.lens?
    plan.beats_ref = ({ id: b.id, purpose: b.purpose, dramatic_function: b.dramatic_function } for b in beatsDoc.beats)

    S.make 'scene_plan_json', plan
    S.done()
    return
