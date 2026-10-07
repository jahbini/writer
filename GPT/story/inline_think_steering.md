# Mid-stream `<think>...</think>` — beat-level generation steering

**Discovered 2026-09-25 at the coffee shop.** Not from our own experiments — from the user's observation of how Qwen3-family models weight think content when it appears INSIDE generated content, not just at the assistant turn head.

## The claim

Embedding `<think>...</think>` blocks **mid-stream inside generated text** works as a beat-level steering lever. Example:

    ...Tommy laughed, but the smile didn't reach his eyes.
    <think>Tommy thinks he has been insulted and that makes him angry</think>
    He set the glass down carefully. Too carefully.

The model reads the inline think block as its own private reasoning and adjusts continuation as if the directive were an already-decided fact about the story world. The reader never sees the directive; the model does. Different from turn-head prefill (which frames the whole response); this is one-emotional-beat, one-plot-lever control.

## Why it works

Same mechanism that makes `<think>` prefill weight higher than user-turn text: chat-tuned Qwen3 treats think content as authoritative-inner-reasoning, higher-priority than instruction-style prose. When the model generates its own `<think>` mid-output, whether directly emitted OR planted for it by the harness, the tokens inside are weighted the same way. That means:

- Injected `<think>` mid-content steers next-token continuation.
- The rest of the story doesn't have to explain the change.
- The directive can be terse — one sentence — and land as authoritative.

## Where this pays off

**Story generation (voice_test, storacle-family, sat_story_ite)** — the pain we've been fighting is "the model drifts into generic voice / loses the beat / forgets what a character wants". Inline `<think>` cues at act boundaries let the harness fix these mid-generation without post-hoc rewrites.

**Spine-guided story generation** — spines already encode "what should happen"; embedding `<think>` cues at each beat lets the harness translate spine directives into inline steering during story synthesis:

- Spine's `disturbance:` section names a beat.
- Story-generation prompt slots that section as an inline `<think>disturbance directive</think>` at the paragraph where the disturbance should land.
- Continuation absorbs the shift.

**Character voice consistency across a long generation** — inject `<think>Character X talks like Y</think>` before each of X's dialogue turns.

## Where this DOESN'T pay off

- **Structure-only artifacts (spines themselves)**. Spines are directive templates read by downstream generators. Embedding think inside a spine would be weird — the downstream generator would either strip it or read it out of context. Spines document what the story is; inline think steers HOW the story unfolds.
- **JSON-return capabilities**. Anything that goes through `runCapability` (with JSON schema enforcement) will get the think content stripped by `stripThink` before parse. Inline think inside JSON would just be lost.

## How to actually implement it

1. **In the storacle / voice_test prompt template** — replace or augment `{{{FRAGMENT_N}}}` substitution with a version that intersperses inline `<think>steering directive</think>` blocks between fragments, drawn from the spine's beat directives.
2. **In a new capability `helper.beat(story_so_far, next_beat)`** — helper suggests a terse steering think block given the story state and the next beat name. Called by the harness to plant think cues at the right places.
3. **As a spine post-processor**: given a spine artifact, generate a companion "beat cue map" file (`<slug>.beats.json`) that says "at position P in the target story, plant `<think>...</think>`". Downstream generators read this alongside the spine.

## Constraints / cautions

- **Placement matters**. A `<think>` block AFTER a fully-committed paragraph doesn't retro-actively shift what was already generated. Cues should sit BEFORE the beat they steer.
- **Cue length**. Short is better. 8-20 words. Long cues consume think-budget without adding steering leverage.
- **Directive, not contemplative**. Same lesson from KAG's guard-audit: `<think>Tommy is now angry</think>` beats `<think>Tommy might be feeling something like anger</think>`. State it as fact, not deliberation.
- **Cue frequency**. Empirically test — one every 200 words is probably fine; one every 30 words is probably too many (model gets distracted from the story into obeying too many small nudges).

## Where this goes next

Nothing built yet — this is a finding awaiting an implementation. Concrete first experiment when the mini is back:

- Fire storacle on `bouncy-boom-gets-her-skates-md` with the same prompt shape we've been using, but inject one `<think>` cue between FRAGMENT_2 and FRAGMENT_3 saying `<think>Wahina is proud of the baby, not scared</think>`.
- Compare the output paragraph-by-paragraph with the un-cued version.
- If the cued version shifts Wahina's emotional posture at the right beat, we have a mechanism. If not, the story fabric is too far from the cue to be moved.

## Option 2 (deferred, 2026-09-25)

The current Path A pipeline (helper writes diary body → second helper
pass derives "observation → affect" clauses → injector plants them
after each section header) is option 1.

Option 2 is the same *shape* of clause, but sourced inline: instruct
the diary-body pass itself to emit the clauses in-band, using a
placeholder token the injector can find and rewrite into `<think>`.
Trade-off: no second LLM pass (faster, cheaper), but the model has to
be trusted to emit clauses at all and in the requested form. Chat-tuned
Qwen strips literal `<think>` but does not strip arbitrary placeholders
like `[[think: because X, Jim Y]]`, so the injector could sub those in.

Kept as a note — try if the second-pass cost is ever felt (currently
~10s on 4B). Do not implement until option 1's clauses are proven to
steer downstream storacle output better than the fixed affect table.
