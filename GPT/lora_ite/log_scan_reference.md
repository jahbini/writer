# Reading `pipes/diary/logs/` — trainer eras & failure modes

Scan reference for `pipes/<pipe>/logs/pipe_HH_MM.log` (+ sibling `.err`).
Recorded 2026-07-25 from a scan of the `diary` pipe.

## Two trainer eras (how to tell them apart in a log)

- **Old ("python") LoRA path** — `run_lora_train_ite` goes straight from
  `mode: train` to `train rows: N` with **no per-step loss**. Training ran
  in a Python `mlx_lm` subprocess whose stdout was not captured inline.
  These logs typically also ran the **full cycle** (ablations → voice →
  judge → diary) and used the **BASE shared model**
  (`/writediary/build/model4`).
- **Native `[lora]` path (current, "upgrade to LLM" era)** — emits inline
  `[lora] loaded base model …`, `[lora] wrapped 72 layers (rank=R alpha=A)`,
  `[lora] step k/N train_loss=…  (x it/s)`, and `checkpoint step k →
  build/adapter/adapters.safetensors`. In-process trainer, no Python
  subprocess. Recent diary runs use a **per-pipe model**
  (`pipes/diary/build/model4`) and are **train-only** — they stop at
  `record_lora_training_ite`, not the full eval/diary cycle.

## Sweep shape (native era)

> Historical: this describes the retired incremental sweep (the old
> `full_cycle_ite` / incremental `lora_ite`). `train_lora` now trains the full
> corpus in ONE selection (`batch_size 200`), so new logs won't show the
> per-batch resume sweep — but this stays useful for reading older logs.

The old incremental train-only runs swept the corpus 4 stories × ~10 iters per
batch, **resuming `build/adapter/adapters.safetensors` every batch**.
Progress is legible from two lines: `remaining stories: X` (at select time)
and `total stories with LoRA usage: Y` (after record). Per-batch loss is
noisy/flat by design (batch-size 1, ~20 fresh sequences, resumed adapter) —
flatness here is not a fault.

## Failure modes seen (with fingerprints)

- `seed_story_sqlite` → **`Missing required artifact 'stories_md'`** (source
  `data/stories.md`). Seen immediately after `reset_base_environment_ite`
  wiped state; self-resolved on the next run. A reset can outrun
  `data/stories.md` being present at the pipe CWD.
- `oracle_ask_sqlite` → **`Cannot find module '../_helpers/cache_embedding.coffee'`**
  — a path-relative require (the CONVENTIONS anti-pattern). Historical;
  addressed by the oracle_ask_sqlite fork removal / no-op-when-fully-oracled
  commits. Should not recur on current code.
- `judge_run_ite` printing **`FALLBACK: voice_similarity unavailable`** even
  though `voice_similarity_ite` ran and produced cosines — the judge wasn't
  consuming the voice artifact, so it scored on `distinct2*100 - mem_sub*50`
  and called the adapter "worse". Check the judge↔voice handoff before
  trusting a "worse" verdict from an old full-cycle run.

## OOM (memory) kill vs clean interruption vs error — reading `fin=0`

A `fin=0` run (no `=== Pipeline finished ===`) has THREE possible causes.
Discriminate by the **last log lines** and whether a **SIGTERM banner**
is present — NOT by `.err` size:

- **OOM / memory kill (the common recent failure).** Log **truncates
  mid-step** (e.g. `[lora] step 9/10 …` is the last line), **no SIGTERM
  banner**, and **empty `.err`**. The OS SIGKILLs the process — no signal
  handler runs, nothing is written. This is a memory problem, not a bug in
  the step. Do NOT read an empty `.err` as "clean"; on a memory kill there
  is no failure log at all.
- **Clean interruption.** Log ends with `=== Signal received: SIGTERM ===`
  and lists the active step. Empty `.err`. This is a real stop (user/UI),
  and the sweep resumes at the same `remaining` count next run.
- **Step error.** Non-empty `.err` with a stack trace (e.g. the
  `stories_md` / `cache_embedding` failures above).

So: `fin=0` + empty `.err` + **no SIGTERM** + truncated mid-step = **OOM**.
`fin=0` + empty `.err` + **SIGTERM banner** = clean stop.

### OOM specifics observed (2026-07-25, native `[lora]` trainer)

- Crashes occur **even on the quantized model** (`build/model4`). Earlier
  runs that trained on the **full unquantized model** (`build/model`) were
  worse for memory — moving LoRA onto `model4` is the mitigation, not a
  cure.
- Config **drifted within one sweep**: `iters` was 20 for one batch
  (`pipe_08_51`), 10 for the rest. The 20-iter batch is one of the OOM
  deaths — longer runs give memory more time to climb.
- OOM hits at **two points**: mid-step, and at the **end-of-run checkpoint
  / model save** (`pipe_09_00` reached step 10/10 then died before writing
  the checkpoint + `record_lora_training_ite`). The save is its own memory
  spike, so "finished all steps" is not yet safe.
