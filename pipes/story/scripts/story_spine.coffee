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
  return false unless spine.questions? and typeof spine.questions is 'object'
  return false unless Array.isArray(spine.questions.story)
  true

resolveAtoms = (S, lib) ->
  atoms = lib.story_atoms
  picks =
    protagonist:         pickAtom atoms.characters,           S.param('protagonist')
    antagonist:          pickAtom atoms.characters,           S.param('antagonist', null)
    witness:             pickAtom atoms.characters,           S.param('witness', null)
    external_problem:    pickAtom atoms.external_problems,    S.param('external_problem')
    internal_obstacle:   pickAtom atoms.internal_obstacles,   S.param('internal_obstacle')
    missed_opportunity:  pickAtom atoms.missed_opportunities, S.param('missed_opportunity')
    primary_consequence: pickAtom atoms.primary_consequences, S.param('primary_consequence')
    lens:                pickAtom atoms.lenses,               S.param('lens', 'mind_worm')

  throw new Error "protagonist atom not found for id '#{S.param('protagonist')}'" unless picks.protagonist?
  throw new Error "external_problem atom not found"   unless picks.external_problem?
  throw new Error "internal_obstacle atom not found"  unless picks.internal_obstacle?
  throw new Error "missed_opportunity atom not found" unless picks.missed_opportunity?
  throw new Error "primary_consequence atom not found" unless picks.primary_consequence?
  picks

buildPrompt = (picks) ->
  # story_parts is deliberately NOT consumed here — it belongs to the
  # legacy 5-beat diary flow. Feeding it in pollutes the spine with
  # atmospheric details the model treats as required events.
  { protagonist, antagonist, witness, external_problem, internal_obstacle,
    missed_opportunity, primary_consequence, lens } = picks

  # Explicit name list so the model can't quietly drop non-protagonist cast.
  castNames = [protagonist.label]
  castNames.push antagonist.label if antagonist?
  castNames.push witness.label if witness?
  castLine = castNames.join(', ')

  """
You are the Story Spine Generator for the Writers Guild pipeline.

Your purpose is NOT to write prose.
Your purpose is NOT to plan scenes, decide who appears where, choose
dialogue, or stage memories. Those are the responsibilities of later
stages (Story Beats and Scene Planner).

Your purpose is to capture DRAMATIC NECESSITY only: the immutable story
facts, the dramatic axis, and the questions that drive the chapter.

Think like a dramaturg locking in the story's obligations, not a
director blocking a scene.

Preserve the author's premise. Never invent a different story. Never
improve it. Never solve it.

ATOMS FOR THIS CHAPTER
---------------------------------------------------------------
Protagonist:          #{formatAtom protagonist, 'character'}
Antagonist:           #{formatAtom antagonist,  'character'}
Witness:              #{formatAtom witness,     'character'}
External problem:     #{formatAtom external_problem, 'external_problem'}
Internal obstacle:    #{formatAtom internal_obstacle,'internal_obstacle'}
Missed opportunity:   #{formatAtom missed_opportunity,  'missed_opportunity'}
Primary consequence:  #{formatAtom primary_consequence,'primary_consequence'}
Interpretive lens:    #{formatAtom lens,        'lens'}
Lens interpretation:  #{lens?.interpretive_note ? '(none)'}

FULL CAST FOR THIS CHAPTER: #{castLine}

ABSTRACTION LEVEL — READ CAREFULLY
---------------------------------------------------------------
The Story Spine describes WHAT MUST HAPPEN, not HOW it happens.

WRONG (staging — belongs to Scene Planner):
  "Southwick appears at the roadside."
  "Tommy remembers his old girlfriend."
  "Old girlfriend arrives in a red car."

RIGHT (dramatic necessity — belongs here):
  "A genuine opportunity to receive help appears."
  "The internal obstacle grows stronger than the immediate need."
  "The choice becomes unavoidable."
  "The consequence becomes physical."

The Story Spine must NEVER decide:
  - which specific character embodies the opportunity
  - where a character stands or how they arrive
  - what anyone says or remembers
  - weather, setting choreography, or sensory staging

Those are Scene Planner decisions, downstream. The premise atoms are
facts; the Story Spine only asserts that certain dramatic movements
must occur.

The protagonist's LABEL may be named in "story.protagonist" because it
is a fact, not staging. Other cast members must NOT be assigned
dramatic roles at this layer (Scene Planner picks who embodies which
beat obligation).

OUTPUT CONTRACT
---------------------------------------------------------------
Return valid JSON only. No prose outside the JSON. No scenes. No
causal chain. No blocking. Structure:

{
  "story": {
    "title": "<short chapter title>",
    "premise": "<one-sentence premise, abstract>",
    "protagonist": "<protagonist label>",
    "dramatic_axis": {
      "external_problem":    "<echo the atom's canonical phrasing>",
      "internal_obstacle":   "<echo>",
      "missed_opportunity":  "<echo>",
      "primary_consequence": "<echo>"
    },
    "starting_state": "<abstract dramatic state at chapter open>",
    "terminal_state": "<abstract dramatic state at chapter close>",
    "protected_facts":     [ "<3-6 immutable facts from the premise; no staging>" ],
    "generation_freedoms": [ "<3-6 things later stages are free to invent>" ]
  },
  "questions": {
    "story":             [ { "id": "q_<snake>", "text": "<question that pulls the plot forward>" } ],
    "reader_curiosities":[ { "id": "q_<snake>", "text": "<secondary question the reader wonders about>" } ],
    "symbolic":          [ { "id": "q_<snake>", "text": "<optional lens/symbolic question; may be empty>" } ]
  }
}

RULES
- Story questions are primary (must have at least one, at most three).
  They pull the plot forward. Example: "Will the protagonist admit
  they need help?"
- Reader curiosities are secondary (0-3). Example: "Is the car
  permanently broken?"
- Symbolic questions are optional (0-2). Example: "What does the
  hexagram mean?" Symbolic questions must NEVER drive the plot.
- protected_facts contain ONLY premise facts (from the atoms above),
  never staging. Good: "The protagonist's car has broken down." Bad:
  "Southwick pulls up in a truck."
- Every string in this artifact must describe dramatic necessity, not
  staging. If a string names a specific action, location, or line of
  dialogue, it is wrong for this layer.

Return the JSON now.
"""

@step =
  desc: "Convert story atoms into a deterministic story spine (JSON plan)"

  action: (S) ->
    # story_parts is still declared in `needs:` (so it's guaranteed to
    # exist when downstream stages want it), but the spine no longer
    # embeds it into the prompt.
    await S.need 'story_parts'
    lib = readAtomsLibrary()
    unless lib?.story_atoms?
      throw new Error "atoms library missing story_atoms block at data/jim_story_library.yaml"

    picks = resolveAtoms S, lib
    prompt = buildPrompt picks

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

    # Inject the cast from the raw atom picks — deterministic, not
    # LLM-dependent. Downstream stages MUST have the cast names
    # available regardless of what the model chose to keep in the plan.
    # The prompt builder will use these to bind voice + inject a
    # mandatory "cast" section into the diary prompt.
    castOf = (atom) ->
      return null unless atom?
      { id: atom.id, label: atom.label }
    spine.cast =
      protagonist: castOf picks.protagonist
      antagonist:  castOf picks.antagonist
      witness:     castOf picks.witness
    spine.lens = castOf picks.lens

    S.make 'story_spine_json', spine
    S.done()
    return
