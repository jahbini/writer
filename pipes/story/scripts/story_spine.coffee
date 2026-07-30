fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

# ─── Story Spine step ─────────────────────────────────────────────────
# Reads the 8 UI selections (protagonist/antagonist/witness + 4 dramatic
# axis atoms + lens) plus story_parts, calls MLX with a strict planning
# prompt, and produces story_spine_json — a deterministic structural
# plan for a single chapter. Contains no prose.

readAtomsLibrary = ->
  # CWD when the runner invokes a step is the pipe's working dir
  # (e.g. pipes/story/). The library lives at data/jim_story_library.yaml.
  libPath = path.join process.cwd(), 'data', 'jim_story_library.yaml'
  yaml.load fs.readFileSync(libPath, 'utf8')

pickAtom = (list, id) ->
  return null unless id? and id.length
  for entry in (list ? [])
    return entry if entry?.id is id
  null

formatAtom = (atom, kind) ->
  return "(unspecified)" unless atom?
  extras = []
  extras.push "tags: #{atom.tags.join(', ')}" if atom.tags?.length
  extras.push "roles: #{atom.role_hints.join(', ')}" if atom.role_hints?.length
  tail = if extras.length then "  [#{extras.join(' | ')}]" else ''
  phrasing = if atom.canonical_phrasing? then "  — “#{atom.canonical_phrasing}”" else ''
  "#{atom.label} (id: #{atom.id})#{phrasing}#{tail}"

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

# Best-effort repair for a truncated JSON object: close any open string,
# trim trailing partial keys / dangling commas, then close arrays/objects
# in reverse stack order.
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
  # First parse failed. If truncated, try repair; otherwise give up.
  return null unless found.truncated
  try return JSON.parse(repairTruncatedJson found.json) catch then null
  null

shapeLooksOk = (spine) ->
  return false unless spine? and typeof spine is 'object'
  return false unless spine.story? and typeof spine.story is 'object'
  return false unless Array.isArray(spine.scenes) and spine.scenes.length > 0
  return false unless Array.isArray(spine.causal_spine) and spine.causal_spine.length > 0
  return false unless spine.questions? and Array.isArray(spine.questions.central)
  true

buildPrompt = (S, storyParts, lib) ->
  atoms = lib.story_atoms
  protagonist = pickAtom atoms.characters, S.param('protagonist')
  antagonist  = pickAtom atoms.characters, S.param('antagonist', null)
  witness     = pickAtom atoms.characters, S.param('witness', null)
  ext_problem = pickAtom atoms.external_problems,    S.param('external_problem')
  int_obstacle= pickAtom atoms.internal_obstacles,   S.param('internal_obstacle')
  missed_opp  = pickAtom atoms.missed_opportunities, S.param('missed_opportunity')
  primary_cons= pickAtom atoms.primary_consequences, S.param('primary_consequence')
  lens        = pickAtom atoms.lenses,               S.param('lens', 'mind_worm')

  throw new Error "protagonist atom not found for id '#{S.param('protagonist')}'" unless protagonist?
  throw new Error "external_problem atom not found"   unless ext_problem?
  throw new Error "internal_obstacle atom not found"  unless int_obstacle?
  throw new Error "missed_opportunity atom not found" unless missed_opp?
  throw new Error "primary_consequence atom not found" unless primary_cons?

  """
You are the Story Spine Generator for the Writers Guild pipeline.

Your purpose is NOT to write prose.
Your purpose is to convert the atoms below into a deterministic story
plan that later pipeline stages will expand into scenes and finished prose.

Think like a dramaturg and story architect, not a novelist.

Preserve the author's story. Never invent a different story. Never
improve it. Never solve it. Never write dialogue or narration.

ATOMS FOR THIS CHAPTER
---------------------------------------------------------------
Protagonist:          #{formatAtom protagonist, 'character'}
Antagonist:           #{formatAtom antagonist,  'character'}
Witness:              #{formatAtom witness,     'character'}
External problem:     #{formatAtom ext_problem, 'external_problem'}
Internal obstacle:    #{formatAtom int_obstacle,'internal_obstacle'}
Missed opportunity:   #{formatAtom missed_opp,  'missed_opportunity'}
Primary consequence:  #{formatAtom primary_cons,'primary_consequence'}
Interpretive lens:    #{formatAtom lens,        'lens'}
Lens interpretation:  #{lens?.interpretive_note ? '(none)'}

The canonical_phrasing on each atom is the phrasing the author chose;
carry it through in the "protected_facts" and "required_story_events"
sections wherever possible.

STORY_PARTS CONTEXT (from the diary_ite recipe's earlier stages)
---------------------------------------------------------------
#{JSON.stringify(storyParts ? {}, null, 2).slice(0, 2000)}

OUTPUT CONTRACT
---------------------------------------------------------------
Return valid JSON only. No prose outside the JSON. Structure:

{
  "story": {
    "title": "<short chapter title>",
    "premise": "<one-sentence premise>",
    "protagonist": "<name>",
    "dramatic_axis": {
      "external_problem":    "<echo the atom's canonical phrasing>",
      "internal_obstacle":   "<echo>",
      "missed_opportunity":  "<echo>",
      "primary_consequence": "<echo>"
    },
    "starting_state": "<state at chapter open>",
    "terminal_state": "<state at chapter close>",
    "required_story_events": [ "<events that MUST occur, in order>" ],
    "protected_facts":       [ "<facts later stages may never contradict>" ],
    "generation_freedoms":   [ "<things later stages may invent>" ]
  },
  "questions": {
    "central":    [ { "id": "q_<snake>", "text": "<question>" } ],
    "supporting": [ { "id": "q_<snake>", "text": "<question>" } ]
  },
  "causal_spine": [
    {
      "id": "c1",
      "event": "<one event, no prose>",
      "depends_on": [],
      "causes": ["c2"],
      "opens_questions": ["q_<snake>"],
      "closes_questions": []
    }
  ],
  "scenes": [
    {
      "id": "s1",
      "purpose": "<one of: establish_need | introduce_opportunity | force_a_decision | raise_stakes | reveal_information | lose_an_opportunity | resolve_a_question>",
      "starting_state": "<state>",
      "catalyst": "<what starts the scene>",
      "required_events":   [ "<events that must appear>" ],
      "dramatic_pressure": "<the pressure the scene applies>",
      "required_choice":   "<or null>",
      "required_reveal":   "<or null>",
      "required_outcomes": [ "<must be true when scene ends>" ],
      "ending_state": "<state at scene close>",
      "carry_forward": {
        "unanswered_questions":     ["q_<snake>"],
        "unresolved_relationships": [],
        "commitments":              [],
        "risks":                    [],
        "obligations":              [],
        "new_knowledge":            []
      },
      "generation_freedoms": [ "<what later stages may invent>" ]
    }
  ]
}

Rules for the plan:
- Every scene must change the story state.
- Every scene must open or close at least one question (except the final scene, which may only close).
- Every scene must leave something unresolved unless it is the final scene.
- The causal_spine chain must be non-empty and internally consistent
  (every id in depends_on / causes must reference another c<n> entry).
- Every question id used in causal_spine or carry_forward MUST be defined
  in the questions.central or questions.supporting arrays.
- Use the minimum number of scenes that carry the story from
  starting_state to terminal_state without gaps.

Return the JSON now.
"""

@step =
  desc: "Convert story atoms into a deterministic story spine (JSON plan)"

  action: (S) ->
    storyParts = await S.need 'story_parts'
    lib = readAtomsLibrary()
    unless lib?.story_atoms?
      throw new Error "atoms library missing story_atoms block at data/jim_story_library.yaml"

    prompt = buildPrompt S, storyParts, lib

    modelDir = S.param 'quantized_model_dir', null
    throw new Error "[story_spine] Missing quantized_model_dir param" unless modelDir?

    # In-process node-mlx path (same as generate_diary_without_adapter_ite).
    # Avoids the per-call Python cold-start of callMLX; the model stays
    # loaded across calls.
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

    # Single-shot at temperature 0 — retrying the same prompt at temp=0
    # is deterministic and would produce identical failures. If we ever
    # move to temp > 0, wrap this in a small retry loop.
    result = await S.callLLM llmArgs
    raw = String(result?.rawText ? result?.text ? '')
    spine = extractJSON raw

    unless shapeLooksOk(spine)
      # Preserve raw for inspection instead of throwing so the artifact
      # explains what the model actually produced.
      spine =
        parse_error: true
        raw: raw
        message: "story_spine could not extract a valid JSON shape (raise llm.maxTokens if the raw output ended mid-object)"

    S.make 'story_spine_json', spine
    S.done()
    return
