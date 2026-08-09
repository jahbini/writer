# LoRA overtraining — the amplitude story

Consolidated 2026-08-09 after a full session's investigation of the
Aug 8 broken adapter run. Supersedes the earlier framing ("cap at
~20 iters") which was superficial.

## The variable that actually matters is EFFECTIVE DISPLACEMENT

Effective displacement of the LoRA delta from init is proportional
to `learning_rate × steps × ‖gradient‖`. The failure mode we call
"overtraining" is really "amplitude too high, wherever that comes
from." Two dials both drive it:

- **Learning rate.** July 30 working config: `lr = 1e-5`. Aug 8
  broken config: `lr = 2e-4`. Ratio: **20×**. Every checkpoint from
  the Aug 8 run is unusable at every step because the delta blew
  past the OOD-safe amplitude before checkpoint 100 was even saved.
- **Iters.** At the small lr, the July 30 config gave usable
  adapters up to ~20 iters and started tipping past that.

Same underlying problem, two levers. When diagnosing "empty
generation," always check the training-command's `learning_rate`
FIRST — it's the biggest lever and the easiest to misconfigure.

## Why the damage concentrates on `<|im_end|>` emission

The most consistent gradient signal in the corpus is not Jim's
voice — it is `<|im_end|>`. Every one of 888 training rows ends
with it. It is the one token whose correct prediction is never
contradicted anywhere in the corpus. Style signal is diffuse and
high-entropy; EOT signal is unanimous.

Gradient descent with a big step size spends the adapter's tiny
budget — rank 8, qProj/vProj only, layers 28–35 — on the steepest
consistent direction first. At `lr = 2e-4`, even 100 steps carves
"emit `<|im_end|>`" deeply into that low-rank subspace. At
`lr = 1e-5`, the same direction gets learned 20× more gently. The
delta stays small enough that the base model dominates OOD
contexts and you get generation with voice tinting — which is
exactly what the July 30 adapters did.

## Why validation loss lied

`valid.jsonl` is the same shape as `train.jsonl`: bare Jim prose
≤ 640 tokens, ending in `<|im_end|>`. That is **in-distribution
by construction.** On in-distribution input, the deeply-carved
EOT direction is aligned with the correct answer, so loss looks
healthy (measured 3.7624 on step 100 of the broken run).

The damage manifests only OUT-of-distribution — real usage is
ChatML wrap + long structured directive. There the adapter's
features fire spuriously and the deepest-carved behavior wins:
instant `<|im_end|>` → empty output. **Validation loss cannot
detect this** because it never leaves the in-distribution
manifold.

Do not trust val loss alone for checkpoint selection. See
[[checkpoint_selection]].

## Signals to watch during training

- `train_loss` dropping fast + `val_loss` also dropping is not the
  signal we thought. It only means "adapter is fitting the
  in-distribution row shape well."
- The absent signal — the one that would predict this failure — is
  "does a generation probe against the real inference-time prompt
  still produce coherent output." Loss cannot answer this. Only a
  generation probe can. See [[checkpoint_selection]].

## Runtime mitigations (partial, downstream of amplitude)

Three fixes shipped in `~/pipeline/mlx/session_api.coffee`. They
are correct independently and necessary for any well-trained
adapter to work with our loaders, but none of them cures an
over-amplitude adapter. See
[[../session_api/stop_markers_and_cache]] and
[[../session_api/eos_shortcut_and_adapter]].

## The durable fix

1. **Retrain at the small learning rate (1e-5).** Not superstition
   — the correct operating point. Confirmed working July 30.
2. **Replace loss-based checkpoint selection with a generation
   probe.** Save-and-keep a checkpoint only if a probe generation
   in the real ChatML+directive context produces non-empty
   coherent output. Detail: [[checkpoint_selection]].
3. **If hot-lr training speed is later wanted back**, the lever is
   reducing the EOT gradient monopoly (masking or downweighting
   the terminal token on some fraction of rows). Optimization,
   not repair — do this AFTER a low-lr adapter is proven working.

## Cross-refs

- Fidelity check that ruled out save/load defects: `scripts/adapter_fidelity.coffee`
  + `test.sh`. See [[adapter_fidelity_test]].
- Runtime plumbing fixes: [[../session_api/stop_markers_and_cache]],
  [[../session_api/eos_shortcut_and_adapter]].
- Diagnostic journal for this whole hunt: `SUPERVISOR.md` at repo root.
- Training entry point: [[train_contract]].
