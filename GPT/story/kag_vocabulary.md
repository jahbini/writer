# KAG emotion vocabulary

Session: 2026-08-06.

## The set (17 keywords)

Original Ekman-adjacent core (12):

    joy, contentment, sadness, grief, fear, anxiety, anger,
    frustration, disgust, shame, surprise, neutral

Register additions (5, added 2026-08-06):

    absurd, wry, playful, melancholy, mysterious

## Why the additions

The Ekman set collapses Jim's dominant register into ill-fitting
buckets. From an oracle_probe run: the "rent-a-used-fencepost"
phrase got tagged `disgust` because that was the least-bad option
in the 12 — the actual register is *absurd*. Same shape for
Southwick-and-Tommy banter (should be `playful`, not `joy` /
`surprise`), letter-closing aphorisms (`wry`, not `contentment`),
tender asides about aging or lost places (`melancholy`, not
`sadness`), and Southwick's alien-myco-probe pronouncements
(`mysterious`, not `surprise` / `neutral`).

The story pipeline reads emotion as a single flat axis
(`collect_diary_kag_ite` picks one keyword per kind and retrieves
chunks tagged with it). Adding categories to the axis fits that
model with no schema or retrieval change — the runtime cost is
that `kag_entries` has zero rows tagged with the new keywords
until a fresh oracle pass writes them.

## Files that carry the set

- `~/pipeline/scripts/kag_oracle_ite/oracle_ask_sqlite.coffee` —
  `ALLOWED_EMOTION_KEYWORDS` set + the fallback regex inside
  `normalizeAllowedEmotionKeyword`.
- `~/pipeline/config/oracle_ite.yaml` — the prompt block that
  tells the LLM what keywords it may emit.
- `writer/config/oracle_ite.yaml` — BASE-fork of the above so the
  writer's pipes see the new prompt (BASE shadows the pinned
  github tarball at `writer/node_modules/@jahbini/pipeline/`).
- `writer/node_modules/.pnpm/.../oracle_ask_sqlite.coffee` —
  interim direct copy so the writer's live oracle runs use the
  new set until the tarball pin is bumped.
- `writer/pipes/story/scripts/collect_diary_kag_ite.coffee` —
  docstring updated (was hardcoded "12 corpus keywords").
- `writer/pipes/story/data/dramatic_grammars.yaml` — header
  comment updated (same reason).
- `writer/test/spy_grammar_probe.coffee` — `CORPUS_EMOTIONS` set
  extended so future kag_emotion values in grammars can use the
  new keywords without failing lint.

## Grammar values today

Both `jim_tragedy` and `spy` grammars in `dramatic_grammars.yaml`
still use only the original 12 (frustration, surprise, anxiety,
fear, sadness, shame, contentment, anger, joy, grief). No change
needed to the shipped grammars; the new keywords are AVAILABLE
for grammar authors to reach for. A follow-up pass on
`jim_tragedy` might reroute a couple of `dramatic_functions` to
absurd / wry / melancholy — e.g. `resolve_a_question` from
contentment to wry — but that's a taste call.

## Populating the corpus

`kag_entries` won't have rows tagged with the new keywords until
a fresh oracle pass processes stories with matching content.
Retrieval by `absurd` returns `[]` today. Ways to get coverage:

1. **Re-run oracle on all stories.** Delete
   `runtime.sqlite:kag_entries` (or run reset in the pipe) and
   re-tag. Expensive but produces uniform coverage.
2. **Iterative addition.** Leave existing rows alone; run oracle
   only on stories currently missing KAG. New stories get
   classified against the full 17 immediately, but existing 1104
   entries in the story pipe stay 12-only. Grammar-derived
   `frustration` retrieval still works; `absurd` retrieval stays
   empty until new content lands.
3. **Manual back-fill.** For a small set of known-absurd chunks,
   INSERT rows by hand with `keyword='absurd'`. Cheap way to
   validate the retrieval path before committing to a full
   re-tag.

Option 2 is the safe default. Choose the others when you're
willing to burn the LLM time for coverage.
