fs   = require 'fs'
path = require 'path'

# ─── Story Beats step ─────────────────────────────────────────────────
# Reads story_spine_json (dramatic necessity: axis + facts + questions)
# and produces story_beats_json — an ordered list of abstract dramatic
# movements. Each beat carries a first-class conflict {need, protection}.
#
# Beats never stage. They never name specific characters, locations,
# dialogue, weather, memory contents. That is Scene Planner's job.
#
# Tommy backbone target:
#   1. Breakdown creates dependence
#   2. Opportunity to receive help appears
#   3. Pride defeats need
#   4. Consequence becomes physical

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

shapeLooksOk = (beats) ->
  return false unless beats? and typeof beats is 'object'
  return false unless Array.isArray(beats.beats) and beats.beats.length >= 3
  for b in beats.beats
    return false unless b?.id? and b?.purpose? and b?.dramatic_function?
    return false unless b?.conflict?.need? and b?.conflict?.protection?
    return false unless b?.required_end_state?
  true

buildPrompt = (spine) ->
  story = spine?.story ? {}
  axis = story.dramatic_axis ? {}
  questions = spine?.questions ? {}
  storyQs = (q.text for q in (questions.story ? []) when q?.text?).join('\n  - ')
  readerQs = (q.text for q in (questions.reader_curiosities ? []) when q?.text?).join('\n  - ')
  symQs = (q.text for q in (questions.symbolic ? []) when q?.text?).join('\n  - ')
  protectedFacts = (spine?.story?.protected_facts ? []).map((f) -> "  - #{f}").join('\n')
  freedoms = (spine?.story?.generation_freedoms ? []).map((f) -> "  - #{f}").join('\n')

  """
You are the Story Beats Generator for the Writers Guild pipeline.

Your purpose is NOT to write prose. You do NOT stage scenes. You do
NOT name specific characters, pick locations, invent dialogue, or
describe memories. Those are Scene Planner responsibilities,
downstream.

Your job is to convert the Story Spine's dramatic necessity into an
ORDERED sequence of abstract dramatic MOVEMENTS. Each beat is one
step of pressure change: what the story demands must shift between
here and the next beat.

Think like a dramaturg marking the beats in a play, not like a
director blocking the scene.

STORY SPINE (dramatic necessity — immutable)
---------------------------------------------------------------
Title:               #{story.title ? '(untitled)'}
Premise:             #{story.premise ? '(none)'}
Protagonist:         #{story.protagonist ? '(none)'}
Starting state:      #{story.starting_state ? '(none)'}
Terminal state:      #{story.terminal_state ? '(none)'}

Dramatic axis:
  external problem:    #{axis.external_problem ? '(none)'}
  internal obstacle:   #{axis.internal_obstacle ? '(none)'}
  missed opportunity:  #{axis.missed_opportunity ? '(none)'}
  primary consequence: #{axis.primary_consequence ? '(none)'}

Protected facts (must not be contradicted):
#{if protectedFacts.length then protectedFacts else '  (none)'}

Generation freedoms (later stages may invent these):
#{if freedoms.length then freedoms else '  (none)'}

Questions:
  story (drive plot; must be visibly at stake):
  - #{storyQs or '(none)'}
  reader curiosities (secondary):
  - #{readerQs or '(none)'}
  symbolic (do NOT let these drive the plot):
  - #{symQs or '(none)'}

ABSTRACTION LEVEL — READ CAREFULLY
---------------------------------------------------------------
Beats describe DRAMATIC MOVEMENT, not staging.

WRONG (staging — belongs to Scene Planner):
  "Southwick pulls up in a truck."
  "Tommy remembers his old girlfriend."
  "Old girlfriend arrives; Tommy looks away."

RIGHT (dramatic movement — belongs here):
  "A genuine opportunity to receive help appears."
  "The internal obstacle grows stronger than the immediate need."
  "The choice becomes unavoidable."
  "The consequence becomes physical."

Beats must NEVER:
  - name a specific character (protagonist label is fine when
    speaking about the story's central figure, but no antagonist
    or witness names — Scene Planner decides who embodies each
    obligation)
  - specify a location, time of day, weather, or object
  - specify what is said or remembered
  - describe sensory detail

CONFLICT IS FIRST-CLASS
---------------------------------------------------------------
Every beat has a `conflict` object with two fields:

  need:       what the protagonist requires to move forward
              (e.g., "receive help", "admit weakness", "let the
              old life go")
  protection: what the protagonist is defending against, that
              opposes the need (e.g., "avoid humiliation",
              "preserve self-image", "keep pride intact")

Together, need and protection define the tension the beat asserts.
Scene Planner later decides how that tension is dramatized.

BACKBONE TARGET
---------------------------------------------------------------
For a Tommy-shaped premise (breakdown / not-deserving-help /
opportunity-passes / walking-home) the ideal beats look like:

  1. Breakdown creates dependence.
  2. Opportunity to receive help appears.
  3. Pride defeats need.
  4. Consequence becomes physical.

Aim for that level of abstraction, that number of beats (3–5), and
that cadence of movement.

OUTPUT CONTRACT
---------------------------------------------------------------
Return valid JSON only. No prose outside the JSON. Structure:

{
  "beats": [
    {
      "id": "b1",
      "purpose": "<one-line role of this beat in the arc>",
      "dramatic_function": "<one of: establish_need | introduce_opportunity | escalate_pressure | force_a_decision | reveal_information | lose_an_opportunity | make_consequence_physical | resolve_a_question>",
      "required_transition": "<how the story state must shift during this beat, abstract>",
      "required_end_state": "<the abstract state that must be true when this beat ends>",
      "conflict": {
        "need":       "<what the protagonist requires>",
        "protection": "<what the protagonist is defending against>"
      },
      "required_story_events": [
        "<1-3 abstract obligations; movements, not stagings>"
      ],
      "generation_freedoms": [
        "<1-3 things Scene Planner is free to invent>"
      ]
    }
  ]
}

RULES
- Produce 3–5 beats total. Do not exceed 5.
- Beats are ORDERED. The end state of beat N is the start state of
  beat N+1. The final beat's end state must match the Spine's
  terminal_state.
- The dramatic axis must move visibly across the beats: external
  problem introduced → internal obstacle rises → opportunity
  appears and is engaged (taken or lost) → consequence lands.
- Each beat's `conflict.need` and `conflict.protection` must be
  non-empty and semantically opposed.
- Each beat's `required_story_events` list is TIGHT (1–3 items),
  every item an abstract movement. NEVER a staging.
- Do NOT reference the Symbolic questions as beat drivers. Story
  questions drive; reader curiosities may be background.

Return the JSON now.
"""

@step =
  desc: "Convert story_spine_json into ordered abstract Story Beats (JSON only)"

  action: (S) ->
    spine = await S.need 'story_spine_json'
    spine = coerceJSON spine
    if spine?.parse_error
      throw new Error "[story_beats] upstream story_spine returned parse_error; cannot plan beats"

    prompt = buildPrompt spine

    modelDir = S.param 'quantized_model_dir', null
    throw new Error "[story_beats] Missing quantized_model_dir param" unless modelDir?

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
    beats = extractJSON raw

    unless shapeLooksOk beats
      beats =
        parse_error: true
        raw: raw
        message: "story_beats could not extract a valid beats array (raise llm.maxTokens or check the Spine)"

    # Carry the Spine's cast + lens forward for downstream stages. Beats
    # themselves must not name specific cast (Scene Planner assigns), but
    # the artifact carries the cast so Scene Planner has one place to read.
    beats.cast = spine?.cast if spine?.cast?
    beats.lens = spine?.lens if spine?.lens?
    beats.spine_ref =
      title:          spine?.story?.title
      premise:        spine?.story?.premise
      protagonist:    spine?.story?.protagonist
      terminal_state: spine?.story?.terminal_state

    S.make 'story_beats_json', beats
    S.done()
    return
