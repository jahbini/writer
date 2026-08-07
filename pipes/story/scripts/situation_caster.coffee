###
  situation_caster.coffee — Phase 2 of the SKYGUY I Ching layer.

  Deterministic (no LLM). Sibling to story_spine — runs after
  story_outline (needs description) and chapter_context (needs the
  chapter index for the seed).

  Gate: use_iching_situations. When off, emits a sentinel artifact
  {enabled: false, reason: ...} so downstream `need`s don't hang.
  When on, does the full computation.

  Selection authority order (from iching_casting.yaml):
    1. explicit — description names a situation (name_internal token,
                  or `situation N` / `situation_id N` pattern)
    2. param    — situation_id override in override/story.yaml
    3. seeded   — deterministic from sha256(description|chapter_number)

  Emits (all render-safe or explicit-provenance):
    - current situation's render-safe fields (situation, tension,
      stages) — internal id/name/glyph/trigrams live under _internal
    - drawn_stages: [{line, text}] for the moving lines actually
      selected (3–5, bottom→top order)
    - derived situation's render-safe fields — same as current but for
      the next chapter, computed by flipping the drawn line bits
    - lepa_affinity for the chapter's lower + upper trigrams
    - _internal: full provenance (ids, glyphs, trigrams, drawn lines)
      kept in ONE nested block so build_diary_prompt (Phase 4) can
      strip it as a unit before any prompt renders.

  Nothing consumes this artifact yet (Phase 3 wires spine/beats).
###

crypto = require 'crypto'
path   = require 'path'
iching = require path.join(__dirname, 'iching.coffee')

coerceJSON = (value) ->
  return value unless typeof value is 'string'
  try JSON.parse value catch then value

# ── Seed discipline (canonical) ──────────────────────────────────
# Byte-source for every deterministic pick below. sha256 gives 32
# bytes — plenty for id + count + up to 5 line draws. The SKYGUY
# brief calls out "one seed discipline for both" (this and
# cast_genesis); cast_genesis today uses per-character snake_case
# and can migrate to this helper when convenient.
seedBytes = (description, chapterNumber) ->
  crypto.createHash('sha256').update("#{description ? ''}|#{chapterNumber ? 1}").digest()

# ── Selection: explicit match ────────────────────────────────────
# Rule (a): a bare name_internal token appears as a word in the
# description. Rule (b): `situation N` / `situation_id N` /
# `situation:N` (case-insensitive). First match wins; the returned
# span lets Phase 4 excise the matched text from any prose that
# derives from the description.
findExplicitSituation = (description, situations) ->
  desc = String(description ? '')
  return {matched: false} unless desc.length
  for entry in situations
    name = entry?.name_internal
    continue unless typeof name is 'string' and name.length
    re = new RegExp "\\b" + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + "\\b", 'i'
    m = desc.match re
    if m?
      return {
        matched: true
        id: entry.id
        name_internal: name
        match_text: m[0]
        match_index: m.index
        rule: 'name_internal_word'
      }
  m = desc.match /\bsituation(?:_id)?\s*[:#=]?\s*(\d+)\b/i
  if m?
    n = Number m[1]
    if Number.isInteger(n) and 1 <= n <= 64
      entry = (e for e in situations when e.id is n)[0]
      if entry?
        return {
          matched: true
          id: entry.id
          name_internal: entry.name_internal
          match_text: m[0]
          match_index: m.index
          rule: 'situation_id_pattern'
        }
  {matched: false}

# ── Selection: seeded pick ───────────────────────────────────────
# Two bytes → uint16 → mod 64 → +1. Documented as `two_bytes_mod_64`
# in the casting file's `selection.derived.method`; that placeholder
# is now real.
pickSituationSeeded = (bytes) ->
  n = (bytes[0] << 8) | bytes[1]
  (n % 64) + 1

# ── Moving line draw ─────────────────────────────────────────────
# K without-replacement picks from lines {1..6}, kept bottom→top.
# Each pick consumes one seed byte, indexed mod remaining-pool-size.
drawMovingLines = (bytes, cursor, count) ->
  pool = [1, 2, 3, 4, 5, 6]
  drawn = []
  c = cursor
  for _ in [0...count]
    b = bytes[c % bytes.length]
    c += 1
    idx = b % pool.length
    drawn.push pool.splice(idx, 1)[0]
  {lines: drawn.sort((a, b) -> a - b), next: c}

# ── Chapter chaining (transformation rule) ───────────────────────
# Flip the drawn line bits in the current glyph; the result is the
# derived glyph, which the library resolves to the next chapter's
# situation.
flipGlyph = (glyph, lines) ->
  arr = glyph.split('')
  for pos in lines
    i = pos - 1
    arr[i] = (if arr[i] is '1' then '0' else '1')
  arr.join ''

situationByGlyph = (glyph, situations) ->
  return null unless typeof glyph is 'string'
  for entry in situations
    return entry if entry.glyph_binary is glyph
  null

# ── LEPA affinity report ─────────────────────────────────────────
# Per casting.lepa_affinity (shop reading — 1-3-1-3, Geemo-approved
# 2026-08-07): heaven→anima, thunder/water/mountain→ethos,
# wind/fire/lake→logos, earth→pathos.
lepaAffinityForTrigrams = (lowerName, upperName, casting) ->
  affinity = casting?.lepa_affinity ? {}
  energyOf = (trigramName) ->
    for own energy, trigrams of affinity
      return energy if Array.isArray(trigrams) and trigramName in trigrams
    null
  lowerEnergy = energyOf lowerName
  upperEnergy = energyOf upperName
  unique = []
  for e in [lowerEnergy, upperEnergy] when e? and e not in unique
    unique.push e
  {lower_trigram: lowerName, lower_energy: lowerEnergy,
   upper_trigram: upperName, upper_energy: upperEnergy,
   energies: unique}

# Exposed for probes.
@seedBytes                = seedBytes
@findExplicitSituation    = findExplicitSituation
@pickSituationSeeded      = pickSituationSeeded
@drawMovingLines          = drawMovingLines
@flipGlyph                = flipGlyph
@situationByGlyph         = situationByGlyph
@lepaAffinityForTrigrams  = lepaAffinityForTrigrams

@step =
  desc: "Deterministic I Ching situation caster (Phase 2). Sentinel when use_iching_situations=false."

  action: (S) ->
    # Gate check first — when off, cheap short-circuit that emits a
    # sentinel so downstream steps that later `L.need` this artifact
    # get {enabled: false} instead of hanging.
    gateOn = S.param('use_iching_situations', false) is true
    unless gateOn
      S.make 'situation_cast_json', {enabled: false, reason: 'use_iching_situations is false'}
      S.done()
      return

    outline = null
    try outline = await S.need 'story_outline_json' catch e then outline = null
    outline = coerceJSON outline

    ctx = null
    try ctx = await S.need 'chapter_context' catch e then ctx = null
    ctx = coerceJSON ctx
    chapterNumber = Number(ctx?.chapter_number ? 1) or 1

    {situations: sitDoc, casting} = iching.loadAll(S)
    situations = sitDoc.situations
    description = String(outline?._source_description ? '')

    # ── Selection authority order ────────────────────────────
    resolution = null
    explicit = findExplicitSituation description, situations
    if explicit.matched
      resolution =
        source: 'explicit'
        rule: explicit.rule
        match_text: explicit.match_text
        match_index: explicit.match_index
        id: explicit.id
    else
      paramId = S.param 'situation_id', null
      if paramId?
        n = Number paramId
        if Number.isInteger(n) and 1 <= n <= 64
          resolution = { source: 'param', id: n }
        else
          throw new Error "[situation_caster] situation_id param must be an integer 1..64; got #{JSON.stringify(paramId)}"
    unless resolution?
      seedForPick = seedBytes description, chapterNumber
      id = pickSituationSeeded seedForPick
      resolution = { source: 'seeded', id }

    currentEntry = (e for e in situations when e.id is resolution.id)[0]
    throw new Error "[situation_caster] resolved situation id #{resolution.id} not in library" unless currentEntry?

    # ── Moving line draw (same seed, cursor advances past bytes 0-2) ─
    bytes = seedBytes description, chapterNumber
    countMin = casting?.selection?.moving_lines?.count_min ? 3
    countMax = casting?.selection?.moving_lines?.count_max ? 5
    countRange = Math.max(1, countMax - countMin + 1)
    forcedCount = S.param 'moving_line_count', null
    if forcedCount?
      forced = Number forcedCount
      unless Number.isInteger(forced) and countMin <= forced <= countMax
        throw new Error "[situation_caster] moving_line_count must be an integer #{countMin}..#{countMax}; got #{JSON.stringify(forcedCount)}"
      count = forced
    else
      count = countMin + (bytes[2] % countRange)

    {lines: movingLines} = drawMovingLines bytes, 3, count

    # ── Chapter chaining ─────────────────────────────────────
    derivedGlyph = flipGlyph currentEntry.glyph_binary, movingLines
    derivedEntry = situationByGlyph derivedGlyph, situations
    unless derivedEntry?
      throw new Error "[situation_caster] derived glyph '#{derivedGlyph}' not in library (from #{currentEntry.glyph_binary} flipping lines #{movingLines.join(',')})"

    # ── LEPA affinity for current chapter's trigram pair ─────
    affinity = lepaAffinityForTrigrams currentEntry.trigrams.lower, currentEntry.trigrams.upper, casting

    drawnStages = ({line: pos, text: currentEntry.stages[pos - 1]} for pos in movingLines)

    console.log "[situation_caster] chapter #{chapterNumber}: id=#{currentEntry.id} (source=#{resolution.source}), " +
                "moving lines=[#{movingLines.join(',')}] → derived id=#{derivedEntry.id}"

    chainChapters = S.param('chain_chapters', true) isnt false

    payload =
      enabled: true
      chain_chapters: chainChapters                # honored by story_spine
      chapter_number: chapterNumber
      resolution: resolution                       # provenance
      current:
        # render-safe fields only
        situation: currentEntry.situation
        tension:
          need: currentEntry.tension.need
          protection: currentEntry.tension.protection
        stages: currentEntry.stages.slice()
      drawn_stages: drawnStages                    # {line, text} pairs
      derived:
        # render-safe fields only
        situation: derivedEntry.situation
        tension:
          need: derivedEntry.tension.need
          protection: derivedEntry.tension.protection
        stages: derivedEntry.stages.slice()
      lepa_affinity: affinity
      # Internal provenance under one key so Phase 4's strip pass in
      # build_diary_prompt can drop the whole bucket as a unit — no
      # id / name_internal / glyph / trigram / moving-line data must
      # ever reach a generator prompt.
      _internal:
        current_id: currentEntry.id
        current_name_internal: currentEntry.name_internal
        current_glyph_binary: currentEntry.glyph_binary
        current_trigrams: currentEntry.trigrams
        moving_lines: movingLines
        derived_id: derivedEntry.id
        derived_name_internal: derivedEntry.name_internal
        derived_glyph_binary: derivedEntry.glyph_binary
        derived_trigrams: derivedEntry.trigrams
        explicit_match_span:
          (if explicit.matched then {text: explicit.match_text, index: explicit.match_index} else null)

    S.make 'situation_cast_json', payload
    S.done()
    return
