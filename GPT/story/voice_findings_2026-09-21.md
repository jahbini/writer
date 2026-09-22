# Voice findings — 3 spines × 4 pipes, 2026-09-21

Tournament `2026-09-21_0457` under `puppeteer/tournaments/`. Same
prompt across four voice pipes, each with its own LoRA adapter,
sampled with chat template on, `repetition_penalty: 1.15`, temp
0.85. Human hasn't judged brackets yet at time of writing; these
are the observations from raw output inspection.

## Per-pipe qualitative summary

### `hf__qwen__qwen3-0-6b`

- **Fastest** (~25s per 2400-token generation).
- **BASE model** (no adapter): coherent letter shape, present-tense
  stage direction rather than Jim's warm-wry-digressive voice, tends
  to end with a strong short line ("She did.") — actually a real
  strength.
- **ADAPTER model**: collapses. On serf_insults_queen ran a 25× loop
  of "Jim's friend tells him that he got the injury...". Under-
  trained (loss went from 4.38 → 4.35 over 300 iters, essentially
  flat). The adapter degrades the base model rather than adding
  voice. **Actionable**: retrain with more iterations, or accept
  the base model is the voice pipe for this size.
- Consistent behavior: mechanical scene-by-scene planning in
  `<think>` block ("First moment... Second moment...").

### `hf__qwen__qwen3-1-7b`

- ~35-60s per generation.
- Has the letter shape. Recognizes "Hi, Friend" framing.
- Still numbers its scenes ("1. First raindrop hits the windowpane
  ... 2. The wind stops..."). Very mechanical.
- Uses SOME KAG material (mentions Southwick, references James John
  Cafe) but as decoration, not integrated.
- **Runs into end-loops** ("Hi, Friend," repeated at bottom).

### `hf__qwen__qwen3-4b`

- ~90-180s per generation.
- Real Jim-ish content emerges. Southwick gets a genuine aside;
  KAG "chakras", "MuseCycle 900" references land in-scene.
- Best surprise-per-token rate of any pipe. Voice moves.
- **Still loops** near end. Repetition penalty 1.15 is not enough.

### `hf__qwen__qwen3-4b-instruct-2507`

- **The best voice pipe of the four** by clear margin.
- ~90-120s per generation.
- No `<think>` block emitted (instruct-tuned, non-thinking-mode
  Qwen3 variant).
- Sustains voice through ~500-800 words without looping.
- **Uses KAG material as cross-passage synthesis**, not
  copy-paste. E.g. on susannas_song: "Southwick was at the counter,
  muttering about Elvis in the ice crystals" — pulls the Elvis
  hook from one KAG passage and the James John Cafe from another
  and lands them in a single Southwick aside.
- Consistent aphoristic close ("power doesn't need to shout — it
  just needs to stand still and let the silence do the talking").

## Rank at inspection time

Best-to-worst on voice fidelity:
`hf__qwen__qwen3-4b-instruct-2507 > hf__qwen__qwen3-4b >
hf__qwen__qwen3-1-7b > hf__qwen__qwen3-0-6b (base) >
hf__qwen__qwen3-0-6b (adapter)`.

The adapter making 0.6B **worse** than base is the training story
here. See `writer/GPT/sat/size_scaled_lora.md` for prior
observations on tiny-model LoRA training — 300 iters at lr=1e-5 was
not enough for this size. Likely fixes: more iters (600-1000), or
lr adjust (5e-6 gave meaningful adapters on 4B; may want 3e-6 for
0.6B). Or: accept that 0.6B is best used base + prompt-engineered.

## Cross-cutting observations

### `<think>` blocks converge on a mechanical plan

Every thinking-mode pipe (0.6B, 1.7B, 4B) opened its `<think>` with
`"Okay, let's tackle this"` and enumerated the scene list as a
numbered plan. Result: letter body reads like a plot summary.

The convergence is prompt-driven. The current
`build_diary_prompt_ite.coffee` presents the 4 scene beats as an
ordered numbered list. Small-to-medium models pattern-match that
into "scene 1 paragraph, scene 2 paragraph, ...", which is the
opposite of Jim's digressive voice.

**Fix directions**:
1. `think_prefill` in the recipe with anti-mechanical guidance
   ("Jim doesn't announce the shape; he just writes"). Tried
   2026-09-21 with `raw:true` — did not fire because raw:true is
   incompatible with our current chat-template path. Would need
   a manual chat-template + prefill construction.
2. Reshape the prompt itself. Present scenes as unordered
   fragments in `build_diary_prompt_ite.coffee` output. Bigger
   architectural change, cleaner solution.

### Sampling: `repetition_penalty: 1.15` is necessary but insufficient

All four pipes end-loop on some spines. Repetition penalty at 1.15
prevents 4-token loops but doesn't stop
"paragraph-level" loops (repeat the same paragraph with word swaps).

**Fix directions**:
- Try `repetition_penalty: 1.2` (careful — starts to distort word
  choice).
- Try `min_p` sampling if session_api supports it.
- Shorter `max_tokens`. 4B-Instruct's best output was 3011 chars;
  most models fall apart past that length.

### Instruction bleed

Every model at `raw:true` opened with a fragment of the prompt's
instructions ("Answer:", "Output only the letter", etc). Chat
template (raw:false) fixes this — the model sees a proper user turn
+ assistant handoff.

## Actionable follow-ups (for next session)

1. **Retrain 0.6B adapter** with more iters (or lower lr). The
   current adapter is a regression.
2. **Investigate think_prefill on raw:true** — the mechanism exists
   in `llm_dispatch.coffee` but requires a manual chat-template
   build in `voice_from_prompt.coffee`. Worth ~30 lines of code
   to get anti-mechanical prompting into every voice run.
3. **Reshape `build_diary_prompt_ite`** to present scenes as
   fragments rather than numbered moments. Larger change but
   downstream every voice model benefits.
4. **Add repetition_context_size + higher penalty for small
   models**. Model-size-scaled sampling knobs, not a fixed setting.
5. **Judge the current tournament brackets**. The `sat_history.jsonl`
   record starts once matchups resolve.
6. **Add more spines** — one comedy-heavy (Gutbuster Institute press
   release), one bar-conversation (merkin at Slim's), one lyric
   scene (Dartagnon at the James). Diverse spines catch different
   voice failure modes.

## Related

- `puppeteer/GPT/design/voice_tournament.md` — how these judgments
  will be captured going forward.
- `writer/GPT/story/spine_library.md` — the fixed-spine convention.
- `writer/GPT/sat/size_scaled_lora.md` — prior LR/adapter tuning notes.
- `writer/GPT/sat/next_experiments.md` — the ongoing experiment plan.
