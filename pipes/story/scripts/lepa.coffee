###
  lepa.coffee — shared LEPA-framework loader for the `story` pipeline.

  Two data sources, resolved separately:

    loadFramework() → pipes/story/data/lepa_framework.yaml
      Summary + pipeline contract (energies, distortions,
      character_archetypes, arcana_usage, voice_policy, ...).

    loadArcana()    → GPT/lepa-ite/lepa_updated.json
      Canonical source of truth for the 22 upper + 4×10 minor arcana
      entries (deliberately not duplicated in the YAML).

  Path resolution mirrors the runner's scripts convention: try CWD
  first, then BASE. When neither exists, throw a contextual error
  naming every path we tried — the one acceptable guard (no shallow
  prescreens; see GPT/CONVENTIONS.md).
###

fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

CWD  = process.cwd()
# BASE = the project root containing node_modules/@jahbini/pipeline.
# From a pipe CWD like pipes/<pipe>/, BASE is two levels up.
BASE = path.resolve CWD, '..', '..'

resolveFirst = (candidates, tag) ->
  tried = []
  for p in candidates
    tried.push p
    return p if fs.existsSync p
  throw new Error "[lepa] #{tag} not found; tried:\n  " + tried.join('\n  ')

loadFramework = ->
  p = resolveFirst [
    path.join(CWD, 'data', 'lepa_framework.yaml')
    path.join(BASE, 'pipes', 'story', 'data', 'lepa_framework.yaml')
    path.join(BASE, 'data', 'lepa_framework.yaml')
  ], 'lepa_framework.yaml'
  yaml.load fs.readFileSync(p, 'utf8')

loadArcana = ->
  p = resolveFirst [
    path.join(CWD, 'data', 'lepa_updated.json')
    path.join(BASE, 'GPT', 'lepa-ite', 'lepa_updated.json')
  ], 'lepa_updated.json'
  JSON.parse fs.readFileSync(p, 'utf8')

@loadFramework = loadFramework
@loadArcana    = loadArcana
