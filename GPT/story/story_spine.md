Step: `story_spine`
Recipe: `story`
Script: `pipes/story/scripts/story_spine.coffee`

## Purpose

Sacred structural planner. Converts eight atom selections into a
strict JSON plan a future prose stage will expand into one chapter.
Contains no prose. Never invents a different story, never "improves"
it, never solves it.

Phase 1 (2026-07-31): sidecar — produces `story_spine_json` but nothing
downstream consumes it yet. `generate_diary_without_adapter_ite` still
handles the narrative output.

## Inputs

Artifact:
- `story_parts` — resolved from the legacy 5-beat selection. Only used
  as context in the prompt (first 2000 chars of pretty-printed JSON).

UI dropdowns (8), all backed by `data/jim_story_library.yaml/story_atoms/*`:

- `protagonist` (required), `antagonist`, `witness` — characters list
- `external_problem`, `internal_obstacle`, `missed_opportunity`,
  `primary_consequence` — dramatic axis, one atom from each list
- `lens` — one of `mind_worm | tarot_major_arcana | four_forces | i_ching_hexagram`

Runtime config (nested `llm:` block on the step):
```yaml
quantized_model_dir: build/model4
llm:
  maxTokens: 4000       # 2000 truncated mid-scene in the failing run
  temperature: 0.05     # near-deterministic; see "Sampler gotcha"
  topP: 0.95
```

## Output

Artifact `story_spine_json` → `out/story_spine.json`. Four top-level
sections — `story`, `questions`, `causal_spine`, `scenes`. Full contract
in `pipes/story/schemas/story_spine.schema.json`. In-step validation is
only a shape check (`shapeLooksOk`); full JSON Schema validation is a
Phase 1.5 addition if the model regularly emits invalid shapes.

Confirmed working on 2026-07-31: "The Road That Flickers" — 4 scenes
(establish_need → introduce_opportunity → force_a_decision →
reveal_information), 8 causal steps, 3 central questions, valid
dramatic_axis with canonical phrasing echoed from the atoms.

On unrecoverable failure, saves `{parse_error: true, raw, message}` so
the artifact explains what the model actually produced.

## Prompt

Built inline in `buildPrompt`. Structure:
1. The "Story Spine Generator" contract (never invent / improve / solve).
2. The eight atoms formatted with `id`, `label`, `canonical_phrasing`,
   tags/role_hints in a fixed table. The lens's `interpretive_note` is
   included as its own line.
3. `JSON.stringify(story_parts, null, 2).slice(0, 2000)` as context.
4. The output contract (full JSON shape with an enum for `scene.purpose`).
5. Structural rules (every scene changes state, every scene opens or
   closes a question, id references must resolve, etc.).

## JSON extraction

Reused patterns from writers-guild's `oracle_brief.coffee`:

- `stripMlxFraming` — drops the `==========\n…\n==========\n<stats>` bracket
  the mlx_lm framing adds.
- `findBalancedJson` — walks brace depth ignoring string content, returns
  `{json, truncated}`.
- `repairTruncatedJson` — closes any open string, trims trailing partial
  keys / dangling commas, closes stacked arrays/objects in reverse order.
- `extractJSON` — tries a straight parse; on failure with `truncated:
  true`, attempts repair. On failure with `truncated: false`, gives up
  (the JSON was malformed, not truncated).

Verified against the truncated 2026-07-31 08:11 output: repair
reconstructed a valid spine (4 sections, 3 scenes, 6 causal steps).

## Sampler gotcha

`temperature: 0` triggers a division-by-zero deep inside
`@frost-beta/llm`'s sampler → `Error converting "this" to mx.array` at
`token.tolist()`. Use `0.05` (near-greedy, no numerical edge case) for
reproducibility. `topP: 1.0` also caused problems in some paths; `0.95`
is safe.

## Session sharing (critical)

`mlx/llm_dispatch.coffee` caches LLM sessions by `modelDir::adapterPath`.
Both `story_spine` and `generate_diary_without_adapter_ite` use
`build/model4` with no adapter, so **they share the exact same LLM
object**. Two consequences:

**(a) kvCache stays populated across calls.** `@frost-beta/llm`'s
`LLM.generate` reuses `this.kvCache` when no explicit cache is passed
(`llm.js:100-108`), and shipped `session_api.coffee` `generate()` did
NOT reset it. Consecutive generations position-index against stale KV
state → bad token → `predict/tolist()` crash.

Fix landed 2026-07-31 in `node_modules/@jahbini/pipeline/mlx/session_api.coffee`:
add `mx.dispose?(llm.kvCache) if llm.kvCache; llm.kvCache = null` at the
top of `generate()`, matching what `embed()` already does. **This patch
lives in `node_modules/` and will evaporate on `pnpm install`** — needs
to be sent upstream, and to be re-applied after every install until it
lands there.

**(b) Concurrent generators on the same session race.** If two steps
sharing the session run in parallel, one's reset can null the other's
cache mid-flight → `Error converting "this" to mx.array` at
`base.js:231` (inside the prefill `mx.core.tidy` block). Fix: serialize
them in the DAG. `story_spine.depends_on: [resolve_story_parts,
generate_diary_without_adapter_ite]` — story_spine can only run *after*
the diary generator, never in parallel with it.

Rule for future MLX steps: **any two steps that call `S.callLLM` on the
same `modelDir` (with the same adapter, or both without one) MUST have
an explicit `depends_on` edge between them.** The runner will run
independent steps concurrently by default; the session cache doesn't.

## Retry loop

None. At temperature 0.05 the model output is nearly deterministic;
retrying the same prompt would produce nearly-identical failures. Single
shot; if `shapeLooksOk` fails, save `{parse_error, raw}` and let the
human raise `maxTokens` or edit the prompt.

## Known pitfalls

- The `mlx:` block name is INCORRECT for `S.callLLM` — use `llm:`. The
  `mlx:` block feeds the Python-subprocess path (`S.callMLX`). Mixing
  them is silent: `S.param('llm', null)` returns null, the step falls
  through to `S.param('mlx', null)`, and passes CLI-flag-shaped keys
  (`max-tokens`) that `L.callLLM` doesn't understand → defaults kick in.
- `story_parts` is currently the legacy 5-beat resolution. The atoms
  the step actually reads are the 8 UI selections; `story_parts` is
  just prompt context. When Phase 2 wires the spine into the prompt
  builder, `story_parts` and the atoms both need to survive to the
  chapter.
