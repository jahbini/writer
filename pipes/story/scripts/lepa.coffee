###
  lepa.coffee — shared LEPA-framework loader for the `story` pipeline.

  Two data sources, both under pipes/story/data/:

    loadFramework(memo?) → parses lepa_framework.yaml
      Summary + pipeline contract (energies, distortions,
      character_archetypes, arcana_usage, voice_policy, ...).

    loadArcana(memo?)    → parses lepa_updated.json
      Canonical source of truth for the 22 upper + 4×10 minor arcana
      entries. Symlinked into data/ so meta json (CWD-only) can find
      it; original lives at GPT/lepa-ite/lepa_updated.json.

  Path convention: prefer the runner's meta devices when a memo is
  passed in (memo.theLowdown parses YAML/JSON via meta/yaml.coffee
  and meta/json.coffee). This is the "must use the meta methods"
  rule — see GPT/CONVENTIONS.md.

  Standalone / probe fallback: when no memo is passed (e.g. from a
  probe that isn't inside a step's action), fall back to fs reads
  with CWD → BASE/pipes/story path resolution.
###

fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

CWD  = process.cwd()
BASE = path.resolve CWD, '..', '..'

# Meta-first read: try memo.theLowdown, fall back to fs when standalone.
# The parser arg only fires on the fallback path — meta devices parse
# for us.
readMetaOrFile = (memo, key, parser) ->
  if memo?.theLowdown?
    return memo.theLowdown(key)?.value
  candidates = [
    path.join(CWD, key)
    path.join(BASE, 'pipes', 'story', key)
    path.join(BASE, key)
  ]
  for p in candidates when fs.existsSync p
    return parser fs.readFileSync(p, 'utf8')
  throw new Error "[lepa] #{key} not found via memo or fallback; tried:\n  " + candidates.join('\n  ')

loadFramework = (memo) ->
  readMetaOrFile memo, 'data/lepa_framework.yaml', yaml.load

loadArcana = (memo) ->
  readMetaOrFile memo, 'data/lepa_updated.json', JSON.parse

@loadFramework = loadFramework
@loadArcana    = loadArcana
