# Checkpoint selection — loss is not enough

Follow-on from [[overtraining_notes]].

## The problem loss can't see

`valid.jsonl` is the same shape as training rows (bare Jim prose
≤ 640 tokens ending in `<|im_end|>`). It is in-distribution by
construction. When an adapter overtrains its EOT direction (see
[[overtraining_notes]]), val loss stays healthy because on the
val set, "emit `<|im_end|>` after a short completion" is often
the right answer. The failure only manifests OOD — real inference
uses ChatML wrap + long structured directives, and there the
same-tuned adapter emits `<|im_end|>` immediately and produces
empty output.

**Val loss is structurally blind to OOD collapse.** Loss-based
best-checkpoint selection (min val_loss) will happily pick an
adapter that generates nothing in production.

## The property we actually need to measure

"Does the adapter still speak when spoken to differently."

Concretely: for each candidate checkpoint, run one generation
against the REAL inference-time prompt (ChatML-wrapped directive)
and count non-whitespace characters in the cleaned output. If
above some floor (say 200 chars for a letter task), the checkpoint
is a candidate. If below, discard.

This is the property loss cannot measure. Any measurement of it
requires actually running the generation loop through the real
prompt shape, with the real inference-time plumbing (chat
formatting, EOS handling, all the fixes in
[[../session_api/stop_markers_and_cache]] and
[[../session_api/eos_shortcut_and_adapter]]).

## Recommended shape

Two options in order of increasing effort:

### Option A — post-train sweep

After training finishes, iterate every saved checkpoint. For each:

- Load adapter through inference-time seam (same as production).
- Generate against the real ChatML+directive prompt.
- Record `{checkpoint, generated_chars, val_loss_at_save, ratio}`.
- Rank by generated_chars first, val_loss second.

Simple. Doesn't change the training loop. Adds runtime after
training but decouples the concerns cleanly. Can be built from
the existing `test.sh` + `scripts/adapter_fidelity.coffee` shape.
See [[adapter_fidelity_test]] for the pattern to fork.

### Option B — inline probe during training

Every `stepsPerEval` (or a new `stepsPerProbe`), after saving the
checkpoint but before continuing, run one generation against the
real prompt. Log the result. Skip-and-keep-training or
save-and-mark depending on operator preference.

More invasive — adds a generation forward pass to the training
loop, which is significantly more expensive than a loss forward
pass. Justified only if you want live signal during training.

**Recommendation for now: Option A.** Least change, decisive
signal, runs on the mac-mini after the retrain finishes overnight.

## Threshold guidance

Rough floors for a Jim-letter task (~5 paragraphs expected):

- **< 50 chars:** adapter is collapsed. Discard.
- **50–200 chars:** adapter is bleeding — one paragraph then EOT.
  Marginal; usable only if base model is doing most of the work.
- **≥ 200 chars:** adapter is speaking. Keep and rank by val_loss.
- **≥ 800 chars:** adapter is fully coherent. Definitely keep.

These are order-of-magnitude, not calibrated. Any threshold works
better than loss-only for detecting the collapse mode.

## What NOT to select on

- **train_loss** — measures fit to training rows, not generation
  quality. A well-fit adapter can still be over-amplitude.
- **val_loss alone** — same argument, in-distribution blind spot.
- **file size** — safetensors sizes are dominated by tensor
  shapes, not learned content. All checkpoints of a given
  rank/alpha config are the same size.

## When to short-circuit and stop training entirely

If a probe at checkpoint N shows < 50 chars generated on the real
prompt, and checkpoint N-1 showed ≥ 200, the adapter tipped over
between them. Stop training. There is nothing to gain past the
tip point at the current lr; further steps just entrench the
collapsed state.
