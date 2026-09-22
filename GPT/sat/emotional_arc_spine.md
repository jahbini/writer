# The positive-message emotional arc (the SAT's structural spine)

Locked 2026-09-19. The 5-segment diary structure is not just
scene / arrival / disturbance / reflection / realization by
narrative form — each segment has a **preselected emotional
quality**, and that emotional arc IS the spine's positive-message
signature.

## The arc

| Position | Segment | Emotion |
|---|---|---|
| 1 | scene | **calm** |
| 2 | arrival | **fear** |
| 3 | disturbance | **anger** |
| 4 | reflection | **sobering** (contemplative) |
| 5 | realization | **confidant / joyful** (resolution) |

This is the shape of a positive-message story: settling into
place, first fear at the disruption, the anger of the moment
before understanding, sobering reflection on what it means, and
the confidant / joyful realization that resolves it. Fixed for
the SAT so a model's performance can be graded against a known
target rather than a moving genre.

## Implications for the SAT KAG ablation

KAG in the diary SAT is NOT a static examples list injected once.
KAG is a **per-segment emotional lookup**: for each of the 5
segments, retrieve corpus examples whose emotion matches that
segment's assigned emotion. The retrieved examples get injected
into the prompt as voice hints organized by segment.

Rough prompt shape when `include_kag: true`:

    For each segment, here are voice-hint examples from the corpus
    matching that segment's emotional mood. Do not copy verbatim.

      Scene (calm):
        - <corpus example matching 'calm'>
        - <corpus example matching 'calm'>
      Arrival (fear):
        - <corpus example matching 'fear'>
        …

The elementary training pipeline already emotion-tags corpus
passages via `oracle_ask_sqlite` (see
`pipeline/config/elementary.yaml` line ~140 — the classifier
categorizes to Joy / Fear / Anger / Melancholy / Neutral etc.).
The SAT KAG lookup uses the same emotion tags.

## Emotion vocabulary mismatch (needs reconciling)

Elementary's KAG classifier uses these emotion labels:
`Joy, Contentment, Sadness, Grief, Fear, Anxiety, Anger,
Frustration, Disgust, Shame, Surprise, Neutral, Absurd, Wry,
Playful, Melancholy, Mysterious`.

The SAT arc uses: `calm, fear, anger, sobering, confidant/joyful`.

Mapping table (SAT arc → classifier labels used for KAG lookup) —
**tentative, will evolve as we learn**:
- **calm** → `Contentment, Neutral`
- **fear** → `Fear, Anxiety`
- **anger** → `Anger, Frustration`
- **sobering** → `Melancholy, Sadness`
- **confidant/joyful** → `Joy, Contentment, Playful, Wry`

Human note 2026-09-19 on wry's placement: **wry is the realization
that tragedy is the flip side of comedy, and leads to a more
uplifting completion.** So `Wry` sits on the confidant/joyful side
(the pivot from "this is heavy" to "this is oddly funny"), not on
the sobering side where I had it first-pass. The sobering segment
should stay heavy — its role is the honest acknowledgment before
the arc turns.

This mapping needs a fixed home so KAG lookups are consistent
across SAT runs. Suggestion: put it in the spine yaml alongside
`emotional_arc:`.

## Consequence for the SAT ablation fixture

Add to `pipes/<pipe>/data/sat_fixed_spine.yaml`:

    emotional_arc:
      scene: calm
      arrival: fear
      disturbance: anger
      reflection: sobering
      realization: confidant

    kag_emotion_map:
      calm:      [Contentment, Neutral]
      fear:      [Fear, Anxiety]
      anger:     [Anger, Frustration]
      sobering:  [Melancholy, Wry]
      confidant: [Joy, Contentment, Playful]

    kag_examples_per_segment: 3   # how many corpus rows per segment
    chunks_per_segment:      2    # how many story chunks to attach

The KAG lookup itself remains dynamic against the corpus, so as
the corpus grows the SAT tests the model's ability to use MORE
data — that's the intended "SAT with KAG" signal, not a bug.

## Chunks definition (going with option a, revisable)

Human deferred a specific call on chunks vs beats — "we will
learn as we go." Going with option (a) for the initial build:
**chunks = sqlite `chunks` table entries** (the story passages
`oracle_ask_sqlite` and `reembed_chunks_clean` tag with emotion),
looked up per-segment by the same emotion key as KAG. This gives
a clean parallel: "KAG = examples of writing; chunks = story
passages"; both emotion-keyed, both dynamic against the current
corpus. If it turns out story-spine beats are more useful, easy
pivot in `sat_diary_ite.coffee`.

## Not addressed here

- Deterministic snapshotting — if we later want a fully-frozen
  SAT for regression testing, snapshot the KAG returns into the
  spine file at fixture-authoring time. Not needed for the
  current "how well does this model use context?" measurement.
