###
  panels/sat_verdicts.coffee — writer's Elementary SAT Verdicts panel
  ===================================================================

  Renders the pass/fail verdicts emitted by
  ~/writer/scripts/elementary_sat_ite.coffee. That recipe calls
  L.make("sat_verdict_#{side}", verdict) where side ∈ {adapted, base},
  so on disk each verdict lands at

      <CWD>/params/sat_verdict_<side>.yaml

  A pipe `applies` for this panel iff at least one of those artifact
  files exists.

  Verdict shape (as produced by elementary_sat_ite):
    {
      side, passed,
      checks: {
        structureCount: {passed, actual, expected},
        characterLock:  {passed, offenders: [...]},
        freshnessCopy:  {passed, runLen, threshold},
        premiseAdherence: {passed, score, threshold},
        checkStructureOrder:   {passed, roles: [...]},
        checkInvariantPreserving: {passed, invariants: [...]}
      }
    }

  The panel is `render_hint: 'custom'` — the client-side renderer
  (sat_verdicts) draws a compact adapted-vs-base grid with per-check
  status dots. Kept eager: two small YAMLs, cheap to read.
###

yaml = require 'js-yaml'

SIDES = ['adapted', 'base']

exports.panel =
  title:        'Elementary SAT'
  render_hint:  'custom'
  column:       'after-outputs'
  eager:        true
  poll_seconds: 15

  applies: (ctx) ->
    {fs, path, CWD} = ctx
    for side in SIDES
      p = path.join(CWD, 'params', "sat_verdict_#{side}.yaml")
      return true if fs.existsSync(p)
    false

  endpoint: (ctx) ->
    {fs, path, CWD} = ctx
    sides = {}
    for side in SIDES
      p = path.join(CWD, 'params', "sat_verdict_#{side}.yaml")
      unless fs.existsSync(p)
        sides[side] = null
        continue
      try
        raw = fs.readFileSync(p, 'utf8')
        parsed = yaml.load(raw)
        stat = fs.statSync(p)
        sides[side] = {
          verdict: parsed
          mtime:   stat.mtime?.toISOString?() ? null
          size:    stat.size
        }
      catch err
        sides[side] = {error: String(err?.message ? err)}
    {sides: sides}
