<!-- 2026-08-22: model paths under $MODELS supersede any `build/model[4]` mentions below. See ~/pipeline/GPT/model_paths.md for the current convention. -->

# Save Good Adapter — preserve winning LoRA checkpoints

Shipped 2026-08-10. Green "Save Good Adapter" button next to
Launch/Kill. One-click way to bookmark a LoRA checkpoint that
generates well, kept beside the pipe's other training output so
future runs in the same pipe can be compared against a known-good
baseline.

## Flow

1. User clicks **Save Good Adapter**.
2. Browser `prompt()` asks for a name. Name must match
   `/^[A-Za-z0-9._-]+$/` and cannot be `.` or `..` — server rejects
   otherwise.
3. Server reads the active pipe's `experiment.yaml`, walks steps
   in declaration order, picks the FIRST step whose
   `adapter_path:` is a non-empty string. That's the "current
   adapter."
4. Server resolves the adapter path (absolute or `CWD`-relative),
   locates the sibling `adapter_config.json`, and copies both
   into `<pipe>/build/good_adapters/<name>/` along with a
   `meta.json` provenance record.
5. UI shows source step/path and destination path.

## Selecting a saved good adapter

The `adapters` dropdown source (in `loadDropdownOptions`) enumerates:

1. The pipe's own `build/adapter*` dirs (the "current" adapter path).
2. Each numbered checkpoint under those dirs (labeled `... @<step>`).
3. Every directory under `build/good_adapters/` that contains an
   `adapter_config.json` — labeled `★ good: <name>`.

Selecting a good-adapter entry writes the value
`build/good_adapters/<name>` into the step's `adapter_path`. It's
a pipe-CWD-relative path just like the numbered checkpoints, so it
resolves the same way at inference time.

## What lands on disk

    <pipe>/build/good_adapters/<name>/
      adapters.safetensors      # copy of the source .safetensors
      adapter_config.json       # copy of the sibling config
      meta.json                 # provenance:
                                #   saved_at, saved_as
                                #   source_pipe, source_step
                                #   source_adapter_path (as declared)
                                #   source_weights_abs (resolved)
                                #   source_config_abs

The weights are copied as `adapters.safetensors` regardless of
the source filename — that's the canonical name inference
loaders (`session_api`, `applyLoRA`, `loadAdapter`) look for when
given a directory instead of a specific `.safetensors` file. So
`build/good_adapters/<name>/` is usable directly as an
`adapter_path:` value in a future run.

## Guardrails

- **Refuses to overwrite.** If `build/good_adapters/<name>/`
  already exists in the current pipe, returns 409 with a message
  pointing at the existing dir. Delete manually and retry to
  replace.
- **Name validation is strict** — no slashes, no dots except
  literal `.`, no shell-special chars. This lets `<name>` be
  used directly as a filesystem path segment without escaping.
- **No experiment.yaml → no save.** The button needs the pipe to
  have run at least once (so `experiment.yaml` is materialized).
- **First adapter wins.** If multiple steps set `adapter_path`,
  only the first (by yaml declaration order) is saved. This is
  the common case; a pipe with two adapters is unusual and
  should probably be split.

## Why per-pipe (the load-bearing reason)

An adapter is a delta on ONE specific base model's weights. It
carries hard dependencies on that base's tensor shapes, layer
count, hidden size, tokenizer, and quantization scheme. Loading
an adapter against the wrong base either errors on shape
mismatch or, worse, "succeeds" (partial name matches) and
silently produces garbage.

The base model lives in the pipe (`<pipe>/build/model4/` and
friends). Every checkpoint under `<pipe>/build/adapter/` was
trained against THAT base and only makes sense there. A good
adapter has to stay close to its mommy model.

`pipes/good_adapters/` as a shared root was tempting — one place
to browse all winners — but it hides the model-adapter binding
and makes it easy to point a pipe with the wrong base at a good
adapter that will fail (or silently misbehave). Per-pipe storage
makes the binding structural: the adapter is inside the pipe
that owns the base it was trained against, and the dropdown only
ever surfaces adapters compatible with the current model.

Secondary bonuses that fall out for free: cloning or rsyncing a
pipe carries its good adapters along; each pipe has its own
namespace (no "jim-2000" collisions between the story and diary
pipes); no shared-directory naming coordination between
concurrent training runs on different pipes.

## Files

- Route: `handleSaveGoodAdapter` in `~/writer/ui_server.coffee`
  and mirrored in `~/pipeline/ui_server.coffee`.
- Button + JS handler: near Launch/Kill in `~/writer/ui/index.html`
  and mirrored in `~/pipeline/ui/index.html`.
- Dropdown source append: `loadDropdownOptions('adapters')` in
  both ui_server copies.
