Step: `generate_diary_event_ordered_ite`
Recipes:
- `diary_ite`
- used under the existing step names `generate_diary_with_adapter_ite` and `generate_diary_without_adapter_ite`

Purpose:
- generate the diary one event at a time in story order

Inputs:
- artifact `story_parts`
- artifact `diary_kag`
- params `quantized_model_dir`
- optional `adapter_path` (UI dropdown `adapters` in the recipe; empty = base)
- optional `mlx`
- `include_chunk_passages` (default `true`), `chunk_excerpt_chars` (default `700`, `0` = full)

Chunk tactic (2026-07-27) — the "does it help" experiment:
- `buildEventPrompt` now folds each event's matched CHUNKS (Jim's own passages,
  the `chunk_text` on `chosenEntries`) into that event's prompt as a `reference:`
  block, plus a "borrow cadence/texture, never whole sentences or plots" rule.
  Before this, only `keyword: headline` cues were passed (`renderKagLines`); the
  passages were collected but dropped.
- Keyed off the diary steps: one reference group per event, from that event's
  matches (deduped, each clipped to `chunk_excerpt_chars` via `clipText`).
- A/B: `include_chunk_passages` is a **UI checkbox** (`[ UI_checkbox, true ]` on
  both generate steps in `diary_ite.yaml`) — check = chunks on, uncheck =
  cues-only (the old behaviour). No yaml/override edit needed. The step logs
  `chunk passages: on/off` so you can confirm which ran. This is the ONLY place
  the tactic reaches the event-ordered output — `build_diary_prompt_ite`/
  `diary_prompt_text` is not consumed here.
- If passages make the voice bloviate/ramble, LOWER `chunk_excerpt_chars` or
  `per_event_match_limit` (collect_diary_kag_ite) before turning them off.

Outputs:
- when called as `generate_diary_with_adapter_ite`:
  - `diary_adapted_raw`
  - `diary_adapted_meta`
  - `diary_adapted_text`
- when called as `generate_diary_without_adapter_ite`:
  - `diary_base_raw`
  - `diary_base_meta`
  - `diary_base_text`

Current behavior:
- generates sections in this order:
  - `scene`
  - `arrival`
  - `disturbance`
  - `reflection`
  - `realization`
- uses `diary_kag.events.<kind>.matches` when present
- falls back to scoring flat `diary_kag.entries` only if event matches are absent

Prompt/voice notes:
- surreal ornament is desired in this project
- the main quality risk is not surrealism itself, but repetitive reflective scaffolding driven by prompt pressure
- if sections keep recurring on abstractions like silence, signal, proof, listening, or quiet, inspect the prompt before blaming adapter depth

Adapter-specific rule:
- for sections after the first, add:
  - `Transition naturally from the previous diary section into this event`

Known pitfalls:
- clean generated text must strip MLX fence lines like `==========`
- adapter path is better at local voice than global continuity; this step exists to reduce that structural drift
