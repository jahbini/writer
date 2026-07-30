Step memories for the `story` recipe — an evolution of the shipped
`diary_ite` pipeline that adds a structural planning step (`story_spine`)
between the recipe-selection stages and the diary generator, so a single
prompt produces one chapter (not one diary entry).

Recipe file: `<BASE>/config/story.yaml` — a full copy of
`node_modules/@jahbini/pipeline/config/diary_ite.yaml` with the
`story_spine` step inserted and `story_spine_json` declared as an artifact.

Pipe: `pipes/story/`. Activated by `pipes/story/override.yaml` (`pipeline: story`).

Pipeline graph:

```
load_library              → story_library
select_story_recipe       → story_recipe          (legacy 5 beat dropdowns)
resolve_story_parts       → story_parts
collect_diary_kag_ite     → diary_kag             (embeddings; SLOW ~30s)
build_diary_prompt_ite    → diary_prompt_text
generate_diary_without_adapter_ite  → diary_base_*  (MLX call #1)
story_spine               → story_spine_json      (MLX call #2 — Phase 1 sidecar)
```

The first four are deterministic. `generate_diary_without_adapter_ite`
is the shipped narrative generator (excellent quality, ~30s). `story_spine`
is the new structural planner — no prose, JSON only, temperature 0.05.
Both LLM calls share the getSession cache and must be serialized (see
`story_spine.md` "Session sharing" section).

Phase 1 (2026-07-31): `story_spine` produces `story_spine_json` but
nothing downstream consumes it yet.

Phase 2 (planned): extend `build_diary_prompt_ite` to fold
`story_spine_json.scenes` into `diary_prompt_text` so the generator
produces a chapter that honors the structural plan.

Conventions:
- The atoms library at `pipes/story/data/jim_story_library.yaml` carries
  a `story_atoms:` block (5 axis lists × 10 entries + 4 lenses). It also
  keeps the legacy `library:`, `stories:`, `arc_shapes:`, `time_of_day:`,
  and `recipe_defaults:` blocks so the shipped `load_library` step's
  assertions still pass.
- Sacred steps only. `action: (S) ->`, `await S.need`, `S.param`,
  `S.callLLM` (in-process node-mlx — do NOT use `S.callMLX`, which is
  the Python subprocess path and is 10× slower for structured output).
- Runtime tuning lives in a nested `llm:` block on each MLX step: keys
  are camelCase (`maxTokens`, `temperature`, `topP`, `systemPrompt`).
  Ledger auto-injects them into the callLLM payload.
- `build/model4` is a symlink chain: `pipes/story/build → ../../build`
  → `~/writer/build/model4 → /Users/jahbini/writediary/pipes/diary/build/model4`.
  This repo does not ship model weights.
