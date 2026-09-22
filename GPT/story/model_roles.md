# Model roles in the story pipeline

Established 2026-09-22 from voice-tournament + think-block +
prefill-transplant experiments. Assigns each voice pipe to the
kind of writing task it does well, not just "which pipe wins overall."

## Qwen3-0.6B — the punctuation model

**Role**: short anchoring text at the boundaries of a piece.
NOT sustained body prose. NOT letters. NOT chapters.

**Good jobs for 0.6B:**
- Chapter headings (5-15 words)
- Story intros / opening hooks (1-3 sentences)
- Closing lines / aphorisms (single line)
- Twitter-repost captions (compress a piece into 1 line)
- Section epigraphs
- Photo captions
- Newsletter subject lines
- Any output where the target is 5-40 tokens

**Why**: the 0.6B's constraint is working memory — it cannot hold a
multi-scene structure or 3+ characters. Its compensation is
*compression*: because it can't afford to spend rhetorical energy
across paragraphs, its endings LAND. Every experiment we ran
confirms it produces closing lines that create a reflective pause
in the reader — the moment where the reader stops scanning and
starts thinking. This is Chekhov's rule accidentally discovered by
working-memory scarcity. See tournament results at
`~/puppeteer/tournaments/2026-09-21_0457/` — the 0.6B WON
susannas_song, the spine with a clean single-line closer available;
lost bouncy_boom and serf_insults_queen where distributed emotional
payoff was needed.

**Configuration for short-form use:**
```yaml
voice_from_prompt:
  max_tokens: 40
  temperature: 0.95    # invite surprise
  top_p: 0.9
  repetition_penalty: 1.3   # prevent rehashing
  adapter_path: null   # register comes from prompt, not LoRA
  raw: true            # completion mode, no chat template
```

**Do NOT use 0.6B for:**
- Multi-paragraph letters (working memory saturates ~3 elements)
- Anything requiring 3+ named characters
- Sustained coherence past ~500 tokens
- Structural planning (the outline/scene/beat steps of story recipe)

## Qwen3-1.7B — the mid-tier journeyman

**Role**: mid-length narrative work when 4B isn't available or is
busy. Diary letters where 4B-Instruct is oversubscribed.

**Good jobs**:
- Diary letters (200-800 words) — competent but mechanical
- Straightforward scene rendering from a well-specified prompt

**Why**: better working memory than 0.6B; can hold 4-scene
structures. Register grasp weaker than 4B — treats KAG passages as
content-to-include rather than voice-cues. Endings usually loop.

## Qwen3-4B (base) — the disciplined craftsman

**Role**: chapter body text when nuanced constraint-following
matters.

**Why**: cleanest planning of the thinking models (see
`voice_findings_2026-09-21.md`). Catches second-order constraints
("Jim doesn't use 'I' except when talking about himself") that
smaller models drop. Rare hallucination. Its `<think>` matches its
output.

**Weakness**: still loops at end. Distributes rhetorical charge
evenly — no single moment carries maximum charge. Best paired
with a 0.6B for the closer.

## Qwen3-4B-Instruct-2507 — the finished-product model

**Role**: chapter body when we want the best voice output in a
single pipe pass. Instruct-tuned; no `<think>` block emitted.

**Why**: tournament data shows this is the strongest voice pipe
across most spines. `force_think:true` + no explicit prefill
produced its best-ever output on susannas_song (see the "sky
forgets how to be grey" letter at
`/tmp/4b-instruct_force_think.txt`). The manual chat template with
`<think>\n` opener somehow unlocked a stronger generation mode
even though visible thinking never appeared.

**Weakness**: opaque. Cannot introspect what it's doing. If a
letter comes out wrong, no `<think>` window to diagnose from.

## Composition patterns

**Stitch (body + closer)**: 4B-Instruct writes the body, 0.6B
writes the last line. Requires a body that DOESN'T already
have a strong close — so use base 4B or 1.7B for body, not
4B-Instruct with force_think (which already closes strongly).

**Anchor (headline + body)**: 0.6B writes chapter heading given
the spine's chapter_purpose, 4B-Instruct writes the body from
the same spine. Reader sees the 0.6B's crystallization before
they read the body — primes their reception.

**Caption (long → short)**: 0.6B given a completed 4B letter,
asked for a 15-word Twitter-repost caption. Uses the 0.6B's
compression pressure as a feature.

**Distillation panel**: fire 0.6B multiple times (fast, cheap) on
the same headline-task with different temperatures, then pick the
winner. Shotgun generation. 0.6B's ~25s per call × 10 candidates
= 4 minutes total for 10 headline candidates.

## Related

- `writer/GPT/story/voice_findings_2026-09-21.md` — per-model
  observations from the tournament.
- `writer/GPT/story/spine_library.md` — the spine artifact these
  models consume.
- `puppeteer/GPT/design/voice_tournament.md` — how we're rating
  them; tournament data is at `puppeteer/tournaments/<id>/`.
- `writer/GPT/sat/size_scaled_lora.md` — prior LR-vs-size notes
  from LoRA training. The 0.6B adapter regressed base; retraining
  is queued.
