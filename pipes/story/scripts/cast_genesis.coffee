###
  cast_genesis.coffee — Phase 1, deterministic character resolver.

  Reads `story_outline_json.unresolved_cast` (optional array of
  description-named characters that have no atom-library label) and
  mints a character sheet for each by looking up its declared
  archetype in `lepa_framework.character_archetypes`.

  NO LLM. NO UI KNOBS. Emits `cast_supplement`:

    { sheets: [ { id, label, archetype, court_role, primary_energy,
                  distortion, typical_imbalance }, ... ] }

  If the outline has no `unresolved_cast` (older outlines, or the
  simple case where every named character is a library atom), the
  step emits `{ sheets: [] }` — a no-op that downstream can just
  merge over an empty array.

  LEAKAGE LAW (see GPT/story/lepa_integration.md): the FULL sheets
  live only in this artifact. Downstream (story_spine) copies only
  `{id, label}` into spine.cast.supplemental. archetype/energy/
  distortion never enter the generator prompt.
###

path = require 'path'

lepa = require path.join(__dirname, 'lepa.coffee')

coerceJSON = (value) ->
  return value unless typeof value is 'string'
  try JSON.parse value catch then value

# name → snake_case: lowercase, non-alnum → _, collapse, trim.
snake = (name) ->
  s = String(name ? '').toLowerCase().replace(/[^a-z0-9]+/g, '_')
  s.replace(/^_+|_+$/g, '')

mintSheet = (entry, archetypes) ->
  name = String(entry?.name ? '').trim()
  archetypeKey = String(entry?.archetype ? '').trim()
  arch = archetypes[archetypeKey]
  unless arch?
    throw new Error "[cast_genesis] archetype '#{archetypeKey}' for '#{name}' is not one of the 9 keys in lepa_framework.character_archetypes"
  distortion = (arch.distortion_pool ? [])[0] ? null
  id:                 "genesis_#{snake(name)}"
  label:              name
  dramatic_relation:  entry?.dramatic_relation ? null
  archetype:          archetypeKey
  court_role:         arch.court_role
  primary_energy:     arch.primary_energy
  distortion:         distortion  # slowstep: one only
  typical_imbalance:  arch.typical_imbalance

@mintSheet = mintSheet
@snake     = snake

@step =
  desc: "Deterministic character-sheet minting from story_outline_json.unresolved_cast"

  action: (S) ->
    outline = null
    try outline = await S.need 'story_outline_json' catch e then outline = null
    outline = coerceJSON outline

    entries = outline?.unresolved_cast ? []
    fw = lepa.loadFramework(S)
    archetypes = fw?.character_archetypes ? {}

    sheets = (mintSheet(e, archetypes) for e in entries)

    console.log "[cast_genesis] minted #{sheets.length} sheet(s) from unresolved_cast"

    S.make 'cast_supplement', { sheets: sheets }
    S.done()
    return
