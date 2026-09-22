# CELARIEN — the maritime series: what it means for tooling and recipes

Briefing for the CLI agent. The spec is the data file:
`data/celarien_story_library.yaml`. This document adds the step
contracts, the phase order, and the fences. Design authority stays
with Geemo; deliver each phase as a discrete change and stop for
review. Report status, questions, and schema objections to
`GPT/story/celarien_status.md` in the SUPERVISOR style.

## What this is

A Firefly-shaped series: the ship Celarien as standing set, an
ensemble crew with fixed tensions, episodic waystones (ports, games,
pirates, crew conflicts, thresholds), and a slow background pressure
(the sea empire falling to the land kings) that oscillating chapter
fortunes ride on top of. Three structural equations drive the design:

1. situation = chapter frame — one hexagram per chapter, drawn from
   the chapter class's family (see chapter_classes in the library)
2. the drawn moving lines (3–5) = the chapter's beats, in line order
3. flipping those line bits = the derived situation — which fills the
   spread's `arriving` position and the ship's device's voice

## Boundary with the corpus/pulse work — read this first

This series is a SEPARATE body of work from the corpus DB and distill
pipeline. Do not merge them, reference them, or "helpfully" unify
schemas in any phase below:

- Celarien "beats" are the chapter-scoped abstract dramatic movements
  that word already legitimately names in story_beats. They are NOT
  pulses. The pulse vocabulary must not appear in celarien steps.
- The celarien library is NOT the corpus store. No celarien step
  reads or writes `db/story/` in any phase here.
- Whether distilled corpus weights ever inform the arc generator is a
  future Geemo decision, out of scope.

## Invariants — do not violate

- **Hygiene (hard rule).** Everything under an `internal:` key,
  every hexagram id, family list, LEPA term, and spread position name
  is planning vocabulary — never in a generator prompt or output.
  Render only `text:` fields, world_bible render lines, situation
  phrasing from iching_situations.yaml, the Two Questions, and the
  goal-stone words. Same enforcement point as always: the directive
  builder strips as it strips planner meta. No exceptions.
- **No inheritance protocol.** There is no chapter-to-chapter state
  passing, no exports block, no runtime handoff. The
  novel_arc_generator authors ALL chapter spines in one deterministic
  pass. Persistent facts are planned facts; improvised facts are
  chapter-local color (the world_bible doctrine block states this;
  directives must carry the generator-facing version of it).
- **Determinism.** novel_arc_generator uses no LLM. One seed (author
  description hash), one casting, whole arc. Same seed → identical
  chapters block, byte for byte.
- **Chapter contract is law.** Invariant breach (crew death, voyage
  unviable, extra named character, second aperture) is a regeneration
  trigger, not a drift note.
- **Data + override, not recipe edits.** Tunables land in the
  override files against reasonable defaults. The only recipe change
  permitted is inserting the new steps. Gates default off:
  `use_celarien_arc: false` until Geemo flips it.
- **No edits to the library or the iching data files.** Schema
  problems are reported to celarien_status.md, not silently fixed.

## Phases (discrete changes, in order — stop after each)

**Phase 1 — loader + validation.** Load celarien_story_library.yaml
where the other `data/` libraries load. Validate: every id in every
chapter_classes family exists in iching_situations.yaml; spread
source strings parse against the known sources (chain, spine, cast,
contract, pool); chapter_contract fields present; pool entries carry
`text:`. Fail loudly. No behavior change anywhere. Report.

**Phase 2 — novel_arc_generator.** New deterministic step, gated on
`use_celarien_arc`. Inputs: author description (UI textarea), chapter
count and class sequence (params; default a policy that cycles
classes with threshold chapters at act boundaries), act scaffold
(the four goal stones). Per chapter, seeded: draw the situation from
the class family, draw 3–5 moving lines, compute the derived
situation by bit-flip, draw the fortune point on an authored
mean-reverting curve that also carries the landward trigram drift
across acts, assign the planned passenger if any. Emit the complete
`chapters:` block in the record format documented at the bottom of
the library, as an artifact (do not write into the data file). Every
field reproducible from the seed. Report with one full sample arc.

**Phase 3 — spread assembler + directive builder.** Per chapter, fill
the nine positions from their declared sources, then build the
generator directive: render-safe fills only, pools drawn per chapter
class, aperture rendered per the aperture block (oracle voices
shield-side as prophecy; underworld walks the sword-side with the
katabasis shape), the doctrine line about chapter-local color
included generator-facing. The directive is assembled by the recipe —
no hand-authored per-chapter prompts anywhere. Submission to
whichever generator pipe is active goes through the existing callLLM
paths unchanged. Report with one full sample directive.

**Phase 4 — audit + tests.** Extend state_extractor for celarien
runs: audit against the pre-planned spread (success criterion,
invariants, tip landed), regeneration trigger on invariant breach,
no propagation of actuals into any later chapter's plan. Tests:
(a) determinism — same seed, identical arc; (b) transformation —
every drawn line-set's bit-flip resolves to a valid situation;
(c) leak — with gates on, directives and outputs contain no
internal vocabulary, hexagram ids, position names, or LEPA terms;
(d) gates-off — defaults untouched, all existing pipelines
byte-identical to current behavior. Report.

## Open items for Geemo (ask in celarien_status.md, do not decide)

- Crew names: cast.captain.name is a placeholder; the Amazons are
  unnamed. Geemo names the crew.
- The acts block is a default proposal (four goal stones, one per
  act). Confirm or replace before Phase 2 hard-codes the scaffold.
- The katabasis grammar addition to dramatic_grammars.yaml: propose
  the entry in the status file for review; do not add it unilaterally.

## Out of scope

No UI work beyond exposing the new params, no corpus/pulse
integration, no changes to the jim/spy/chicago/new_orleans/strong
libraries or their recipes, no gate flips, no edits to any data
file, and no renaming of existing steps.
