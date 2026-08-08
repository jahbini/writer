# Pipeline Graph — reactivity status

Original plan drafted 2026-08-07 evening. Updated 2026-08-08 after
the follow-up session. This doc reflects what shipped and what's
still open.

## What ships

### The panel
Full-width, above the two-column grid. Not default-collapsed —
opens on load. Fetched via `GET /api/pipeline_svg` which hot-reloads
`pipeline_svg.coffee` on every request (edits land without a UI
restart). Larger font, wider circles than the original mock.

### Render
Circles only (no boxes). Hover-reveal labels with a paint-order
white halo so text pops over neighbors. Colors are meaningful:

- **script.pending** — hollow dashed thin (waiting)
- **script.running** — bright orange solid + black outline + pulse
  + always-visible label + expanding halo (unmistakable, spot from
  across the room)
- **script.done** — solid dark green
- **script.failed** — solid crimson red
- **artifact.produced** — solid black (touched by this run)
- **artifact.stale** — solid light grey (from a previous run)
- **artifact.absent** — hollow dashed (producer exists but no file)
- **artifact.source** — solid green (input data with no producer)
- **artifact.terminal** — red outline layered on top of any fill

### Reactivity loop
`refreshPipelineGraph(steps, outFiles)` runs on every 2s heartbeat.

- **Signature-cached SVG re-fetch.** Sig = `(currentPipe,
  subtitle)`. Only re-fetches on change.
- **Script status classes** derived from `data.steps[i]` — note the
  API field is `.step` (not `.name`), the sync accepts either
  shape (`s?.step ?? s?.name`).
- **Artifact status classes** derived from `data.out_files[i]`,
  matched by `data-target` (which `pipeline_svg.coffee` emits on
  each artifact `<g>`). Uses `exists` and `is_fresh` — the server
  sets `is_fresh` by comparing file mtime to the current run's
  `started_at`.

### Click interactions
- **Data circle → file modal.** Opens the existing file modal
  (full-page text + copy-to-clipboard). Reuses `openFileModal(path)`.
- **Script circle → step-detail modal.** Two panes: state file
  (JSON) + params file (YAML). Restart button in the top bar. See
  [[step_restart]].

### Modal freeze guard
While EITHER modal (file OR step) is open, `refresh()` no-ops on
its heartbeat. Reader can dwell without under-modal DOM churn.
On modal close, one immediate `refresh()` fires to catch up.

## What's still open

Items 3–5 from the original plan haven't landed. Order of value:

### Edge reactivity (item 3)
Static gray edges today. Could color-shift on activation. Needs
`pipeline_svg.coffee` to tag paths with `data-source` /
`data-target-artifact` so client can find them.

### Pending vs ready vs blocked (item 4)
A `pending` script could be waiting-on-deps, ready-to-run, or
blocked-by-failed-upstream. Compute client-side from status +
topology, distinct fills.

### Polish (was "nice-to-have")
- **Legend row** under the panel header naming the color scheme.
- **Zoom + pan** for larger recipes.
- **Panel collapsed state** in localStorage.

## Interactions that shipped

Not in the original plan but built:

- Step-detail modal + Restart This Step button — see
  `GPT/ui/step_restart.md`.
- Selective upstream cascade for restart — see same.
- Modal-freeze guard — mentioned above.

## Guardrails

- Hover-only labels stay. Every enhancement above is compatible.
- Every filesystem read from the UI server still uses `fs`; the
  meta-methods rule in `CONVENTIONS.md` scopes to step actions,
  not the UI server. The UI has no memo — direct `fs` is correct.
- SVG endpoint hot-reload behavior stays; don't cache the module.
