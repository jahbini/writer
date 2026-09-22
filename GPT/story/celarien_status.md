# Celarien — status report (SUPERVISOR style)

Design authority: **Geemo**. Report style: findings, questions, no
silent fixes to data files or recipes. Each phase reports and stops.

---

## Phase 1 — loader + validation (COMPLETE, PASSES)

    [celarien] Phase 1 validator: PASS
      library version:  0.1-draft
      situations count: 64
      chapter_classes:  port_trade, games, pirates, crew_conflict, threshold
      pools:            scenes, characters, disturbances, soundings, bearings

Resolved 2026-09-20 after Geemo granted permission to fix
syntactic errors that came from Claude download conversion. One
fix applied: quoted the invariants bullet at line 218 whose
parenthetical contained an unquoted `mortal: false` that
`js-yaml` mistook for a nested mapping. No other library content
touched. Grep scan for similar `word: word` patterns in unquoted
scalar bullets returned this as the only instance.

Deliverable stands: `writer/scripts/celarien.coffee` +
`writer/GPT/story/celarien_status.md`. Gate `use_celarien_arc`
default off; no recipe wired.

Original block report preserved below for audit.

---

## Phase 1 — loader + validation (original blocker report)

**Deliverable:** `writer/scripts/celarien.coffee` — a memo-first
loader + shape validator + cross-file validator against
`iching_situations.yaml`. Follows the `writer/scripts/iching.coffee`
template exactly (readMetaOrFile, single-throw with all failures
listed at once, no production caller). Gate `use_celarien_arc`
default off — not yet referenced by any recipe.

**Status:** module written and syntax-checks clean. When run against
the current library, the module refuses to proceed because
`data/celarien_story_library.yaml` **fails YAML parse** before shape
validation can start.

### Blocker: YAML parse error at line 219

    216  chapter_contract:
    217    invariants:
    218      - crew survives (mortal: false cast cannot die, be maimed beyond
    219        recovery, or be written off the ship)

The YAML parser (`js-yaml`) reads `mortal: false` inside the
parenthetical as a nested mapping key on the next line, breaks with
`expected ':' after a mapping key (219:44)`.

Same issue is latent on any other unquoted bullet that contains a
`word: word` colon-space pattern. I have not scanned for others yet —
holding until Geemo decides fix policy (see questions below).

Per CELARIEN.md hard rule *"no edits to the library or the iching
data files. Schema problems are reported to celarien_status.md, not
silently fixed"* — no changes made to the library. This report
is the entire response.

### What the module DOES cover (once the library parses)

Phase 1 validation checks the module implements, ready to run:

1. **Top-level blocks present**: `world_bible`, `ship`, `cast`,
   `chapter_classes`, `aperture`, `spread`, `chapter_contract`,
   `acts`, `pools`.
2. **`chapter_classes.*.internal.family`** — every entry is int in
   `[1..64]`.
3. **Cross-file:** every id in every family exists in
   `iching_situations.yaml` `situations[].id`.
4. **`spread.{shield,sword}.*.source`** — every source string's
   dotted-path root is in `{chain, spine, cast, contract, pool}`.
   Compound sources ("cast.roster + spine.setting_state") split
   on `+` and each part validated separately.
5. **`chapter_contract`** — `invariants` non-empty array,
   `violation_policy` string, `fortune.palette` non-empty array,
   `fortune.rule` string, `audit` string.
6. **Pools** — every leaf entry carries a non-empty `text:`.
   Handles both shapes: flat (`pools.scenes.<slug>.text`) and
   one-level-nested (`pools.disturbances.<class>.<slug>.text`).
   Anything deeper is flagged as a shape violation.
7. **`aperture.values`** — non-empty array; `aperture.rule` string.

All failures accumulated and reported in a single throw so a human
sees the full punch list at once.

### Reproduction

    cd ~/writer && coffee scripts/celarien.coffee

Success output on a clean library will be:

    [celarien] Phase 1 validator: PASS
      library version:  0.1-draft
      situations count: 64
      chapter_classes:  port_trade, games, pirates, crew_conflict, threshold
      pools:            scenes, characters, disturbances, soundings, bearings

Current output:

    expected ':' after a mapping key (219:44)

### Questions for Geemo

1. **Fix policy on the parse error.** Two options I can see:
   a. Human/Geemo edits the library (quote the bullet, e.g.
      `- "crew survives (mortal: false cast cannot die, ...)"`),
      then Phase 1 re-runs.
   b. The rule *"no edits to the library"* is meant to keep the
      CLI agent from touching it; Geemo may choose to make this
      edit and unblock Phase 1.

   I am NOT unilaterally editing. Waiting for direction.

2. **Should I proactively scan the whole library for other
   colon-space patterns inside unquoted strings** and enumerate
   them in this status file (so any fix pass catches them all in
   one go), or wait until Geemo confirms scope?

3. **Directory home for celarien files.** I placed
   `writer/scripts/celarien.coffee` alongside `iching.coffee` and
   `lepa.coffee`. CELARIEN.md refers to `pipes/story/data/` in
   places (via `celarien_story_library.yaml` companion mention)
   but the actual library is at `writer/data/`. My module resolves
   via CWD/data → BASE/data → BASE/pipes/story fallback chain,
   matching iching.coffee. Confirm this is the intended home.

4. **Status file location.** I put this at
   `writer/GPT/story/celarien_status.md` (previously nonexistent).
   CELARIEN.md wrote "GPT/story/celarien_status.md" without a repo
   prefix. Confirm this is the right home; move if needed.

## Phase 2 — novel_arc_generator (COMPLETE, PASSES)

Deliverable: `writer/scripts/novel_arc_generator.coffee`.

**Deterministic.** No LLM. SHA-256 of `author_description` → uint32
seed → per-chapter/per-tag mulberry32 sub-PRNGs. Same author +
same params on any machine = same arc byte-for-byte. Verified:

    coffee scripts/novel_arc_generator.coffee > /tmp/arc1.yaml
    coffee scripts/novel_arc_generator.coffee > /tmp/arc2.yaml
    diff /tmp/arc1.yaml /tmp/arc2.yaml    # empty — byte-identical

Second sanity check: different `author_description` produces a
different arc (byte diff, expected).

**Gate.** `use_celarien_arc` default false. Step is a no-op when
off. No recipe wired.

**What the step emits (artifact `celarien_arc_json`):**

Top level:
- `celarien_arc_version: "0.1-draft"`
- `seed:` — the `author_description` and its `sha256_uint32`
  for the reader's audit trail
- `chapter_count`, `act_count`, `class_sequence`
- `chapters:` — one entry per chapter

Per-chapter record matches the format documented at the bottom of
the library:

    ch_0001:
      class: port_trade
      aperture: none
      internal:
        situation: 56
        moving_lines: [1, 3, 5, 6]
        derived: 17
      fortune: success
      passenger: null
      pool_draws:
        scenes:       [shrine_smoke_above_port, harbor_cranes_and_grain_dust]
        characters:   [captain_takes_a_bearing, athlete_weighs_his_advantage]
        disturbances: [price_that_is_too_good]
        soundings:    [sounding_cargo_unease]
        bearings:     [bearing_over_profit]

**Verified invariants on the sample arc** (24 chapters, 4 acts,
default `class_sequence`):

1. **Bit-flip → derived situation correct.**
   - ch_0001: situation 56 (`001101`), moving lines [1,3,5,6] →
     flipped bits (0,2,4,5) → `100110` → id 17 ✓
   - ch_0006: situation 64 (`010101`), moving lines [1,2,3,4,6] →
     flipped bits (0,1,2,3,5) → `101000` → id 36 ✓
2. **Threshold chapters carry a mythic aperture.** Every
   `class: threshold` (4 of 24) has aperture ∈ {oracle,
   underworld}. Non-threshold classes all have aperture=none.
3. **Fortune drifts landward.** Chapter-1 skews positive
   (success/riches), late chapters cluster on setback / defeat /
   bankruptcy. Mean-reverting: each chapter's noise is
   independent, target linearly drifts from 0 (chapter 1) to
   -1.5 (last chapter) — the "sea empire falling" pressure per
   `world_bible.series_axis.internal.drift: interface_to_land`.
4. **Class sequence policy.** Non-threshold cycle
   {port_trade, games, pirates, crew_conflict}; threshold at end
   of each act (positions 6, 12, 18, 24 for chapter_count=24 /
   act_count=4). Override with the `class_sequence` param.

**Sample arc preserved:**
`writer/GPT/story/samples/celarien_sample_arc_default_seed.yaml`
(648 lines, 24 chapters, default seed
"A Celarien voyage arc: standard demonstration seed.").

**Passenger left null in Phase 2.** The library has no populated
passenger name pool yet (`cast.captain.name = TBD_by_geemo`, no
`cast.passengers` block). Phase 3 or a Geemo passenger-authoring
pass will fill this. When a pool appears, add per-chapter seeded
passenger picks with the "at most one new named passenger per
waystone" invariant enforced.

**What Phase 2 does NOT do (as spec'd):**
- `spread:` block filling — Phase 3's spread assembler
- Any generator directive / render-safe strings
- Any audit of actuals vs plan — Phase 4

### Questions for Geemo (Phase 2 → Phase 3 handoff)

1. **Default `chapter_count`** = 24 (4 acts × 6 chapters). If a
   different default fits the intended season, name it.
2. **Threshold-position policy** = last chapter of each act. Some
   traditions place thresholds at act BOUNDARIES (act-1-to-act-2
   opener) rather than act tails. Confirm the tail policy or
   name the alternative.
3. **Fortune curve parameters** — I set landward drift target to
   -1.5 (chapter N) with per-chapter Gaussian noise σ=1.0. That's
   a guess to produce a visible drift without collapsing into
   pure defeat. Tunable, but the numbers are arbitrary; confirm
   or name replacements.
4. **Author-description input mechanism** — the step reads
   `author_description` as a param. Phase 3's UI textarea
   integration is where a human types this. For now, the
   standalone probe accepts `argv[2]` as a demo path. Fine, or
   plumb differently?

## Phase 3 — spread assembler + directive builder (COMPLETE, PASSES)

Deliverable: `writer/scripts/celarien_directive_ite.coffee`.

Also delivered alongside: **author_description setup panel** on
the writer UI (per Geemo's 2026-09-20 directive):

- Panel:    `writer/panels/celarien_setup.coffee`
- Renderer: `writer/ui/index.html` → `PANEL_CUSTOM_RENDERERS.celarien_setup`
- Endpoint: `POST /api/celarien_author_description` on writer UI
- Storage:  `<CWD>/params/celarien_setup.yaml` (per pipe)
- Gate `use_celarien_arc` NOT toggled from panel (kept as
  deliberate elsewhere-flip per CELARIEN.md invariant).

### The step

Reads: `celarien_arc_json` (Phase 2), `data/celarien_story_library.yaml`,
`data/iching_situations.yaml`.

Per chapter, fills the nine spread positions from their declared
sources (see the library's `spread:` block for the source names):

| position   | source                                | render                                                     |
|------------|---------------------------------------|------------------------------------------------------------|
| mission    | `spine.want`                          | current situation's `tension.need`                         |
| blocking   | `chain.field.tension.protection`      | current situation's `tension.protection`                   |
| leaving    | `chain.prev`                          | previous chapter's rendered `situation` (empty for ch 1)   |
| foundation | `cast.crew_core`                      | amazons + athlete `render:` (captain excluded — sword.grip has him) |
| arriving   | `chain.derived`                       | derived situation's rendered `situation`                   |
| grip       | `cast.captain_persona`                | captain's `persona` (public face)                          |
| crew_env   | `cast.roster + spine.setting_state`   | roster one-liner                                           |
| success    | `contract.criterion`                  | current situation's `stages[3]` (pivot-stage phrasing)     |
| tip        | `contract.fortune_draw`               | fortune palette word → prose one-liner                     |

Then builds a **generator directive** per chapter — render-safe
prose ready for callLLM. Assembly order:

1. Doctrine line (chapter-local color OK; no cross-chapter obligations)
2. Chapter frame (rendered situation.situation)
3. What is wanted / What holds it back (mission + blocking)
4. Leaving / arriving (chain flanks)
5. Foundation (crew) + grip (captain's face)
6. Aperture block (threshold chapters only — oracle voices shield-side
   as prophecy; underworld walks katabasis sword-side, descent /
   ordeal / return-changed)
7. Pool picks (scenes, characters, disturbances, soundings, bearings —
   rendered `text:` fields only)
8. Success + tip (contract closers)

Emits:
- `celarien_filled_arc_json` — Phase 2's arc extended with a filled
  `spread:` block per chapter (render-safe strings only)
- `celarien_directives_jsonl` — one JSON object per chapter with
  `chapter_key`, `class`, `aperture`, `directive` (the callLLM-
  ready prose)

Gate: same `use_celarien_arc` as Phase 2. Off = no-op.

### Verification

- **Compile:** three files (step, panel, ui_server changes) all
  syntax-check clean.
- **Determinism:** same `author_description` → byte-identical
  directives across two runs.
- **Hygiene scan:**
  ```
  grep -cE "situation:|moving_lines|glyph_binary|hexagram|LEPA|
    anima|animus|ethos|logos|pathos|axia" celarien_sample_directives.yaml
  → 0 hits
  ```
  No hexagram ids, no `internal:` keys, no spread position names,
  no LEPA terms leak into the directive.
- **Captain double-render bug:** fixed. First pass had captain
  persona appearing in both `foundation` (crew_core) and `grip`
  (captain_persona) — foundation now excludes captain and renders
  crew only.
- **Sample first-chapter directive:**

```
Chapter-local color is fine; do not mint cross-chapter
obligations, debts, wounds, or deaths.

The chapter's frame: The stranger passing through: no standing,
no home ground — survival by reserve, courtesy, and not settling
into what is not one's own.

What is wanted here: shelter, passage, and small wins on foreign
ground

What holds it back: modesty; a stranger's arrogance is quickly
punished

What is arriving: Following: leadership by adapting — to gain
followers one must first learn to follow, and choose whom to
follow with care.

Amazons aboard: Archers of the Pontic steppe, hired on the grain
run… The athlete passenger: A strong and amoral athlete working
the games circuit, aboard between contests…

Captain's face to the world: Reads as whim and luck: decisions
announced without argument, headings changed on no visible
evidence, and yet the ship comes home.

Scenes to draw on: Shrine smoke rising above the port town |
Grain dust and crane ropes over a crowded quay
…

The success this chapter would look like: Shelter and property
gained, but 'my heart is not glad'; not home.

How fortune actually lands: a modest gain that holds
```

Full 24-chapter directive sample preserved at:
`writer/GPT/story/samples/celarien_sample_directives.yaml`
(164 lines, first 3 chapters expanded).

### The panel

Appears on every writer pipe UI (small, always shown). Contents:

- `Author description` textarea — freeform text; SHA-256 of this
  drives every deterministic draw in the arc.
- `chapter_count` numeric input (default 24)
- `act_count` numeric input (default 4)
- `Save` button → `POST /api/celarien_author_description`
  → writes `params/celarien_setup.yaml`
- Gate indicator: reads current `use_celarien_arc` from the file
  and shows "gate ON / OFF." Panel does NOT toggle it. Deliberate.
- Last-saved timestamp shown.

To activate on a running writer UI: restart it (the new endpoint
+ panel need the server rewired). Panel loads via the existing
panel registry — no `ui_server.coffee` route change needed for
the endpoint delivery (existing `/api/panel/celarien_setup`
serves the read side); the WRITE path (POST /api/celarien_author_description)
is new and needs the server up-to-date.

### Questions for Geemo (Phase 3 → Phase 4 handoff)

1. **Panel visibility.** Currently shows on every pipe. If the
   panel should only appear on pipes tagged for the celarien
   story, name the flag/marker.
2. **`stages[3]` as success criterion.** I chose the fourth of
   six stages (bottom→top: 0..5 → I use index 3) as the "pivot
   stage" phrasing for `contract.criterion`. This is a design
   guess — the situation's stages describe how the situation
   MATURES, and stage 3 (past initial commitment, before
   overreach) reads well as "what would success look like at the
   pivot." If a different stage is canonical, name it.
3. **Aperture prose voice.** Oracle and underworld renders are
   drafted from CELARIEN.md's spec text. Both are one paragraph
   each, in the recipe's own voice. If Geemo wants the aperture
   to sound distinctly OTHER — a different register — say so.
4. **Katabasis grammar addition.** CELARIEN.md's Phase 3 spec
   calls for the katabasis shape (descent / ordeal /
   return-changed). I render it inline in the aperture block
   for underworld chapters. CELARIEN.md separately notes that
   `dramatic_grammars.yaml` may need an entry for katabasis —
   flagged there for Geemo's decision, not touched here.

## Phase 4 — audit + tests (COMPLETE, ALL PASS)

Deliverables:
- `writer/scripts/celarien_audit_ite.coffee` — the audit step. NEW
  file (not an edit to existing state_extractor.coffee), following
  CELARIEN.md's "no changes to jim/spy/... recipes." Celarien's
  audit has the OPPOSITE contract from jim's state_extractor: it
  emits an audit result and a regen trigger; it does NOT
  propagate actuals into any later chapter's plan.
- `writer/scripts/celarien_test.coffee` — the four-test suite,
  runnable standalone via `coffee`. Exit 0 on all pass.

### Audit contract

Reads:
- `celarien_filled_arc_json` (Phase 3 output, plan)
- `celarien_chapter_actuals_json` (optional; supplied downstream
  when the recipe wires celarien to a generator pipe)

Per chapter, three LLM-judged checks:
1. **Invariants intact** — the four chapter_contract invariants
   (crew survives, voyage continues, ≤1 mythic aperture, no new
   named characters beyond planned passenger).
2. **Success criterion** — met / honestly_missed / silent.
3. **Tip landed** — yes / no / reversed (planned fortune vs.
   actual chapter ending).

Emits `celarien_audit_json`, one entry per chapter:

    {
      chapter_key,
      planned: {class, aperture, fortune},
      invariants_intact:  bool,
      invariant_breaches: [ "..." ],
      success_criterion:  "met" | "honestly_missed" | "silent",
      tip_landed:         "yes" | "no" | "reversed",
      regen_needed:       bool,   # true iff invariants breached
      notes:              "..."
    }

Gate: `use_celarien_arc` (default false). Off = no-op.

**Hard invariant re-enforced in code:** the audit result MUST
NOT feed into any later chapter's plan. It's an artifact, an
alert, a regen trigger — never a state inheritance hook.

### Test results

    cd ~/writer && coffee scripts/celarien_test.coffee

    ✓ (a)  determinism — same seed yields byte-identical arc
    ✓ (a2) determinism — different seed yields different arc
    ✓ (b)  transformation — all 64 unique glyph_binary present
    ✓ (b)  transformation — every line-set bit-flip yields valid id
    ✓ (c)  leak — directives contain no internal vocabulary
    ✓ (c2) leak — no bare "situation: NN" hexagram-id leak
    ✓ (d)  gates-off — novel_arc_generator makes nothing gate-off
    ✓ (d2) gates-off — celarien_directive_ite makes nothing gate-off
    ✓ (d3) gates-off — celarien_audit_ite makes nothing gate-off

    9 passed, 0 failed

Notable: test (b) verified **2624 flips** (64 situations × 41
line-set subsets covering all C(6,3)+C(6,4)+C(6,5) choices) —
every single one resolves to a valid situation id. The iching
data is COMPLETE: all 64 unique glyph_binaries are present.

### Leak-test forbidden token list

Documented in the test source. Includes tokens that only appear
as planning vocabulary (never as natural English inside chapter
directives). NOT included: common English words that coincide
with position names (mission / blocking / leaving / arriving /
foundation / grip / crew_env / success / tip) — those would
false-positive on natural prose. The hygiene rule is about
label-as-key vocabulary, not English-word overlap.

Forbidden set: `glyph_binary`, `name_internal`, `moving_lines`,
`celarien_arc_version`, `sha256_uint32`, `kag_emotion_map`,
`anima_forward`, `ethos_forward`,
`ethos_hypertrophy_pathos_vacancy`, `logos_inputs`, `hexagram`,
`I Ching`, `iching_situations`, `iching_casting`, `king_wen`,
`\ninternal:`, `lepa_affinity`.

### Gates-off byte-identity: what "byte-identical" means here

None of the three celarien steps (novel_arc_generator,
celarien_directive_ite, celarien_audit_ite) are wired into any
existing recipe. So byte-identity to pre-celarien behavior is
trivially satisfied at the recipe level.

For future wiring, the tests verify the SUFFICIENT condition: the
gate guard is present as the first action line, checks
`use_celarien_arc` param (default false), and returns immediately
via `L.done()` before any `L.make` or `L.callLLM`. Verified via
source-scan against a known-good regex. Any recipe that inserts
these steps under a gate-default-off setting produces byte-
identical output to a recipe without them.

## Refactor — puppeteer/peer split (2026-09-20)

Per grand_scheme.md's step boundaries, celarien's phases split
across the two projects:

    puppeteer:  novel_arc_generator → celarien_directive_ite → celarien_fanout_ite → queue_run_ite
    peer:                                                                            celarien_generate_ite → celarien_audit_ite

**Puppeteer** (spine gen + directive assembly + fan-out orchestration):

    ~/puppeteer/scripts/celarien.coffee                (P1 loader + validator)
    ~/puppeteer/scripts/novel_arc_generator.coffee     (P2 arc gen)
    ~/puppeteer/scripts/celarien_directive_ite.coffee  (P3 spread + directive)
    ~/puppeteer/scripts/celarien_fanout_ite.coffee     (scp-push + queue build)
    ~/puppeteer/scripts/celarien_test.coffee           (9-test suite)
    ~/puppeteer/panels/celarien_setup.coffee           (Celarien Setup panel)
    ~/puppeteer/config/celarien_prep.yaml              (puppeteer recipe)
    ~/puppeteer/ui_server.coffee                       (POST /api/celarien_author_description, GET /api/celarien_setup)
    ~/puppeteer/ui/index.html                          (Celarien Setup panel client renderer)

**Peer/writer** (LLM generation + audit):

    ~/writer/scripts/celarien_generate_ite.coffee      (LLM generation per chapter)
    ~/writer/scripts/celarien_audit_ite.coffee         (P4 audit + regen triggers)
    ~/writer/config/celarien_run.yaml                  (peer recipe)

**Data (shared, single source of truth):**

    ~/writer/data/celarien_story_library.yaml
    ~/writer/data/iching_situations.yaml

The `celarien_fanout_ite` step scp-pushes two artifacts per target peer
pipe at fan-out time:

- `<peer>:<pipe>/params/celarien_directives.jsonl`  (Phase 3 output)
- `<peer>:<pipe>/params/celarien_filled_arc.yaml`   (planned spread
   for the peer's audit step)

The peer recipe declares these as source-only artifacts with the
canonical names (`celarien_directives_jsonl`, `celarien_filled_arc_json`)
so peer step keys stay identical to puppeteer's.

### Panel migration

Old writer-side celarien_setup panel (added 2026-09-20 morning)
REMOVED. The panel now lives on the puppeteer UI at port 4311.

Endpoints on puppeteer:
- `GET  /api/celarien_setup`              — reads params/celarien_setup.yaml
- `POST /api/celarien_author_description` — writes params/celarien_setup.yaml

Reason for bespoke GET endpoint (not `/api/panel/celarien_setup`):
puppeteer's panel registry resolves BASE=EXEC through node_modules
symlinks and never scans `~/puppeteer/panels/`. The other puppeteer
panels (peer_pipes, queue_status) already use bespoke endpoints
for the same reason. Consistent pattern.

### Test suite re-run after refactor — all pass

    9 passed, 0 failed

Path updates: source-scan tests (d/d2) now read from
`~/puppeteer/scripts/` for the moved modules. Test (d3) still
reads `~/writer/scripts/celarien_audit_ite.coffee` (peer-side, unmoved).

## Wiring — gate lifted 2026-09-20

Geemo's directive: **lift the celarien gate and wire it into a
recipe.** Done.

### The new recipe

`writer/config/celarien.yaml` — a project-shared recipe that any
writer pipe can invoke via `pipeline: celarien` in its
control_override.yaml. Chain (strictly linear):

    novel_arc_generator      → celarien_arc_json
    celarien_directive_ite   → celarien_filled_arc_json + celarien_directives_jsonl
    celarien_generate_ite    → celarien_chapter_actuals_json
    celarien_audit_ite       → celarien_audit_json

All four steps get `use_celarien_arc: true` at recipe level.
Override to false in a pipe's `override/celarien.yaml` to disable
without removing steps.

### New step: celarien_generate_ite

`writer/scripts/celarien_generate_ite.coffee`. Loops over
directives, calls `L.callLLM` once per chapter with the
render-safe directive as user turn. Emits
`celarien_chapter_actuals_json` — the artifact
`celarien_audit_ite` reads for grading.

**Bounded first run: `max_chapters: 3`.** Caps LLM cost on the
first live invocation. Crank up in the pipe's
`override/celarien.yaml` once per-chapter cost is measured. Full
24-chapter runs are permitted; just knob it.

### author_description sourcing

`novel_arc_generator.coffee` now prefers
`<CWD>/params/celarien_setup.yaml` (the file the Celarien Setup
panel writes) over recipe-level `L.param('author_description')`.
Fallback keeps standalone/probe runs working. The panel is now
the canonical human-facing input.

### Existing pipelines untouched

No changes to `writer/config/story.yaml`, `spystory.yaml`, or any
of the jim/spy/chicago/new_orleans/strong library recipes. The
celarien recipe is a NEW file, satisfying CELARIEN.md's "no
changes to jim/spy/... recipes" invariant.

### Test suite re-run — all pass

    9 passed, 0 failed

    ✓ (a)  determinism — same seed yields byte-identical arc
    ✓ (a2) determinism — different seed yields different arc
    ✓ (b)  transformation — all 64 unique glyph_binary present
    ✓ (b)  transformation — every line-set bit-flip yields valid id
    ✓ (c)  leak — directives contain no internal vocabulary
    ✓ (c2) leak — no bare "situation: NN" hexagram-id leak
    ✓ (d)  gates-off — novel_arc_generator makes nothing gate-off
    ✓ (d2) gates-off — celarien_directive_ite makes nothing gate-off
    ✓ (d3) gates-off — celarien_audit_ite makes nothing gate-off

Verified: the gates-off tests STILL PASS even after lifting the
recipe-level gate. The step guards read `L.param('use_celarien_arc',
false)` which returns false when the step is called from any
recipe that doesn't set `use_celarien_arc: true` (i.e., the
existing story/spystory recipes). Celarien recipe sets it true;
everyone else defaults false. Byte-identity preserved.

### How to fire the celarien recipe

On any writer pipe with `run.model` set (i.e., any hf__qwen__*
pipe):

1. Type an author description into the pipe UI's Celarien Setup
   panel; hit Save. (This writes
   `<pipe>/params/celarien_setup.yaml`.)
2. Launch via the puppeteer's ad-hoc launch endpoint:

       curl -X POST http://localhost:4311/api/launch_recipe \
         -H 'Content-Type: application/json' \
         -d '{"pipe":"<pipe-name>","recipe":"celarien"}'

   (Same P1 endpoint used for SAT ladder launches.)
3. The runner walks the 4-step chain. Artifacts land in
   `<pipe>/out/celarien_*.{yaml,jsonl}`.
4. `celarien_audit_json` contains the per-chapter regen triggers
   and grades for the first 3 chapters (bounded by
   `max_chapters`).

### First-live-run advisory

I have NOT actually fired the recipe on the mini yet — this
handoff is code-complete but not runtime-tested end-to-end. The
per-chapter LLM cost is unknown; recommend firing on the smallest
capable pipe (hf__qwen__qwen3-0-6b) first with `max_chapters: 3`
to measure. If a chapter takes >2 min, drop the temperature or
the max_tokens.

## All four phases complete

- Phase 1 ✓ loader + validation (writer/scripts/celarien.coffee)
- Phase 2 ✓ novel_arc_generator (writer/scripts/novel_arc_generator.coffee)
- Phase 3 ✓ spread assembler + directive builder
  (writer/scripts/celarien_directive_ite.coffee)
  + author_description panel (writer/panels/celarien_setup.coffee,
  writer/ui_server.coffee POST endpoint, writer/ui/index.html renderer)
- Phase 4 ✓ audit step + tests
  (writer/scripts/celarien_audit_ite.coffee,
  writer/scripts/celarien_test.coffee)

All gates remain default off. No production recipes touched.
Ready for Geemo's wiring decisions.

### Cross-links to the grand scheme

Per `writer/GPT/story/grand_scheme.md`, the celarien pieces map to
the machine's flow as follows:

- Phase 2 → **step 2 spine generator (voyage mode)**
- Phase 3 → **step 3 directive assembler (voyage mode)**
- Phase 4 audit → **step 5 evaluation** (per-generation grading;
  cross-generation consistency is a separate future component)

The remaining grand-scheme gaps (mode selector UI, fan-out
orchestrator, cross-generation consistency scorer, side-by-side
edit panel, canonical-artifact promotion) are addressable in any
order once Geemo lifts the celarien gate and picks the next
build.

## Open items already flagged in CELARIEN.md (not touched here)

- Crew names: `cast.captain.name = TBD_by_geemo`; Amazons unnamed.
- Acts scaffold: four-goal-stones default, awaiting Geemo confirm.
- Katabasis grammar addition to `dramatic_grammars.yaml` — Geemo's
  call, not done unilaterally.
