# Cast archetype scrub + protagonist promotion

Two-part fix in `story_outline` → `story_spine` handoff. Shipped
2026-08-08 after a shutdown incident.

## The problem

`story_outline`'s LLM sometimes returns `cast.protagonist_label`
(and antagonist/witness) set to an ARCHETYPE KEY rather than a
character name — literally the string `"executor"` or
`"adversary"` or `"beneficiary"`. This is the LLM confusing "here
is the archetype slot" with "here is the character's name."

Downstream `story_spine` uses the labels as if they were character
names when rendering beats. An archetype key in that position
produces beats about "the executor decides..." — nonsense masking
as story.

## Fix, part 1 — the scrub

In `pipes/story/scripts/story_outline.coffee` after the LLM parse:

Any `cast.{protagonist,antagonist,witness}_label` whose value
matches an archetype key from the LEPA archetype set gets
**nulled**. The archetype key itself is retained separately as
`cast.{role}_archetype` (that's real information — the LLM's
archetype-slot intent). Only the LABEL is scrubbed.

Keys currently in the archetype set: executor, adversary,
beneficiary, mentor, herald, shapeshifter, guardian, trickster,
shadow. Additions here should also land in
[[lepa_integration]].

## Fix, part 2 — protagonist promotion

The scrub often left `outline.protagonist` empty (because the LLM
put the archetype in `cast.protagonist_label` and left the
outline's top-level `protagonist` unfilled). Downstream can't
work with that.

If `outline.protagonist` is empty AND `unresolved_cast[0]?.name`
exists, promote `unresolved_cast[0].name` to `outline.protagonist`.
Reasoning: the LLM emits the actual character it's thinking about
in `unresolved_cast` while trying to also fill archetype slots.
The first unresolved-cast entry is a strong signal of "the person
this story is about."

## Fix, part 3 — spine relaxation

`pipes/story/scripts/story_spine.coffee`'s `outlineIsUsable`
originally hard-required `cast.protagonist_label`. That was too
strict — the outline is usable if EITHER `cast.protagonist_label`
OR non-empty `outline.protagonist` is present. The existing spine
code path already falls back correctly:

    lbl = outline.cast?.protagonist_label ? outline.protagonist

So relaxing the gate was the whole change; no downstream logic
needed to move.

## Why this shape

Alternatives considered and rejected:

- **Re-prompt the LLM until it fills the label correctly.** Adds
  latency and tokens; failure rate high enough that this became
  the dominant retry cost.
- **Insert the scrub inside story_spine.** Scattering
  outline-schema knowledge across scripts is worse than fixing it
  at the producer.
- **Change the LLM prompt to distinguish archetype from label.**
  Tried; the model still conflates on ~1/5 of runs. The scrub is
  the belt for the prompt's suspenders.

## Guardrails

- **Do not** silently drop `unresolved_cast[0]` when promoting;
  keep it in the list. Some downstream steps read the full cast.
- **Do not** widen the archetype key set without updating
  [[lepa_integration]]. A key added here that isn't a real
  archetype will incorrectly null a real character name.
- **Do not** promote from `unresolved_cast[1..]`. The ordering is
  meaningful; the first entry is the protagonist candidate.
- If the shutdown reappears with a different missing field
  (e.g. `antagonist_label`), the fix is the same shape — relax
  `outlineIsUsable`, don't strengthen the scrub.

## Files

- `~/writer/pipes/story/scripts/story_outline.coffee` — scrub +
  promotion.
- `~/writer/pipes/story/scripts/story_spine.coffee` — relaxed
  `outlineIsUsable`.
- Archetype set of record: LEPA docs under `GPT/lepa-ite/`.
