# The spine library — `~/writer/data/spines/`

Built 2026-09-21. Formalizes the "diary_prompt_text" artifact from
the story recipe as a reusable, human-referenceable name. Each
`data/spines/<name>.txt` is a completed `diary_prompt.txt` bundle:
voice framing + KAG passages + character constraints + "Begin writing
the letter now" — everything the final voice model needs, in one
file, verbatim-feedable to `L.callLLM`.

## Why spines exist

The story recipe's structural steps (outline / spine / beats /
scene_planner / KAG collect / build_diary_prompt) are the hard
cognitive work. Small models (0.6B, 1.7B) fail at them. Big models
(4B, 4B-Instruct-2507) succeed. But the *voice* work at the end —
turning the built prompt into a Jim letter — is a smaller task
that even 0.6B can do (with sampling adjustments).

Decoupling the two lets:
- Structural work happen once, on ONE big pipe.
- Voice work fan out to every pipe with its own adapter/model.
- Fair voice-only comparison across pipes: same prompt, same
  constraints, different voice weights.

The spine library is the archive of these ready-to-use prompts.
Once authored, they're portable and durable.

## Current inventory (as of 2026-09-21)

- **`serf_insults_queen.txt`** (15,313 B) — the initial demo spine.
  Serf insults queen; king executes serf. A scene-heavy prompt with
  four numbered moments. Tends to elicit mechanical scene-by-scene
  planning from the models.
- **`susannas_song.txt`** (16,606 B) — Susanna talks her way into
  staying home during a thunderstorm; uses her mother's phrase "Not
  if I have anything to say about it" as a mantra. Better voice
  triggers than the serf spine because it's Jim-native material
  and the mantra gives a clear rhetorical hook to reprise at the
  end.
- **`bouncy_boom.txt`** (11,997 B) — Bouncy Boom born mid-jam at a
  rigged Roller Derby match; mother skates a victory lap holding
  the newborn; they flee mob revenge into 18 years of hiding.
  Wildest content — good stress test for "how far from normal will
  a small model wander."

## The generation flow (how a spine gets made)

1. Human decides on a story description (2-3 sentence prompt).
2. Fire `story` recipe on a capable pipe (4B-Instruct-2507 works;
   0.6B fails at `story_outline`).
3. Wait ~5-10 min for the structural chain to run through
   `build_diary_prompt_ite`.
4. Pull `<pipe>/out/diary_prompt.txt` off the peer to
   `~/writer/data/spines/<name>.txt`.

Once saved, the spine is durable and can be referenced by name from
any voice_test / voice_tournament / sat_tournament run.

## How to reference a spine

Recipe: name it in `voice_from_prompt.spine` — the step reads
`data/spines/<name>.txt` via the meta layer (BASE tier wins), copies
content to `out/diary_prompt.txt` for UI visibility, then feeds it
to `L.callLLM`.

Fanout: puppeteer's `voice_tournament_dispatch` and `sat_tournament`
recipes accept a `spines:` list param — every listed spine fans out
to every target pipe.

## Design principles

- **Fixed for comparability.** Canonical spines shouldn't change
  once they're used in a tournament. If the spine changes, every
  prior rating on that spine is invalidated. Add new spines
  liberally; edit existing ones with archaeological care.
- **One prompt = one file.** No indirection, no templates, no
  substitutions at run time. What's in the file is exactly what
  goes to the model. Reproducibility depends on this.
- **Voice test material, not everything.** Spines are for
  *diary-letter* generation. A future recipe for headlines,
  outlines, or dialogue would use its own library subdir (say
  `data/spines/headlines/`) with a different prompt shape.
- **Grow the set deliberately.** Every new spine adds a permanent
  axis to the tournament matrix. Two dozen is probably the useful
  cap; a single tournament with 24 pipes × 24 spines would be 576
  matchups and no human would finish judging.

## UI surface

Puppeteer UI Voice Tournaments panel (sub-section "Spines library")
enumerates every `data/spines/*.txt` with byte count. Endpoint:
`/api/spines`. See `puppeteer/GPT/design/voice_tournament.md`.

## Related

- `puppeteer/GPT/design/voice_tournament.md` — how spines are used.
- `writer/GPT/story/grand_scheme.md` — the mode → spine → directive
  → fan-out → eval → edit → T2V North Star this is one step of.
- `writer/config/voice_test.yaml` — the recipe that eats a spine.
