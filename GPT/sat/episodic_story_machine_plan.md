# Episodic story machine — build target for 2026-09-20

Human's EOD directive: *"we will look at the results and start
building a new episodic story machine. It uses all of our spine
generation stuff, and should need only small adaptation to our
story recipe, but with very different scenario and action."*

## What we're building

A recipe (probably `writer/config/episode.yaml`) that generates
episode N of a serial story, given:
- The **spine** (allowed_names, invariants, emotional_arc — the
  shape we've been using for SAT).
- The **prior-episode context** — what happened in episodes 0..N-1,
  so character continuity, unresolved plot threads, and factual
  consistency propagate forward.
- A **per-episode scenario and action** — the twist that
  distinguishes this episode from the last.

## What's reusable from today's work

1. **Spine format** (`sat_fixed_spine.yaml`) — same allowed_names,
   invariants, past_scraps, premise, emotional_arc, kag_emotion_map.
   An episode has all these; the "premise" field becomes
   per-episode.
2. **Per-segment emotional-arc KAG lookup** in `sat_diary_ite.coffee`
   is the reusable engine for injecting mood-matched context. An
   episode step invokes the same lookup — the arc might differ
   (episodic stories often have a different pacing shape than the
   diary's calm/fear/anger/sobering/joyful) but the machinery is
   identical.
3. **The grading framework** — `elementary_sat_ite.coffee` scores
   diaries; `sat_story_ite.coffee` scores stories. An episode is
   closer to a short story than a diary — start from
   sat_story_ite's structure and add episode-continuity checks.
4. **KAG/chunks ablation surface** — every episode should be
   gradable across the same 4 configs (baseline / kag / chunks /
   both). Same panel + recommendation logic applies.
5. **Puppeteer capability P1** (`POST /api/launch_recipe`) already
   handles arbitrary recipe launches. It'll launch episode-per-pipe
   the same way it launched sat_ladder.

## What's new (the "small adaptation")

1. **Episode context artifact** — a new spine-shaped file (or a
   sidecar to the spine) that carries:
   - Cast state (which allowed_names have appeared, their current
     status, relationships they've formed).
   - Fact accumulator (invariants earned across episodes, not just
     those set in the spine).
   - Prior-episode summaries (short prose per past episode, used
     to seed continuity in the current episode's prompt).
   - Cliffhangers / unresolved threads.
2. **`episode.yaml` recipe** — probably 4-6 steps:
   - `episode_scenario_ite` — decides this episode's scenario +
     action (human-authored config OR generator step that reads
     prior context and proposes something new).
   - `episode_context_ite` — assembles the "prior episodes"
     digest that gets injected into the generation prompt.
   - `episode_generate_ite` — the story generator, forked from
     `sat_story_ite.coffee` with the episode-context block added.
   - `episode_grade_ite` — grader, forked from `sat_story_ite`
     with new checks for cross-episode consistency.
   - `episode_context_update_ite` — writes back the updated cast
     state, fact accumulator, prior-episode summaries so N+1 has
     what it needs.
3. **New checks** worth having:
   - **Cast consistency** — characters retain their established
     traits/status from prior episodes.
   - **Fact continuity** — no contradiction of a fact stated in
     any prior episode.
   - **Novel scenario** — the episode's action is meaningfully
     different from prior ones (not just repetition).
   - The **repetition-collapse check** we identified today (same
     clause repeated 3+ times in a paragraph) applies to episodes
     too and is worth building now.

## Design questions to bring to the human first thing tomorrow

1. **Episode structure** — same 5-segment
   (scene/arrival/disturbance/reflection/realization) as diary,
   or a different narrative shape (e.g. TV pilot's 4-act, or
   short-story 3-act)?
2. **Character continuity** — persistent Ari + Mira across all
   episodes, or does each episode get a fresh cast (with the
   spine changing per episode)?
3. **Where does per-episode scenario come from** — human authors
   `season_plan.yaml` listing 10 episode scenarios? Generator
   step proposes them? Combination?
4. **How many episodes per pipe** — a fixed season length (10, 13),
   or open-ended (until quality degrades or the model exhausts
   ideas)?
5. **Grading extension** — does the episode SAT get a new tier,
   or extend Tier 3 (story) with episode-specific checks?
6. **Cross-episode ablation** — should the "prior episodes"
   digest be its own ablation axis alongside KAG and chunks?

## Suggested build order (subject to human's answers)

1. Answer the design questions.
2. **Extend `sat_fixed_spine.yaml` schema** with the per-episode
   context slots (or design a separate `episode_context.yaml`).
3. **Fork `sat_story_ite.coffee` → `episode_generate_ite.coffee`**
   with the episode-context injection block.
4. **Fork `sat_story_ite.coffee`'s grader → `episode_grade_ite`**
   with cross-episode consistency checks.
5. **Write `episode.yaml` recipe** that chains the four/five
   episode steps.
6. **First test run** on one pipe with one hand-authored season
   plan (3 episodes) to see if the machinery works end-to-end.
7. **Extend the SAT Grades panel** to include episode-tier
   verdicts (a new panel section OR a per-episode drill-down).

## Anti-patterns to remember (from today)

- **Route every launch through `POST /api/launch_recipe`.** No
  bash drivers on the mini. Ever. This is now
  `puppeteer/GPT/rules/route_runs_through_puppeteer.md` and it
  cost the user real trust today.
- **Grade at the BEST config, not the worst.** The panel's
  `best.recommendation` is the answer to "what should we use this
  model for?", not the failing-cell list. Same principle applies
  to episode grading.
- **Never substitute analysis for raw data.** If the human asks
  for text, produce text first, analysis second (if at all). The
  SAT Grades panel exists to make this structurally impossible
  going forward — the cells ARE the data, no summary layer.
