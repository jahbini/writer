# Celarien Muse — the human's boilerplate for calling a voyage chapter

Read this first if you're about to run a celarien voyage. It tells you
what to fill in, what you get back, and what you cannot control.

The machine is deterministic: **same input, same voyage, byte for byte.**
Change one comma in your author_description and you get a different
seed and a different voyage. Nothing else about the pipeline is random.

---

## The one-thing you fill out

Everything you need to enter is on the puppeteer UI at
**http://localhost:4311**, in the **Celarien Setup** panel.

Three fields. That's it.

```
┌─────────────────────────────────────────────────────────────┐
│  Author description                                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  (freeform text — a paragraph or a sentence)            │ │
│  │                                                         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  chapter_count  [ 24 ]        act_count  [ 4 ]               │
│                                                              │
│  [ Save ]                                                    │
└─────────────────────────────────────────────────────────────┘
```

### Author description — what to write

The **author description** is a freeform seed for the entire voyage.
SHA-256 of the text produces a 32-bit integer seed that drives every
draw (situation, moving lines, fortune, passenger, pool picks). The
CONTENT of the text does not steer the story — only the hash-derived
seed does. What you write influences the arc only through the hash.

**Practical implication:** the words themselves are for YOU. Write
something that lets you tell one voyage from another later. Examples:

- `"A voyage that gets the crew home with less than they left with."`
- `"The captain's last season before he stops sailing."`
- `"Amazons in charge for the middle third."`
- `"A voyage where the athlete disappears at Corinth."`

Change any character → different seed → different arc. Keep the same
string → same arc, byte for byte, on any machine.

**Length:** any length works. Empty string is technically legal (all
zeros seed) but you should type SOMETHING you can remember.

### chapter_count

How many chapters in the voyage. Default **24**. Legal range: 4–120.

More chapters = longer voyage, more diverse situations drawn from the
class families, more fortune curve visible. Fewer chapters = tighter
season. `chapter_count=12` is a reasonable "half-season."

### act_count

How many acts the voyage is divided into. Default **4** (one per goal
stone: ensophia, enaxia, eusophia, euaxia). Legal range: 1–12.

Threshold chapters (oracle / underworld) land at each act's last
chapter. So with `chapter_count=24, act_count=4`: thresholds at 6, 12,
18, 24.

---

## What you cannot control

The following are all set by the seed. You cannot request a specific
value. If you want a different result, change the author_description.

1. **Which hexagram each chapter draws** — deterministic pick from that
   chapter class's family. (Class families are defined in
   `data/celarien_story_library.yaml`.)
2. **Which moving lines are drawn** — 3, 4, or 5 lines, picked
   randomly (but deterministically) from positions 1–6.
3. **The derived situation** — computed by bit-flipping the drawn
   moving lines on the situation's glyph_binary.
4. **The chapter's fortune** — one of {riches, success, setback,
   defeat, bankruptcy}, drawn from a landward-drifting mean-reverting
   curve. Early chapters skew positive; late chapters skew negative.
5. **Aperture on threshold chapters** — oracle or underworld,
   deterministic per chapter.
6. **Pool picks** (scenes, characters, disturbances, soundings,
   bearings) — deterministic slug selections from the library's pool
   entries.
7. **The class sequence** — always cycles
   `port_trade → games → pirates → crew_conflict → port_trade …` with
   `threshold` inserted at each act boundary.

You can OVERRIDE the class sequence with a `class_sequence` param at
the recipe level (in `~/puppeteer/override/celarien_prep.yaml`), but
that's an advanced knob, not part of the boilerplate.

---

## What the machine will produce

After you fire the celarien recipe (see "Firing" below), the
puppeteer produces four artifacts on itself:

1. `out/celarien_arc.yaml` — the raw arc plan, one entry per chapter,
   with class / aperture / situation id / moving_lines / derived id /
   fortune / passenger / pool_draws.
2. `out/celarien_filled_arc.yaml` — the same plan with each
   chapter's spread filled (mission, blocking, leaving, foundation,
   arriving, grip, crew_env, success, tip — all render-safe strings).
3. `out/celarien_directives.jsonl` — one JSON per chapter with the
   generator-ready directive (render-safe prose, no internal
   vocabulary).
4. `out/celarien_fanout_report.json` — a record of which peer pipes
   received the directives via scp.

Then, on each target peer pipe (default: `hf__qwen__qwen3-0-6b`, tune
via `override/celarien_prep.yaml`), two more artifacts appear:

5. `out/celarien_chapter_actuals.yaml` — the LLM-generated chapter
   text, keyed by chapter_key.
6. `out/celarien_audit.yaml` — per-chapter audit: invariants intact?
   success criterion met? tip landed? regen needed?

---

## What YOU must do to fire it

1. **Open http://localhost:4311** on the puppeteer.
2. **Fill in the Celarien Setup panel:**
   - Author description: your seed text.
   - chapter_count: default 24 is fine.
   - act_count: default 4 is fine.
   - Click **Save**.
3. **Fire the puppeteer recipe.** For now, you or the CLI do this via:
   ```
   cd ~/puppeteer && rm -f pipeline.json state/step-*.json state/queue_state.json
   cat > control_override.yaml <<'EOF'
   pipeline: celarien_prep
   EOF
   nohup coffee node_modules/@jahbini/pipeline/pipeline_runner.coffee \
     > logs/celarien_prep_$(date +%H_%M).log 2>&1 & disown
   ```
   (Or ask the CLI to do it — "fire celarien_prep on the puppeteer".)
4. **Watch the log.** In `~/puppeteer/logs/celarien_prep_HH_MM.log`
   you'll see:
   - `[novel_arc_generator] emitted N chapters (seed=…)`
   - `[celarien_directive_ite] filled N chapters; N directives emitted`
   - `[celarien_fanout_ite] <pipe> scp'd (directives + filled_arc)`
   - `[queue_run_ite] launched anchor=…`
5. **When the peer finishes**, read
   `<peer>:writer/pipes/<pipe>/out/celarien_audit.yaml` for the
   chapter-by-chapter grades and any regen triggers.

---

## What YOU must obey — the hard rules

These are baked into the CELARIEN.md briefing and are enforced by the
code + validators. You cannot violate them via the panel or the
overrides; the machine will refuse or the audit will breach.

1. **The seed is the seed.** If you want a different voyage, change
   the author_description. Do not try to nudge specific chapters by
   editing artifacts mid-run — the plan is authored wholesale in one
   pass, and there is no chapter-to-chapter state inheritance.
2. **Do not edit the library** (`writer/data/celarien_story_library.yaml`)
   or the iching files (`iching_situations.yaml`,
   `iching_casting.yaml`) casually. Schema problems get reported to
   `writer/GPT/story/celarien_status.md`, not silently fixed.
3. **Chapter contract is law.** Invariants:
   - Crew survives (mortal:false cast — captain, amazons, athlete —
     cannot die, be maimed, or leave the ship).
   - The voyage continues (ship afloat, next chapter reachable).
   - At most one mythic aperture per chapter (threshold chapters get
     one; others get zero).
   - No new named characters beyond the chapter's planned passenger.
   Any generation that breaches these is flagged in the audit with
   `regen_needed: true`. You don't rescue it by edit; you regenerate.
4. **Persistent facts are planned facts.** Everything the crew
   "knows" across chapters comes from the pre-planned spine —
   allowed_names, invariants, waystones. Improvised facts (a
   generator invents a new bar, a stranger, a piece of weather) are
   chapter-local color and never obligate future chapters.
5. **Chapter outcomes are temporary; the series axis is not.** The
   sea empire is losing to the land kings. Every chapter takes place
   under that pressure; the fortune curve reflects it. Individual
   chapters may win or lose; the arc drifts landward.
6. **The captain's practice is not a winning formula.** He asks
   "Do I like this?" and "Which way is up?" — the practice governs
   HOW fortune is met, not WHETHER fortune arrives.
7. **No LEPA vocabulary, hexagram numbers, spread position names, or
   `internal:` keys should ever surface in the rendered chapter.**
   If they do, that's a hygiene breach — report it in the audit and
   file a bug against the directive builder.

---

## Iterating

- **Different voyage, same intent:** change one character in the
  author_description. The whole arc re-rolls.
- **Same voyage, different length:** change `chapter_count`. The
  class sequence extends or contracts; per-chapter draws re-derive.
- **Same voyage, different structural pacing:** change `act_count`.
  Threshold positions move; goal stones distribute differently.
- **Different fan-out target:** edit `target_pipes` in
  `~/puppeteer/override/celarien_prep.yaml`. Anything with
  `use_celarien_arc: true` capacity can receive the directive.
- **Larger first run:** raise `max_chapters` in the peer's
  `override/celarien_run.yaml`. Default is 3 chapters (bounded first
  run, ~5–10 min on a 0.6B pipe). 24 chapters is the full voyage;
  expect much longer runtime, especially on smaller models.

---

## The rest of the plumbing

For architectural / theoretical detail:

- `writer/CELARIEN.md` — Geemo's original briefing (design authority
  stays with Geemo; report progress to
  `writer/GPT/story/celarien_status.md`).
- `writer/GPT/story/grand_scheme.md` — the whole-machine flow: mode
  selector → spine generator → directive → fan-out → eval → edit → T2V.
- `writer/GPT/story/celarien_status.md` — SUPERVISOR-style report
  covering Phases 1–4 + the puppeteer/peer refactor.
- `writer/GPT/story/samples/celarien_sample_arc_default_seed.yaml`
  and `writer/GPT/story/samples/celarien_sample_directives.yaml` —
  reference outputs from the standard demo seed.

If you're wondering "why does this rule exist" for anything above,
it's in CELARIEN.md's Invariants block. All the safety rails are
there so this thing produces coherent, faithful voyages under a
random iching draw — not so it can be edited into producing
something specific.
