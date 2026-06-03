cleanGeneratedText = (prompt, rawOutput) ->
  text = String(rawOutput ? '').trim()
  return '' unless text.length

  if text.indexOf(prompt) is 0
    text = text.slice(prompt.length).trim()

  lines = text.split /\r?\n/
  lines = lines.filter (line) ->
    trimmed = line.trim()
    return false if /^=+$/.test trimmed
    return false if /^Prompt:\s+\d+\s+tokens/.test trimmed
    return false if /^Generation:\s+\d+\s+tokens/.test trimmed
    return false if /^Peak memory:\s+/.test trimmed
    true

  lines.join("\n").trim()

coerceJSON = (value) ->
  return value unless typeof value is 'string'
  try
    JSON.parse value
  catch
    value

normalizeDiaryKag = (value) ->
  value = coerceJSON value
  return value if Array.isArray(value?.entries)

  if value? and typeof value is 'object' and not Array.isArray(value)
    if Array.isArray(value.value?.entries)
      return value.value
    if typeof value.entries is 'string'
      parsedEntries = coerceJSON value.entries
      if Array.isArray parsedEntries
        out = Object.assign {}, value
        out.entries = parsedEntries
        return out

  value

resolveEventMatches = (diaryKag, kind) ->
  row = diaryKag?.events?[kind]
  matches = row?.matches
  return [] unless Array.isArray matches
  matches

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

resolveRunTag = (L) ->
  raw = process.env.HH_MM ? L.theLowdown('env/HH_MM')?.value ? null
  return null unless raw?
  text = String(raw).trim()
  text = text.replace(/^"+|"+$/g, '')
  text = text.replace(/^'+|'+$/g, '')
  return null unless text.length
  text

wordSet = (text) ->
  words = String(text ? '').toLowerCase().match(/[a-z0-9]+/g) ? []
  new Set(words)

scoreEntryForEvent = (entry, eventWords) ->
  return 0 unless entry? and typeof entry is 'object'
  score = 0
  keyword = String(entry.keyword ? '').trim().toLowerCase()
  headlineWords = wordSet String(entry.headline ? '')
  score += 4 if keyword.length and eventWords.has keyword
  score += 2 if entry.chunk_index?
  for word in headlineWords
    score += 1 if eventWords.has word
  score

describeEvent = (kind, event) ->
  return null unless event? and typeof event is 'object'
  text = String(event.text ? '').trim()
  location = String(event.location ? '').trim()
  character = String(event.character ? '').trim()
  theme = String(event.theme ? '').trim()
  lines = []
  lines.push "Event kind: #{kind}"
  lines.push "Event text: #{text}" if text.length
  lines.push "Location: #{location}" if location.length
  lines.push "Character: #{character}" if character.length
  lines.push "Theme: #{theme}" if theme.length
  return null unless lines.length
  lines.join "\n"

eventWordsFor = (kind, event) ->
  bits = [
    kind
    event?.text ? ''
    event?.location ? ''
    event?.character ? ''
    event?.theme ? ''
    event?.emotion ? ''
    (event?.emotions ? []).join(' ')
  ]
  wordSet bits.join ' '

pickEventKagEntries = (entries, kind, event, limit = 4) ->
  eventWords = eventWordsFor kind, event
  scored = []

  for entry, idx in (entries ? [])
    score = scoreEntryForEvent entry, eventWords
    continue unless score > 0
    scored.push
      idx: idx
      score: score
      entry: entry

  if scored.length is 0
    return (entries ? []).slice 0, Math.min(limit, (entries ? []).length)

  scored.sort (a, b) ->
    if b.score isnt a.score then b.score - a.score else a.idx - b.idx

  (row.entry for row in scored.slice(0, limit))

renderKagExcerpts = (entries) ->
  blocks = []
  for entry in (entries ? [])
    chunkText = String(entry?.chunk_text ? '').trim()
    continue unless chunkText.length
    keyword = String(entry?.keyword ? '').trim()
    label = if keyword.length then "[#{keyword}]" else "[reference]"
    blocks.push "#{label}\n#{chunkText}"
  blocks

renderSceneHints = (event) ->
  return null unless event? and typeof event is 'object'
  lines = []
  location = String(event.location ? '').trim()
  character = String(event.character ? '').trim()
  theme = String(event.theme ? '').trim()
  lines.push "location: #{location}" if location.length
  lines.push "character: #{character}" if character.length
  lines.push "theme: #{theme}" if theme.length
  if lines.length then lines.join("\n") else null

buildEventPrompt = (kind, event, chosenEntries, priorSections, mode) ->
  eventText = String(event?.text ? '').trim()
  excerpts = renderKagExcerpts chosenEntries
  hints = renderSceneHints event
  priorText = if priorSections.length > 0 then priorSections[priorSections.length - 1].text else null

  parts = [
    "You are Jim from St. John's, writing a diary entry. First person."
    ""
    "Write exactly ONE paragraph. No line breaks inside it. No headings. No lists."
    "Continue directly from the prior paragraph. Do not restart the scene."
    "Stay in one physical place. Concrete sensory detail. At most one metaphor."
    "Return only the paragraph."
    ""
    "Prior paragraph:"
    if priorText? then priorText else "(none — this is the opening paragraph)"
    ""
    "Emotional reference (use the FEEL, not the words — do not quote):"
    if excerpts.length then excerpts.join("\n\n") else "(none)"
    ""
    "This section is the #{kind}."
    "Event: #{if eventText.length then eventText else '(none)'}"
  ]
  parts.push "Hints:\n#{hints}" if hints?

  emotionWords = []
  seen = new Set()
  for entry in (chosenEntries ? [])
    keyword = String(entry?.keyword ? '').trim()
    continue unless keyword.length
    continue if seen.has keyword
    seen.add keyword
    emotionWords.push keyword
  if emotionWords.length
    emotionPhrase = emotionWords.join ', '
    parts.push ""
    parts.push "Use the FEEL of #{emotionPhrase}."

  parts.join "\n"

resolveMode = (L) ->
  if /with_adapter/.test(L.stepName)
    return
      mode: 'adapter'
      rawKey: 'diary_adapted_raw'
      metaKey: 'diary_adapted_meta'
      textKey: 'diary_adapted_text'
      fileSuffix: '.adapter.txt'
  if /without_adapter/.test(L.stepName)
    return
      mode: 'base'
      rawKey: 'diary_base_raw'
      metaKey: 'diary_base_meta'
      textKey: 'diary_base_text'
      fileSuffix: '.txt'

  throw new Error "[#{L.stepName}] event ordered diary generator expects a with_adapter or without_adapter step name"

callDiaryGenerate = (L, modelDir, prompt, adapterPath, mlxConfig) ->
  args =
    model: modelDir
    prompt: prompt

  args["adapter-path"] = adapterPath if adapterPath?
  if mlxConfig? and typeof mlxConfig is 'object' and not Array.isArray(mlxConfig)
    for own key, value of mlxConfig
      continue unless value?
      args[key] = value

  L.callMLX 'generate', args

@step =
  desc: "Generate a diary entry one event at a time in story order"

  action: (L) ->
    modeInfo = resolveMode L

    storyParts = await L.need 'story_parts'
    storyParts = coerceJSON storyParts
    unless storyParts? and typeof storyParts is 'object' and not Array.isArray(storyParts)
      storyParts = await readArtifactTarget L, 'story_parts'
      storyParts = coerceJSON storyParts
    throw new Error "[#{L.stepName}] story_parts must be an object" unless storyParts? and typeof storyParts is 'object' and not Array.isArray(storyParts)

    diaryKag = L.theLowdown('diary_kag')?.value
    unless Array.isArray(diaryKag?.entries)
      diaryKag = await readArtifactTarget L, 'diary_kag'
    diaryKag = normalizeDiaryKag diaryKag
    throw new Error "[#{L.stepName}] diary_kag must be an object with entries" unless Array.isArray(diaryKag?.entries)

    modelDir = L.param 'quantized_model_dir', null
    adapterPath = L.param 'adapter_path', null
    mlxConfig = L.param 'mlx', null
    throw new Error "[#{L.stepName}] Missing quantized_model_dir param" unless modelDir?
    throw new Error "[#{L.stepName}] Missing adapter_path" if modeInfo.mode is 'adapter' and not adapterPath?
    throw new Error "[#{L.stepName}] mlx must be an object when provided" if mlxConfig? and (typeof mlxConfig isnt 'object' or Array.isArray(mlxConfig))

    eventOrder = [
      ['scene', storyParts.scene]
      ['arrival', storyParts.arrival]
      ['disturbance', storyParts.disturbance]
      ['reflection', storyParts.reflection]
      ['realization', storyParts.realization]
    ]

    priorSections = []
    rawSections = []

    for [kind, event] in eventOrder
      continue unless event? and typeof event is 'object'

      chosenMatches = resolveEventMatches diaryKag, kind
      chosenEntries = if chosenMatches.length > 0 then chosenMatches else pickEventKagEntries diaryKag.entries, kind, event, 4
      prompt = buildEventPrompt kind, event, chosenEntries, priorSections, modeInfo.mode
      rawOutput = callDiaryGenerate L, modelDir, prompt, adapterPath, mlxConfig
      sectionText = cleanGeneratedText prompt, rawOutput

      continue unless sectionText.length

      rawSections.push
        kind: kind
        prompt: prompt
        raw: String(rawOutput ? '')
        text: sectionText
        chunk_indexes: (entry.chunk_index for entry in chosenEntries when entry?.chunk_index?)
        keywords: (String(entry.keyword ? '').trim() for entry in chosenEntries when String(entry?.keyword ? '').trim().length)

      emotionKeywords = []
      seenEmotion = new Set()
      for entry in chosenEntries
        keyword = String(entry?.keyword ? '').trim()
        continue unless keyword.length
        continue if seenEmotion.has keyword
        seenEmotion.add keyword
        emotionKeywords.push keyword

      priorSections.push
        kind: kind
        text: sectionText
        emotions: emotionKeywords
        recipe: String(event?.text ? '').trim()

      console.log "[#{L.stepName}] generated section #{kind} chars:", sectionText.length

    finalText = priorSections.map((section) ->
      emotionPart = if section.emotions?.length then ", emotion: #{section.emotions.join(', ')}" else ''
      recipePart = if section.recipe?.length then ", recipe: #{section.recipe}" else ''
      "{event: #{section.kind}#{emotionPart}#{recipePart}}\n#{section.text}"
    ).join "\n\n"
    rawJoined = rawSections.map((section) -> "[#{section.kind}]\n#{section.raw}").join "\n\n==========\n\n"
    meta =
      story_id: String(storyParts.story_id ? '').trim() or null
      mode: modeInfo.mode
      model_dir: modelDir
      adapter_path: if modeInfo.mode is 'adapter' then adapterPath else null
      section_count: priorSections.length
      sections: rawSections.map (section) ->
        kind: section.kind
        text_chars: section.text.length
        chunk_indexes: section.chunk_indexes
        keywords: section.keywords
      raw_chars: rawJoined.length
      text_chars: finalText.length

    console.log "[#{L.stepName}] story:", String(storyParts.story_id ? '').trim()
    console.log "[#{L.stepName}] section count:", priorSections.length
    console.log "[#{L.stepName}] text chars:", finalText.length

    L.make modeInfo.rawKey, rawJoined
    L.make modeInfo.metaKey, meta
    L.make modeInfo.textKey, finalText

    runTag = resolveRunTag L
    if typeof runTag is 'string' and runTag.length
      L.saveThis "diary/diary_#{runTag}#{modeInfo.fileSuffix}", finalText

    L.done()
    return
