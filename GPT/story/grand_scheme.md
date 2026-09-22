# Grand scheme — the whole machine

Recorded 2026-09-20 from Geemo's directive. This is what everything
we've built the last three weeks is FOR. Individual pieces (SAT,
celarien, sync-overrides, best-per-pipe overrides) are components
of the pipeline described here; keep this as the North Star when
scoping any single-piece decision.

## The flow

```
  ┌─────────────────────────────────────────────────────────────┐
  │  1. MODE SELECTOR (human)                                   │
  │     diary | story | spy_story | voyage                      │
  └─────────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────────┐
  │  2. SPINE GENERATOR (mode-specific recipe)                  │
  │     Takes optional human input (author_description,         │
  │     tuning). Assembles a COMPLETE story arc that must be    │
  │     robust to whatever random iching / draw outputs it      │
  │     receives. Same seed + same input → same spine.          │
  └─────────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────────┐
  │  3. DIRECTIVE ASSEMBLER (mode-specific)                     │
  │     Renders the spine into a callLLM-ready directive        │
  │     (render-safe strings only, internal vocab stripped)     │
  └─────────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────────┐
  │  4. FAN-OUT TO CAPABLE MODELS                               │
  │     Reads the SAT matrix; sends the directive to every      │
  │     pipe whose can_X bucket matches this mode. Every pipe   │
  │     runs at its BEST per-pipe config (KAG/chunks/adapter    │
  │     choice from best_per_pipe_overrides.md).                │
  └─────────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────────┐
  │  5. EVALUATION + HUMAN EDIT                                 │
  │     Auto-grade per generation (mode-specific SAT checks +   │
  │     cross-generation consistency scoring).                  │
  │     Human reviews finalists side-by-side, picks or edits.   │
  │     Selection persists as "the canonical episode/chapter."  │
  └─────────────────────────────────────────────────────────────┘
                              ↓
  ┌─────────────────────────────────────────────────────────────┐
  │  6. (Future) TEXT-TO-VIDEO                                  │
  │     The most-consistent generations feed a T2V pipeline.    │
  └─────────────────────────────────────────────────────────────┘
```

## What each existing piece is doing in this scheme

### Step 1 — Mode selector
**Not built yet.** No UI for picking mode. Once modes are wired
into recipes symmetrically, a puppeteer or writer UI dropdown
selects which mode fires.

### Step 2 — Spine generator
- **Voyage mode:** `novel_arc_generator.coffee` (celarien Phase 2)
  — deterministic, seeded, iching-driven. Complete arc regardless
  of dice.
- **Diary mode:** currently uses hand-authored `sat_fixed_spine.yaml`
  (per pipe under `pipes/*/data/`). No programmatic generator yet
  — the fixture is authored once and reused. Needs a generator if
  we want fresh-per-invocation spines.
- **Story mode:** `story_spine.coffee` + `story_beats.coffee` +
  `story_outline.coffee` exist under `writer/scripts/`. That's the
  existing spine machinery for the JIM story library.
- **Spy_story mode:** `writer/config/spystory.yaml` recipe exists.
  Same shape as story but different fixtures.

### Step 3 — Directive assembler
- **Voyage:** `celarien_directive_ite.coffee` (celarien Phase 3).
  Renders spread into a callLLM-ready directive; hygiene enforced.
- **Diary/story:** the mode-specific `_ite` steps combine spine +
  callLLM directly (e.g., `sat_diary_ite.coffee`). Directive
  assembly is inline rather than a separate step. Fine for now;
  could be lifted out for uniformity later.

### Step 4 — Fan-out to capable models
Infrastructure exists, orchestration doesn't:
- **`POST /api/launch_recipe`** — enqueues one recipe on one pipe
  (or a serial batch of pipes on the same recipe). Fires through
  queue_run_ite. Built 2026-09-20.
- **SAT matrix** — knows which pipes have `can_read` /
  `can_diary` / `can_story` buckets. Presently exposes best-cell
  recommendations per pipe. What's MISSING: a "fan out this
  spine to every pipe in this bucket" call.
- **best_per_pipe_overrides.md** + `override/sat_ladder.yaml` per
  pipe — knows each pipe's best KAG/chunks/adapter combo. Used at
  SAT run time; needs to be threaded through the fan-out step so
  each pipe runs at its own peak.

### Step 5 — Evaluation + human edit
- **SAT graders** (`elementary_sat_ite`, `sat_story_ite`) —
  per-generation grading. Solid for per-pipe checks.
- **SAT Grades panel** — visualizes per-pipe/config verdicts +
  raw text. Panel already exists for showing what each model
  produced.
- **Cross-generation consistency scoring** — NOT built. Would
  compare multiple pipes' outputs on the same spine for
  agreement (character consistency, invariant preservation, etc.).
- **Human edit surface** — panel currently shows text
  read-only. No side-by-side compare-and-edit yet.
- **Selection artifact** — after human picks a canonical
  version, where it lands is undecided. Suggestion: a
  `canonical_episode_<n>_text` artifact per pipe/spine, promoted
  to a `canonical_series/` directory once selected.

### Step 6 — Text-to-video
Long way off. No pieces yet. Placeholder in the vision.

## Design invariants (from Geemo's directive)

1. **The spine generator must ALWAYS produce a complete story arc,
   no matter what the random iching draws.** No dead-end spines,
   no "please rerun" outputs. If the deterministic draws produce
   an unusable combination, the spine generator resolves it —
   never the human downstream.
2. **Modes are peers.** Diary / story / spy_story / voyage should
   share as much structure as possible: spine → directive →
   fan-out → grade → select. Mode-specific pieces (like voyage's
   hexagram machinery) are internal; the outer contract stays
   uniform.
3. **Some human input is welcome; complete automation is not the
   goal.** `author_description` on the voyage panel is the
   canonical example — a seed, an intent, a nudge — not a
   full-authored piece of prose.
4. **Best-per-pipe params.** Every pipe runs at its best-known
   config in the fan-out. The SAT is what discovers those; the
   overrides are what encodes them.

## Concrete gaps to close (working list, in likely build order)

1. **Voyage mode Phase 4** — audit + tests for the celarien pipeline
   (in flight; not started).
2. **Mode-selector UI panel** — one panel with a mode dropdown +
   the shared inputs (author_description, chapter count, etc.).
   Fires the mode's spine generator on save.
3. **Fan-out orchestrator** — a puppeteer step or endpoint that
   reads the SAT matrix, picks pipes in bucket X, and fires the
   directive across all of them with per-pipe best overrides.
4. **Cross-generation consistency scorer** — SAT-adjacent step
   that compares multiple pipes' outputs on the same spine for
   agreement. Feeds the "which generation is most consistent"
   ranking.
5. **Side-by-side compare/edit panel** — human review UI. Shows N
   generations side-by-side, per-check verdicts, and a text
   editor for the picked one.
6. **Canonical artifact promotion** — after human selects, promote
   to `canonical_series/<mode>/<episode>_text.md`.
7. **Diary spine generator** (parallel to celarien voyage) — a
   deterministic spine generator for diary mode. Emotional_arc
   already lives in the spine fixture; needs a generator step
   that produces fresh spines from a seed.
8. **Mode-agnostic directive protocol** — factor the celarien
   directive builder's shape (render-safe, hygiene-stripped,
   assembled from a spread) into a shared protocol every mode's
   directive assembler follows.
9. **Text-to-video handoff** — much later, once the consistency
   layer is producing reliable outputs.

## Not the same as SAT (adjacent, complementary)

SAT is HOW we know which pipes CAN do a mode. The grand scheme is
HOW we USE the pipes that can. SAT is diagnostic; the grand
scheme is production. Both live in `writer/GPT/sat/` and
`writer/GPT/story/` respectively; cross-link when a piece
touches both.

## When to update this doc

Any time a component's role in the flow above changes, or when a
gap on the working list is closed (mark it done + note the
delivering file), or when a NEW mode is added to the mode
selector. The flow is the North Star — keep it accurate.
