# session.generate — stop markers, KV cache, cross-call isolation

The rules for `~/pipeline/mlx/session_api.coffee`'s `session.generate`.
Two invariants that took several sessions to get right.

## Invariant 1 — every call starts with a fresh KV cache

`session.generate` disposes `llm.kvCache` (if present) BEFORE running:

    mx.dispose?(llm.kvCache) if llm.kvCache
    llm.kvCache = null

Without this, back-to-back generate calls on the same session inherit
the previous prompt's attention state. Symptoms of the bug (fixed
2026-08-06): later per-group KAG outputs referenced content from
earlier groups even though prompts were rendered per-group.

`session.embed` already disposed before/after; `generate` did not.
Now both do. Any caller that wants a persistent cache across turns
must manage it explicitly — the default is isolation.

## Invariant 2 — stop markers are `<|endoftext|>` and `</s>` ONLY

`STOP_MARKERS = ['<|endoftext|>', '</s>']`.

**`<|im_end|>` is NOT in the list, deliberately.** It's a Qwen
chat-template turn delimiter, not a true end-of-generation signal.
A model trained/adapted on chat-format data emits it at natural
paragraph breaks. Halting there truncates letters to their first
paragraph. Callers who want chat-turn stopping can post-process
raw text; generation itself doesn't stop on it.

The two markers in the list are model-signalled "I'm out of
content." Honoring them saves tokens and keeps trailing garbage
out of the raw text.

## Invariant 3 — never truncate to empty

`MIN_CONTENT_BEFORE_STOP = 16` (non-whitespace chars).

If a stop marker appears in the rolling 32-char tail BEFORE 16
non-whitespace chars have been generated, the marker is ignored:
the tail is blanked (so the same marker doesn't retrigger every
iteration) and generation continues. Only after the model has
produced real content is a stop marker honored.

This exists because LoRA adapters can shift the model's stop-
emission distribution so far that `<|endoftext|>` becomes the
FIRST-token choice. Without this guard, adapter runs truncate to
empty rawText. With it, mildly-overtrained adapters recover; truly
tipped-over adapters still fail (see
[[overtraining_notes]] under `GPT/lora_ite/`).

Every ignored early stop is logged to stderr as:

    [session.generate] ignored N early stop-marker(s) (adapter-quirk?):
       [{"marker":"<|endoftext|>","atToken":3,"contentSoFar":4}, ...]

That log line is the diagnostic signal for adapter overtraining.
Growing counts across iter checkpoints = the adapter is tipping.

## Truncation after honored marker

When a stop marker IS honored (post-MIN_CONTENT_BEFORE_STOP), the
rawText is sliced at the marker's position — trailing garbage
after `<|endoftext|>` (repeated prompt echoes, etc.) is dropped.
Guaranteed non-empty by construction.

Returned `stopMarker` field is `null` when maxTokens capped the
run, otherwise the marker string that was honored. Probes and
`generate_diary_with_adapter_ite`'s meta include this.

## Do NOT re-add

- `<|im_end|>` to `STOP_MARKERS`. Documented as removed 2026-08-08.
- Any zero-tolerance early-stop path. `MIN_CONTENT_BEFORE_STOP` is
  the floor; if you want tighter behavior for a specific caller,
  make it a per-call option, not a default.
- KV cache PRESERVATION across calls without an explicit opt-in.
  Default is isolation for a reason (see Invariant 1 above).
