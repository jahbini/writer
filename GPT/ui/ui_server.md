Area: `ui_server.coffee` + `ui/index.html`

Purpose:
- provide the pipe-local UI for selecting recipes, editing overrides, launching runs, and inspecting outputs/logs

Deployment posture (human directive, May 2026):
- this UI is a DEVELOPMENT-ONLY tool. It is never shipped to consumer/
  production land. So its endpoints are intentionally UNAUTHENTICATED and
  no auth is to be added — anyone who can reach `UI_PORT` is, by design, the
  trusted developer. Do not add auth, CSRF guards, or confirm-dialogs to
  these endpoints on the grounds of "production safety"; that is out of
  scope for this surface.

UI lifecycle controls (restart + kill switch):
- the served page does NOT hot-reload. Relaunching `ui_server` (then
  reloading the browser) is how edits to `ui_server.coffee` / `ui/index.html`
  go live.
- `POST /api/switch_pipe` (`handleSwitchPipe`, "Switch Pipe UI" button) is the
  canonical RESTART action. A real pipe name switches+relaunches into
  `pipes/<name>/`; an EMPTY pipe restarts the current workspace IN PLACE
  (critical for non-`pipes/` workspaces like the repo root). It relaunches the
  TARGET workspace's own `ui_server.coffee` (falls back to `EXEC_ROOT`'s),
  preserving a project's edited UI + its `runtime.sqlite`. The button is never
  disabled.
- `POST /api/shutdown_ui` (`handleShutdownUi`, "Shutdown UI Server" button) is
  the KILL SWITCH. A relaunched server is `detached` + `unref`'d, so the
  browser is the only handle on it; this endpoint responds then
  `process.exit(0)` after 150 ms (freeing `UI_PORT`). CONFIRMED WORKING.
  This is distinct from "Kill Run" (`/api/kill`), which SIGTERMs the pipeline
  run pid, not the server.
- chicken-and-egg: a running server predates any change to its own restart/
  shutdown routes, so it cannot load such a fix through itself. After editing
  those handlers, do ONE manual relaunch; the buttons work thereafter.

Page title (top of window + browser tab):
- the `<h1 id="page-title">` and `document.title` read
  `Pipeline Monitor for <base_dir> (<pipe.current>)`. The parenthesized
  pipe is omitted entirely when no pipe is active — at the project
  root the title degrades cleanly to `Pipeline Monitor for <base_dir>`.
- `base_dir` is `path.basename(BASE)`, served from
  `buildPipeSummary` → `/api/status` `controls.pipe.base_dir`. The
  client sets the title in `refresh()`.

Current UI layout contract:
- left column is observability:
  - `Pipeline Death`
  - `Outputs`        (only the `out/*` files)
  - `Diary Files`    (its own panel — kept separate from `Outputs`)
  - `Logs`           (log files from `logs/`; starts collapsed by default via `data-default-collapsed="1"`)
  - `Steps`
  - `Latest Err`
  - `Latest Log`
- right column is one merged `Controls` pane containing:
  - `Pipe`
  - `Run`
  - `Recipe And Overrides`
  - recipe selector
  - launch / kill / restart controls
  - recipe UI fields

Collapsible sections:
- every `.panel` (and every `.controls-group` inside the right column) has
  its first `<h2>` or `<h3>` wired as a click toggle. The header gets a
  `▼` (open) / `▶` (collapsed) chevron prefix via `::before` on the
  `.section-toggle` class that `setupCollapsibles()` injects.
- when `.collapsed` is on the container, CSS hides every direct child
  except the header (`*:not(.section-toggle)`).
- per-section state persists in `localStorage` under
  `ui-collapse:<header-text-slug>` so the user's open/closed preferences
  survive page reloads.
- default behavior: every section opens. The user opts into collapsing.
- to make a panel start closed by default, add `data-default-collapsed="1"`
  to the `.panel` element. `setupCollapsibles()` checks that attribute as the
  fallback when no `localStorage` entry exists yet. Once the user opens or
  closes the panel, `localStorage` takes over and the attribute is ignored.
  Current panel with this attribute: `Logs`.

Per-pane fullscreen expand:
- two classes of element get a small `⤢` button in their top-right corner:
  - `.yaml-pane` (Recipe Background, Human Override, UI Control Override,
    Effective experiment.yaml — the four YAML viewers/editors)
  - `.ui-textarea-pane` (each `UI_textarea` field inside the Recipe UI
    Fields list — wrapped at render time by `renderControls()`)
- clicking the button lifts that pane to a `position: fixed` overlay
  with 24 px margins on all sides, over a semi-transparent backdrop.
  Inside the overlay, the textarea fills the available height via
  `grid-template-rows: auto 1fr`.
- exactly one pane can be expanded at a time. Clicking `⤢` on another
  pane closes the first. Backdrop-click and `Escape` also close.
- pane-expand state is hoisted to module scope (`paneCurrentlyExpanded`,
  `paneBackdrop`) so it survives across `renderControls()` re-renders
  that destroy and rebuild the `#ui-fields` subtree. The setup function
  also detects when the previously-expanded pane has been disconnected
  from the DOM (re-render) and tears the backdrop down before wiring the
  new DOM.
- `renderControls()` calls `setupPaneExpanders()` at its end so freshly-
  injected `.ui-textarea-pane` elements get their buttons. The wiring is
  idempotent (`dataset.expanderWired` guard) so it is safe to call on
  every refresh.

Current control model:
- recipe UI fields are discovered from the active recipe YAML
- supported directives are:
  - `UI_checkbox`
  - `UI_dropdown`
  - `UI_textarea`
- UI-backed values are stored in `state/ui-control.json`
- effective run control is materialized to `control_override.yaml`
- human overrides are recipe-scoped under `override/<pipeline>.yaml`
- legacy `override.yaml` is only a fallback/bootstrap source and should be
  copied forward into `override/<pipeline>.yaml` when selected

Recipe UI Fields ordering (mirrors writeStory's `scanUiFields`):
- Fields are NOT alphabetized. They are grouped by diary event kind so
  each event's story selection renders immediately followed by its
  emotion selection:

      select_story_recipe.scene
      collect_diary_kag_ite.scene_emotion
      select_story_recipe.arrival
      collect_diary_kag_ite.arrival_emotion
      select_story_recipe.disturbance
      collect_diary_kag_ite.disturbance_emotion
      select_story_recipe.reflection
      collect_diary_kag_ite.reflection_emotion
      select_story_recipe.realization
      collect_diary_kag_ite.realization_emotion

- The order is produced by:
  `eventOrder = ['scene', 'arrival', 'disturbance', 'reflection', 'realization']`
  → `kindFor(path)` matches `tail == kind` or `tail == "<kind>_emotion"`
  → kinned rows sorted by `kindIndex`, ties broken by original walk order
  → unkinned rows render first, in original recipe order.
- This relies on the recipe declaring `select_story_recipe` BEFORE
  `collect_diary_kag_ite`; within a single kind the walk order
  (preserved by the tie-break) puts the story selection before the
  emotion. Don't reorder the recipe's step keys without checking this.

Pipe/workspace rules:
- the active UI is pipe-local under `CWD`
- if a pipe-local file exists, prefer it over the repo-top fallback
- a new empty pipe infers `run.model` from the pipe directory name and
  materializes the selected recipe override when needed

BASE-tier resolutions (writediary, npm-extracted layout):
- `BASE` (project root containing the `node_modules/` that EXEC sits under)
  is computed once in `ui_server.coffee` mirroring the runner's `BASE`.
- `PIPES_ROOT = BASE/pipes`, NOT `EXEC_ROOT/pipes`. Fixes the dropdown +
  active-pipe label after a pipe switch.
- `resolveConfigPath(name)` returns the first existing of
  `[BASE, EXEC_ROOT]/config/<name>.yaml` — same precedence as the runner —
  so the recipe viewer shows the SAME recipe the runner will run.
- `resolveUiAsset(rel)` resolves `CWD/ui/<rel> → BASE/ui/<rel> → EXEC_ROOT/ui/<rel>`.
  The BASE tier serves the project's own `ui/` after a pipe switch
  (CWD = pipe, no `ui/`).
- the story library reads `CWD/data/jim_story_library.yaml` first, with
  `EXEC_ROOT/data/jim_story_library.yaml` as fallback — pipe data is the
  authoritative location.

Recipe selector — DYNAMIC (supersedes the prior hardcoded-list rule):
- the `pipelines:` value returned in `/api/status` controls is
  `discoverRecipes()`, which scans `[BASE, EXEC_ROOT]/config/*.yaml` and
  returns the sorted union of basenames. Every recipe that actually
  exists is selectable.
- the prior "hardcoded `_ite` covering set" rule is REMOVED. The dynamic
  list intentionally surfaces `test`, `download_model`, `base_ite`,
  alongside the `_ite` set, because they all resolve cleanly and each is
  selectable for a legitimate reason (smoke test, model bootstrap, base
  prep chain). Non-`_ite` reference recipes that don't ship a config
  yaml simply don't appear — no 404 risk.

Switch-pipe relaunch (writediary):
- `handleSwitchPipe` picks `uiServerPath` from the first existing of
  `targetCwd/ui_server.coffee` → `BASE/ui_server.coffee` → `EXEC_ROOT/ui_server.coffee`.
  The BASE tier is what survives a pipe switch with the PROJECT-edited UI
  (otherwise the package's stock `ui_server` silently takes over).
- the relaunch shell is `bash -lc` (login shell). A login shell re-sources
  the user's profile and can re-export an `EXEC` that clobbers what
  `spawn` sets — observed when the trainer host had a leftover
  `export EXEC=/Users/.../pipeline` in its profile. To defeat this,
  `handleSwitchPipe` reasserts the critical env vars INSIDE the exec:

      "sleep 1; exec env EXEC=… CWD=… UI_PORT=… UI_BIND_MODE=… coffee <uiServerPath>"

  `env VAR=val coffee …` sets the vars on the coffee process AFTER the
  profile is sourced, so a profile export can't clobber them.
- empty pipe selection = in-place restart of the current workspace (see
  `GPT/ui/ui_restart_on_switch_pipe.md`); do NOT 400 on empty `pipe`.

Polling contract:
- do one `refresh()` on page load
- do not run the 2-second polling loop all the time
- start the polling loop whenever any long-running job is active, stop it
  when everything is quiescent so the user can edit freely without the UI
  yanking values back from disk
- "active" means EITHER condition:
  - pipeline `run.status` is one of: `launching`, `running`, `killing`,
    `skipped`, `cooldown`
  - merge `merge_run.status` is one of: `launching`, `running`
- terminal merge states (`exited`, `failed`) intentionally stop polling —
  the immediate `refresh()` after the state transition has already captured
  the final display values
- the decision lives in `ui/index.html`'s `refresh()` function as a single
  `runActive || mergeActive` gate; do not split it into separate per-source
  loops

Active jobs that gate polling (today):
- pipeline run via `/api/launch` → `run.status`
- adapter+SQLite merge via `/api/merge_pipe` → `merge_run.status`
- when a third long-running operation is added (e.g. a model download), it
  must show up in this list AND in the polling gate, or its completion will
  not be noticed until manual reload

Branch portability:
- the UI is dev infrastructure used on every branch (`main`, `rusty`,
  `KAG`, `artifacts`, `coffeeToTheMetal`, `sqlite`, etc.). Improvements
  and bug fixes to it should propagate to ALL branches, not just the
  branch where they were authored.
- portable (apply to every branch):
  - `ui/index.html` — polling logic, layout, form rendering, file viewer
  - `ui_server.coffee` — polling gate, route handlers, file-viewer
    sandboxing, override hierarchy, refresh API contracts
- branch-specific (do NOT propagate blindly):
  - on writediary the recipe list is dynamic (`discoverRecipes()`), so it
    auto-matches whichever recipes exist on the branch. On older branches
    that still ship a hardcoded `pipelines: [...]`, that array is what
    differs per branch.
  - any UI directive that references branch-specific recipe step names
  - assumptions about which artifacts exist in `out/` (rusty produces
    different artifact names than gypsy)
- when I make a UI fix on one branch, I should explicitly flag it as
  "branch-portable" in the response so the human knows to cherry-pick
  or merge it across. I should not switch branches myself — the human
  drives the cross-branch propagation.

Known pitfalls:
- do not re-merge `Outputs`, `Diary Files`, and `Logs` into a single panel —
  each has its own collapse toggle and serves a distinct file class
- the `Logs` panel lists `logs/*.log` and `logs/*.err` files sorted newest-first
  (descending by filename); Outputs and Diary are ascending. Do not normalise
  them to the same direction — newest-first is more useful for logs.
- `log_files` entries use relative paths (`logs/<name>`) so they pass
  `isAllowedFilePath` and open correctly in the file viewer modal on dblclick
- do not silently reintroduce always-on polling
- do not narrow the polling gate back to pipeline-only — that breaks
  termination notification for merges (the May 2026 fix)
- do not split `Latest Err` and `Latest Log` into one pane unless explicitly requested
- do not treat `control_override.yaml` as a substitute for
  `override/<pipeline>.yaml`
- if a new recipe needs freeform text from the UI, prefer `UI_textarea` over inventing a separate ad hoc endpoint
- the recipe selector is dynamic via `discoverRecipes()` — do NOT regress
  it to a hardcoded `pipelines: [...]` array. A recipe appears exactly
  when its `config/<name>.yaml` exists in `BASE/config/` or
  `EXEC_ROOT/config/`. (Earlier writeStory-era doctrine required
  hardcoding the `_ite` covering set; writediary explicitly supersedes
  that — see "Recipe selector — DYNAMIC" above.)
- pane-expand state must stay at module scope, not closure-scope. If you
  refactor `setupPaneExpanders()` and trap `paneCurrentlyExpanded` /
  `paneBackdrop` back inside its function body, every `renderControls()`
  re-render will reset the state and leave the backdrop visible without
  any pane underneath.
- do not put the expand button (`.pane-expand-btn`) inside the
  `<textarea>` parent path in a way that lets label-click forward focus
  to the textarea. The current structure (button is a `<button>` child
  with `e.preventDefault()` + `e.stopPropagation()` on click) suppresses
  this; if you change the markup, re-test that clicking `⤢` does not
  also focus the underlying textarea.
- `.ui-textarea-pane` textareas have an explicit `min-height: 70px;
  max-height: 160px` so all `UI_textarea` fields in a recipe are visible
  at once in the compact state. Do not lift these to the global
  `.controls textarea { min-height: 260px }` rule — that would defeat
  the "all three fields visible" intent of the per-textarea expand.
