# LoRA overtraining — empty-generation cliff

Session finding: 2026-08-08.

## The pattern

On `prompt_llm` training against the current corpus + prompt shape,
adapters trained past **~20 iters** produce empty generation. A
20-iter adapter is usable; anything past that starts trimming the
output, and quickly reaches the point where every generation is
empty (or empty after cleanGeneratedText strips trailing garbage).

Non-adapter (base model) generation is unaffected — the base
produces full letters whether the corpus was 20-iter or 200-iter
LoRA'd, because the LoRA weights are never loaded in that path.

## Why this happens

LoRA fine-tuning shifts two distributions simultaneously:

1. **Content distribution** — which content tokens the model picks
   given the prompt. This is what you want the adapter to learn.
2. **Stop-emission distribution** — how eager the model is to emit
   `<|endoftext|>` / `<|im_end|>` at a given position.

Every training example ends with a stop token. At low iters, the
adapter mostly touches (1) and barely touches (2). Past a threshold,
the adapter starts to think "emitting a stop token IS a
high-probability action at the start of a response" — because the
training data's prompt→response shapes are shorter and end sooner
than what natural generation would produce. The overtrained model
picks stop-emission as its FIRST-token choice.

Signal: on a run whose adapter is tipping, `.err` shows growing
counts of

```
[session.generate] ignored N early stop-marker(s) (adapter-quirk?):
   [{"marker":"<|endoftext|>","atToken":1,"contentSoFar":0}, ...]
```

Watch that count grow across iter checkpoints; it inversely tracks
generation quality.

## Runtime mitigations we have (partial, non-cure)

`~/pipeline/mlx/session_api.coffee` — `session.generate`:

- `MIN_CONTENT_BEFORE_STOP = 16` — ignore stop markers until at
  least 16 non-whitespace chars have been generated. Saves the
  mildly-overtrained case where the adapter emits `<|endoftext|>`
  on token 1 but would have generated real content on token 2.
- `<|im_end|>` REMOVED from `STOP_MARKERS`. It's a Qwen chat-template
  turn delimiter, not a true EOG. Chat-format-trained adapters emit
  it at paragraph breaks; halting there truncated letters to their
  first paragraph.

These help with mild overtraining. They do NOT rescue a truly
tipped-over adapter — the model has no real content to give past
the first few tokens and just runs out its `maxTokens` on
whitespace / trivial repetition.

## What to do

1. **Cap iters at the ceiling you find.** Current empirical ceiling:
   **≈ 20 iters** for prompt_llm on Jim's corpus.
2. **Bracket the ceiling with checkpoints.** Train with smaller
   `steps_per_save` so you have `_adapters.safetensors` snapshots
   every few iters. Point the UI adapter dropdown at each in turn;
   the one that generates full letters without empties is your
   working point.
3. **If you need to push past the ceiling** for more style
   internalization: reduce learning rate (halves per-iter shift),
   reduce LoRA rank (less capacity to memorize stop patterns), or
   augment training data with longer response examples so the model
   doesn't learn "responses end soon."
4. **Validation-loss early-stop** isn't wired up in this project's
   `train_lora` chain. Would be a good addition; watch loss on a
   held-out sample and stop when it starts climbing.

## Cross-refs

- Runtime stop-marker logic: `~/pipeline/mlx/session_api.coffee`
  (search `MIN_CONTENT_BEFORE_STOP`, `STOP_MARKERS`).
- Diary generator: `pipes/story/scripts/generate_diary_with_adapter_ite.coffee`
  (uses `S.callLLM` which routes through the session.generate above).
- Training entry points: `GPT/lora_ite/train_contract.md`.
