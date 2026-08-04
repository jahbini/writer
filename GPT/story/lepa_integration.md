# LEPA integration — story pipeline

Session: 2026-08-04. Multi-phase integration of the LEPA framework
(`pipes/story/data/lepa_framework.yaml` + canonical
`GPT/lepa-ite/lepa_updated.json`) into the story pipeline. Every new
behavior is param-gated OFF by default so the `jim_tragedy`
regression baseline stays byte-identical until a knob is turned.

## Phase 0 — shared loader

`pipes/story/scripts/lepa.coffee` exports:

- `loadFramework()` → parses `pipes/story/data/lepa_framework.yaml`.
- `loadArcana()`    → parses `GPT/lepa-ite/lepa_updated.json`.

Resolution order (contextual error if none exist, per no-prescreens
rule):

- framework: `CWD/data/lepa_framework.yaml` → `BASE/pipes/story/data/`
  → `BASE/data/`.
- arcana: `CWD/data/lepa_updated.json` → `BASE/GPT/lepa-ite/`.

Probe: `test/lepa_loader_probe.coffee` — 4 energies, 9 distortions,
9 archetypes, 22 uppers, 4×10 minors, suit→energy complete. **13/13
pass.**

## Phase 1 — character genesis (archetype resolver)

### story_outline.coffee

- Loads `lepa_framework.character_archetypes` at run time.
- Prompt now includes a CHARACTER ARCHETYPES section — the 9
  archetype keys with up to 4 `examples` each — as a closed enum.
- OUTPUT CONTRACT extended with an OPTIONAL `unresolved_cast` array:
  `{ name, archetype, dramatic_relation }`.
- `shapeLooksOk`: `unresolved_cast` absent = valid (old outlines
  still pass); when present, entries must have all three fields.
- New UNRESOLVED_CAST RULES block in the prompt explains: cast-slot
  label fields keep their atom-only rule; description-named
  characters without a library atom go into `unresolved_cast`
  instead of being invented into a slot or dropped.

### cast_genesis.coffee (new step, no LLM)

- Reads `story_outline_json.unresolved_cast`.
- For each entry, mints a sheet from the archetype mapping:
  `{ id: genesis_<snake(name)>, label, dramatic_relation, archetype,
     court_role, primary_energy, distortion (= first of
     distortion_pool — slowstep: one only), typical_imbalance }`.
- Emits `cast_supplement = { sheets: [...] }`.
- Empty `unresolved_cast` → `{ sheets: [] }` (no-op).
- Contextual error (no shallow prescreen) if an entry names an
  archetype not in the closed enum — the one legitimate guard.

### story_spine.coffee

- Adds `cast_supplement` to `needs` (via override; see Wiring).
- `mergeSupplementalCast(outline, supplementDoc)` folds sheets in.
- **The leakage boundary is here.** `spine.cast.supplemental` carries
  ONLY `{id, label}` per entry. archetype / court_role /
  primary_energy / distortion / typical_imbalance stay in the
  `cast_supplement` artifact and are dropped at the spine boundary.
- Defensive slot assignment: if a genesis label exactly matches
  `outline.cast.antagonist_label` / `witness_label` (which the
  outline generator is instructed NOT to do), the sheet fills that
  slot instead of going to supplemental[]. In practice this path is
  cold — genesis characters always land in `supplemental`.

### scene_planner.coffee

- `castNamesList` now includes `cast.supplemental[*].label` — the
  cast-discipline filter (line 252-255) ADMITS genesis names.
- CAST section of the prompt gained an `Also present: <names>` line
  so the LLM sees the supplemental names as usable.
- Exports `buildPrompt` and `castNamesList` for the probe.

### build_diary_prompt_ite.coffee

- Untouched. It reads `story_spine_json`, `story_beats_json`,
  `scene_plan_json`, `diary_kag` — all of which now carry cast in
  label-only form for supplemental entries. The leakage law is
  enforced upstream at the spine boundary; no changes are required
  in the generator prompt builder.

### Wiring — `pipes/story/override/story.yaml`

`config/story.yaml` was NOT edited. The new step and its produced
artifact are registered via deep-merge into the experiment
(`pipeline_runner.coffee:822-824` confirms `discoverSteps` walks the
merged experiment dict for anything with `run:`; artifact keys are
similarly merged):

```yaml
artifacts:
  cast_supplement:
    target: out/cast_supplement.json

cast_genesis:
  run: cast_genesis.coffee
  depends_on: [story_outline]
  needs: [story_outline_json]
  makes: [cast_supplement]

story_spine:
  depends_on: [story_outline, chapter_context, cast_genesis]
  needs: [story_outline_json, chapter_context, cast_supplement]
```

Mirrored into `pipes/story/override/spystory.yaml`. That override is
now minimal — just `pipeline: spystory` + the Phase 1 wiring above.
The generator gate that used to live there was removed when
`spystory` collapsed to a single-generator recipe; see
`GPT/story/spystory.md`.

### Probe

`test/cast_genesis_probe.coffee`. Feeds a canned outline with
`unresolved_cast = [King of Poodepoo (authority), king's nephew
(beneficiary)]`. Asserts:

- 2 sheets mint correctly (id, archetype→court_role/primary_energy
  mapping, first-of-pool distortion).
- `spine.cast.supplemental` entries have EXACTLY `{id, label}`.
- `scene_planner.castNamesList` includes both genesis names.
- Rendered scene_planner prompt names both characters.
- LEAKAGE LAW at the artifact boundary:
  - no archetype key / energy name / -mensch label / card token in
    `spine.cast.supplemental` JSON.
  - no such tokens in the Phase-1 prompt delta (the `Also present:`
    line).

**All Phase 1 assertions pass.** Log:
`test/logs/cast_genesis_probe/<ts>/run.log`.

Note on the leakage-law's target: the probe scans the ARTIFACT CHAIN
(what fields cross the spine boundary) and the delta lines Phase 1
added — NOT arbitrary English prose already in downstream prompts.
`scene_planner.coffee`'s pre-existing prose includes the word
"catalyst" as a scene-plan output field name; that's a data-contract
name, not LEPA leakage.

## Phase 2 — minor arcana as beat vocabulary (param-gated)

### dramatic_grammars.yaml

Grammars gained an OPTIONAL `energies: [...]` list naming which
energies the grammar stresses:

- `jim_tragedy.energies: [ethos, pathos]` — ethos/pathos collision.
- `spy.energies: [logos]` — logos under siege.

When a grammar lacks `energies`, the vocab renderer uses all four.
The field is ignored when `beat_vocabulary` is off.

### story_beats.coffee

- New param `beat_vocabulary` (default absent/false).
- `buildPrompt(spine, grammar, vocabBlock = '')` — third arg is a
  pre-rendered string. When `''`, the prompt is byte-identical to
  the pre-Phase-2 baseline (blank line spacing preserved).
- `buildBeatVocabularyBlock(grammar, arcana)` renders a MOVEMENT
  VOCABULARY section: for each stressed energy, the 10 minor-arcana
  entries as `public_name: movement` lines (rank and suit fields are
  NOT emitted).
- Action: when `beat_vocabulary` is truthy, calls `lepa.loadArcana()`
  and passes the rendered block to `buildPrompt`; otherwise passes
  `''`.

### Probe (extended regression)

`test/dramatic_grammars_probe.coffee` now covers:

- Baseline byte-identity: `buildPrompt(spine, jim_tragedy)` still
  matches the pre-externalization snapshot (5234 chars).
- Byte-identity again with explicit `vocabBlock=''`.
- Vocab-ON case (spy grammar):
  - `MOVEMENT VOCABULARY` header present.
  - `[logos]` section present.
  - `[ethos]`, `[pathos]`, `[anima]` sections NOT present (spy
    stresses only logos).
  - Sample logos public_names appear (`First Signal`,
    `Thought Collapse`).
  - No suit / arcana / tarot tokens (`swords`, `pentacles`, `cups`,
    `wands`, `arcana`, `tarot`, `of cups`, `of wands`, `of swords`,
    `of pentacles`) or `rank:` field label leak into the block.

**All Phase 2 assertions pass.** Spy vocab-on prompt is
6146 chars (+912 vs baseline).

## Leakage law — grep list

The generator prompt (`out/diary_prompt.txt`) must NOT contain any
of the following as framework tokens:

- Archetype keys: `authority`, `adversary`, `beneficiary`,
  `executor`, `catalyst`, `messenger`, `witness`, `victim`,
  `populace`.
- Energy names as bare tokens: `logos`, `ethos`, `pathos`, `anima`.
- Distortion labels: `babbelmensch`, `victimensch`,
  `victlessmensch`, `molotovmensch`, `sensomensch`, `grabbermensch`,
  `stupomensch`, `slobbermensch`, `spentmensch`.
- Card / suit tokens: `swords`, `pentacles`, `cups`, `wands`,
  `arcana`, `tarot`; `of cups` / `of wands` / etc.

The English words `catalyst` and `witness` occur as pre-existing
data-contract field / slot names in `scene_planner.coffee`; those are
not framework leaks.

## Deferred (not in scope this session)

- **Upper-arcana lens resolution at `story_outline`.** `arcana_usage`
  marks uppers as story-scoped ("life goals and settings"). Wiring
  uppers into outline is a separate increment.
- **Gestures on genesis character sheets.** The current sheet has no
  gesture field; the leakage law leaves room for `label` and `later
  gestures` to reach the generator prompt.
- **Grammar backbones as card sequences.** Today's `backbone.beats`
  are `{fn, gloss}` pairs; a card-anchored variant (a minor-arcana
  progression that seeds a chapter's beats) is future work per
  `arcana_usage.minor_arcana.doctrine`.
- **Renaming `scene_planner` prose word `catalyst`.** The word
  collides with an archetype key but is a scene-plan output field
  name in the recipe's data contract — renaming would ripple through
  downstream consumers.
