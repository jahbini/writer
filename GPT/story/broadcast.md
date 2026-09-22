# Broadcast — headline + epilogue for a story, ready to post

Built 2026-09-22. Small dedicated recipe that turns a completed
story into shareable snippets for X (Twitter), Facebook, email
subject lines, and newsletter preheaders. Runs on the Qwen3-0.6B
writer pipe, per the punctuation-model assignment in
`writer/GPT/story/model_roles.md`.

## Flow

1. **Pick a candidate story.** Tournament winner, other pipe's
   output, any text file.
2. **Drop it at** `~/writer/pipes/Qwen3-0.6B/out/story.txt` (or set
   `story_file:` to any path relative to the pipe CWD).
3. **Fire** `pipeline: broadcast` on the Qwen3-0.6B pipe.
4. **Recipe shotgun-generates** N headlines + N epilogues (default
   N=5) at temperature spread 0.85 → 1.05. Each is one line, short.
5. **Review page** rendered at
   `out/broadcasts/<story>_<timestamp>.html`. Radio-button picker
   for headline + epilogue, live-preview per platform, "Queue for
   publishing" button.
6. **Puppeteer UI panel** (Broadcast Review) at
   http://localhost:4300 lists every broadcast run across writer
   pipes and links to the review page.
7. **Human picks winners** and hits Queue. Choice appends to
   `~/puppeteer/state/broadcast_queue.jsonl` — one row per queued
   bundle, awaiting a future publishing tool.

## Files

- `writer/config/broadcast.yaml` — recipe, one step.
- `writer/scripts/broadcast_ite.coffee` — the step. Extracts the
  story's first substantive paragraph (hook) and last paragraph
  (closer). Builds headline + epilogue prompts. Shotgun-generates
  candidates at spread temperatures. Emits three JSON artifacts
  (`broadcast_headlines_jsonl`, `broadcast_epilogues_jsonl`,
  `broadcast_bundle_json`) and the review HTML.
- `puppeteer/ui_server.coffee` — `/api/broadcast_bundles` (list),
  `/broadcast_review/<pipe>/<file>` (static serve),
  `/api/broadcast_pick` (queue-append).
- `puppeteer/ui/index.html` — Broadcast Review panel calling those
  endpoints.
- `puppeteer/state/broadcast_queue.jsonl` — append-only queue.

## Queue row shape

```
{
  at:            <iso timestamp>,
  bundle_id:     <story slug>_<yyyy-mm-ddThh-mm>,
  story_path:    <path relative to pipe CWD>,
  headline_idx:  <int>,
  epilogue_idx:  <int>,
  headline:      <chosen text>,
  epilogue:      <chosen text>,
  platforms:     [twitter, facebook, email, newsletter],
  formatted:     { platform: <ready-to-paste string> },
  status:        "queued"
}
```

Future publisher tool: `tail -f` this file, take each `queued` row,
send to whichever platform, rewrite the row with `status: "sent"`
(or "failed" with an error). This file is the ONLY handoff between
the writer's judgment and the actual posting infrastructure —
which means the publisher tool can be built independently of
everything else and just consume the queue.

## Configuration knobs

Recipe defaults (`broadcast.yaml`):

- `story_file` — path to the story. UI_textarea.
- `spine` — optional spine name for structural anchoring. UI_textarea.
- `n_candidates` — how many candidates per output type (default 5).
- `headline_max_words` — hard cap on headline word count (default 15).
- `platforms` — which platforms to render bundles for.
- `quantized_model_dir` — `${run.quantized_dir}` from pipe foundation.

Runtime tunings inside `broadcast_ite.coffee`:

- Temperature spread: linear from 0.85 to 1.05 across the N runs.
  The caption test (2026-09-22) showed moderate temps produce
  cleaner winners than pure high-temp.
- `repetition_penalty: 1.3` — small model needs this cranked.
- `raw: true` — completion mode, no chat template. Avoids the
  0.6B's tendency to over-plan when it sees an assistant handoff.

## Known limitations

- **Auto-picker uses candidate[0] (T=0.85)** for the platform
  bundle. Not reliably the best. Human review is essential for now.
- **Copy-from-examples failure**: the 0.6B sometimes verbatim-copies
  an example line from the prompt. Real Jim-style closers (like
  "Some things you just say") happen to appear as examples AND as
  legitimate Jim endings — so the copy IS acceptable output, but
  the copy detection is not built in.
- **Off-topic drift**: at higher temps the 0.6B hallucinates
  content ("Ocean has no face", "Apocalypsis told the land
  stories"). Human review catches these.

## Design principle

The broadcast step is the **first end-to-end demonstration of the
punctuation-model role** (see `model_roles.md`). It's not a
tournament, it's not a comparison — it's a production pipeline
where the 0.6B does the thing it's supposed to do (short
crystallized text), and a human closes the loop. Every other pipe
in the fleet is for BODY work; this pipe is for BOUNDARY work.

## Related

- `writer/GPT/story/model_roles.md` — why 0.6B is the right host.
- `writer/GPT/story/spine_library.md` — the spine artifact that
  optionally provides structural anchor for headlines.
- `puppeteer/GPT/design/voice_tournament.md` — where the candidate
  stories come from.
