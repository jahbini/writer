# Elementary SAT verdict UI panel

**Where:** `~/writer/panels/sat_verdicts.coffee` (server) +
`~/writer/ui/index.html` `PANEL_CUSTOM_RENDERERS.sat_verdicts` (client).
Registered automatically by the writer UI's panel registry — no
`ui_server.coffee` edits required.

**What it shows:** per-pipe verdict grid — checks × {adapted, base}
with pass/fail dots — plus a raw-JSON drilldown per side and the
mtime of each verdict file. Header line shows the top-level PASS/FAIL
per side.

**Data source (live artifacts, per user 2026-09-18):** reads
`<CWD>/params/sat_verdict_adapted.yaml` and `sat_verdict_base.yaml`
directly. These are produced by
`~/writer/scripts/elementary_sat_ite.coffee` via
`L.make("sat_verdict_#{side}", verdict)`. `applies()` returns true iff
at least one of the two files exists on that pipe.

**Poll cadence:** 15 s, eager (data is tiny — two small YAMLs).

**Sits on the pipe UI at:** `column: 'after-outputs'`, alongside the
existing `sat_generations` panel (raw text outputs). SAT Generations
shows *what the model wrote*; SAT Verdicts shows *whether it passed
the six elementary checks*.

**Checks rendered (in row order):**
1. `structureCount` — five paragraphs
2. `characterLock` — no unlisted proper names
3. `freshnessCopy` — no n-gram overlap ≥ 6 with prior scraps
4. `premiseAdherence` — noun-overlap score with the premise
5. `checkStructureOrder` — LLM confirms scene/arrival/disturbance/reflection/realization order
6. `checkInvariantPreserving` — LLM confirms invariants preserved

**Tomorrow (still open):**
- Wire the two `elementary_sat_*` steps into `writer/experiment.yaml`
  so the verdicts actually get produced during a run — the panel is
  ready and will populate the moment the first artifact lands.
- Copy `elementary_sat_ite.coffee` to the mac-mini.
- Consider a cross-pipe roll-up view (all pipes' latest verdicts
  in one table) — the current panel is per-pipe only.
