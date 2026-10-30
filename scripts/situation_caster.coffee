###
  situation_caster.coffee — Phase-1 deterministic I-Ching → voyage caster.

  Sibling of cast_genesis (deterministic, NO LLM, NO network). Turns a
  single hexagram draw into the top of a voyage per the spec blocks in
  data/iching_casting.yaml:

    - selection:       authority_order explicit → param → derived
                       (derived = two_bytes_mod_64 of the description hash)
    - moving_lines:    seeded choice without replacement, 3..5, bottom→top
    - weather_reading: two trigrams → lepa_affinity → {sea, sky} energy
                       climate (lower=sea, upper=sky)
    - captain_axis:    heaven-position reading; heaven-absent → the run's
                       moving-line centre of gravity

  Everything above is DETERMINISTIC from (description, chapter_number,
  + optional situation_id / moving_line_count overrides), so the same
  seed always casts the same voyage — the grand_scheme invariant.

  TWO OUTPUT LAYERS in `situation_cast_json`:
    internal  — diagnostic (trigrams, weather energies, captain axis,
                moving-line numbers, stressed dimensions). NEVER rendered.
    render    — render-safe only (situation text, tension, the moving
                lines' stage statements as beats). The leakage law
                (GPT/story/lepa_integration.md + iching_casting.yaml
                voice_policy) lives at this boundary: no energy name, no
                trigram/hexagram token crosses into `render`.

  Data + validation come from iching.loadAll(); this file adds only the
  casting decisions on top of the validated library.
###

path   = require 'path'
iching = require path.join(__dirname, 'iching.coffee')

# ── Deterministic primitives (no Math.random) ──────────────────────
# djb2 string hash → unsigned 32-bit. Stable across runs/machines.
stableHash = (str) ->
  h = 5381
  s = String(str ? '')
  for i in [0...s.length]
    h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
  h

# mulberry32 PRNG — seeded, deterministic, returns a thunk → [0,1).
prng = (seedInt) ->
  a = seedInt >>> 0
  ->
    a = (a + 0x6D2B79F5) | 0
    t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    ((t ^ (t >>> 14)) >>> 0) / 4294967296

# Seeded shuffle of a copy of `arr` (Fisher-Yates driven by `rand`).
shuffled = (arr, rand) ->
  a = arr[..]
  for i in [a.length - 1..1] by -1
    j = Math.floor rand() * (i + 1)
    [a[i], a[j]] = [a[j], a[i]]
  a

# ── Trigram → energy, inverted from casting.lepa_affinity ──────────
trigramEnergy = (casting) ->
  map = {}
  for own energy, trigrams of (casting?.lepa_affinity ? {})
    map[t] = energy for t in trigrams
  map

# ── Situation selection (authority: explicit → param → derived) ────
selectSituation = (opts) ->
  { description, situationId, situations } = opts
  list = situations?.situations ? []

  # explicit: the description literally names a situation (name_internal
  # or "#id"). Matched text is a directive, never passed to prose — the
  # caller is responsible for not echoing it. Cheap scan, lowercased.
  descLc = String(description ? '').toLowerCase()
  for e in list
    if descLc.indexOf(String(e.name_internal).toLowerCase()) >= 0 or descLc.indexOf("##{e.id}") >= 0
      return { entry: e, selected_by: 'explicit' }

  # param: an operator-pinned id (override/*.yaml: situation_id).
  pinned = parseInt situationId, 10
  if Number.isInteger(pinned) and 1 <= pinned <= 64
    hit = (e for e in list when e.id is pinned)[0]
    return { entry: hit, selected_by: 'param' } if hit?
    throw new Error "[situation_caster] situation_id #{pinned} not found in the 64-entry library"

  # derived: two_bytes_mod_64 of the description hash → id 1..64.
  h = stableHash description
  id = ((h & 0xFFFF) % 64) + 1
  hit = (e for e in list when e.id is id)[0]
  throw new Error "[situation_caster] derived id #{id} not found in library" unless hit?
  { entry: hit, selected_by: 'derived' }

# ── Moving lines (seeded, without replacement, bottom→top) ─────────
selectMovingLines = (opts) ->
  { seedInt, count, casting } = opts
  pol = casting?.moving_lines ? {}
  lo  = pol.count_min ? 3
  hi  = pol.count_max ? 5
  rand = prng seedInt

  n =
    if Number.isInteger(count) and count >= 1
      Math.max lo, Math.min(hi, count)
    else
      lo + Math.floor rand() * (hi - lo + 1)   # derived count in [lo, hi]

  picks = (shuffled [1, 2, 3, 4, 5, 6], rand)[0...n]
  picks.sort (a, b) -> a - b                    # order: bottom_to_top

# ── Weather (lower=sea, upper=sky; lepa_affinity) ──────────────────
readWeather = (entry, casting) ->
  t2e  = trigramEnergy casting
  wr   = casting?.weather_reading ? {}
  lower = entry.trigrams.lower
  upper = entry.trigrams.upper
  seaEnergy = t2e[lower]
  skyEnergy = t2e[upper]
  pure = seaEnergy is skyEnergy
  clim = wr.energy_climate ? {}

  sea: { trigram: lower, energy: seaEnergy }
  sky: { trigram: upper, energy: skyEnergy }
  pure: pure
  # The sky climate is the named/visible one; its stressed dimensions
  # lead. On a pure climate sea == sky, so the union is just that set.
  stresses: Array.from new Set([].concat(
    (clim[skyEnergy]?.stresses ? []),
    (clim[seaEnergy]?.stresses ? [])))
  gloss_sky: clim[skyEnergy]?.gloss ? null
  gloss_sea: clim[seaEnergy]?.gloss ? null

# ── Captain's axis (heaven-position; absent → moving-line CoG) ─────
readCaptainAxis = (entry, casting, movingLines) ->
  ca   = casting?.captain_axis ? {}
  bhp  = ca.by_heaven_position ? { sky: 'direction', sea: 'identity', both: 'vitality' }
  ha   = ca.heaven_absent ? { upper_majority: 'direction', lower_majority: 'identity', balanced: 'vitality' }
  heavenSky = entry.trigrams.upper is 'heaven'
  heavenSea = entry.trigrams.lower is 'heaven'

  if heavenSky and heavenSea
    return { axis: bhp.both, source: 'heaven_both' }
  if heavenSky
    return { axis: bhp.sky, source: 'heaven_sky' }
  if heavenSea
    return { axis: bhp.sea, source: 'heaven_sea' }

  # heaven absent → centre of gravity of the moving lines.
  # lines 1-3 = lower trigram (sea), 4-6 = upper trigram (sky).
  upperCount = (l for l in movingLines when l >= 4).length
  lowerCount = movingLines.length - upperCount
  axis =
    if upperCount > lowerCount then ha.upper_majority
    else if lowerCount > upperCount then ha.lower_majority
    else ha.balanced
  { axis, source: 'moving_lines', upper_lines: upperCount, lower_lines: lowerCount }

# ── The cast — pure, library-in / reading-out ──────────────────────
cast = (opts) ->
  { description, chapterNumber, situationId, movingLineCount, situations, casting } = opts

  { entry, selected_by } = selectSituation { description, situationId, situations }

  # Seed folds the chapter in so chained chapters cast distinctly.
  seedInt = stableHash "#{description}|ch#{chapterNumber ? 1}|s#{entry.id}"
  mlCount = parseInt movingLineCount, 10
  movingLines = selectMovingLines { seedInt, count: mlCount, casting }

  weather     = readWeather entry, casting
  captainAxis = readCaptainAxis entry, casting, movingLines

  # Moving lines' stages (0-indexed) become the chapter's beat pressure,
  # in line order. These are render-safe by construction (situations
  # file holds only surface text in stages[]).
  beats = (entry.stages[l - 1] for l in movingLines)

  internal:
    situation_id:   entry.id
    name_internal:  entry.name_internal
    glyph_binary:   entry.glyph_binary
    trigrams:       { lower: entry.trigrams.lower, upper: entry.trigrams.upper }
    weather:        weather
    captain_axis:   captainAxis
    moving_lines:   movingLines
    stresses:       weather.stresses
    selected_by:    selected_by
  render:
    situation:  entry.situation
    tension:    { need: entry.tension.need, protection: entry.tension.protection }
    beats:      beats
  seed:
    description_hash: stableHash description
    chapter_number:   chapterNumber ? 1
    seed_int:         seedInt

# ── Exports (pure fns for the probe) ───────────────────────────────
@stableHash        = stableHash
@prng              = prng
@shuffled          = shuffled
@trigramEnergy     = trigramEnergy
@selectSituation   = selectSituation
@selectMovingLines = selectMovingLines
@readWeather       = readWeather
@readCaptainAxis   = readCaptainAxis
@cast              = cast

# ── Step (mirrors cast_genesis: meta-layer only, no direct I/O) ────
@step =
  desc: "Deterministic I-Ching voyage caster — situation + moving lines + weather + captain axis"

  action: (S) ->
    # Param-gated OFF by default (preserves the non-voyage baseline),
    # same discipline as the LEPA integration. Voyage recipes turn it on.
    unless S.param('use_iching_situations', false) is true
      S.make 'situation_cast_json', { off: true }
      S.done()
      return

    { situations, casting } = iching.loadAll S

    reading = cast
      description:     S.param('story_description', S.param('author_description', ''))
      chapterNumber:   S.param('chapter_number', '1')
      situationId:     S.param('situation_id', '')
      movingLineCount: S.param('moving_line_count', '')
      situations:      situations
      casting:         casting

    i = reading.internal
    console.log "[situation_caster] cast '#{i.name_internal}' (##{i.situation_id}, #{i.selected_by}) — " +
      "weather #{i.weather.sky.energy} sky / #{i.weather.sea.energy} sea, " +
      "captain axis #{i.captain_axis.axis} (#{i.captain_axis.source}), " +
      "#{i.moving_lines.length} beats"

    S.make 'situation_cast_json', reading
    S.done()
    return
