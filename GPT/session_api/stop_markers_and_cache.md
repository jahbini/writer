# session.generate — stop markers, KV cache, cross-call isolation

Rules for `~/pipeline/mlx/session_api.coffee`'s `session.generate`.
Updated 2026-08-09 after the adapter-empty-generation session.

## Invariant 1 — every call starts with a fresh KV cache

`session.generate` disposes `llm.kvCache` (if present) BEFORE running:

    mx.dispose?(llm.kvCache) if llm.kvCache
    llm.kvCache = null

Without this, back-to-back generate calls on the same session
inherit the previous prompt's attention state. Symptoms of the
bug (fixed 2026-08-06): later per-group KAG outputs referenced
content from earlier groups even though prompts were rendered
per-group.

`session.embed` already disposed before/after; `generate` did not.
Now both do. Any caller that wants a persistent cache across turns
must manage it explicitly — the default is isolation.

## Invariant 2 — STOP_MARKERS

    STOP_MARKERS = ['<|endoftext|>', '</s>', '<|im_end|>']

**`<|im_end|>` is now IN the list**, restored 2026-08-09. Earlier
notes claimed it was permanently removed because it truncated
letters to their first paragraph. That was correct AT THE TIME —
the `MIN_CONTENT_BEFORE_STOP` counter (Invariant 3) had a bug that
made the guard non-functional, so `<|im_end|>` in the list DID
truncate at every paragraph break. With the counter fixed and the
library EOS shortcut neutralized on adapter runs (see
[[eos_shortcut_and_adapter]]), `<|im_end|>` in the list is now
correct: early emissions are ignored by the guard, later ones are
honored as clean stops.

Order in the list is search order. `<|endoftext|>` and `</s>` are
true "I'm out of content" signals; `<|im_end|>` is a chat-turn
delimiter that adapters treat as EOT. All three, once past the
guard, terminate the loop cleanly.

## Invariant 3 — never truncate to empty (counter FIXED)

`MIN_CONTENT_BEFORE_STOP = 16` (non-whitespace chars, EXCLUDING
stop marker text).

If a stop marker appears in the tail before 16 non-marker
non-whitespace chars have been generated:

- The marker is ignored.
- Its text is spliced out of `chunks` so it can't reform in later
  iterations.
- The rolling tail is blanked.
- Generation continues.

**The counter previously counted marker chars.** `<|endoftext|>`
is 13 non-ws chars; a single such piece vaulted `contentSoFar`
from 3 to 16+, defeating the guard before it could protect
anything. The fix is `realContentChars()`:

    realContentChars = ->
      joined = chunks.join ''
      joined = joined.split(m).join('') for m in STOP_MARKERS
      n = 0
      n += 1 for ch in joined when /\S/.test(ch)
      n

Called only when a marker fires (rare). Excludes every
STOP_MARKERS occurrence from the count. Only true prose contributes
to the 16-char floor.

**Signal it's working:** every ignored early stop is logged to
stderr as:

    [session.generate] ignored N early stop-marker(s) (adapter-quirk?):
       [{"marker":"<|im_end|>","atToken":3,"contentSoFar":4}, ...]

That log line is the diagnostic that (a) the guard fires when it
should, (b) tells you at what token count and what the model
actually had produced. Watch it grow across iter checkpoints as a
proxy for how "hot" an adapter has become.

## Truncation after an honored marker

When a stop marker IS honored (post-guard), rawText is sliced at
the marker's position — trailing garbage after `<|endoftext|>`
(repeated prompt echoes, etc.) is dropped. Guaranteed non-empty
by construction of the guard.

Returned `stopMarker` field is `null` when maxTokens capped the
run, otherwise the marker string that was honored. Probes and
`generate_diary_with_adapter_ite`'s meta include this.

## Interaction with the library-level EOS shortcut

The library at `@frost-beta/llm/dist/base.js:248` will break its
own generator loop the instant `nextTokens.indexOf(eosToken) > -1`
— BEFORE yielding the token. For Qwen3, `eosToken` is
`<|im_end|>`. On adapter runs, `session_api.createSession`
overrides `tokenizer.eosToken = -1` so the library never
shortcuts and our text-layer machinery is authoritative.

If you ever see the guard's `ignored` log lines missing on a run
that should have fired them, the first suspect is that the
override didn't apply — check startup log for
`[session_api] eos shortcut neutralized`. See
[[eos_shortcut_and_adapter]].

## Do NOT re-remove

- `<|im_end|>` from `STOP_MARKERS`. Was removed once, restored
  2026-08-09 with a working guard. Do not remove again without
  first confirming the counter fix is intact and the library-EOS
  neutralization is present on adapter paths.
- Any zero-tolerance early-stop path. `MIN_CONTENT_BEFORE_STOP`
  is the floor; if you want tighter behavior for a specific
  caller, make it a per-call option, not a default.
- KV cache PRESERVATION across calls without an explicit opt-in.
  Default is isolation for a reason (see Invariant 1).

## Cross-refs

- [[eos_shortcut_and_adapter]] — the library-level shortcut and
  why adapter sessions need it neutralized.
- [[../lora_ite/overtraining_notes]] — the underlying training-side
  cause of the "adapter emits `<|im_end|>` immediately" problem.
- [[../lora_ite/checkpoint_selection]] — why loss can't tell you
  which adapter checkpoint is safe.
