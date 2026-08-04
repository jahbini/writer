# spystory recipe

Sibling of `story`, pinned to the `spy` dramatic grammar
(`dramatic_grammars.yaml`). Selectable from the UI recipe dropdown.

## Shape (2026-08-04, post-cleanup)

- **One generator.** `generate_diary_with_adapter_ite` runs by
  default (`depends_on: [build_diary_prompt_ite]`); no
  `generate_diary_without_adapter_ite` step exists in the recipe.
  No `[never]` gates and no override flips.
- **`state_extractor` and `archive_chapter`** depend on the adapter
  step directly (`needs: [diary_adapted_text, ...]`).
- **Artifact registry** carries only `diary_adapted_*` — the
  `diary_base_*` targets were removed with the step.
- **Grammar pin:** `story_beats.grammar: spy` and
  `collect_diary_kag_ite.grammar: spy` are set in the recipe.

## Override (`pipes/story/override/spystory.yaml`)

The override is minimal: pipeline selector + Phase 1 LEPA wiring
(cast_supplement artifact registration, cast_genesis step,
story_spine's cast_genesis dep). No generator flips.

## Why one-generator

Earlier the recipe shipped both generators with the adapter one
gated `depends_on: [never]` and the override flipping it on. That
pattern violated the "never means never" convention (see the
feedback memory), and it produced a real toposort crash when the
override for a given pipeline gated the wrong generator.
`spystory` collapses to the single adapter path so there is no gate
to flip.

If a spy-trained adapter is ever produced and a base-comparison
generator is wanted back, add a second step block with its own
`makes: [...]` and wire a second consumer to it (do NOT introduce a
`[never]` sibling that a downstream `depends_on` points at).

## Blandness notes (from 2026-08-04 autopsy)

Independent of this cleanup, the earlier `spy_run_autopsy` found the
main drivers of bland output were:

1. **UI emotion dropdowns overrode the grammar** — every kind in
   `diary_kag.json` showed `source=ui_override`, so the spy grammar
   contributed nothing to KAG retrieval that run. The knobs are
   sticky between sessions.
2. **KAG corpus is Jim's writing.** There is no spy corpus, so
   passages always sound like Jim.
3. **Generator system prompt says "You are Jim from St. John's."**
   Register bleed is guaranteed regardless of grammar.
4. **State_extractor parse_error** — chapter_state had
   `status=conflict` with no diagnostic beats; continuity signal
   nonfunctional that run.

Levers left for later: rewrite the diary system prompt for spy;
narrow or clear the UI emotion overrides so the grammar's map
drives; investigate the state_extractor parse failure.
