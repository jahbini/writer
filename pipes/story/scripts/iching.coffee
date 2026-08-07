###
  iching.coffee — shared I Ching situation-layer loader for the
  `story` pipeline. Phase 1 of the SKYGUY briefing (2026-08-07).

  Two data sources, both under pipes/story/data/:

    loadSituations() → iching_situations.yaml
      64 canonical dramatic situations. Fields per entry: internal
      ids (`id`, `name_internal`, `glyph_binary`, `trigrams`) and
      render-safe text (`situation`, `tension.need`,
      `tension.protection`, `stages[0..5]` bottom→top).

    loadCasting()    → iching_casting.yaml
      Mechanics: trigram binaries, LEPA affinity map, selection
      authority order, moving-line policy, chapter-chaining
      transformation rule, voice policy, `param_defaults`.

  Path resolution mirrors lepa.coffee (`CWD/data/` first, then
  `BASE/pipes/story/data/`, then `BASE/data/`). Contextual throw when
  no path resolves.

  Validation (the "validate on load" mandate from SKYGUY):
    - situations: exactly 64 entries; ids 1..64 unique;
      glyph_binary is six [01] chars consistent with the trigram
      binaries (lower = chars 0..2, upper = chars 3..5); exactly six
      stages[] per entry; every trigram name in the situations file
      exists in the casting file's trigrams block.
    - casting: trigrams block present; each trigram maps to a
      3-char [01] binary.
  Any violation throws a single error naming every failure at once,
  so the human doesn't play whack-a-mole with successive fixes.

  Phase 1 is loader-only: nothing else in the tree calls these yet.
  Gates `use_iching_situations` / `use_iching_beats` stay closed.
###

fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

CWD  = process.cwd()
# BASE = the project root containing node_modules/@jahbini/pipeline.
# From a pipe CWD like pipes/<pipe>/, BASE is two levels up.
BASE = path.resolve CWD, '..', '..'

# Meta-first read: use memo.theLowdown when a step passes its ledger.
# Standalone/probe callers get an fs fallback resolving CWD →
# BASE/pipes/story → BASE. Fallback exists so
# `iching.loadAll()` in a probe doesn't require a memo — see
# GPT/CONVENTIONS.md on the meta-methods rule.
readMetaOrFile = (memo, key, parser = yaml.load) ->
  if memo?.theLowdown?
    return memo.theLowdown(key)?.value
  candidates = [
    path.join(CWD, key)
    path.join(BASE, 'pipes', 'story', key)
    path.join(BASE, key)
  ]
  for p in candidates when fs.existsSync p
    return parser fs.readFileSync(p, 'utf8')
  throw new Error "[iching] #{key} not found via memo or fallback; tried:\n  " + candidates.join('\n  ')

# ── Shape validators (single-file). Each returns an array of failure
#    strings; empty array = clean. Callers accumulate and throw once
#    with the full list. ────────────────────────────────────────────

validateCastingShape = (casting) ->
  fails = []
  unless casting? and typeof casting is 'object'
    return ['iching_casting.yaml: not an object at top level']
  trigrams = casting.trigrams
  unless trigrams? and typeof trigrams is 'object'
    return ['iching_casting.yaml: missing trigrams block']
  for own name, spec of trigrams
    binary = spec?.binary
    unless typeof binary is 'string' and binary.length is 3 and /^[01]{3}$/.test(binary)
      fails.push "iching_casting.yaml: trigrams.#{name}.binary must be 3 chars of [01], got #{JSON.stringify(binary)}"
  fails

validateSituationsShape = (doc) ->
  fails = []
  unless doc? and typeof doc is 'object'
    return ['iching_situations.yaml: not an object at top level']
  situations = doc.situations
  unless Array.isArray(situations)
    return ['iching_situations.yaml: situations must be an array']
  if situations.length isnt 64
    fails.push "iching_situations.yaml: expected 64 situations, got #{situations.length}"
  seenIds = new Set()
  for entry, i in situations
    tag = "situations[#{i}]"
    unless entry? and typeof entry is 'object'
      fails.push "#{tag}: not an object"
      continue
    id = entry.id
    unless Number.isInteger(id) and 1 <= id <= 64
      fails.push "#{tag}: id must be an integer 1..64, got #{JSON.stringify(id)}"
    else
      if seenIds.has id
        fails.push "#{tag}: duplicate id #{id}"
      seenIds.add id
    unless typeof entry.name_internal is 'string' and entry.name_internal.length
      fails.push "#{tag}: name_internal missing or empty"
    unless typeof entry.glyph_binary is 'string' and /^[01]{6}$/.test(entry.glyph_binary)
      fails.push "#{tag} (id=#{id}): glyph_binary must be 6 chars of [01], got #{JSON.stringify(entry.glyph_binary)}"
    unless entry.trigrams? and typeof entry.trigrams is 'object'
      fails.push "#{tag} (id=#{id}): trigrams block missing"
    else
      for slot in ['lower', 'upper']
        n = entry.trigrams[slot]
        unless typeof n is 'string' and n.length
          fails.push "#{tag} (id=#{id}): trigrams.#{slot} must be a non-empty string"
    unless typeof entry.situation is 'string' and entry.situation.length
      fails.push "#{tag} (id=#{id}): situation missing or empty"
    unless entry.tension? and typeof entry.tension is 'object'
      fails.push "#{tag} (id=#{id}): tension block missing"
    else
      unless typeof entry.tension.need is 'string' and entry.tension.need.length
        fails.push "#{tag} (id=#{id}): tension.need missing or empty"
      unless typeof entry.tension.protection is 'string' and entry.tension.protection.length
        fails.push "#{tag} (id=#{id}): tension.protection missing or empty"
    unless Array.isArray(entry.stages) and entry.stages.length is 6
      fails.push "#{tag} (id=#{id}): stages must be an array of exactly 6, got #{entry.stages?.length}"
    else
      for stage, si in entry.stages
        unless typeof stage is 'string' and stage.length
          fails.push "#{tag} (id=#{id}): stages[#{si}] must be a non-empty string"
  fails

# ── Cross-file validation ─────────────────────────────────────────
# Requires both files loaded. Two invariants:
#   1. Every trigram name a situation references must exist in the
#      casting file's trigrams block.
#   2. glyph_binary's lower 3 chars must equal the lower trigram's
#      binary, and its upper 3 chars must equal the upper trigram's
#      binary (per the bottom-line-first, lower=0..2, upper=3..5
#      convention documented in both files).
validateCrossConsistency = (situations, casting) ->
  fails = []
  trigrams = casting?.trigrams ? {}
  for entry, i in (situations?.situations ? [])
    tag = "situations[#{i}] (id=#{entry?.id})"
    lowerName = entry?.trigrams?.lower
    upperName = entry?.trigrams?.upper
    glyph = entry?.glyph_binary
    for name, slot in [lowerName, upperName]
      slotLabel = if slot is 0 then 'lower' else 'upper'
      continue unless typeof name is 'string' and name.length
      unless trigrams[name]?
        fails.push "#{tag}: trigrams.#{slotLabel} '#{name}' is not defined in iching_casting.yaml"
    continue unless typeof glyph is 'string' and /^[01]{6}$/.test(glyph)
    lowerBinary = trigrams[lowerName]?.binary
    upperBinary = trigrams[upperName]?.binary
    if typeof lowerBinary is 'string' and lowerBinary.length is 3
      actualLower = glyph[0...3]
      unless actualLower is lowerBinary
        fails.push "#{tag}: glyph_binary[0..2] '#{actualLower}' does not match trigrams.lower '#{lowerName}' (#{lowerBinary})"
    if typeof upperBinary is 'string' and upperBinary.length is 3
      actualUpper = glyph[3...6]
      unless actualUpper is upperBinary
        fails.push "#{tag}: glyph_binary[3..5] '#{actualUpper}' does not match trigrams.upper '#{upperName}' (#{upperBinary})"
  fails

# ── The one-shot loader ──────────────────────────────────────────
# Load both files, validate shapes, then cross-validate. Fail loud
# with the full failure list on any violation. Callers who want
# just one dict can call the convenience getters below (which
# delegate here — full validation always runs).
loadAll = (memo) ->
  situationsDoc = readMetaOrFile memo, 'data/iching_situations.yaml'
  castingDoc    = readMetaOrFile memo, 'data/iching_casting.yaml'

  fails = []
  fails.push (validateCastingShape castingDoc)...
  fails.push (validateSituationsShape situationsDoc)...
  # Only run cross-checks when the shapes look sane enough — otherwise
  # the cross-check would spew noise on already-flagged issues.
  if fails.length is 0
    fails.push (validateCrossConsistency situationsDoc, castingDoc)...

  if fails.length
    throw new Error "[iching] validation failed (#{fails.length} issue(s)):\n  - " + fails.join('\n  - ')

  { situations: situationsDoc, casting: castingDoc }

loadSituations = (memo) -> loadAll(memo).situations
loadCasting    = (memo) -> loadAll(memo).casting

@loadSituations           = loadSituations
@loadCasting              = loadCasting
@loadAll                  = loadAll
@validateSituationsShape  = validateSituationsShape
@validateCastingShape     = validateCastingShape
@validateCrossConsistency = validateCrossConsistency
