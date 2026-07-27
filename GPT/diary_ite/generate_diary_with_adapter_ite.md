Step: `generate_diary_with_adapter_ite`
Recipe: `diary_ite`

Purpose:
- generate final diary text with the trained adapter

Inputs:
- artifact `story_parts`
- artifact `diary_prompt_text`
- params `quantized_model_dir`, `adapter_path`

Adapter picker (added 2026-07-27):
- `adapter_path: [ UI_dropdown, adapters, build/adapter ]` — same directive
  `prompt_llm` uses. The `adapters` source (ui_server `loadDropdownOptions`)
  lists every `build/adapter*` dir in the pipe that has an `adapter_config.json`,
  plus a `(base)` option; default `build/adapter`. Pick any adapter per run
  without editing yaml.
- Empty value (`(base)`) generates with NO adapter — the underlying
  `generate_diary_event_ordered_ite` treats an empty/whitespace `adapter_path`
  as base (same rule as `session_api`). The step name (`*_with_adapter_*`) still
  selects `mode: 'adapter'`, so a genuinely missing (null) param still errors.

Checkpoint selection (added 2026-07-27):
- `train_lora`'s `saveEvery` writes numbered checkpoints (`NNNNNNN_adapters.
  safetensors`) as FILES inside `build/adapter/`, alongside the final
  `adapters.safetensors`. The dropdown now surfaces each checkpoint as its own
  option — `adapter (current)` (= the final `adapters.safetensors`) plus
  `adapter @100`, `adapter @200`, … — so you can A/B training-step depth in the
  diary, not just the final adapter.
- Mechanism: a checkpoint option's `adapter_path` is the `.safetensors` FILE
  path (e.g. `build/adapter/0000100_adapters.safetensors`). `session_api`
  detects a `.safetensors` adapterPath and loads that file against the parent
  dir's shared `adapter_config.json` (via `loadAdapter(configDir, wrapped,
  weightsPath)` in `mlx/lora/wrap.coffee`). A dir path keeps the old behaviour
  (loads `adapters.safetensors`).
- Gotcha: stale numbered files from earlier short runs (e.g. `0000005_…` from a
  5-iter smoke) also appear as `adapter @5`. Delete the file to drop it.
- UI note: the dropdown options are built server-side, so the UI server must be
  restarted to see newly listed checkpoints; the loader change lives in
  node_modules and applies on the next run.

Outputs:
- artifacts `diary_adapted_raw`, `diary_adapted_meta`, `diary_adapted_text`
- optional file save `diary/diary_HH_MM.adapter.txt`

Invariants:
- this step does not depend on `generate_diary_without_adapter_ite`
- both diary generators are sibling consumers of `build_diary_prompt_ite`

Error reporting:
- when `diary_prompt_text` is invalid, report the actual resolved values and sources
- do not hide graph/config errors behind a bare type check
