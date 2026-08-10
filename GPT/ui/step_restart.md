# Step-detail modal + Restart This Step

Shipped 2026-08-08. Lets the operator re-run a single script in a
recipe without blowing away the rest of the run's state.

## The modal

Trigger: click any script circle in the pipeline SVG.

Endpoint: `GET /api/step_detail?name=<step>` returns:

    { state: {...state/step-<name>.json...},
      params: "...params/<name>.yaml as text..." }

UI renders two panes side-by-side (state JSON pretty-printed on the
left, params YAML raw on the right). Top bar has a **Restart This
Step** button. Modal-freeze guard suppresses the 2s heartbeat
while open so the reader can dwell (see
[[pipeline_graph_reactivity]]).

## The restart

Endpoint: `POST /api/step_restart` with body `{name: "<step>"}`.

**Uses the sanctioned `restart_here` protocol from
`~/pipeline/runner/pipeline_runner.coffee` §6.** Does NOT delete
state files. Never writes new params — existing `params/<name>.yaml`
is reused verbatim.

**Only the target step is marked.** No upstream cascade, no
regeneration of prior steps' params or state. Anything the target
step needs from upstream must already be on disk from a previous
run; if it isn't, the runner will block on that dependency and the
operator has to resolve the upstream state themselves (typically by
restarting the missing upstream step first, or launching the whole
pipe from a clean state).

Concrete steps the endpoint takes:

1. Validate the target step exists in `experiment.yaml`.
2. Read `state/step-<name>.json`, set `restart_here: true`, write
   it back. That's the runner's signal on next start to re-execute
   this step and everything downstream of it. If no state file
   exists yet, no write is needed — the step will run on launch.
3. Remove `state/pipeline.json` (the "we crashed last time" gate).
   Without this, the runner refuses to start.
4. `startRunner()` — spawns the pipe runner exactly as a normal
   launch would.

## Why no cascade (design decision, 2026-08-10)

An earlier implementation cascaded upstream automatically: BFS
through the target's `depends_on`, mark `restart_here` on any
ancestor whose declared `makes:` files were missing on disk. The
intent was to prevent the runner's infinite-wait when an upstream
`done` marker existed but its output file didn't.

Operator feedback: this was confusing. It regenerated prior steps'
state silently, and it was never obvious which steps would be
touched by a click. The mental model "restart this step, nothing
else" is worth more than the convenience of auto-fixing missing
upstream files.

Current contract: restart-this-step touches exactly one state
file. If the runner blocks waiting on a missing upstream artifact,
that's visible in the pipeline graph and the operator restarts
that step next. Explicit is better than clever.

## Non-goals

- **Not** for changing params. Set the UI form + click Launch for
  that flow.
- **Not** a way to override the pipeline gate for a different
  reason than "I want to re-run this step." If you need to force
  through a real failure, `restart_here` does not lie about that
  history — the failed step's state still records the failure.
- **Not** required for a fresh run. The main Launch button already
  clears/rebuilds state as part of normal launch.

## Guardrails

- **Do not** manually delete files under `state/` from this
  endpoint. The whole point is to leave state intact except for
  the specific `restart_here` flags this operation sets.
- **Do not** bypass the runner. Restart always goes through
  `startRunner()`, same as Launch — that keeps a single code path
  for pipeline lifecycle events (subprocess management, log
  redirection, pipeline.json creation, etc.).
- **Do** re-verify runner §6 semantics if `restart_here` behavior
  ever changes — this endpoint is a direct client of that
  protocol.

## Files

- `~/writer/ui_server.coffee` — `handleStepDetail`,
  `handleStepRestart`, and the cascade helper.
- `~/writer/ui/index.html` — `openStepModal`, `restartStep`,
  `closeStepModal`.
- `~/pipeline/runner/pipeline_runner.coffee` §6 — the underlying
  `restart_here` protocol.
