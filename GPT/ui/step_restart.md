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
state files. Never writes new params (existing params/<name>.yaml
is reused verbatim — this is a "restart with what's already
there" operation, not a re-launch).

Concrete steps the endpoint takes:

1. Compute the recipe DAG (`buildDag` from runner helpers, given
   the current pipe's recipe.yaml + override).
2. Read the target step's `state/step-<name>.json`, set
   `restart_here: true`, write it back. This is the runner's
   signal on next start to re-execute this step and everything
   downstream of it.
3. **Selective upstream cascade.** BFS through the target's
   `depends_on` closure. For each ancestor, check if all files
   listed in its `makes` are present on disk. If ANY are missing,
   mark that ancestor `restart_here: true` too.
4. Remove `state/pipeline.json` (the "we crashed last time" gate).
   Without this, the runner refuses to start.
5. `startRunner()` — spawns the pipe runner exactly as a normal
   launch would.

Response body includes the cascade list so the UI can flash "Also
restarting: step_a, step_b" in the status bar.

## Why the cascade exists

`restart_here` on a step whose upstream `done` markers exist but
whose upstream OUTPUT FILES do NOT exist causes an infinite wait.
Symptom: step never starts; runner's `resolveArtifact` awaits a
notifier for a file that already-`done` upstream will never
regenerate.

This case is real — an operator can delete artifacts from disk
between runs, or an old `state/` directory can be paired with a
fresh `output/` directory. The cascade fixes it precisely: any
ancestor whose promises can't be honored from disk gets marked to
re-execute, so files reappear before the target waits on them.

Ancestors whose files ARE present on disk are left as `done` —
those don't need to re-run.

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
