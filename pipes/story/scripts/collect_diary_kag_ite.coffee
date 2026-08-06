###
  collect_diary_kag_ite.coffee — LOCAL FORK for the `story` recipe
  ================================================================
  Original: node_modules/@jahbini/pipeline/scripts/diary_ite/collect_diary_kag_ite.coffee
  Fork rationale (Increment e6, 2026-08-02):

  The original reads 5 hand-picked UI emotion params — one per legacy
  diary phase (scene/arrival/disturbance/reflection/realization) — and
  looks up KAG chunks for each. That decouples KAG retrieval from the
  actual chapter being generated: user picks "contentment" and gets
  paragraphs about the merkin bar bet, regardless of whether the
  chapter is about miserliness or a car breakdown.

  This fork DERIVES each emotion from `story_beats_json` — mapping each
  beat's `dramatic_function` to a KAG keyword — so KAG retrieval
  follows the chapter's dramatic arc automatically. The UI params
  still work as OVERRIDES: any non-empty `<kind>_emotion` param wins
  over the derived value.

  Beat → kind assignment is position-based (beat 1 → scene, 2 →
  arrival, …). If there are fewer than 5 beats, later slots reuse the
  last beat's emotion. If there are more, extras beyond position 5 are
  ignored (the diary_prompt structure only has 5 slots).
###

# ── Dramatic_function → KAG keyword mapping ──────────────────────
# Sourced from data/dramatic_grammars.yaml — dramatic_functions.<fn>.kag_emotion.
# Selector: `grammar:` param in override/<recipe>.yaml (default: jim_tragedy).
# kag_emotion values MUST be one of the allowed corpus keywords
# (see ALLOWED_EMOTION_KEYWORDS in the oracle script — currently 17:
# joy, contentment, sadness, grief, fear, anxiety, anger,
# frustration, disgust, shame, surprise, neutral, absurd, wry,
# playful, melancholy, mysterious).
fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

DEFAULT_EMOTION = 'neutral'

readGrammar = (name) ->
  libPath = path.join process.cwd(), 'data', 'dramatic_grammars.yaml'
  doc = yaml.load fs.readFileSync(libPath, 'utf8')
  grammar = doc?.grammars?[name]
  unless grammar?
    throw new Error "[collect_diary_kag_ite] grammar '#{name}' not found in #{libPath} (available: #{Object.keys(doc?.grammars ? {}).join(', ') or '(none)'})"
  grammar

buildBeatEmotionMap = (grammar) ->
  m = {}
  for own fn, spec of (grammar?.dramatic_functions ? {})
    emo = String(spec?.kag_emotion ? '').trim()
    m[fn] = emo if emo.length
  m

emotionForBeat = (beat, beatEmotionMap) ->
  return null unless beat?
  fn = String(beat.dramatic_function ? '').trim()
  beatEmotionMap[fn] ? DEFAULT_EMOTION

coerceJSON = (value) ->
  return value unless typeof value is 'string'
  try JSON.parse value catch then value

splitParagraphs = (text) ->
  paragraphs = []
  return paragraphs unless text?
  for block in String(text).split(/\n\s*\n/)
    trimmed = block.trim()
    paragraphs.push(trimmed) if trimmed.length
  paragraphs

buildStoryGroups = (text) ->
  paragraphs = splitParagraphs text
  return [] unless paragraphs.length

  if paragraphs.length < 5
    return [
      group_index: 1
      text: paragraphs.join "\n\n"
    ]

  groups = []
  total = paragraphs.length
  baseSize = Math.floor(total / 5)
  remainder = total % 5
  startIndex = 0

  for groupIndex in [0...5]
    groupSize = baseSize
    groupSize += 1 if groupIndex < remainder
    selected = paragraphs.slice startIndex, startIndex + groupSize
    groups.push
      group_index: groupIndex + 1
      text: selected.join "\n\n"
    startIndex += groupSize

  groups

selectMatches = (rows, limit, usedStoryIDs = null) ->
  matches = []
  seen = new Set()

  for row in rows
    storyID = String(row?.story_id ? '').trim()
    continue unless storyID.length
    continue if usedStoryIDs?.has(storyID)

    chunkIndex = Number row?.chunk_index
    continue unless Number.isFinite(chunkIndex) and chunkIndex > 0

    chunkText = String(row?.chunk_text ? '').trim()
    startParagraph = Number row?.start_paragraph
    endParagraph = Number row?.end_paragraph

    if chunkText.length is 0
      groups = buildStoryGroups row?.text ? ''
      group = groups[chunkIndex - 1]
      continue unless group?
      chunkText = group.text

    dedupeKey = "#{row.story_id}|#{chunkIndex}|#{row.keyword}|#{row.headline ? ''}"
    continue if seen.has dedupeKey
    seen.add dedupeKey

    matches.push
      story_id: storyID
      title: row.title ? null
      chunk_index: chunkIndex
      start_paragraph: if Number.isFinite(startParagraph) then startParagraph else null
      end_paragraph: if Number.isFinite(endParagraph) then endParagraph else null
      keyword: row.keyword ? null
      headline: row.headline ? null
      chunk_text: chunkText

    usedStoryIDs?.add storyID if usedStoryIDs?
    break if matches.length >= limit

  matches

flattenEntries = (eventMap) ->
  entries = []
  keywords = []
  seenKeywords = new Set()

  for own kind, payload of (eventMap ? {})
    for match in (payload?.matches ? [])
      entries.push
        story_id: match.story_id
        chunk_index: match.chunk_index
        keyword: match.keyword
        headline: match.headline
        chunk_text: match.chunk_text
      keyword = String(match?.keyword ? '').trim()
      continue unless keyword.length
      continue if seenKeywords.has keyword
      seenKeywords.add keyword
      keywords.push keyword

  { entries, keywords }

# ── Derive per-kind emotions from beats ──────────────────────────
# Position-based: beat 1 → scene, beat 2 → arrival, etc. If fewer
# than 5 beats, later slots reuse the last beat's emotion. UI
# override wins if the user set a non-empty param.
KINDS = ['scene', 'arrival', 'disturbance', 'reflection', 'realization']

derivePerKindEmotions = (L, beatsDoc, beatEmotionMap) ->
  beats = beatsDoc?.beats ? []
  emotions = {}
  provenance = {}

  # First fill from beats by position.
  lastEmotion = DEFAULT_EMOTION
  for kind, i in KINDS
    beat = beats[i] ? beats[beats.length - 1]  # reuse last beat if we ran out
    derived = emotionForBeat(beat, beatEmotionMap) ? lastEmotion
    lastEmotion = derived
    emotions[kind] = derived
    provenance[kind] =
      source: (if beats[i]? then "beat[#{i}]" else "beat[#{beats.length-1}] (reused)")
      dramatic_function: beat?.dramatic_function ? null

  # UI param OVERRIDES if non-empty.
  # 'default' (any case, trimmed) is the sentinel meaning "no override
  # — grammar decides". The UI's blank option renders as "(default)"
  # with value="" today, so the empty branch already covers the common
  # case; treating the literal string as sentinel makes the semantic
  # explicit and future-proofs against UIs that send the label as the
  # value. See GPT/story/spystory.md for the crash trace.
  for kind in KINDS
    override = String(L.param("#{kind}_emotion", '') ? '').trim()
    continue unless override.length
    continue if override.toLowerCase() is 'default'
    emotions[kind] = override
    provenance[kind].source = 'ui_override'

  { emotions, provenance }

@readGrammar             = readGrammar
@buildBeatEmotionMap     = buildBeatEmotionMap
@derivePerKindEmotions   = derivePerKindEmotions
@KINDS                   = KINDS

@step =
  desc: "Collect KAG chunk matches, driven by story_beats dramatic_functions (UI params override)"

  action: (L) ->
    # e7 (2026-08-02): story_parts is no longer read here — the legacy
    # 5-beat subgraph was deleted, and this fork drives KAG from beats
    # instead. Only story_beats_json feeds this step.
    beatsDoc = null
    try beatsDoc = await L.need 'story_beats_json' catch e then beatsDoc = null
    beatsDoc = coerceJSON beatsDoc

    limitRaw = L.param 'per_event_match_limit'
    limit = Number limitRaw
    throw new Error "[#{L.stepName}] per_event_match_limit must be a positive integer" unless Number.isFinite(limit) and limit > 0 and Math.floor(limit) is limit

    grammar = readGrammar L.param('grammar', 'jim_tragedy')
    beatEmotionMap = buildBeatEmotionMap grammar

    { emotions, provenance } = derivePerKindEmotions L, beatsDoc, beatEmotionMap

    eventMap = {}
    usedStoryIDs = new Set()

    for kind in KINDS
      selectedEmotion = String(emotions[kind] ? '').trim()
      rows = if selectedEmotion.length
        L.theLowdown("kagByKeyword{#{selectedEmotion}}.jsonl")?.value ? []
      else
        []
      matches = selectMatches rows, limit, usedStoryIDs
      eventMap[kind] =
        kind: kind
        selected_emotion: selectedEmotion
        source: provenance[kind]
        matches: matches

    flattened = flattenEntries eventMap

    payload =
      story_id: null
      keywords: flattened.keywords
      entries: flattened.entries
      events: eventMap
      # Provenance stamp: which beat drove each kind, and whether it
      # was derived or overridden.
      _emotion_source: provenance

    for own kind, row of eventMap
      console.log "[collect_diary_kag_ite] #{kind}: emotion=#{row.selected_emotion} source=#{row.source?.source} (#{row.source?.dramatic_function ? '-'}) matches=#{row.matches.length}"

    L.make 'diary_kag', payload
    L.done()
    return
