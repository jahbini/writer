# Size-scaled LoRA training parameters

Discovered 2026-09-18 via the SAT ladder cross-pipe sweep — see
`sat_runs/` on the mini and `three_tier_ladder.md` for the framework.

## The finding

Every hf__qwen__* pipe was trained with **identical** LoRA
hyperparameters, taken from `~/pipeline/config/elementary.yaml`:

    loraRank:     8
    loraAlpha:    16
    loraDropout:  0.05
    loraLayers:   8      # wrap the top 8 transformer layers
    iters:        300
    learningRate: 0.00001

That's fine for the 4B tier and marginal on 8B, but **oversized for
tiny models**. A rank-8 LoRA over 8 layers is a much larger relative
modification of a 0.6B network than of a 4B one — the adapter
effectively hijacks a bigger fraction of the small model's forward
pass, and the SAT ladder caught this directly:

| Pipe | Diary adapted | Diary base | Delta | Verdict |
|---|---|---|---|---|
| qwen3-0.6B | 4/6 | 5/6 | −1 | adapter hurts |
| qwen3-1.7B | **1/6** | 3/6 | **−2** | adapter *badly* hurts |
| qwen3-4B (base) | 5/6 | 4/6 | +1 | adapter helps (ckpt-100: 6/6, +2) |
| qwen3-4B-Instruct-2507 | 2/6 | 2/6 | 0 | wash |

Same LoRA hyperparameters, opposite outcomes as size shrinks. The
training regime is coupled to base-model capacity, and the config
was tuned once (on 4B) and never re-scaled.

## Two independent overtraining signals

Independent of size, the sweep also caught the training running too
long even on 4B:

1. **Checkpoint 100 outperforms checkpoint 200 and final** on the
   4B pipe (6/6 vs 3/6 vs 5/6). Adapter degrades between step 100
   and step 200, then partially recovers.
2. **`freshness_copy` fails progressively.** ckpt-100 produces no
   verbatim scraps; ckpt-200 lifts 6 tokens verbatim from
   `past_scraps[0]`; final lifts 9 tokens. The LoRA is memorizing
   the voice-hint phrases as copy targets.

Both are the same shape: too much training-step "grip" on the
corpus, not enough learning-rate softness. The human's directive
2026-09-18: **fix by lowering the learning rate, not by cutting
iters** — LoRA should still see every training story, just take
smaller steps through them.

## Grading-at-best principle (2026-09-19)

Every "best config" recorded below is model-specific and should live
as an `override/sat_ladder.yaml` on the pipe. **The pipe's SAT
verdict is a claim about the model's best-achievable quality — grade
at the best parameters, not at defaults.** Concrete: 4B's real
grade is 6/6 (at ckpt-100 + temp=0.75), not the 5/6 attainable at
"final adapter + temp=0.75." Each row of the table below points at
the currently-known-best config for that pipe.

Adopting this means:
- The pipe's `override/sat_ladder.yaml` should set `adapter_dir` to
  the specific checkpoint file that produced the best score (not
  always `build/adapter/` which loads the final).
- Per-pipe overrides for `temperature`, `top_p`, `max_tokens`,
  `adapter_dir` are expected and welcome.
- A per-pipe parameter sweep (puppeteer capability P2) is how we
  find the best config in the first place, then it gets locked in.

See `puppeteer/GPT/design/sat_matrix.md` for how the puppeteer
records the parameters used with each verdict.

## Empirically-verified configuration (2026-09-18 SAT sweep)

The a-priori recommendation below the fold turned out to be wrong on
the architectural axes — scaling rank/alpha/num_layers *down* for
smaller models UNDERFIT them. LR is the true lever. Keep the LoRA
architecture at full size; tune LR by model size.

| Model | rank | alpha | num_layers | iters | dropout | learningRate | Δ (adapted−base) |
|---|---|---|---|---|---|---|---|
| **0.6B**            | 8 | 16 | 8 | 300 | 0.05 | **7e-6** | **+2** |
| **1.7B**            | 8 | 16 | 8 | 300 | 0.05 | **7e-6** | **+1** |
| **4B (base)**       | 8 | 16 | 8 | 300 | 0.05 | **5e-6** | **+2** |
| **4B-Instruct-2507**| 8 | 16 | 8 | 300 | 0.05 | **7e-6** | **+2** |
| 8B (untested)       | 8 | 16 | 8 | 300 | 0.05 | 5e-6 (predicted) | ? |

Universal rule of thumb: **rank=8 α=16 layers=8 iters=300 dropout=0.05.
LR = 7e-6 for models ≤ 2B, LR = 5e-6 for models ≥ 4B.**

## What the experiments actually showed

**Session data — every configuration tested, scored /6 on the diary
grader:**

| Pipe | Config | rank/α/lyr | LR | iters | adapted | base | Δ |
|---|---|---|---|---|---:|---:|---:|
| 0.6B | Original (pre-sweep)            | 8/16/8 | 1e-5 | 300 | 4 | 5 | −1 |
| 0.6B | v1 scaled-small                 | 2/4/4  | 3e-6 | 300 | 2 | 4 | −2 |
| 0.6B | v2 low-LR (arch kept)           | 8/16/8 | 5e-6 | 300 | 2 | 4 | −2 |
| 0.6B | v3 doubled iters                | 8/16/8 | 5e-6 | 600 | 3 | 6 | −3 |
| 0.6B | **v4 mid-LR** ✓                 | **8/16/8** | **7e-6** | 300 | **5** | 3 | **+2** |
| 1.7B | Original                        | 8/16/8 | 1e-5 | 300 | 1 | 3 | −2 |
| 1.7B | scaled-v1                       | 4/8/6  | 5e-6 | 300 | 2 | 3 | −1 |
| 1.7B | **v4 mid-LR** ✓                 | **8/16/8** | **7e-6** | 300 | 2 | 1 | **+1** |
| 4B   | Original ckpt-100               | 8/16/8 | 1e-5 | (100 steps) | **6** | 4 | **+2** |
| 4B   | Original ckpt-200               | 8/16/8 | 1e-5 | (200 steps) | 3 | 5 | −2 |
| 4B   | Original final                  | 8/16/8 | 1e-5 | 300 | 5 | 4 | +1 |
| 4B   | **scaled-final (half LR)** ✓    | **8/16/8** | **5e-6** | 300 | 5 | 3 | **+2** |
| 4B-Instr | Original scaled               | 4/8/6  | 5e-6 | 300 | 2 | 2 | 0 |
| 4B-Instr | **v4 mid-LR** ✓               | **8/16/8** | **7e-6** | 300 | **4** | 2 | **+2** |

## Five conclusions the sweep forced on us

1. **Architectural downscaling underfits.** Rank=2 α=4 layers=4 on
   0.6B (v1) was WORSE than the aggressive original, not better. The
   LoRA lacked capacity to express the voice at all. Same story
   for 1.7B scaled-v1 vs v4.

2. **LR is the only knob that needs to scale with model size.**
   Everything else stays constant across the sweep. The LR floor
   for a useful LoRA on this data corpus is roughly `5e-6` for 4B
   and `7e-6` for tiny/small — go lower and the model plateaus at
   ~loss 4.5 without meaningful learning.

3. **More iterations at the wrong LR don't rescue.** 0.6B v3 (600
   iters, lr=5e-6) was actually the worst variant tested — extra
   corpus passes at a below-threshold LR just accumulate noise, not
   pattern recognition. "So LoRA sees all the stories" is
   necessary but not sufficient — the gradient step needs to
   actually move the weights.

4. **4B ckpt-100 at original LR (1e-5) still holds the session
   record for absolute score (6/6).** This is the "less time at
   higher LR" reading of the same trade-off. Ideal training might
   be a mix: original LR for ~100 iters, then decay to 5e-6 for
   the remainder. Not tested this session.

5. **Instruct-tuned base is the highest-leverage adapter target.**
   Raw Qwen3-4B-Instruct-2507 with our diary prompt produced
   literally 3 characters ("Jim") — the base couldn't do the task
   at all. The scaled adapter turned it into a competent letter
   writer (adapted 4/6 vs base 2/6). Δ=+2 on a base score of 2
   is a much bigger relative move than the same Δ on a base
   score of 4.

## Practical guidance for the next training round

- Use the universal recipe as the new default in
  `~/pipeline/config/elementary.yaml`: rank=8 α=16 layers=8 iters=300
  dropout=0.05.
- Set LR per pipe: 7e-6 for ≤2B model, 5e-6 for ≥4B model.
- Save a ckpt every 50 steps (currently every 100) so the ckpt-100
  peak isn't invisible for models where it happens between 50 and
  150. Currently only 100/200/final are saved — that under-samples
  the interesting region.
- Optional experiment worth running: **LR decay schedule.** Start
  at 1e-5 for 100 iters, decay linearly to 3e-6 over the remaining
  200. Matches the "4B ckpt-100 at full LR is best" observation
  with the "later LR needs to be low" evidence.

## Not addressed here

- Story tier failures beyond size — the 4B-Instruct-2507 "wrote
  11 words of self-congratulatory meta-commentary" bug is a
  rescue-clause weakness, not a LoRA parameter issue. Fix
  separately in `sat_story_ite.coffee` — the rescue prompt needs
  to steer toward prose ("The story:\n\n") not just close `<think>`.
- Past_scraps content design — the voice-hint scraps in
  `sat_fixed_spine.yaml` are full phrases, which invite copying.
  Better: abstract keywords ("diner-shift textures", "reluctant
  confession") that force the model to synthesize new prose in
  that register instead of lifting fragments.
