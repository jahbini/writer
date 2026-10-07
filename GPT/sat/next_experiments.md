# Next-session plan (handoff 2026-09-29 → 2026-09-30)

## PICK UP HERE IN THE MORNING (2026-09-30)

**Where we ended the day:** Laptop is now internet-connected via Thunderbolt cable to the mini (mini shares its Wi-Fi over TB → cable → laptop). Wi-Fi on the laptop is OFF. Every packet: laptop → cable → mini's en7 → mini's Wi-Fi → porch router → internet. This bypasses the porch RF congestion the laptop's own Wi-Fi radio can't punch through.

### Network setup (today's stack — remember which lives where)

- `~/.ssh/config` — `mac-mini.local` now points at `169.254.140.5` (TB link-local); auto-refreshable.
- `~/bin/mac-mini-tb-refresh.sh` — mDNS-discovers the mini's current TB IP and rewrites the SSH config `HostName` line. Run after any mini reboot.
- `~/claude_zone/use_mini.sh` — laptop-side. Finds the TB interface, requests DHCP, sets default route via mini gateway, configures DNS through `networksetup`. Run as root after any laptop sleep/wake if the TB path drops.
- `~/claude_zone/diagnose.sh` — laptop-side. Writes full network state to `~/claude_zone/diagnostic.txt`. Use when things break.
- `~/claude_zone/mini_sharing_fix.sh` (shipped to mini as `~/mini_sharing_fix.sh`) — auto-discovers all TB interfaces, rewrites `SharingDevices` in the NAT plist.
- `~/claude_zone/mini_bootpd_persistent.sh` (on mini) — installs `/Library/LaunchDaemons/local.persistent-bootpd.plist` that runs `bootpd -v` with `KeepAlive=true` so it survives macOS's on-demand 10-minute idle shutdown.
- `~/claude_zone/mini_sharing_realign.sh` (on mini) — realigns `/etc/bootpd.plist` interface reference to the currently-cabled port; moves the `192.168.2.1` alias onto it.

### The nasty story

macOS Internet Sharing (Tahoe / Darwin 27) is fragile: cable-flaps and sleep/wake leave layered stale configs (3 leftover shared subnets, aliases on wrong interfaces, `bridge100` referenced by bootpd but never created). The scripts above patch symptoms but only a full mini reboot + fresh GUI toggle of Internet Sharing cleanly resets everything. **This is the reset ritual when TB breaks:**

1. Reboot the mini (`ssh theaiguy@mac-mini.local 'sudo shutdown -r now'`).
2. On the mini's own screen: Sharing → Internet Sharing → **OFF**, wait 3s, **ON**. Check the port your cable is physically in.
3. On the laptop: `sudo bash ~/claude_zone/use_mini.sh`.
4. `curl https://ifconfig.me` → expect 200. Then turn laptop Wi-Fi off if you want.

### Today's pipeline changes (unrelated to networking)

- **UI cleanup** — removed 4 broken panels from writer UI (Stories, Training Runs, Story Usage, Run History). All called `/api/sqlite/*.jsonl`, an endpoint that never existed. sqlite tables are authoritative; a human queries them directly.
- **Left-column reorder** — Pipeline Death → Outputs → Steps at top of writer left column. Slot IDs unchanged so panel registry mapping intact.
- **Delete Log Files button** — now `Delete Logs Older Than 48h`, deletes any regular file in `logs/` older than 48h regardless of filename shape (was previously filtered to `<name>_HH_MM.(log|err)` and missed everything else).
- **Pipeline graph bug fix** — files referenced via step params like `library_file: data/jim_story_library.yaml` now render as implicit source-only nodes (dashed border). Endpoint file-viewer gate expanded to include `data/`, `params/`, `override/` so those files open when clicked.
- **`writer/pipeline_svg.coffee` shadow copy** — was stale (Aug 10 file); now overwritten by sync-to-mini AND added to sync script so it can't drift again.
- **Queue rotation fix** in `puppeteer/scripts/queue_run_ite.coffee` — `peer_dead` failures now `work.push` (end of queue) instead of `work.unshift` (head). Was hot-looping the same failing pipe forever. `peer_busy` and `stale_peer_state` still unshift (they really are wait-same-pipe cases).
- **Volume-glob resolver** in `pipeline_runner.coffee` `substituteBraces` — any string like `/Volumes/bigbig*/models/...` gets glob-resolved at read time to whichever mount actually exists. Handles the mini's `bigbig` ↔ `bigbig 1` renaming.
- **Swept 20 pipe override files** to use `/Volumes/bigbig*/...` pattern. Zero literal paths remain.
- **Reap-on-read + persistent PID stamping** for step-state and peer-sessions across `pipeline_runner`, `writer/ui_server`, `puppeteer/ui_server`. Dead runners' `running` step files now flip to `died` on next read, and puppeteer's Peer Session History pane persists that back to sqlite.

### Priority tomorrow

The qwen3-8B reset (jahbini started manually on 2026-09-28) — check whether it survived the mini reboot, or needs a re-fire. The oracle_ite queue on qwen3-8B was error-looping with `fetch failed` before yesterday's queue-rotation fix; that fix + the mini reboot should let it make progress.

---
## PREVIOUS HANDOFF (kept for reference)


# Next-session plan (handoff 2026-09-27 → 2026-09-28)

## PICK UP HERE IN THE MORNING (2026-09-28)

**Where we ended the night:** The puppeteer UI got a major reorg into a
per-pipe, recipe-scoped view. Recipe Flowchart panel is the new
centerpiece — top-of-page, full-width, click-to-popup on every diagram
box. Framework docs (pipeline_runner, test recipe) render there
automatically via the flowchart resolver's framework fallback.

**Do this first — GitHub UX polish (already scoped, deferred by user).**
The pipeline_runner.md flowchart works beautifully in the puppeteer UI
but degrades to a scrolly list of collapsibles on GitHub because
mermaid click callbacks don't fire in GitHub's sandbox. User asked for
teaser sentences inside each `<summary>` so the collapsed list on
GitHub is scannable without expanding.

Plan:
1. Rewrite each `<summary>` line in
   `~/pipeline/flowchart/pipeline_runner.md` from
   `<summary>3. Memo — the artifact store</summary>`
   to
   `<summary><b>3. Memo — the artifact store</b> — one-line teaser
   ending in a period.</summary>`
2. The `<b>` inside `<summary>` renders fine on both surfaces.
3. Also consider adding anchor IDs to each `<details>` so we can link
   `#s3` from the README — "jump to Memo" style navigation.
4. Also consider moving the collapsibles between the two diagrams so
   GitHub readers see them in flow order (invisible impact on UI —
   collapsibles are `display: none` there).

Ask user whether to apply teasers, anchors, or both before writing.

**Everything else that's live from today (do NOT re-do):**
- **Flowchart convention**: per-pipe at `puppeteer/pipes/<pipe>/flowchart/<recipe>.md`; framework fallback at `pipeline/flowchart/<recipe>.md`. Endpoint at `/api/recipe_flowchart?recipe=X` walks CWD → BASE → EXEC.
- **Three new pipes on the mini**: `sat`, `tournament`, `test`. Each has a scaffold + flowchart/ with stub .md files (sat_ladder/sat_scan/sat_sweep; sat_tournament/voice_tournament/voice_fanout). The stubs are honest one-liners pointing at recipe YAMLs — content pending.
- **UI reorg**:
  - Recipe Flowchart panel promoted to top-of-page, full width
  - `body.has-pipe` class toggles: `.pipe-only` visible inside a pipe, `.puppeteer-only` visible at root
  - Peer Session History + dynamic peer panels moved to puppeteer-root view
  - Recipe dropdown shows `<optgroup>` groups: "This pipe (N)" (from pipe's flowchart dir + override.yaml default) then "Other recipes"
  - "(no pipe — puppeteer root)" sentinel option lets you escape a pipe
  - At puppeteer root, flowchart panel hard-defaults to `pipeline_runner` framework doc
- **Popup mechanism**: click any mermaid node → popup with `<details data-flow-node="ID">` content, positioned half-inch upper-right of the mouse. Dismiss via ×, Escape, or click-outside. `securityLevel: 'loose'` on mermaid init; `window.showFlowchartDetail(id)` handler.
- **Fixed textarea wipe bug**: localStorage-backed drafts on `.ui-textarea`, `.ui-dropdown`, `.ui-checkbox` keyed by pipe:recipe:path. Survive daemon restart.
- **Fixed sticky pipe pointer**: `state/current_pipe.txt` read at daemon startup so launchd respawns land in the right cwd.
- **Fixed BASE_ROOT resolution**: walks CWD parents to find `node_modules/@jahbini/pipeline`.
- **Fixed resolveUiAsset + handleSwitchPipe fallback**: three-tier CWD → BASE (puppeteer/) → EXEC (pipeline/) so pipe-switches don't accidentally serve the writer UI.
- **Fixed UI_input → UI_textarea** in spine_* recipes (UI_input was silently dropped by scanUiFields).
- **Fixed recipe-change wipe bug**: change handler blurs the dropdown, clears #ui-fields innerHTML, forces controlsInitialized=false.
- **Fixed markdown paragraph gathering**: now stops at rawTag lines so `</details>` isn't swallowed into the previous paragraph.
- **Repo-relative links** in flowchart .md files: `../meta/`, `../GPT/ui/panels.md`, `../config/test.yaml`, etc. Render as clickable on GitHub.
- **New hard rule**: `~/puppeteer/GPT/rules/no_tmp_outside_claude_zone.md` — session files always under `~/claude_zone/`. Applied prospectively.

**Poetry filter on spine clauses** is live and working. All four kinds (diary/story/spystory/voyage) at 4B-Instruct on the mini produce clean grounded clauses; when a clause slips through with a simile, the retry loop kicks (3× with temp ramp 0.35→0.55), and any surviving poetic clause is dropped so the injector falls back to `DIARY_SECTION_EMOTIONS`.

**Sanity check the daemon** on wake:
```
ssh theaiguy@mac-mini.local 'curl -sS http://localhost:4300/api/status | jq ".pipe.current, .workspace"'
```
Should show whichever pipe was active last, or `null` if sticky pointer got cleared.

---
## PREVIOUS HANDOFF (kept for reference)


# Next-session plan (handoff 2026-09-25 → 2026-09-26)

## PICK UP HERE IN THE MORNING (2026-09-26)

**Where we ended the night:** spine-generation recipes wired into puppeteer, running on the mini via a new `spines` pipe. Path A (post-process `<think>` injection) works. Option 1 (second-pass "because X, <who> Y" clauses grounded in the actual generated content) works for all 4 kinds — diary/story/spystory/voyage. All four have live artifacts at `/Users/theaiguy/writer/data/spines/` from probe runs. Puppeteer sees the pipe and all four recipes in its dropdown.

**Bug that ate the user's typed prompts and MUST be fixed first thing:**
Pipe-switching (via handleSwitchPipe → daemon restart) wipes the UI textareas that were being filled in (brief, constraints, slug). Cause: those textareas serialize to `pipes/spines/control_override.yaml` (or wherever collectUiValues writes them) only on Run, not on typing. A daemon restart via launchd kickstart runs before Run and there's nothing to persist. Two fixes to consider:
- Auto-save typed input on blur / debounce → same behavior as if the user Run'd, but every 500ms.
- Persist UI form state to `state/ui-form-draft.json` on every keystroke; reload on daemon startup.
Neither is done. Do this FIRST tomorrow before user retries a spine run — they'll type prompts a second time and lose them a second time.

**Other pieces that are live and working:**
- `~/pipeline/scripts/spine/spine.coffee` — the step. Uses relative require (`../../mlx/helper_llm`) — needed because pipeline_runner requires steps from `~/pipeline/`, not via `@jahbini/pipeline` node_modules chain.
- `~/pipeline/config/spine_{diary,story,spystory,voyage}.yaml` — four recipes, each with `brief` / `constraints` / `slug` textareas.
- `~/writer/pipes/spines` → symlink to `~/puppeteer/pipes/spines` (the real dir lives under puppeteer/pipes because puppeteer's PIPES_ROOT is there).
- `~/puppeteer/pipes/spines/env/EXEC` — points at `/Users/theaiguy/pipeline` so resolveExecRoot() succeeds when CWD is the pipe dir.
- **Sticky pipe pointer** at `~/puppeteer/state/current_pipe.txt` — daemon startup reads it and chdirs before CWD capture. Fixes launchd re-taking the workspace on every restart. Written by handleSwitchPipe.
- **BASE_ROOT ancestor walk** — patched to walk CWD parents looking for `node_modules/@jahbini/pipeline`. Fixes BASE_ROOT collapsing when sticky chdir moves CWD into a pipe subdir.
- Second-pass clause derivation in `helper_llm.spine()` — `deriveSpineThinkClauses(kind, spineText, brief)` + generalized `injectSpineThinkBlocks(kind, text, overrides)` + `SPINE_SECTION_NAMES[kind]` per-kind alternation tables. Voyage's `## Act I — Departure` markdown headers preserved intact; header prefix required to avoid false matches on "Passage" etc. mid-body.

**Deferred, do NOT lose:** Option 2 for inline `<think>` steering — model emits placeholder tokens the injector rewrites. Recorded in `~/writer/GPT/story/inline_think_steering.md` "Option 2 (deferred, 2026-09-25)". Try if the second-pass cost is ever felt (~10-40s per kind on 4B).

**Fresh spine artifacts to eyeball tomorrow:**
- `~/writer/data/spines/mini_4B_v2_{diary,story,spystory,voyage}.txt` — clean 4B-Instruct outputs with think blocks injected. Also their `.manifest.json` sisters.
- The four clauses per kind read as concrete: e.g. spystory catch — *"because the gauze is from a hospital in Van used to bury a dead man, the protagonist lands quietly"*.

**When user retries the puppeteer Run in the morning:**
1. Open <http://mac-mini.local:4300>. Confirm pipe.current = "spines".
2. Pick recipe from dropdown (spine_diary/story/spystory/voyage).
3. Fill brief / constraints / slug. **Save immediately before doing anything else** (bug above).
4. Kick Run. Wait ~20-80s. Output in `pipes/spines/out/spine_<kind>.txt` and copy at `~/writer/data/spines/<slug>_<kind>.txt`.

---
## PREVIOUS HANDOFF (kept for reference)


## STATE OF THE WORLD AT MORNING 2026-09-25

**Puppeteer runs on the mini now.** All 9 migration steps done + writer-pipe mutex wiring + SSH-bypass rewrite of every panel data-fetch. See `~/puppeteer/RETIRED_2026-09-25.md` for the full layout.

**New URL**: <http://mac-mini.local:4300> (was `http://127.0.0.1:4300` on laptop). Reachable from any LAN browser.

**Panel refresh times post-migration:**
| endpoint | before | after |
|---|---|---|
| `/api/peer_pipes?fresh=1` | 2-15s (30s on Wi-Fi flap) | ~250 ms |
| `/api/sat_matrix?fresh=1` | ~30s (SSH storm) | ~290 ms |

**SAT Grades panel** now shows the fresh sat_ladder verdicts from yesterday's overnight run:
- All 4 contestants pass Tier 1 (`can_read`).
- **0-6b (base) + baseline diary config → PASS** (also `both` config passes).
- **4b (adapter) + baseline diary config → PASS**.
- All other diary configs fail on all 4 pipes.
- No pipe passes Tier 3 story — real ceiling to work on.

**Dev workflow unchanged**: edit `~/puppeteer/`, `~/pipeline/`, `~/writer/` on laptop; `~/bin/sync-to-mini.sh` pushes; `launchctl kickstart -k gui/$(id -u)/com.jahbini.puppeteer-ui` on mini if the ui_server needs a restart. Rsync excludes state/logs/tournaments/runtime.sqlite so mini state stays authoritative.

**GPU mutex active**: `helper_llm.runCapability`, `session_api.createSession`, and `pipeline_runner.callMLX` all claim `/Users/theaiguy/puppeteer/state/gpu_claim.lock` before touching Metal. `helper_ab_probe.coffee`'s subprocess-per-probe hack can retire whenever we come back to that file.

**Helper LLM upgraded**: `HELPER_LLM_MODEL_DIR=/Volumes/bigbig 1/models/Qwen/Qwen3-4B-Instruct-2507-mlx4` (was 1.7B). Expected: better KAG reasoning, better `<think>` prefill following, sharper action decisions. Not re-run against the 7-canonicals yet — worth doing to measure the actual lift.

## Helper A/B against 4B-Instruct — RESULT: 11/11 (2026-09-25 morning)

The 4B-Instruct helper upgrade cleared BOTH remaining wrong answers from yesterday's 1.7B v3 run. Full A/B tally (canonicals + live pipes):

| # | scenario | v3 (1.7B) | **v4 (4B-Instruct)** | expected |
|---|---|---|---|---|
| 1-4 | live pipes | 4/4 | **4/4 ✓** | wait |
| 5 | empty-sqlite | reset ✓ | reset ✓ | reset |
| 6 | 3× Metal crash | reset ✗ | **hospitalize ✓** | hospitalize |
| 7 | peer busy | wait ✓ | wait ✓ | wait |
| 8 | SAFETY 2.4× | reject ✓ | reject ✓ | reject |
| 9 | SAFETY 1.5× | raise_ceiling ✓ | raise_ceiling ✓ | raise_ceiling |
| 10 | rep_loop | graduate ✓ | graduate ✓ | graduate |
| 11 | healthy continue | wait ✗ | **launch ✓** | launch |

**Canonicals 7/7. Live 4/4. Overall 11/11. Confidence emitted on 11/11 (up from 5/11 on 1.7B). `target_recipe` field leaked 0 times (down from 3/11).**

Progression across the whole arc:
- baseline (1.7B, KAG-top-5, no `<think>`): 3/7 canonicals
- v1 (approach 1 — `<think>` in few-shot examples): 3/7
- v2 (approach 2 — turn-prefill from retrieved rows): 4/7
- v3 (v2 + `ACTION_GUARDS`): 5/7
- **v4 (v3 + 4B-Instruct helper on mini): 7/7 canonicals + 4/4 live**

The two flips that closed the gap (#6 Metal crash → hospitalize, #11 healthy continue → launch) came from the SAME prefill; the model change was what unlocked them. 4B-Instruct honors `ACTION_GUARDS` more literally and holds longer chains of directive reasoning without collapsing to the "wait" default that plagued 1.7B.

Log at `mini:/tmp/kag_ab_4binstruct.log`. Rows also visible in the SAT Grades panel now that the panel's click-to-see-text works properly (bugfix landed 2026-09-25 morning — see "UI fixes" section below).

## Still-open work

1. **Helper generates all story spines** (recorded 2026-09-24, IMPLEMENTED 2026-09-25 morning — recipe live at `~/puppeteer/config/helper_spines.yaml`). Not yet smoke-tested against a real brief; next fire whenever the mini is idle. Prior `celarien_prep.novel_arc_generator` step still runs its own MLX; a follow-up is to swap it over to `helper.spine('voyage', ...)` so celarien uses the new capability.
2. **Retire the subprocess-per-probe hack** in `helper_ab_probe.coffee` — now that the GPU mutex is in place AND the 4B-Instruct A/B ran three capability calls per probe cleanly in a single process, the subprocess isolation isn't needed. Cleanup for whoever visits that file next.
3. **`callMLX` async refactor** — the sync busy-wait for the mutex in `pipeline_runner.callMLX` (Python subprocess path) is ugly. If any recipe still uses that path (mostly quantize / fuse), migrate to `L.callLLM` (async in-process) or make `callMLX` properly async.
4. **SAT Grades Tier 3 (story) ceiling** — no pipe passes. Look at what the story invariants are checking; consider softening them, OR train a stronger story-specific adapter, OR try feeding tuned-params + KAG context to see if either lifts scores.
5. **Smoke-test helper_spines** on all four kinds (`diary`, `story`, `spystory`, `voyage`) with representative briefs. Verify each kind's structural prefill produces the expected shape; grade against canonical spines in `~/writer/data/spines/` for diary tone-fidelity.

## UI fixes landed 2026-09-25 morning

- **SAT Grades click-to-see-text was broken**. Root cause: `wireSatCellClicks()` was called only from `startRefreshLoop()`, which only fires when a pipeline is running or a merge is active. Idle puppeteer meant score chips had no click handler; browsers treated clicks as text-selection and appended `#:~:text=…` fragments to the URL. Fixed by wiring the delegation at document-parse time (on `DOMContentLoaded` if still loading, immediately otherwise). See `~/puppeteer/ui/index.html` `wireSatCellClicks` section for the guard.
- **Chip text was selectable, causing Chrome text-fragment URL side-effect**. Added `user-select:none` on the `.sat-cell` `<td>` + `pointer-events:none; user-select:none;` on the inner `<span>` chip so clicks always reach the delegated handler and never trigger text-fragment behavior.
- **Viewer text was same color as background** (invisible). Set `color:#000` on `#sat-text-body`.
- **Panel refresh times**: `/api/peer_pipes?fresh=1` 2-15s → ~250ms (60× speedup). `/api/sat_matrix?fresh=1` ~30s SSH storm → ~290ms (100× speedup). Achieved by adding `PEER_IS_LOCAL` detection + `runPeerBash`/`runPeerCmd` helpers that bypass SSH when running on the mini itself. sat_matrix's per-pipe loop uses direct `fs.readFileSync` when local. Cells stay clickable in either mode.

## Previous handoff (2026-09-24 evening)

# Next-session plan (handoff 2026-09-24 evening)

## TOMORROW MORNING — FIRST WORK (2026-09-25)

### 1. Migrate the puppeteer to the mini

**Decision recorded 2026-09-24**: comm issues (Wi-Fi choke, hotspot switches, SSH timeouts wedging the UI) will not be the last of these problems. Move the puppeteer to the mini. Dev + git repos STAY ON THE LAPTOP. Mini gets no development code. Everything reachable via web page (LAN + browser).

**Migration order** (this is the plan, do it first thing in the morning):

1. **Build the `gpu_claim.lock` mutex** on laptop first (test it). Both `queue_run_ite` and `helper.schedule` acquire it before creating an MLX session; release on step end. Once serialized, "Received parameters not in model" concurrent-createSession crashes disappear and the subprocess-per-probe hack in `helper_ab_probe.coffee` can retire. Simple flock or a state file with pid+timestamp.
2. **Extend `~/bin/sync-to-mini.sh`** to include `~/puppeteer` (currently syncs `~/pipeline` only). Adds ~15 lines. Includes `config/`, `scripts/`, `ui/`, `panels/`, `meta/` — NOT `state/`, NOT `logs/`, NOT `runtime.sqlite`, NOT `tournaments/`. State is authoritative on mini going forward.
3. **On the mini**: `mkdir ~/puppeteer/{state,logs,tournaments,params}`; install node deps; symlink `~/puppeteer/node_modules/@jahbini/pipeline` → `~/pipeline` (same trick as laptop).
4. **Freeze current state**: one-time copy from laptop to mini of `runtime.sqlite` (helper_training_examples with the reason-field rewrites + KAG annotations), `state/pipe_states.json`, `state/sat_history.jsonl`, `state/broadcast_queue.jsonl`, `tournaments/2026-09-23_0557/` (judged), `params/celarien_setup.yaml`. This is the "here's where the puppeteer left off" snapshot.
5. **Bind mini's puppeteer ui_server to `0.0.0.0:4300`** so it's reachable from any LAN browser. Open port on mini's firewall. IPv4/IPv6 localhost gotcha goes away because the LAN address IS the address.
6. **`launchctl` daemon on mini** to keep the ui_server + pipeline_runner running at login (no manual restart on reboot).
7. **Retire the laptop's puppeteer** — leave the code on the laptop for dev; just don't run the ui_server there. `~/claude_zone/test/` scripts stay on laptop (they're dev-time; they SSH into mini via the puppeteer API just like a browser would).
8. **Upgrade the helper model** from Qwen3-1.7B to Qwen3-4B-Instruct-2507. Same MLX device the writer pipes use; the serialized-GPU rule makes it safe. Better scheduling decisions, better grading, richer KAG reasoning. Set `HELPER_LLM_MODEL_DIR=/Users/theaiguy/models/Qwen/Qwen3-4B-Instruct-2507-mlx4` in the puppeteer launchd job.

**GPT/ notes**: keep on the laptop (dev-time truth). Sshfs-mount `~/puppeteer/GPT` and `~/writer/GPT` from mini onto the laptop if the mini's copies of those need editing; else rsync one-way laptop→mini. `~/claude_zone/memory/` stays on laptop (auto-memory system uses laptop paths and it's about the human, not the puppeteer).

**What gets EASIER post-migration**:
- Peer crashes visible in <100 ms via `pgrep`, not 5 s via SSH poll.
- `sat_matrix` reads become milliseconds (no more 11 SSH round-trips per refresh).
- `killLocalRunner` + `waitPeerFinishedAt` become local process ops (the two-phase spawn detector was fighting SSH lag; on-mini it's not needed).
- `mem overload` detection via `vm_stat`, not SSH scrape.
- `sync_overrides` becomes a local file copy, not an SSH tunnel.

**One thing to plan carefully during migration**: `queue_run_ite` currently distinguishes local/peer via SSH+HTTP. Post-move, the "peer" writer/ui_server is on the same machine at `http://127.0.0.1:4311`. Good news — zero code change needed. Same HTTP calls just go over loopback. curl doesn't care whether it's talking to LAN or lo0.

### 2. Helper generates ALL story spines going forward

**Design directive recorded 2026-09-24**: All story spines are generated by the helper LLM (post-migration: Qwen3-4B-Instruct on mini). **Only the actual story text generation is done by peer pipes.**

**Impact on existing recipes:**

- `celarien_prep` — the `novel_arc_generator` step should become a HELPER capability call (`helper.spine(author_description)`) instead of running on the puppeteer's local MLX. Currently it uses the pipeline's own MLX; wire it to `helper_llm.coffee` as a new capability.
- `writer/data/spines/*.txt` — the canonical human-authored spines (susannas_song, bouncy_boom, serf_insults_queen) stay as reference/fixture material for the voice tournament. They're the "gold standard" the helper's generated spines should be measured against.
- New spine format: helper-generated spines go to `params/spine_generated_<slug>.txt` on the puppeteer (post-migration: mini). `voice_test` / storacle / tournament dispatch reads by path or by name; helper-generated spines get names like `helper_2026-09-25_1730`.
- The helper needs a new `spine` capability in `~/pipeline/mlx/helper_llm.coffee` alongside `schedule`, `classify_failure`, `grade_role`, `grade_invariants`. Prefill it with directive reasoning (learned from 2026-09-23 KAG audit): "I write a diary-prompt spine following the 5-part structure (scene, arrival, disturbance, reflection, realization) matching the length + tone of the reference spines in the corpus."

**Why this change**: the peer pipes are text-generation specialists tuned for STORY output. Spine generation is a different task (structure + directive + brevity, not voice + narrative). The helper is already the "structured-reasoning model" of the fleet; make it responsible for the structural-reasoning artifacts too. Peer pipes get their input (a spine) fully cooked from the helper and focus on their strength (voice + story).

**Order to implement**:
1. Add `spine` capability to `helper_llm.coffee` — new prefill block, `helper.spine(brief)` function.
2. Test on the laptop with Qwen3-1.7B first (baseline). Then on mini post-migration with 4B-Instruct.
3. Retire the puppeteer-local MLX in `novel_arc_generator` — the step now calls `helper.spine(author_description)`.
4. Any future recipe that needs a spine: `helper.spine(brief)`, then peer pipe consumes it.
5. Grade helper's spines against the canonical human-authored ones (susannas_song etc.) — the tournament vote structure can be reused; label each match "helper vs canonical".

---



## Today's tournament result (2026-09-23_0557) — JUDGED

All three spines graded, 26 rows in `~/puppeteer/state/sat_history.jsonl`, all matchups now count (both sides sat_complete). RMS(R + W + C) ranking (see UI changes below).

| pipe | W-L | matches | role |
|---|---|---|---|
| **hf__qwen__qwen3-4b (base)** | **4-2** | 6 | **workhorse for advanced recipes (malleable)** |
| hf__qwen__qwen3-0-6b | 3-3 | 6 | **punctuation model — brevity champion** |
| hf__qwen__qwen3-1-7b | 3-4 | 7 | middle-child, reserve for candidate diversity |
| hf__qwen__qwen3-4b-instruct-2507 | 3-4 | 7 | judge/grade/broadcast-eval, NOT workhorse |

Note: **4b-instruct-2507 dropped from previous 4W-1L to 3W-4L** now that matches are gated on both parties having SAT-2. Its earlier "champion" score was against un-tuned opponents. First fair contest here.

**Durable role assignments** (from human eval + tally) are recorded in `~/writer/GPT/story/model_roles.md` — "2026-09-24 tournament confirmation" section. Any advanced-recipe development from here on should default to 4b (base) unless there's a specific reason to pick another.

## Tournament UI changes landed today (2026-09-24)

- **Cohesion** added as a third rated axis alongside Richness and Wit (0-10). "Does it tell the story, or go down rabbit holes."
- **Sliders → compact ▼/▲ counters** (each label spelled out, centered horizontally). Sliders took too much horizontal space; long stories made the letters push counters off screen.
- **Default value 5, no "moved" gate** — Judge button captures whatever the counters show even if untouched.
- **Grandfather rule**: prior scores without cohesion are treated as `cohesion = 5`.
- **Winner selection: RMS(R, W, C)** instead of sum. Sum-of-squares is compared (monotonic with RMS, saves the sqrt); RMS shown to 2 decimals in display + as `human_rms` in history. RMS rewards excelling on one axis over blandly-good on all three.
- **Carry-forward within a spine**: when a pipe wins a round, its (R, W, C) values become the STARTING values for its next round in that spine. Same text should get the same starting evaluation. Scoped per-spine; different spines start fresh at 5/5/5.
- **No failure alerts**: judge button reloads unconditionally. If you pressed it, it was judged.
- **URL gotcha**: puppeteer ui_server binds IPv4-only. Use `http://127.0.0.1:4300/...` not `localhost` (browsers try `::1` first and can 404).

## UI/render files touched today

- `~/puppeteer/scripts/voice_tournament_render.coffee` — counter widget, cohesion, RMS display, carry-forward `findPriorScores()`, no-popup judge JS, centered layout, spelled-out labels
- `~/puppeteer/ui_server.coffee` `handleTournamentVote` — cohesion in scores, RMS ranking (winner by argmax(sum-of-squares)), carry-forward at advancement time, `human_rms` field in history
- `/tmp/rerender_tournament.coffee` — re-renders an existing tournament in place with the current render code (called after any render.coffee change)

## What's still open

- **Re-fire the SAT sweep on 4b-instruct-2507 alone** with `MAX_RUN_SECONDS = 900`. Today's sweep had 7 timeouts on that pipe at higher temp/rep combos — insufficient data at that corner of the grid. Best-known for now: temp=0.9 rep=1.55 (from 33 real datapoints).
- **Helper A/B guard tuning**: canonicals 5/7 with v3 ACTION_GUARDS. Still wrong: #6 (Metal crash → wants signature-specific hospitalize guard) and #11 (healthy continue → launch guard too strict). Small edits.
- **KAG rows draft**: `~/puppeteer/GPT/helper/kag_rows_2026-09-23_draft.md` has 5 candidates (Wi-Fi choke, storacle wedge, force-launch kill-first, un-SAT match, cool-down). Not yet inserted. Rows 3 & 5 borderline (code-behavior vs helper decisions).
- **Sweep script cleanup**: `~/claude_zone/test/sat_sweep.coffee` doesn't kill lingering `pipeline_runner` on exit — leaves a zombie that later launches trip over. Extract the `killLocalRunner()` call from `peer_utils.coffee` into a final `main()` step.
- **Approach 2 remaining lever**: model's own `<think>` still ruminates AFTER our directive prefill. Fixable by increasing prefill weight OR by adapter-training on the new prefill shape.

## Morning first-steps (2026-09-25)

1. Read `~/writer/GPT/story/model_roles.md` "2026-09-24 tournament confirmation" section to reload the role assignments in your head.
2. If you want to change the workhorse assignment, review `sat_history.jsonl` and `tournaments/2026-09-23_0557/*.html`. Current data says 4b (base).
3. Any advanced-recipe work (story, diary, oracle, celarien): default to 4b (base). Not 4b-instruct.
4. Broadcast (0.6b's punctuation role): already wired at `~/writer/pipes/Qwen3-0.6B` with the SAT-tuned params.
5. Consider firing sat_sweep-lite on 4b-instruct with the 900s cap to close the gap in the parameter grid.

## Previously-recorded state (2026-09-23)

# Next-session plan (handoff 2026-09-23 evening)

## HARD PREREQUISITE (read before touching anything)

**Read `puppeteer/GPT/rules/route_runs_through_puppeteer.md` FIRST.**
Every run must go through puppeteer's `/api/launch_recipe` (peer pipes) or a direct `pipeline_runner.coffee` from `~/puppeteer` (puppeteer-native recipes like `voice_tournament`). Never `nohup coffee pipeline_runner.coffee` inside a peer pipe from the laptop.

## Where we stopped

A voice tournament using the SAT-2 tuned params **is complete and awaiting human judgment**:

- **Tournament id**: `2026-09-23_0557`
- **Location**: `~/puppeteer/tournaments/2026-09-23_0557/`
- **URL for judging**: **http://127.0.0.1:4300/tournament/2026-09-23_0557/index.html** (use 127.0.0.1 NOT `localhost` — puppeteer ui_server binds IPv4-only; Safari resolves localhost to IPv6 and fails)
- **What to do**: open the three spine pages (susannas_song / bouncy_boom / serf_insults_queen), rate each pipe on Richness + Wit sliders (0-10), click Judge. Votes go to `~/puppeteer/state/sat_history.jsonl` and unlock the tournament tally in the fleet panel.
- **Fresh matchup**: this is the FIRST tournament where all 4 contestants have `sat_complete=true`. Every match will count toward each pipe's `NW-ML` record in the peer_pipes panel.

## Today's SAT-2 sweep results (durable, on peer)

Per-pipe best params from the overnight → this-morning parameter grid (5 temps × 4 rep_penalties × 2 stories = 40 fires per pipe). Written to `override/storacle.yaml` on the mini AND translated into `override/voice_test.yaml` for the tournament.

| pipe | temp | rep_penalty | outLen | worst-window repeats |
|---|---|---|---|---|
| hf__qwen__qwen3-0-6b | **1.2** | **1.55** | 12031 | 2 |
| hf__qwen__qwen3-1-7b | **1.2** | **1.55** | 12637 | 1 |
| hf__qwen__qwen3-4b | **0.9** | **1.15** | 12973 | 2 |
| hf__qwen__qwen3-4b-instruct-2507 | **0.9** | **1.55** | 12042 | 2 |

Fleet-wide pattern: **small models need HIGH temp + HIGH rep_penalty** (1.2 / 1.55) to escape loop pathology at 3000-token retells. **4b runs cleanest at moderate temp + gentle rep_penalty** (0.9 / 1.15). 4b-instruct-2507 needs high rep_penalty despite being large — its instruction-tuned tendency is to repeat structural phrases. maxTokens = 3000 works for all.

Raw per-attempt data: `~/claude_zone/test/sat_sweep_results.jsonl` (160 rows). Sweep script: `~/claude_zone/test/sat_sweep.coffee`.

Two crashes + seven timeouts on 4b-instruct-2507 — that pipe genuinely generates slow at some combos; if we re-sweep it, bump the wait ceiling from 600s.

## Helper KAG improvements landed today

Three iterations against the 7-canonicals A/B. Baseline was KAG-top-5, no `<think>` steering, **3/7 correct**.

| version | approach | canonicals | live pipes | notes |
|---|---|---|---|---|
| v1 | approach (1) — `<think>` inside few-shot examples | **3/7** | 4/4 | flat with baseline; model defaults to `wait` on everything unclear |
| v2 | approach (2) — turn-prefill at assistant turn with retrieved rows' reasons | **4/7** | 3/4 | +1 (empty-sqlite fixed) but #9 regressed to destructive-wrong (reject on ratio 1.5×) |
| v3 | v2 + **ACTION_GUARDS** — explicit preconditions per action (ratio bands, N-consecutive-crash counts, etc.) | **5/7** | 4/4 | +2 total; #9 (raise_ceiling ✓), #10 (graduate ✓) fixed |

**Live in the code** (`~/pipeline/mlx/helper_llm.coffee` `schedule()`):

1. `runCapability` accepts `opts.thinkPrefill` override so a caller can inject a scenario-specific prefill (line ~283).
2. `schedule()` when called with retrieved KAG rows builds a dynamic prefill combining (a) the top-5 cases as short cues and (b) explicit precondition guards per action from `ACTION_GUARDS`. The model reads: `these cases apply … but each action has a guard that MUST hold … match strongest signal against guards, first-holding guard wins`. Falls through to the static `thinkPrefillFor.schedule` block if no examples.

**Still wrong after v3:**
- **#6 (3× Metal crash → reset, should be hospitalize)**: hospitalize's guard says "≥3 crashes with SAME non-empty-sqlite signature" but model matches the crash pattern to reset regardless of signature. Fix: signature-name specificity in the guard, e.g. explicitly list `Metal Command Buffer / GPU Timeout / lm_head.scales / model_loader_attr` as valid hospitalize signatures.
- **#11 (healthy continue → wait, should be launch)**: launch's guard has multiple ANDed conditions ("reset done AND elementary not since AND peer idle"). Model probably reads "AND" as "need all three PERFECTLY certain" and defaults to wait. Fix: soften to "if reset just completed AND peer idle → launch"; make elementary-not-since implicit.

**Corpus grooming done today** (helper_training_examples table):
- Rows 30, 52, 53: trimmed contemplative tails ("no action needed", "at their discretion", "not currently in the action vocabulary"). Now directive.
- Rows 69, 70, 71 (all `escalate`): rewritten from first-person rumination ("I have no rule that applies", "Signals point two ways", "I can't tell which") to directive ("error_signature X matches NONE of the seven seed patterns. Escalate; a new rule for this class belongs in the corpus"). Backup at `/tmp/kag_seeds_backup_20260923_101548.tsv`.

## Runtime utilities extracted

`~/puppeteer/scripts/peer_utils.coffee` — first-class home for the three fixes:
- `killLocalRunner()` — call BEFORE any `/api/launch_recipe` fire. `force:true` bypasses the API 409 but NOT pipeline_runner's ensureSingleInstance file lock. Without this, zombie runners silently no-op every new launch.
- `waitPeerFinishedAt({baseline, pipe})` — poll peer's `/api/status.run.finished_at`; pgrep-based detection is broken (queue_run_ite's own SSH probes show up as false peer runners).
- `sshPeer(cmd, opts)` — multiplexed control connection + try/catch + one retry. Never throws.

Imports as `require '/Users/jahbini/puppeteer/scripts/peer_utils'`. Any new driver should USE these, not re-invent them.

## Network fixes landed today

- `~/.ssh/config` now has a `Host mac-mini.local` block pinning to the Wi-Fi IPv4 `192.168.1.89` with `HostKeyAlias mac-mini.local` (so `known_hosts` still validates) and `AddressFamily inet` (skips IPv6 link-local scope traps). ServerAliveInterval 30 / ServerAliveCountMax 6 = ~3 minute grace for Wi-Fi choke.
- **User rule**: Wi-Fi AP at this location reboots ~2× daily (5PM and 4AM local), ~2 min outages. If Wi-Fi is down, flip HostName to `169.254.245.203` (Thunderbolt Bridge — direct point-to-point when the cable is plugged in). Sweep script's SSH mux socket survives 3 min of dead-air, so most reboots don't kill in-flight work.

## UI changes landed today

- **Recipe divergence banner**: freshness panel now shows "Selected" (dropdown / control_override) separate from "RUNNING" (from state/ui-run.json). Red banner when they differ, "Show the running recipe" button peeks without disturbing state.
- **Fleet table row compression**: DL and Q columns removed. State radio dropped SAT (computed transition) and pause (folded into hospital). Text labels, no emoji.
- **Tournament wins tally**: gated on `sat_complete` — only matches where BOTH pipes have storacle done count toward the record. Sat-history file: `~/puppeteer/state/sat_history.jsonl`.
- **SAT Launcher panel**: full-width, above fleet. Pipe multi-select (auto-checks SAT-needed), story ID / prompt / LLM knobs (maxTokens 3000, temp 0.7, etc.). Fires `/api/launch_recipe` with dot-path ui_values.
- **"▶ RUNNING on mini" hero** at the top of Peer Session History. Single stable line — shows current pipe + recipe if a peer runner is alive, or "◯ mini idle · last: X (Nm ago)" otherwise. Panel moved above Peer Pipes, below Pipeline Graph. Table shows top 10 by default, "show all N" toggle expands.

## Code fixes at source (permanent — no helper role needed)

- `pipeline_runner.stripUiDirectives` UI_number handler — `pipeline/pipeline_runner.coffee:381`. `[UI_number, 400]` arrays were reaching the model layer as literal arrays (bug since 2026-09-15). Every storacle / chat_llm / voice-family run before today has this bug baked in; treat prior results with suspicion.
- `BASE_ROOT` symlink resolution — `puppeteer/ui_server.coffee:99`. When `node_modules/@jahbini/pipeline` is a symlink to `~/pipeline`, `require.resolve` returns the real path and the `/node_modules/` marker check missed it. Result: none of puppeteer's project-tier panels were loading.

## Morning first-steps

1. Judge the tournament: http://127.0.0.1:4300/tournament/2026-09-23_0557/index.html — three spine pages, 4 pipes each, sliders + judge buttons.
2. After judging, check the fleet panel: each pipe should show a fresh `NW-ML` record in its activity cell.
3. Decide: does the tuned tournament outcome differ from the previous ones (`~/puppeteer/tournaments/2026-09-21_*`)? Same winner (4b-instruct-2507) or has the SAT-tuning shifted the ranking?
4. If A/B on the 7 canonicals matters this morning: guard-augmented prefill is loaded, score is 5/7 canonicals + 4/4 live. Fix #6 by adding Metal-timeout signature specificity to hospitalize's guard; fix #11 by softening launch's guard.
5. Consider re-firing the SAT sweep on 4b-instruct-2507 alone with 900s max_wait (7 timeouts today; not enough data at higher temp/rep combos).

## Files touched today (for tomorrow's memory)

- `~/pipeline/pipeline_runner.coffee` — UI_number handler
- `~/pipeline/mlx/helper_llm.coffee` — approach 2 + ACTION_GUARDS
- `~/puppeteer/ui_server.coffee` — BASE_ROOT, tournament tally sat_complete gating
- `~/puppeteer/ui/index.html` — SAT Launcher, peer-now hero, Peer Session History move, table compression, tournament record
- `~/puppeteer/scripts/peer_utils.coffee` — NEW extracted utilities
- `~/.ssh/config` — mac-mini pin
- `~/claude_zone/test/sat_sweep.coffee` — the overnight driver (self-cleaning: doesn't kill lingering runners on exit; if you re-run it, kill any leftover pipeline_runner first, or extract that final-kill into the script)
- `~/puppeteer/GPT/helper/kag_rows_2026-09-23_draft.md` — 5 new advisory rows drafted (Wi-Fi choke, storacle maxTokens wedge, force-launch requires kill-first, un-SAT tournament match, cool-down). Not yet inserted into helper_training_examples — decision pending on rows 3 & 5 (borderline: code-behavior facts vs helper decisions).
- helper_training_examples table — rows 30, 52, 53, 69, 70, 71 rewritten. Backup at `/tmp/kag_seeds_backup_20260923_101548.tsv`.

## Standing conclusions (durable)

- **Every tournament contestant MUST have SAT-2** (storacle at tuned params). Un-SAT'd pipes' matches don't count in the tally — the ranking only reflects fair fights.
- **UI_number bug**: every SAT / storacle / chat_llm run before 2026-09-23 morning has un-stripped `['UI_number', 400]` arrays reaching the model layer. Any grade or ranking from earlier data is suspect.
- **KAG few-shot alone doesn't shift model reasoning shape** — the model reads examples as context but generates its own ruminative think. Turn-prefill at inference (approach 2) is the stronger lever, but needs explicit PRECONDITION guards per action or the model matches to the first plausible case without honoring numeric guards.
- **Peer's writer/ui_server needs 10s cool-down between fires** — rapid-fire re-launches race the finalize-write cycle and get silently rejected as "runner not spawned".
- **Peer completion detector**: use `run.finished_at` timestamp advancement from peer's `/api/status`, NOT pgrep. pgrep catches queue_run_ite's own SSH probes as false peer runners.
