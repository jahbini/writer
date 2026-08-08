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

# ─── SKYGUY Phase 4: forbidden-surface scrub ──────────────────────
# The hard rule (iching_casting.yaml voice_policy): the words hexagram
# / I Ching / trigram / moving line, hexagram numbers ("hexagram 42"),
# and pinyin name_internal tokens (qian_creative, kun_receptive, …)
# NEVER reach a generator prompt. The upstream boundaries already
# enforce this — situation_caster keeps ids/glyphs/trigrams under an
# `_internal` block that never crosses into spine — but this is the
# last chance to catch a slipup. Throw loud with the exact term and
# a 40-char context window so the leak's origin can be traced.
#
# Loads the iching name_internal list lazily; if the iching data is
# absent (older pipes without SKYGUY yet), just skip the pinyin scan
# — the fixed forbidden phrases still fire.
loadIchingNameInternals = (L) ->
  try
    ichingPath = path.join(process.cwd(), 'scripts', 'iching.coffee')
    return [] unless fs.existsSync ichingPath
    iching = require ichingPath
    doc = iching.loadAll(L)
    (e.name_internal for e in (doc?.situations?.situations ? []) when typeof e?.name_internal is 'string' and e.name_internal.length)
  catch
    []

SKYGUY_FORBIDDEN_PHRASES = [
  # word-boundary regexes; case-insensitive
  /\bhexagram\b/i
  /\bi[- ]?ching\b/i
  /\btrigram\b/i
  /\bmoving line\b/i
]

scrubForbiddenSurfaceTerms = (promptText, extraTokens = []) ->
  return unless typeof promptText is 'string' and promptText.length
  hits = []
  for re in SKYGUY_FORBIDDEN_PHRASES
    m = promptText.match re
    if m?
      hits.push {term: m[0], index: m.index, rule: 'fixed_phrase'}
  for tok in extraTokens
    continue unless typeof tok is 'string' and tok.length
    # name_internal tokens have `_` separators — match as one word.
    re = new RegExp "\\b" + tok.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + "\\b", 'i'
    m = promptText.match re
    if m?
      hits.push {term: m[0], index: m.index, rule: 'name_internal_token'}
  return if hits.length is 0
  # Contextual throw: first offender, with a 40-char window around it.
  h = hits[0]
  lo = Math.max 0, h.index - 40
  hi = Math.min promptText.length, h.index + h.term.length + 40
  ctx = promptText[lo...hi].replace(/\n/g, ' ')
  throw new Error """
  [build_diary_prompt] hygiene violation: forbidden surface term
  reached the generator prompt (rule=#{h.rule}). This should have been
  stripped at the spine boundary — trace back to see what leaked.
    term:      #{JSON.stringify h.term}
    at char:   #{h.index}
    context:   …#{ctx}…
    total hits (this scan): #{hits.length}
  """

# ─── Story-spine folding (LOCAL FORK) ─────────────────────────────
# The spine now carries ONLY dramatic necessity: title, premise, axis,
# protected facts, and the three question kinds. No scenes, no causal
# chain, no staging. Beats/scenes come from later stages when added.
@scrubForbiddenSurfaceTerms = scrubForbiddenSurfaceTerms
@SKYGUY_FORBIDDEN_PHRASES   = SKYGUY_FORBIDDEN_PHRASES

renderSpine = (spine) ->
  return null unless spine? and typeof spine is 'object' and spine.story?
  return null if spine.parse_error
  lines = []
  lines.push "Title: #{spine.story.title}" if spine.story.title?
  lines.push "Premise: #{spine.story.premise}" if spine.story.premise?
  axis = spine.story.dramatic_axis ? {}
  lines.push "Dramatic axis:"
  lines.push "  external problem:    #{axis.external_problem}"    if axis.external_problem?
  lines.push "  internal obstacle:   #{axis.internal_obstacle}"   if axis.internal_obstacle?
  lines.push "  missed opportunity:  #{axis.missed_opportunity}"  if axis.missed_opportunity?
  lines.push "  primary consequence: #{axis.primary_consequence}" if axis.primary_consequence?
  lines.push "Starting state: #{spine.story.starting_state}"  if spine.story.starting_state?
  lines.push "Terminal state: #{spine.story.terminal_state}"  if spine.story.terminal_state?
  if Array.isArray(spine.story.protected_facts) and spine.story.protected_facts.length
    lines.push "Protected facts (must not be contradicted):"
    lines.push "  - #{f}" for f in spine.story.protected_facts
  if Array.isArray(spine.story.generation_freedoms) and spine.story.generation_freedoms.length
    lines.push "Generation freedoms (you may invent these; they are not required):"
    lines.push "  - #{f}" for f in spine.story.generation_freedoms
  q = spine.questions ? {}
  if Array.isArray(q.story) and q.story.length
    lines.push "Story questions (drive the plot; at least one must be visibly at stake):"
    lines.push "  - #{it.text}" for it in q.story when it?.text?
  if Array.isArray(q.reader_curiosities) and q.reader_curiosities.length
    lines.push "Reader curiosities (secondary; may remain open):"
    lines.push "  - #{it.text}" for it in q.reader_curiosities when it?.text?
  if Array.isArray(q.symbolic) and q.symbolic.length
    lines.push "Symbolic questions (do NOT let these drive the plot):"
    lines.push "  - #{it.text}" for it in q.symbolic when it?.text?
  lines.join "\n"

# ─── Story-beats folding (LOCAL FORK, Increment b) ────────────────
# Beats are ORDERED abstract dramatic movements. They are the chapter's
# backbone — the axis moves through them, in order. Each beat carries
# a first-class conflict {need, protection}. Beats never name specific
# cast; the generator (or Scene Planner in Increment c) picks who
# embodies each obligation, constrained by the Cast block.
renderBeats = (beatsDoc) ->
  return null unless beatsDoc? and typeof beatsDoc is 'object'
  return null if beatsDoc.parse_error
  return null unless Array.isArray(beatsDoc.beats) and beatsDoc.beats.length
  lines = ["Beats (dramatic backbone — realize IN ORDER, one to the next):"]
  for b, i in beatsDoc.beats
    lines.push "  #{i+1}. [#{b.dramatic_function ? 'beat'}] #{b.purpose ? ''}"
    if b.conflict?
      lines.push "     need:       #{b.conflict.need}"       if b.conflict.need?
      lines.push "     protection: #{b.conflict.protection}" if b.conflict.protection?
    lines.push "     required transition: #{b.required_transition}" if b.required_transition?
    lines.push "     required end state:  #{b.required_end_state}"  if b.required_end_state?
    if Array.isArray(b.required_story_events) and b.required_story_events.length
      lines.push "     obligations (abstract — realize concretely with the Cast):"
      lines.push "       - #{e}" for e in b.required_story_events
  lines.join "\n"

# ─── Scene-plan folding (LOCAL FORK, Increment d) ─────────────────
# Render ONLY the concrete staging fields. Planner-internal metadata
# (satisfies_conflict, lands_end_state, selection_rationale,
# alternatives_considered) MUST NOT reach the generator's prompt —
# the previous run showed the model parroting those meta lines
# ("The opportunity to restart the car is now physically available")
# as narration. dialogue_beats and sensory_grounding are also
# excluded now: the adapter provides voice; we don't want the
# generator locked to the planner's phrasing.
renderScenePlan = (plan) ->
  return null unless plan? and typeof plan is 'object'
  return null if plan.parse_error
  return null unless Array.isArray(plan.scenes) and plan.scenes.length
  lines = ["What happened (in order — each is one moment Jim is recounting):"]
  for sc, i in plan.scenes
    lines.push "  #{i+1}."
    lines.push "     setting: #{sc.setting}"                            if sc.setting?
    if Array.isArray(sc.present_cast) and sc.present_cast.length
      lines.push "     who's involved: #{sc.present_cast.join(', ')}"
    lines.push "     what starts it: #{sc.catalyst}"                    if sc.catalyst?
    lines.push "     what happens: #{sc.action}"                        if sc.action?
    lines.push "     how it lands: #{sc.outcome}"                       if sc.outcome?
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
    # e7 (2026-08-02): story_parts is no longer read here — the legacy
    # 5-beat subgraph (select_story_recipe + resolve_story_parts) was
    # deleted from the recipe. Only KAG (which now derives its emotions
    # from beats) and the four planning artifacts remain as inputs.
    diaryKag = await L.need 'diary_kag'
    storySpine = await L.need 'story_spine_json'
    storyBeats = await L.need 'story_beats_json'
    scenePlan = await L.need 'scene_plan_json'
    diaryKag = normalizeDiaryKag diaryKag
    storySpine = coerceJSON storySpine
    storyBeats = coerceJSON storyBeats
    scenePlan = coerceJSON scenePlan

    unless Array.isArray(diaryKag?.entries)
      diaryKag = await readArtifactTarget L, 'diary_kag'
      diaryKag = normalizeDiaryKag diaryKag

    throw new Error "[#{L.stepName}] diary_kag must be an object" unless Array.isArray(diaryKag?.entries)

    kagLines = (renderKagEntry(entry) for entry in diaryKag.entries when entry?).filter(Boolean)

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

    # Beats block is DELIBERATELY not rendered into the generator's prompt
    # anymore (Increment d). Beats are useful for the planner; by the time
    # we have concrete scenes, beats are scaffolding.
    scenePlanBlock = renderScenePlan scenePlan
    hasScenePlan = typeof scenePlanBlock is 'string' and scenePlanBlock.length > 0

    # Only the protected_facts from the spine survive into the generator
    # prompt — those are premise-immutable and the generator can violate
    # them. Everything else (axis, questions, states, freedoms) was
    # planner-internal.
    protectedFacts = storySpine?.story?.protected_facts ? []
    protectedBlock = if Array.isArray(protectedFacts) and protectedFacts.length
      "Things that must stay true (from the premise):\n" +
        (protectedFacts.map (f) -> "  - #{f}").join("\n")
    else null

    cast = storySpine?.cast ? {}
    protagonistName = cast.protagonist?.label
    castRoles = []
    castRoles.push "  - #{cast.protagonist.label} (the one this happened to)" if cast.protagonist?
    castRoles.push "  - #{cast.antagonist.label} (also in the story)"          if cast.antagonist?
    castRoles.push "  - #{cast.witness.label} (was there / saw it / heard about it)" if cast.witness?
    hasCast = castRoles.length > 0
    castBlock = if hasCast
      "People in the story (the only named characters you may use):\n" + castRoles.join("\n")
    else null

    # ── Voice line (Increment d) ───────────────────────────────────
    # Reframed as a LETTER from Jim to a friend — retelling something
    # that happened to someone else. Jim wasn't the center of action;
    # he's recounting from half-forgotten memories, the way he'd tell
    # it at the James John Cafe. Voice/cadence live in the adapter;
    # this prompt only fixes the genre/framing/POV.
    aboutClause =
      if protagonistName? and protagonistName isnt 'Jim'
        "It happened to #{protagonistName}. You (Jim) were not the center of the action — you're retelling it the way you heard it, or half-remember it, or pieced it together after."
      else
        "You're retelling it in your own voice."

    voiceLine = """
You are Jim from St. John's, writing to a friend.

This is a letter, not a chapter. Open with an address ("Hi, Friend"
or similar). Warm, wry, digressive. Gossipy. #{aboutClause}

Jim tells stories from half-forgotten memories. Details are hazy in
places. Some things are third-hand ("Southwick told me…", "the way
I heard it…"). Jim wanders — a small unrelated observation or aside
somewhere is welcome. Jim is never inside another character's head.
Jim never uses "I" to speak as anyone but himself.
"""

    # Enumerated, step-by-step directive. Qwen-derivative models
    # (Huihui-abliterated included) execute numbered procedures much
    # more reliably than "Do X, do Y, and by the way Z" prose. Each
    # numbered step forces a chunk of output, which is what stretches
    # the letter past the two-sentence blurb the old prompt produced.
    finalInstruction = if hasScenePlan
      sceneCount = scenePlan?.scenes?.length ? 0
      perMomentLine = if sceneCount > 0
        "Write ONE PARAGRAPH per numbered moment above (there are #{sceneCount})."
      else
        "Write ONE PARAGRAPH per numbered moment in \"What happened\" above, in order."
      """
Your task: write ONE letter from Jim to Friend, retelling what
happened above. Complete these steps in order:

1. Open with a greeting ("Hi, Friend" or similar). One line.
2. Set the scene in Jim's voice — when / where / the mood — in
   2-3 sentences.
3. #{perMomentLine} Retell each moment as prose in Jim's voice.
   Do NOT copy the phrasing of the "what happened" notes. Do NOT
   narrate abstract obligations ("the need appears", "the choice
   becomes unavoidable"). Just tell what happened.
4. Somewhere in the middle, add ONE small unrelated aside — a
   Southwick sighting, a James John Cafe note, a passing weather
   observation. One or two sentences.
5. Close the letter with what Jim makes of it, or a wry aphorism.
   2-3 sentences.

Constraints:
- Every named person in "People in the story" MUST appear in the
  letter by name at least once.
- Do NOT introduce named characters not listed.
- Do NOT contradict any line in "Things that must stay true".
- Output is ONLY the letter itself. No preamble, no explanation,
  no section headers, no notes.

Begin writing the letter now.
"""
    else
      """
Your task: write ONE letter from Jim to Friend covering these five
moments, IN ORDER, one paragraph each:
  1. scene
  2. arrival
  3. disturbance
  4. reflection
  5. realization

Open with a greeting, close with a wry sign-off, output only the
letter. Begin now.
"""

    # Prompt shape (Increment d): letter framing FIRST, then Jim's own
    # writing near the top as register anchor (adapter carries voice;
    # this reminds the base of the world), then who + what happened +
    # what must stay true, then finally the retell instruction. No
    # planner meta, no beats block, no spine axis/questions.
    prompt = [
      voiceLine
      ""
      "Some scraps of your own past writing (for register — do NOT copy their plots, do NOT quote whole sentences; these are just to remind you what Jim's letters sound like):"
      if passageLines.length then passageLines.join("\n\n") else "- (none available)"
      ""
      if castBlock? then castBlock else "People in the story: (none provided)"
      ""
      if protectedBlock? then protectedBlock else ""
      ""
      if hasScenePlan then scenePlanBlock else "What happened: (no scene plan available; fall back to the events below)"
      ""
      "Emotional cues from the pipeline (background feel; no need to name them):"
      if kagLines.length then kagLines.join("\n") else "- none"
      ""
      finalInstruction
    ].join "\n"

    # SKYGUY Phase 4 hygiene: final scrub before persisting.
    # loadIchingNameInternals() returns [] if the iching data isn't in
    # this pipe (older pipes without the SKYGUY layer), so this is a
    # no-op for pre-SKYGUY installs.
    scrubForbiddenSurfaceTerms prompt, loadIchingNameInternals(L)

    console.log "[build_diary_prompt_ite] prompt chars:", prompt.length,
      "| passages:", (if includePassages then passageLines.length else "off"),
      "| protected_facts:", (protectedFacts?.length ? 0),
      "| scenes:", (if hasScenePlan then scenePlan.scenes?.length else "absent")

    L.make 'diary_prompt_text', prompt
    L.done()
    return
