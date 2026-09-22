# Three-tier SAT ladder — recipes + buckets

Built 2026-09-18. Three new step scripts, one new UI panel, all
knob-tunable via `override/<pipe>.yaml` so a sweep over
(temperature, top_p, adapter_dir, KAG on/off) tells us which
bucket a model belongs to.

## Tiers

| Tier | Recipe (writer/scripts) | Bucket key | Verdict artifact |
|------|--------------------------|------------|-------------------|
| 1. Elementary reading | `elementary_ite.coffee` | `can_read` / `cannot_read` | `elementary_verdict` |
| 2. Diary (fixed spine) | `sat_diary_ite.coffee` (generator) + `elementary_sat_ite.coffee` (grader, existing) | `pass=true/false` per side | `sat_verdict_<adapted\|base>` |
| 3. Story (fixed spine) | `sat_story_ite.coffee` (self-grading) | `can_story` / `cannot_story` | `sat_story_verdict` |

Each recipe is location-anonymous, meta-device only (`L.need` / `L.make`
/ `L.param` / `L.callLLM`), no `fs`, no parameter prescreens.

## Inputs each recipe expects

### Tier 1 — elementary_ite
- `elementary_story_text` — a short story blob (few hundred words).
- `elementary_qa_json` —
  ```yaml
  questions:
    - q: "Who fell into the river?"
      expected_keywords: ["Sam", "river"]
    - q: "What did they find?"
      expected_keywords: ["locket"]
  summary_keywords: ["river", "locket", "grandmother"]
  max_summary_words: 60
  ```

### Tier 2 — sat_diary_ite
- `sat_fixed_spine_json` —
  ```yaml
  allowed_names:
    - display: "Ari"
      slug: "ari_gold"
    - display: "Mira"
  invariants:
    - "The letter is written on a Tuesday."
    - "Ari has moved to Portland."
  past_scraps:
    - "the smell of pine and diesel"
    - "another crooked evening"
  premise: "Ari has just started a new job..."
  emotional_cues: "tired, wry, tender"
  task: "Write the five-paragraph letter."
  ```
- Then `elementary_sat_ite` reads `diary_<side>_text` + `diary_prompt_text`
  and emits `sat_verdict_<side>`.

### Tier 3 — sat_story_ite
- `sat_fixed_spine_json` (same shape as Tier 2 — the story recipe
  ignores `past_scraps` / `emotional_cues`).

## Knobs (all L.param — put in override/)

Shared across all three: `temperature`, `top_p`, `adapter_dir`,
`model_dir` (falls back to `quantized_model_dir`), `grader_model_dir`
(falls back to whichever generator is running), `grader_temperature`.

Tier-specific:
- Tier 1: `with_judge`, `min_keywords_hit`, `min_summary_hits`,
  `max_answer_tokens`, `max_summary_tokens`.
- Tier 2: `side` (adapted|base), `max_tokens`, `system_prompt`.
- Tier 3: `min_words`, `max_words`, `max_tokens`.

## Sweep pattern (override/<pipe>.yaml)

To A/B a knob without cloning recipes, override:

```yaml
elementary_ite:
  temperature: 0.15
  adapter_dir: /Users/.../adapters/helper_v3

sat_diary_ite_adapted:  # if you alias two step-runs of sat_diary_ite in the recipe
  side: adapted
  adapter_dir: /Users/.../adapters/helper_v3
  temperature: 0.75

sat_diary_ite_base:
  side: base
  adapter_dir: null
  temperature: 0.75

sat_story_ite:
  temperature: 0.85
  adapter_dir: /Users/.../adapters/helper_v3
  min_words: 400
  max_words: 1100
```

## UI

Two panels on the writer UI, both `after-outputs`:

- **Elementary SAT** (`sat_verdicts`) — per-check dots grid across
  the two diary sides (`adapted` vs `base`). Built earlier this session.
- **SAT Buckets** (`sat_buckets`) — new. Three-tier ladder with a
  pass/fail chip per tier + the knobs used (temp, top_p, adapter tail).
  Pending tiers render as grey chips so partially-run pipes are legible.

Both panels are `applies`-gated — they don't show on pipes that have
no verdict files yet.

## Recipe + override wiring

**Recipe file** (canonical, tuning-forbidden):
`~/pipeline/config/sat_ladder.yaml` composes all six steps in a
linear DAG:

  elementary_ite  →                                (Tier 1 gate)
  sat_diary_adapted  →  elementary_sat_adapted →   (Tier 2 adapted)
  sat_diary_base     →  elementary_sat_base    →   (Tier 2 base)
  sat_story_ite                                    (Tier 3)

The diary/story branches are serialized (not parallel) — MLX
session_api's native state doesn't tolerate two concurrent
createSession calls in one process.

**Fixture files** the recipe expects (source-only artifacts):

  <pipe>/data/elementary_story.txt        (Tier 1 story)
  <pipe>/data/elementary_qa.yaml          (Tier 1 QA + summary kw)
  <pipe>/data/sat_fixed_spine.yaml        (Tiers 2 + 3 locked spine)

Canonical scaffold: `writer/pipes/small/data/` — copy it to any new
pipe you want to grade.

**Per-pipe knobs**: `<pipe>/override/sat_ladder.yaml`. Never edit
`config/sat_ladder.yaml` for tuning. Template lives at
`writer/pipes/small/override/sat_ladder.yaml`.

## To run on a pipe

1. Copy the three data files into `<pipe>/data/`.
2. Author `<pipe>/override/sat_ladder.yaml` (start from the small
   template; set `adapter_dir` on `sat_diary_adapted` +
   `sat_story_ite` for the adapted branches).
3. Flip the pipe into sat_ladder mode via its `control_override.yaml`
   (or launch it via the puppeteer with pipeline=sat_ladder).
4. Watch verdicts land in `<pipe>/params/*.yaml`. The SAT Verdicts
   and SAT Buckets panels populate automatically.

## Not yet done
- Copy the recipe + step scripts to the mac-mini (`sync-mini`).
- Cross-pipe roll-up view (all pipes' bucket state in one table) —
  current SAT Buckets panel is per-pipe.
- Consider using a DIFFERENT grader model than the generator for
  adversarial rigor (Tier 3 currently uses same-model self-judgment).
