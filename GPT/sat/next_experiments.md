# Next-session experiment plan (recorded 2026-09-18)

## HARD PREREQUISITE (before any pipe launch tomorrow)

**Read `puppeteer/GPT/rules/route_runs_through_puppeteer.md` FIRST.**
2026-09-19 EOD update: I broke this rule four times today with
bash drivers on the mini. The runs produced data but disappeared
from the human's Peer Session History as raw UUIDs — unreadable
and unclickable. That doc lists the specific puppeteer capabilities
that need building so tomorrow's experiments can be launched
through the puppeteer instead of scripted around it:

  P1. Ad-hoc recipe launch API (`POST /api/launch_recipe`)
  P2. Parameter-sweep queue (`POST` with a sweep list)
  P3. Retrain-then-eval chained queue item (elementary → sat_ladder
      as one atomic entry)

**Build P1 first** before any of the Arc-A/Arc-B experiments below.
Everything downstream needs it.

## Grading principle (locked 2026-09-19)

**A pipe's SAT grade must reflect its best-achievable quality, not
performance at globally-chosen defaults.** Every pipe's
`override/sat_ladder.yaml` should be tuned per-pipe (adapter
checkpoint, temperature, top_p, max_tokens). "How does this
model do?" is answered at ITS best knobs. Concrete: 4B's grade
is 6/6 (ckpt-100), not 5/6 (final).

That makes **per-pipe parameter sweep (puppeteer capability P2)**
central, not optional. The workflow is:
1. Sweep temperature × adapter-checkpoint per pipe.
2. Adopt the winning cell as the pipe's override.
3. Grade at that override.
4. Matrix on the puppeteer shows verdict + which knobs were used.

Design reference: `puppeteer/GPT/design/sat_matrix.md`.

## Two experiment arcs

  A) Refine the SAT-derived LoRA training recipe further.
  B) Apply the wisdom to the scheduling helper — including a
     real 0.6B-vs-1.7B model-size test for helper capability.

Cross-links: `writer/GPT/sat/size_scaled_lora.md` for the
empirical table + five conclusions; `writer/GPT/sat/three_tier_ladder.md`
for the SAT framework; `puppeteer/GPT/helper/kag_design.md` for
the current helper (Qwen3-1.7B-Instruct + KAG in-context).

---

## A) SAT / LoRA refinements

Direct outgrowth of today's sweep. Ordered by expected payoff.

### A1. Save checkpoints every 50 steps, not 100
The current `saveEvery: 100` in `elementary.yaml` under-samples the
region where the peak lives. Session evidence: 4B ckpt-100 (6/6)
was the highest absolute adapter score all day, ckpt-200 collapsed
to 3/6, final recovered to 5/6. The optimum is somewhere between
50 and 150 and we can't see it. Change `saveEvery: 50` and rerun
the whole ladder — the sweet-spot checkpoint is likely to be one
of steps 50/100/150 rather than the final save.

### A2. LR decay schedule
Married observation: "4B ckpt-100 at LR=1e-5 is peak" +
"later checkpoints at LR=1e-5 overfit; 5e-6 avoids the overfit but
plateaus early." The natural resolution is a schedule: start at
1e-5, decay linearly to 3e-6 over 300 steps. Would want the same
schedule tried for 0.6B (start 7e-6 → 2e-6) and 1.7B (same as 0.6B).

MLX's `train.coffee` currently uses a fixed LR; we'd need to add a
`learningRateSchedule: "linear"` / `endLearningRate: 0.000003`
option to `run_lora_train_ite.llm` and thread it through. Small
runner change; low risk.

### A3. Story tier rescue-clause fix
Independent of training, in `sat_story_ite.coffee`. When the
model burns its budget on `<think>` and the rescue injects
`</think>`, the model often writes meta-commentary ("above is a
full coherent story") instead of prose. Fix: the rescue text
should steer content, not just close the block. Replace
`"\n\nOK, time is up. Answering now.\n</think>\n\n"` with
something like:
`"\n\nOK, time is up. I will now write ONLY the story prose,
no summary or preamble.\n</think>\n\nThe story begins:\n\n"`.

### A4. Past-scraps content redesign
The freshness_copy fails across every pipe were driven by two
specific verbatim phrases (`"the smell of fry oil and cold river
water"` and `"another crooked evening"`) — both full phrases in
`sat_fixed_spine.yaml`'s `past_scraps` list. Replace those with
*abstract* voice keywords ("diner-shift textures", "reluctant
Tuesday confession", "found-object patience") so the model has to
synthesize prose in that register instead of lifting fragments.

Predicted effect: freshness_copy stops firing on adapters that
would otherwise pass every other check.

---

## B) Helper training arc

The scheduling helper is currently Qwen3-1.7B-Instruct + KAG-selected
in-context examples, no LoRA. See `puppeteer/GPT/helper/kag_design.md`
and `puppeteer/GPT/helper/reason_mining_findings.md`.

### Wisdom from today's sweep that transfers directly

1. **LR floor by size**: 7e-6 for ≤2B, 5e-6 for ≥4B. This applies
   to helper training too — same MLX training path.
2. **Don't shrink the LoRA architecture**: keep rank=8 α=16
   layers=8 regardless of model size. Shrinking underfits.
3. **Instruct-tuned bases have the biggest adapter leverage.**
   The Qwen3-4B-Instruct-2507 case is a warning AND an
   invitation: base wrote 3 chars ("Jim"), adapted wrote a real
   letter. If Qwen3-1.7B-Instruct behaves similarly on the
   helper task (currently masked by KAG in-context examples),
   a LoRA could dominate.
4. **iters=300 sees all stories, LR moves the needle.** Same
   applies to helper training: 300 passes over the scheduling
   decisions corpus with the right LR.

### B1. Build a Helper SAT (evaluation harness)
Currently the helper is graded ad-hoc via the 7 canonicals A/B
probe. Formalize it: a `helper_sat` recipe that takes a fixture
set of (scenario, expected action, expected reason) and grades
outputs on:
- **Action correctness** — did the helper pick the same action?
  (Or one from an acceptable-set?)
- **Reason coherence** — does the reason match the expected
  category (safety / scaling / user-request / policy)?
- **Format compliance** — did it emit the required JSON shape?
- **Reasoning quality** — LLM judge on the `<think>` content:
  is the reasoning sound? Does it reference the right corpus rows?

Model this after `elementary_sat_ite.coffee`. Same six-check
diary framework, but tuned to the helper's task: replace
structure_count / character_lock with action_match / reason_valid,
keep freshness_copy (helper shouldn't lift training example text
verbatim into its answers), keep an LLM-judge check for `<think>`
quality.

### B2. Model-size test: 0.6B vs 1.7B vs 4B as helper
Today's SAT sweep shows 0.6B passes Tier 1 (reading comprehension)
6/7 to 7/7 with 45-word summaries. The helper task IS reading
comprehension — read scenario, produce decision. **0.6B may be
enough.** Directly test:

- Raw Qwen3-0.6B  + KAG examples (current architecture, tiny base)
- Raw Qwen3-1.7B  + KAG examples (current setup)
- Raw Qwen3-4B    + KAG examples (upper bound)

Run each on the 7 canonicals + a broader set (30+ scenarios).
If 0.6B ≈ 1.7B on action correctness, drop to 0.6B for the ~3×
inference-speed win. If 1.7B ≈ 4B, 1.7B is the sweet spot.

### B3. Train a helper LoRA
Once B1 (evaluation) is in place and B2 (size choice) is made,
train a LoRA on scheduling decisions:
- Corpus: rows from `helper_training_examples` table (~17 seed
  rows today; will grow with reason-mining).
- Base model: whatever B2 picks.
- LR: 7e-6 if base is 0.6B or 1.7B; 5e-6 if base is 4B.
- Architecture: rank=8 α=16 layers=8 iters=300 dropout=0.05
  (the sweep's universal recipe).
- Save checkpoints every 25 steps (helper corpus is small — the
  peak may come very early).

Expected effect (from 4B-Instruct analogy): the adapter should
teach the model to emit the expected JSON shape + reason category
without needing all N in-context KAG examples. If the LoRA works,
we can cut KAG's `k` from 5 to 2 (baseline anchors only) with no
quality loss and significant token savings.

### B4. Compare (LoRA + KAG) vs (LoRA + no-KAG) vs (raw + KAG)
Once B3 is trained, the interesting three-way comparison:
- LoRA + KAG=on : does context still help?
- LoRA + KAG=off: is the adapter enough on its own?
- raw  + KAG=on: the baseline (current production).

Predicted: LoRA+KAG > LoRA-alone > raw+KAG. If LoRA-alone ≥ raw+KAG,
we've bought a real speedup (KAG selection + long context both cost
inference time). If LoRA+KAG >> LoRA-alone, KAG's per-example
grounding is doing work the LoRA can't replicate; keep both.

---

## Suggested order for the next session

1. **Fix A3 (story rescue clause)** — 15 minutes; removes ongoing
   noise from every SAT run.
2. **Fix A4 (past-scraps content)** — 5 minutes; removes the
   dominant freshness_copy failure mode.
3. **Change saveEvery to 50** and rerun 4B-base SAT once —
   ~10 minutes. See if the new peak is at 50 or 150.
4. **B1 (helper SAT harness)** — this is the big new build.
   30-90 minutes depending on how thorough the fixture set is.
5. **B2 (0.6B/1.7B/4B helper size comparison)** — once B1
   exists, running the three sizes takes maybe 10 minutes total.
6. **B3 (helper LoRA training)** — pending B2's size choice.

Items A1 (saveEvery) and A2 (LR decay) are worth doing but not
first — they refine an already-working recipe. B1/B2 are new
capability.

## Not for tomorrow (deferred)

- Cross-pipe SAT roll-up UI (mentioned in three_tier_ladder.md).
- Extending the SAT to more Qwen variants once 8B and Qwen2.5-0.5B
  are properly quantized to mlx4 on the mini.
- The 4B ckpt-100 outperforms final observation deserves a proper
  "early-stop" recipe experiment but it's downstream of A1/A2.
