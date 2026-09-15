# storacle_observations — human notes corpus for helper training

> **Status 2026-09-15**: Phase 1 built and live on the peer. Peer table exists, meta rules registered, HTTP endpoints `POST /api/storacle_observation` (create+update) and `GET /api/storacle_observations` respond, writer UI "📝 Save Observation of Previous Storacle Run" button captures, "Captured Observations" panel lists with editable notes + Save Notes button. Auto-links `lora_run_id` from `lora_training_runs`. Phase 1b (puppeteer sync poll + durable archive + peer_pipes popup) still to build.


## Purpose

Capture qualitative human observations about storacle outputs, with
enough provenance that a downstream reader (helper LLM, human
reviewer) can reconstruct what caused what. No numeric scores — the
notes carry meaning that numbers would flatten. Confirmed by user
2026-09-15: "we will learn lots of techniques that don't translate
well into numbers. But added to the knowledge of the helper, might
give it good insight into prompts and parameters."

## Not a hard scoring system

- No score column. Never add one until we've learned enough about
  what makes an output "good" that a number would carry meaning.
- Auto-capture is off. Only saves when the human explicitly clicks
  "Save observation" in the writer UI after a storacle run.
- Panel shows only captured rows. Uncaptured runs are noise.

## Schema (per-pipe `runtime.sqlite`)

```sql
CREATE TABLE storacle_observations (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  observed_at       TEXT NOT NULL,
  storacle_logdir   TEXT,           -- 'storacle_HH_MM' — points at per-run log dir
  adapter_path      TEXT,           -- '' or 'build/adapter'
  lora_run_id       TEXT,           -- FK → lora_training_runs.run_id; nullable
  adapter_mtime     TEXT,           -- mtime of adapters.safetensors when observed
  story_id          TEXT,           -- nullable
  prompt_text       TEXT NOT NULL,
  think_prefill     TEXT,           -- nullable
  use_kag           INTEGER,        -- 0/1
  use_chunks        INTEGER,
  rag_top_k         INTEGER,
  llm_config_json   TEXT,           -- full generation config
  generated_text    TEXT,           -- raw output
  notes             TEXT,           -- freeform human observation
  noted_by          TEXT
);
CREATE INDEX idx_storacle_observations_observed_at
  ON storacle_observations (observed_at);
CREATE INDEX idx_storacle_observations_lora_run_id
  ON storacle_observations (lora_run_id);
```

## Capture flow (UI + API)

1. Storacle run finishes → writer UI shows "Save observation" button
   alongside the generated_text.
2. Click → POST to `/api/storacle_observation` with the current
   run's config + generated_text. Server:
   - Reads `~/writer/pipes/<pipe>/build/adapter/adapters.safetensors`
     mtime and stats it, if adapter is on.
   - Looks up the most recent `lora_training_runs` row where
     `adapter_path='build/adapter'` and `finished_at ≤ adapter_mtime`.
     That's the training run that produced this adapter.
   - INSERTs the observation with empty `notes`.
   - Returns the new row id.
3. Panel refresh → the row appears in the "Captured observations"
   list with an editable `notes` textarea.
4. Edits to `notes` are POSTed back and UPDATE the row.

## Durable archive on puppeteer (2026-09-15 refinement)

The peer's per-pipe `storacle_observations` is transient. Pipes get
wiped (as we've been doing to force clean re-runs — 2026-09-15
alone: multiple wipes on the 4 newborn pipes). Any observations
captured before a wipe would be lost unless mirrored somewhere
durable. User directive 2026-09-15: "keep the puppeteer's sqlite as
up to date as you can, these scores should last a long time, and no
deletions."

- **Puppeteer's `storacle_observations` is the durable archive.**
  Same schema plus three sync-side columns: `peer_host` (string,
  future-proof for >1 peer), `id_at_source` (the id assigned by the
  peer's sqlite), `synced_at`.
- **Sync-side natural key**: `(peer_host, pipe, id_at_source)`. Poll
  cadence 30–60 s: SSH to each peer, SELECT rows with
  `updated_at > last_synced_updated_at`, INSERT-OR-REPLACE into the
  puppeteer's copy.
- **`updated_at` on both sides.** Bumped on INSERT and on any note
  UPDATE. Sync uses it for delta pulls AND conflict resolution
  (peer's newer `updated_at` wins on note UPDATEs).
- **No deletion path exists.** Meta rules define no delete op.
  Neither UI offers a delete button. If a peer-side row vanishes
  because its pipe got wiped, the puppeteer's archived copy stays.
  The archive is append-only forever — the corpus size is bounded
  by how often the human clicks "Save observation," not by any
  cleanup policy.

## Puppeteer popup panel (phase 1b — same session as capture)

The puppeteer driver needs visibility into these observations for
scheduling decisions ("this pipe's adapter has 3 observations saying
'too repetitive' — retrain before promoting"). Design:

- **Trigger**: `peer_pipes` panel row for each pipe carries a
  `📝 obs (N)` button. `N` is the count of captured observations
  (cheap SSH + SELECT COUNT, cached briefly). Click → popup.
- **Data source**: the puppeteer's OWN sqlite. The popup does not
  SSH-fetch from the peer per open — puppeteer's copy is authoritative
  for archival and is kept current by the sync poll (see "Durable
  archive on puppeteer" above). This makes the popup instant and
  works even when the peer is offline.
- **The badge count** on the peer_pipes row (`📝 obs (N)`) is a
  cheap SELECT COUNT against the puppeteer's local table — no SSH,
  no cache warming needed.
- **Popup content** (reverse-chronological):
    - date, prompt (truncated, click to expand)
    - generated_text (truncated, click to expand)
    - config tags: `temp=0.5`, `adapter=on/off`, `kag=on/off`,
      `chunks=on/off`, adapter provenance link showing `lora_run_id`
      if any
    - notes (multi-line, not truncated)
- **Read-only in puppeteer.** Edits stay on the writer UI where the
  human sees the generation live. This keeps notes-editing single-
  writer and avoids cross-host update races.

## Ingestion into helper corpus (phase 2)

Puppeteer step, not part of phase 1:
- Poll each pipe's `storacle_observations` on some cadence.
- Rows with non-empty `notes` and not-yet-ingested get copied into
  puppeteer's `helper_training_examples` with `source='storacle_observation'`.
- Helper's training bundle then includes them alongside the failure
  classifier data.

## Design principles

- **Provenance is more important than judgment.** Every knob that
  changed the output gets stamped. Later readers reconstruct
  conditions, don't just read verdicts.
- **The `notes` field is prose, not tags.** Users write full
  sentences. That's what the helper trains on.
- **Adapter versioning via lora_run_id.** An observation of an
  adapter is only useful if you can trace which training produced
  the adapter. Without it, you can't compare across retrainings.

## Not-yet-designed follow-ons

- A/B panel: side-by-side generations with the same prompt at two
  adapter versions. Compare bland-vs-adapter, or old-adapter vs
  new-adapter.
- Batch replay: re-run captured prompts against a new adapter and
  capture the deltas.
- Query-by-note: helper reads all observations matching a keyword
  ("repetition", "too formal", "missed the ending") to find failure
  modes.
