###
  build_diary_prompt_ite.coffee  —  DIARY_ITE pipeline step
  =====================================================
  Renders the selected diary events into a single
  prompt string for the diary-generation models. Pure
  string-building; no MLX calls live here. The output
  artifact feeds both the with-adapter and without-adapter
  generation steps.
###
renderEvent = (event) ->
  kind = String(event?.kind ? '').trim()
  text = String(event?.text ? '').trim()
  keyword = String(event?.keyword ? '').trim()
  headline = String(event?.headline ? '').trim()
  lines = []
  lines.push "- #{kind}: #{text}" if kind.length or text.length
  lines.push "  keyword: #{keyword}" if keyword.length
  lines.push "  headline: #{headline}" if headline.length
  lines.join "\n"

renderKagEntry = (entry) ->
  keyword = String(entry?.keyword ? '').trim()
  headline = String(entry?.headline ? '').trim()
  return "- #{keyword}: #{headline}" if keyword.length and headline.length
  return "- #{headline}" if headline.length
  return "- #{keyword}" if keyword.length
  "- unlabelled KAG cue"

renderEventSupport = (kind, payload) ->
  return null unless payload? and typeof payload is 'object'
  emotion = String(payload.selected_emotion ? '').trim()
  matches = payload.matches ? []
  lines = []
  lines.push "#{kind}:"
  lines.push "  desired emotion: #{emotion}" if emotion.length
  if matches.length is 0
    lines.push "  support: none"
    return lines.join "\n"

  for match in matches
    keyword = String(match?.keyword ? '').trim()
    headline = String(match?.headline ? '').trim()
    if keyword.length and headline.length
      lines.push "  - #{keyword}: #{headline}"
    else if headline.length
      lines.push "  - #{headline}"
    else if keyword.length
      lines.push "  - #{keyword}"
    else
      lines.push "  - support cue"
  lines.join "\n"

# Render the actual story CHUNKS (Jim's own words) collected per diary event,
# capped to keep the prompt bounded. These are the passages collect_diary_kag_ite
# matched for each event — reference voice/detail, NOT plot to copy.
excerpt = (text, cap) ->
  s = String(text ? '').replace(/\s+/g, ' ').trim()
  return s if not (cap > 0) or s.length <= cap
  cut = s.slice(0, cap)
  lastSpace = cut.lastIndexOf ' '
  cut = cut.slice(0, lastSpace) if lastSpace > cap * 0.6
  "#{cut}…"

renderEventPassages = (kind, payload, cap) ->
  return null unless payload? and typeof payload is 'object'
  passages = []
  for match in (payload.matches ? [])
    txt = excerpt match?.chunk_text, cap
    passages.push txt if txt.length
  return null unless passages.length
  lines = ["#{kind}:"]
  lines.push "  “#{p}”" for p in passages
  lines.join "\n"

coerceJSON = (value) ->
  return value unless typeof value is 'string'
  try
    JSON.parse value
  catch
    value

# ─── Story-spine folding (LOCAL FORK ADDITION) ────────────────────
# Renders the structural plan into prose-neutral bullet points that the
# generator can honor without copying phrasing. Order and phrasing echo
# the schema so the diary chapter carries the plan's obligations.
renderSpine = (spine) ->
  return null unless spine? and typeof spine is 'object' and spine.story?
  return null if spine.parse_error
  lines = []
  lines.push "Title: #{spine.story.title}" if spine.story.title?
  lines.push "Premise: #{spine.story.premise}" if spine.story.premise?
  axis = spine.story.dramatic_axis ? {}
  lines.push "Dramatic axis:"
  lines.push "  external problem:   #{axis.external_problem}"    if axis.external_problem?
  lines.push "  internal obstacle:  #{axis.internal_obstacle}"   if axis.internal_obstacle?
  lines.push "  missed opportunity: #{axis.missed_opportunity}"  if axis.missed_opportunity?
  lines.push "  primary consequence: #{axis.primary_consequence}" if axis.primary_consequence?
  lines.push "Starting state: #{spine.story.starting_state}"  if spine.story.starting_state?
  lines.push "Terminal state: #{spine.story.terminal_state}"  if spine.story.terminal_state?
  if Array.isArray(spine.story.required_story_events) and spine.story.required_story_events.length
    lines.push "Required events (must occur, in order):"
    lines.push "  - #{e}" for e in spine.story.required_story_events
  if Array.isArray(spine.story.protected_facts) and spine.story.protected_facts.length
    lines.push "Protected facts (must not be contradicted):"
    lines.push "  - #{f}" for f in spine.story.protected_facts
  if Array.isArray(spine.scenes) and spine.scenes.length
    lines.push "Scenes (each = one paragraph or short section, in order):"
    for sc, i in spine.scenes
      lines.push "  #{i+1}. purpose=#{sc.purpose}"
      lines.push "     catalyst: #{sc.catalyst}"           if sc.catalyst?
      lines.push "     dramatic pressure: #{sc.dramatic_pressure}" if sc.dramatic_pressure?
      lines.push "     required choice: #{sc.required_choice}"     if sc.required_choice?
      lines.push "     required reveal: #{sc.required_reveal}"     if sc.required_reveal?
      if Array.isArray(sc.required_events) and sc.required_events.length
        lines.push "     required events:"
        lines.push "       - #{e}" for e in sc.required_events
      lines.push "     ending state: #{sc.ending_state}"   if sc.ending_state?
  lines.join "\n"

normalizeDiaryKag = (value) ->
  value = coerceJSON value
  return value if Array.isArray(value?.entries)

  if value? and typeof value is 'object' and not Array.isArray(value)
    if Array.isArray(value.value?.entries)
      return value.value
    if typeof value.entries is 'string'
      parsedEntries = coerceJSON value.entries
      if Array.isArray(parsedEntries)
        out = Object.assign {}, value
        out.entries = parsedEntries
        return out

  value

readArtifactTarget = (L, artifactKey) ->
  experiment = L.theLowdown('experiment.yaml')?.value ? {}
  targetKey = experiment?.artifacts?[artifactKey]?.target
  return undefined unless typeof targetKey is 'string'

  targetEntry = L.theLowdown targetKey
  targetValue = targetEntry?.value
  if targetValue is undefined
    if typeof targetEntry?.waitFor is 'function'
      targetValue = await targetEntry.waitFor()
    else if targetEntry?.notifier?
      targetValue = await targetEntry.notifier
  targetValue

@step =
  desc: "Build the final diary prompt from diary events and matched KAG"

  action: (L) ->
    storyParts = await L.need 'story_parts'
    diaryKag = await L.need 'diary_kag'
    storySpine = await L.need 'story_spine_json'
    storyParts = coerceJSON storyParts
    diaryKag = normalizeDiaryKag diaryKag
    storySpine = coerceJSON storySpine

    unless storyParts? and typeof storyParts is 'object' and not Array.isArray(storyParts)
      storyParts = await readArtifactTarget L, 'story_parts'
      storyParts = coerceJSON storyParts

    unless Array.isArray(diaryKag?.entries)
      diaryKag = await readArtifactTarget L, 'diary_kag'
      diaryKag = normalizeDiaryKag diaryKag

    throw new Error "[#{L.stepName}] story_parts must be an object" unless storyParts? and typeof storyParts is 'object' and not Array.isArray(storyParts)
    throw new Error "[#{L.stepName}] diary_kag must be an object" unless Array.isArray(diaryKag?.entries)

    eventLines = []
    eventLines.push renderEvent kind:'scene', text: storyParts.scene?.text, keyword: storyParts.scene?.location, headline: ''
    eventLines.push renderEvent kind:'arrival', text: storyParts.arrival?.text, keyword: storyParts.arrival?.character, headline: ''
    eventLines.push renderEvent kind:'disturbance', text: storyParts.disturbance?.text, keyword: storyParts.disturbance?.theme, headline: ''
    eventLines.push renderEvent kind:'reflection', text: storyParts.reflection?.text, keyword: '', headline: ''
    eventLines.push renderEvent kind:'realization', text: storyParts.realization?.text, keyword: '', headline: ''
    eventLines = eventLines.filter(Boolean)
    kagLines = (renderKagEntry(entry) for entry in diaryKag.entries when entry?).filter(Boolean)
    supportLines = []
    for kind in ['scene', 'arrival', 'disturbance', 'reflection', 'realization']
      row = renderEventSupport kind, diaryKag?.events?[kind]
      supportLines.push row if row?

    # Fold the actual matched CHUNKS (Jim's own words) in per event. Toggle with
    # include_chunk_passages (default on); chunk_excerpt_chars caps each passage
    # (0 = full text) so 5 events × per_event_match_limit chunks stay bounded.
    includePassages = L.param('include_chunk_passages', true) isnt false
    excerptCap = Number(L.param('chunk_excerpt_chars', 700)) or 0
    passageLines = []
    if includePassages
      for kind in ['scene', 'arrival', 'disturbance', 'reflection', 'realization']
        row = renderEventPassages kind, diaryKag?.events?[kind], excerptCap
        passageLines.push row if row?

    spineBlock = renderSpine storySpine
    hasSpine = typeof spineBlock is 'string' and spineBlock.length > 0

    finalInstruction = if hasSpine
      "Write ONE chapter that dramatizes the Structural plan above. Realize each scene in order, honoring its purpose, catalyst, required events, required choice, required reveal, and ending state. Do NOT skip scenes. Every required event and protected fact must appear. Weave the diary events and KAG cues in as texture — voice and sensory detail — inside the scenes that fit them; do not narrate them as a separate section."
    else
      "Write the events in the following order: scene, arrival, disturbance, reflection, realization. Make each one a separate paragraph in your writing."

    prompt = [
      "You are writing in the narrative voice of Jim from St. John's."
      ""
      "Write a chapter in first person."
      "Use the STRUCTURAL PLAN as the backbone — the plan's scenes are the chapter's paragraphs, in order."
      "Use the diary events and KAG cues as texture: voice, sensory detail, emotional grounding. They belong INSIDE the scenes, not as their own list."
      ""
      "Rules:"
      "- Do not introduce plot contradictions"
      "- Do not invent facts that contradict the Protected facts below"
      "- Every Required event MUST occur in the finished chapter"
      "- Add sensory detail and reflective narration"
      "- Keep the voice observational, slightly humorous, and reflective"
      "- Echo the cadence and texture of the reference passages below; borrow phrasing sparingly, never whole sentences, and never their plots"
      "- Return only the finished chapter"
      ""
      "Structural plan (obligations you MUST honor):"
      if hasSpine then spineBlock else "- none (falling back to 5-beat order)"
      ""
      "Diary events:"
      if eventLines.length then eventLines.join("\n") else "- none"
      ""
      "Event support cues:"
      if supportLines.length then supportLines.join("\n\n") else "- none"
      ""
      "Reference passages from Jim's own writing (voice + concrete detail; do NOT copy their plots), by event:"
      if passageLines.length then passageLines.join("\n\n") else "- none"
      ""
      "KAG cues:"
      if kagLines.length then kagLines.join("\n") else "- none"
      ""
      finalInstruction
    ].join "\n"

    console.log "[build_diary_prompt_ite] prompt chars:", prompt.length,
      "| chunk passages:", (if includePassages then passageLines.length else "off"),
      "| spine:", (if hasSpine then "folded (#{storySpine.scenes?.length ? 0} scenes)" else "absent")

    L.make 'diary_prompt_text', prompt
    L.done()
    return
