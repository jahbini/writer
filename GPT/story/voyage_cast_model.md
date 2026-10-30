# Voyage cast model — the ship is a kingdom

Recorded 2026-10-26 from jahbini's directive while scoping the voyage
(celarien) anchor of the LEPA + tarot story framework. This is the
CHARACTER model for voyage mode. It extends `cast_genesis.coffee`'s
archetype sheet; it does not replace the closed `character_archetypes`
enum in `data/lepa_framework.yaml`.

## The core idea

"A ship is a kingdom." The `court_roles` table in
`data/lepa_framework.yaml` (king / queen / knight / page) IS the ship's
company. A character is not just an archetype stamp — it is:

    character = court_role  ×  4-energy profile  ×  ability/passion tags

From that profile, the emotional axes a character will MOVE (the
`dimensions:` block) and the way they will FAIL (their mensch
`distortion`) are DERIVED, not hand-assigned. That derivation is the
whole point of LEPA for voyage.

## Voyage refinement of the court

The framework's default `energy_bias` for `king` is **ethos** — correct
for a *static* kingdom (rules, walls, administration). On a VOYAGE the
King is **anima**-biased instead: the captain is the **axis** (the
`dynamical_model` axis) that decides whether logos/ethos/pathos move
together or fall apart. The sea rewards coherence, not administration.
This is a per-mode override of the court energy_bias, not a change to
the framework file.

| Aboard | Court role | Primary energy | Holds |
|---|---|---|---|
| Captain | king — *The Direction* | **anima** (+ethos) | the ship's coherence / the axis |
| Named officers | knight — *The Hands* | **ethos** (+anima) | execution, seamanship, specific abilities |
| The crew (as a mood) | queen — *The Populace* | **pathos** | the vibe — morale, the emotional weather |
| Passengers / news-bearers | page — *The Signal* | **logos+pathos** | word from outside, the pull of a destination |

## Crew modeling decision — HYBRID (2026-10-26)

Chosen over all-individuals and two-fields-only:

- **Captain** — exactly one. Individual King. High anima.
- **Named officers** — 1–4 individual Knights (bosun, cook, first mate,
  navigator…). Full sheets: own 4-energy profile, abilities, one
  distortion each (slowstep: one only).
- **The company** — ONE Queen-FIELD entity, not individuals. Carries the
  collective pathos "vibe", with a **masculine and feminine register**
  (jahbini: "male and female pathos to provide the vibe of the
  voyage"). Has a mood baseline and a souring-risk, not a distortion.
- **Passengers** — individuals. Pages (The Signal); a passenger who
  WORKS their passage gains knight (Hands) flavor.

## Sheet schema (voyage extension)

```yaml
cast:
  captain:                                   # always one; the axis
    name: <name>
    court_role: king
    energy_profile: { anima: high, ethos: high, pathos: med, logos: med }
    abilities: [command, reads weather, holds the line]
    passions:  [the ship, reaching port]
    distortion: null                         # captain's job is not to distort

  officers:                                  # named Knights, 1-4
    - name: <name>
      court_role: knight
      role_aboard: bosun|cook|first_mate|navigator
      energy_profile: { ethos: high, anima: high, pathos: low, logos: med }
      abilities: [...]
      passions:  [...]
      distortion: <one from the archetype's distortion_pool>

  company:                                   # the crew-as-field (one entity)
    court_role: queen
    energy_profile: { pathos: high }
    registers: { masculine: <flavor>, feminine: <flavor> }
    mood_baseline: <e.g. loyal-but-restless>
    souring_risk: [molotovmensch, slobbermensch]   # how the field goes bad

  passengers:                                # individuals; Pages
    - name: <name>
      court_role: page
      works_passage: true                    # → gains knight/hands flavor
      energy_profile: { anima: high, ethos: high, pathos: high, logos: low }
      abilities: [...]
      passions:  [...]
      distortion_risk: <derived from the weakest guardrail in the profile>
```

## Worked example — the athlete passenger

jahbini's canonical example: *pays by working, bound for the Olympic
Games; high anima, low logos, specific abilities (ethos), passions
(pathos).*

```
court_role: page (works passage → knight-flavored)
energy_profile: { anima: high, ethos: high, pathos: high, logos: low }
  strong axes:  direction(+)  — knows exactly which way is up: the Games
                vitality(+)   — flourishing, driven
  fragile axes: clarity / truth — low logos: won't see a deception coming
  distortion risk: sensomensch — desire captures direction
```

Everything under "strong/fragile/distortion" is COMPUTED from the
profile against the `dimensions:` and `distortions:` blocks. Nothing
there was hand-assigned. That is the model working.

## The draw → voyage seed contract (DECIDED 2026-10-26)

The I-Ching hexagram seeds EXACTLY two things, both at the top of the
kingdom — nothing else in the cast is drawn:

    hexagram  →  captain's axis   (which anima dimension the captain
                                   embodies: vitality / identity /
                                   direction — the KIND of coherence
                                   the captain holds the ship to)
              →  voyage weather   (the climate the whole voyage lives
                                   inside; = arcana_usage.upper_arcana
                                   scope, "the weather the whole story
                                   lives inside")

Everything below — officer dials, the company's registers, passengers'
profiles — is AUTHORED within that frame, not drawn. The draw constrains
the top; human authorship fills the court. Satisfies grand_scheme
invariant #1 (deterministic seed → complete frame) and #3 (human input
welcome).

### Weather — DONE 2026-10-26 (hexagram-native, not upper-arcana)

Resolved: weather is read NATIVELY off the hexagram's two trigrams via
the existing Geemo-approved `lepa_affinity` map in
`data/iching_casting.yaml` — NOT a tarot/upper-arcana bridge. New
`weather_reading` block authored there:

    lower trigram → SEA (the true undercurrent)
    upper trigram → SKY (the visible, named condition)
    each → a LEPA energy via lepa_affinity → a 4×4 climate grid.

The affinity map aligns exactly with the ship-kingdom:
heaven→anima→captain, earth→pathos→company-field, {thunder,water,
mountain}→ethos→crew, {wind,fire,lake}→logos→pages. Sky≠sea = the
voyage's tension is the gap between visible weather and true current;
sky==sea = a pure/doubled climate. Validated against all 64 situations.
Distribution skew (from the 1-3-1-3 asymmetry): 9 pure-ethos, 9
pure-logos, but only 1 pure-anima (Qian) and 1 pure-pathos (Kun) — rare
climates by construction. Each energy-as-weather foregrounds its
`dimensions` cluster (see the block's `energy_climate`).

### Captain's axis — DONE 2026-10-26 (heaven-position reading)

Resolved: the captain's anima axis is read from WHERE heaven (the sole
anima trigram) sits, same sky/sea logic as the weather. New
`captain_axis` block in `data/iching_casting.yaml`:

    heaven as SKY  → direction   (outward compass)      7 hexagrams
    heaven as SEA  → identity    (coherence underneath) 7 hexagrams
    heaven BOTH    → vitality    (Qian; the pure axis)  1 hexagram
    heaven ABSENT  → under pressure, resolved by the run's moving-line
                     center of gravity (upper→direction, lower→identity,
                     balanced→vitality)                 49 hexagrams

Validated across all 64. The 49 under-pressure cases are deliberate:
the captain's coherence is EARNED across the beats, not handed over at
the dock — and when the axis is under pressure, that contest IS the
voyage's spine. Still deterministic (moving lines are seeded from the
description hash, per `selection.derived`).

THE DRAW CONTRACT IS NOW COMPLETE: one hexagram → {weather (sky/sea
energy climate), captain's axis (anima dimension)}, both off the same
draw, no second mechanism.

### situation_caster — BUILT + PROVEN 2026-10-26

`scripts/situation_caster.coffee` — deterministic, no-LLM, sibling of
cast_genesis. Builds on `iching.loadAll`. Pure `cast()` +
selectSituation/selectMovingLines/readWeather/readCaptainAxis, plus a
`@step` (meta-layer: S.need/S.param/S.make/S.done, no direct I/O;
param-gated `use_iching_situations`, default OFF). Emits
`situation_cast_json` with two layers:
  - internal (diagnostic): situation id/name, trigrams, weather
    {sea,sky,energy,stresses}, captain_axis {axis,source}, moving_lines,
    stressed dimensions. NEVER rendered.
  - render (surface-safe): situation text, tension, moving-line stages
    as beats. Leakage law enforced at this boundary.
Determinism: djb2 hash of (description|chapter|situation) → mulberry32
→ seeded Fisher-Yates for moving lines; two_bytes_mod_64 for derived
situation. Same seed → identical voyage.
Probe `test/situation_caster_probe.coffee`: 29/29 pass — determinism,
weather=lepa_affinity, captain-axis spec (incl. CoG fallback), line
range/order, leakage law, all-64 sweep. `npx coffee` compiles both.
WIRED + RAN THROUGH PUPPETEER 2026-10-26. Rather than add a second,
divergent draw, the weather + captain_axis READERS were folded into the
celarien arc generator that already owns the per-chapter draw:
`puppeteer/scripts/novel_arc_generator.coffee` now attaches
`internal.weather` + `internal.captain_axis` to every chapter (inlined
readers, same `iching_casting.yaml` blocks, single-sourced via the
puppeteer/data symlink to writer/data; `generateArc` gained an optional
4th `casting` arg so 3-arg callers/tests are unaffected). Proven: a
cast-only recipe `puppeteer/config/celarien_cast.yaml` (novel_arc_generator
ONLY — no smoke gen / fan-out / mini) run through the puppeteer
pipeline_runner emitted celarien_arc.yaml with weather+captain_axis on
24/24 chapters (axis spread identity 10 / vitality 7 / direction 7).
Deterministic (byte-identical reruns), compiles clean. Shared
control_override.yaml backed up + restored to hf_scan; no mini contact.

CONSUMPTION side — DONE 2026-10-26 (task #3 CLOSED). `celarien_directive_ite`
now reads each chapter's `internal.weather` + `internal.captain_axis`
and emits a surface-safe `steer` per directive (`buildSteer`): a short
Jim-voice private weather-read built ONLY from dimension `jim_render`
phrases (sky pressure + sea undercurrent + the captain's besetting edge
on his axis). Needs `data/lepa_framework.yaml` (now symlinked into
puppeteer/data) for the jim_renders and `iching_casting.yaml`
weather_reading for the per-energy dimension sets. Both generators
(`celarien_generate_ite` peer, `celarien_smoke_ite` local) plant `steer`
as an OPEN `<think>` seed at the assistant turn head — the beat-level
lever — GATED by `use_lepa_steer` (default OFF → byte-identical
baseline; their existing `</think>` strip keeps the seed out of saved
prose). Proven through the puppeteer runner via `celarien_cast.yaml`
(now draw + directive, both deterministic, no LLM): 24/24 directives
carry steer, on-disk JSONL correct, steers leakage-clean (0 framework
labels; the only forbidden-token matches are pre-existing English in the
render prose — "wind over water" situation imagery, "obligations"
doctrine line — not in the steer). Also fixed a pre-existing bug: the
step passed a pre-joined STRING to the jsonl meta device (which wants an
array of objects) → it char-split into 52970 one-char rows; now passes
the array. Generators gated-off + NOT synced to mini; turning
`use_lepa_steer: true` and running a chapter is the next (model-bound)
demonstration.

### 4B-Instruct peer, steer ON — RUN + FIXED 2026-10-26

Synced `celarien_generate_ite.coffee` (additive gated change only) to the
mini, pushed the 24 steered directives to
`pipes/hf__qwen__qwen3-4b-instruct-2507/params/`, and ran a standalone
`celarien_gen_only.yaml` (generate step only, no audit/fan-out) on the
4B-Instruct-2507 with `use_lepa_steer:true`, 2 chapters. Pipe's
`control_override.yaml` backed up + restored to `sat_scan`; no live
runner disturbed.

FINDING + FIX: the first pass LEAKED the steer seed verbatim into ch1's
prose. Root cause — Qwen3-4B-**Instruct**-2507 is a NON-thinking model,
so the OPEN `<think>` seed had no model-emitted `</think>`, and
`callWithThinkRescue` (built for thinking models) surfaced it. Fix (both
`celarien_generate_ite` + `celarien_smoke_ite`): prefill a CLOSED
`<think>…</think>` seed, SKIP the rescue when seeded (no open think to
rescue), and defensively strip a leading verbatim echo in `stripText`.
Re-ran on the 4B: zero bleed, seed fully invisible, and the steering
clearly present — ch1 fear/displaced-cause/slippery-truth ("wronged by a
lie", "she sees the wind in its tongue"); ch2 depletion/debt/contested-
truth ("blade made of memory", "two promises tugged at once—each backed
by a different name", "a script no man had written—where the truth met
resistance"). The thinking 0.6B local smoke never leaked (it closes its
own think); the fix makes steer robust across thinking AND instruct
models. Lesson: the `<think>` lever must prefill a CLOSED block for
non-thinking instruct models.

## Open / still being thought through

- Named-officer roster: which ship roles get individual sheets per
  voyage, and whether that set is fixed or drawn.
- The `energy_profile` 4-vector is richer than cast_genesis's
  primary/secondary. Decide whether to widen the genesis sheet or keep
  voyage profiles as a voyage-only superset.

## Leakage

All of this is framework vocabulary — court roles, energy names,
distortion labels, axis names. NONE of it reaches a generator prompt.
Only `jim_render` forms and surface abilities/passions/gestures do, per
`voice_policy` and the leakage law in `GPT/story/lepa_integration.md`.
