# The library-level EOS shortcut, and why adapters need it neutralized

Session finding: 2026-08-09. The reason `MIN_CONTENT_BEFORE_STOP`
was invisible for months and every adapter run produced empty
output.

## The mechanism

`@frost-beta/llm/dist/base.js:248`:

    do {
        // Quit after getting EOS.
        if (nextTokens.indexOf(eosToken) > -1)
            break;
        ...
        yield [...]
    }

The generator loop BREAKS the instant the sampled token id equals
`tokenizer.eosToken` — **before yielding the token**. Our text-layer
STOP_MARKERS scan in `session_api.generate` never runs. Our
`MIN_CONTENT_BEFORE_STOP` guard never runs. The token never
appears in a piece string.

For Qwen3, `tokenizer_config.eos_token = "<|im_end|>"` (id 151645).

## Why adapters trip this

Training rows are assembled by `build_lora_dataset_ite` as:

    prompt + "\n\n" + completion + tokenizer_config.eos_token

which for Qwen3 puts a `<|im_end|>` at the end of every row. The
adapter learns "emit `<|im_end|>` when the completion is done."
An over-amplitude adapter (see [[../lora_ite/overtraining_notes]])
learns this so strongly that `<|im_end|>` is the FIRST-token choice
in many contexts.

Library shortcut then halts generation on token 1. Zero characters
returned. Every downstream stop-machinery is bypassed.

## The neutralization

In `session_api.createSession`, right after tokenizer construction:

    if opts.adapterPath? and String(opts.adapterPath).trim().length > 0
      originalEos = tokenizer.eosToken
      tokenizer.eosToken = -1
      console.log "[session_api] eos shortcut neutralized (was #{originalEos}); text-layer STOP_MARKERS now authoritative"

Setting `eosToken = -1` makes `base.js:248`'s
`nextTokens.indexOf(-1) > -1` always false — token ids are always
non-negative. The library never shortcuts. Every token gets
yielded. Our text-layer machinery becomes authoritative.

**Only applies when an adapter is loaded.** Non-adapter runs keep
the library's shortcut active — ChatML behavior stays exactly as
before, no risk to existing callers.

## What has to come with it

Fix 2 (this file) alone would generate forever. Two companions:

1. **`<|im_end|>` back in STOP_MARKERS** (see
   [[stop_markers_and_cache]]). With the library shortcut gone,
   we need a text-layer signal to stop. `<|im_end|>` is the
   adapter's honest "I'm done" signal — honor it, but only after
   the guard confirms real content.
2. **`MIN_CONTENT_BEFORE_STOP` counter fixed** (also
   [[stop_markers_and_cache]]). Excluding marker chars from the
   count is what makes the guard actually protect against early
   emissions.

All three fixes together: adapter's early `<|im_end|>` is
swallowed; generation continues; later `<|im_end|>` (after ≥ 16
non-marker chars) is honored; clean stop, non-empty output.

None of the three, individually, works. They are a matched set.

## Signal it's working

Startup log gains one line per adapter session:

    [session_api] eos shortcut neutralized (was 151645); text-layer STOP_MARKERS now authoritative

If you don't see it on an adapter run, the neutralization didn't
apply (bug or wrong session path).

## What this does NOT fix

An adapter whose amplitude is too high still produces short
output. The neutralization exposes what the adapter WOULD have
generated past `<|im_end|>`; a collapsed adapter has nothing to
say and emits whitespace or degenerate tokens until maxTokens.
See [[../lora_ite/overtraining_notes]] for the amplitude story
and [[../lora_ite/checkpoint_selection]] for how to detect
collapse before shipping.

## Guardrails

- **Do not** neutralize on non-adapter sessions. Base-model chat
  responses depend on the library's EOS to terminate. Removing it
  for non-adapter runs would break every non-adapter caller.
- **Do not** try to disable this in @frost-beta/llm itself. We
  don't own that upstream; overriding `tokenizer.eosToken` from
  the outside is the least-invasive fix.
- **Do** keep the console.log — it's the only external signal that
  the override applied.

## Files

- Source: `~/pipeline/mlx/session_api.coffee` — search
  `eos shortcut neutralized`.
- Installed copy: `~/writer/node_modules/@jahbini/pipeline/mlx/session_api.coffee`.
  Same fix; must stay in sync until upstream release.
- Library file (do not edit):
  `~/writer/node_modules/@frost-beta/llm/dist/base.js:248`.
