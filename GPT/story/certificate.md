# Certificates — human-administered lifecycle gates

**Introduced**: 2026-10-09. Replaces the ad-hoc "flip the State
dropdown after reading storacle output" workflow with a durable,
auditable per-pipe artifact.

## What a certificate is

`out/certificate.yaml` on a writer pipe — a frozen snapshot of a
single storacle run plus a human verdict. The puppeteer scans
certificates on every `hf_scan` tick, applies the verdict as a
state transition, and archives the file to
`out/certificates/<stage>-<graded_at>.yaml`.

One live certificate at a time per pipe. Previous certs live in the
archive dir forever (append-only record of every stage transition
the pipe has gone through).

## Shape

```yaml
pipe:   hf__qwen__qwen3-0-6b
stage:  newborn            # auto-filled from the pipe's current state at submit time
test:
  prompt_text:  "retell this story in your best voice\n{{{FRAGMENT_1}}}…"
  story_id:     anna-played-piana-md
  story_title:  Anna Played Piana
  story_text:   |
    …the entire story body as fed to the model, pulled from runtime.sqlite
    at submit time so the certificate is a self-contained archive…
  response:     |
    …the exact text storacle emitted (from out/storacle_text.txt or _raw.txt)…
  llm:
    model_dir:          /Volumes/bigbig/models/Qwen/Qwen3-0.6B-Base-mlx4
    adapter_path:       null
    temperature:        0.7
    maxTokens:          200
    topP:               0.9
    repetition_penalty: 1.4
    presence_penalty:   1.5
    think_prefill:      ""
  generated_at:   2026-10-09T12:34:56Z
  prompt_tokens:    717
  generated_tokens: 3000
  elapsed_sec:      36.5
grade:
  verdict:   pass           # pass | hospital | graveyard
  comments:  |
    Model answered coherently; subject-verb agreement held; name
    inference was correct. Promote to elementary.
  graded_at: 2026-10-09T12:40:00Z
  graded_by: jahbini
```

## Verdict vocabulary

The three verdicts (and only these three — the scanner refuses
unknown values):

| Verdict      | Scanner action |
|--------------|---------------|
| `pass`       | Promote per the transition table below. |
| `hospital`   | Set state → `hospital` (holding pen; disk preserved). |
| `graveyard`  | Set state → `rejected` (cemetery; disk eventually cleaned). |

## Promotion rules (`pass` only)

The scanner reads the pipe's current state in `pipe_states.json` and
promotes it per `PROMOTION_PASS` in
`puppeteer/scripts/certificate_scan_ite.coffee`:

| From state   | → next state  | Meaning |
|--------------|---------------|---------|
| `newborn`    | `continue`    | Enters the elementary queue. |
| `continue`   | `SAT`         | Triggers SAT-2 param tuning. |
| `SAT`        | `graduated`   | Tournament contestant. |
| `graduated`  | `graduated`   | No-op — already terminal; cert still archives. |
| `hospital`   | `continue`    | Released from hospital. |
| `rejected`   | `continue`    | Resurrection (rare but allowed). |

A certificate can therefore walk a pipe `newborn → continue → SAT →
graduated` across four stage-gated grading passes. Each stage asks
its own "is this good enough?" and the human can inject
`hospital`/`graveyard` at any point to divert.

## Create path (writer plugin)

`writer/ui/project.coffee` ships two endpoints:

- `GET /api/certificate` — returns `{pipe, state, stage,
  storacle_present, storacle_meta, storacle_text,
  current_certificate}`. The Writer UI's Certificate panel polls
  this via `refreshCertificate()`.
- `POST /api/certificate` — body `{verdict, comments, graded_by?}`.
  Preconditions:
  - `out/storacle_meta.json` must exist (no storacle output = can't
    certify; returns 400 "no storacle output in out/ — nothing to
    certify").
  - `verdict` must be one of `pass | hospital | graveyard`.
  Behavior:
  - Reads `storacle_meta.json`, `storacle_text.txt` (or
    `_raw.txt`), and `runtime.sqlite`'s `stories` table to freeze
    `test:`.
  - Reads `BASE_ROOT/state/pipe_states.json` to infer current
    `stage:`.
  - If a prior un-consumed `certificate.yaml` exists, archives it
    first before overwriting (preserves graded-but-unscanned history).
  - Writes `out/certificate.yaml` atomically-ish (dump + write).

## Consume path (puppeteer scanner)

`puppeteer/scripts/certificate_scan_ite.coffee`, wired into
`hf_scan.yaml` immediately after `caffeinate_ite` and declared as a
dependency of `hf_queue_gen_ite` so promotions land in the queue
regeneration **this tick** rather than next.

Per tick:
1. Enumerates pipes with a live `out/certificate.yaml` (local fs
   walk when co-located with the mini, SSH `ls` otherwise).
2. For each: reads the cert, validates verdict, computes next state
   via the table above, writes the transition into
   `pipe_states.json` with `promoted_by: certificate` + a
   `last_certificate` provenance block.
3. Archives the consumed cert to
   `out/certificates/<stage>-<graded_at>.yaml` on the pipe side.
4. Appends a row to `puppeteer/state/certificates_log.jsonl`.
5. Emits `certificate_scan_report` artifact at
   `out/certificate_scan_report.json` with `{scanned_at, consumed,
   errors, peer_local}`.

Idempotent — once archived, the pipe has no live `certificate.yaml`
so subsequent scans skip it. A cert that fails to archive still
records the state transition; the next scan tries archive again
(mkdir -p / rename).

## Who writes `pipe_states.json`

Multiple writers touch this file:

- Puppeteer UI (`project.coffee` → `handlePipeState`): manual
  dropdown flips, carries no `promoted_by` tag.
- `certificate_scan_ite`: carries `promoted_by: certificate` and a
  `last_certificate` block.
- Other scheduler helpers (`sat_pipe_selector`, legacy flips).

Readers that want to distinguish "human flipped the dropdown" from
"certificate scan promoted it" check `promoted_by`.

## Peer_pipes panel integration

The eligibility hint in the puppeteer peer_pipes panel (writer's
plugin doesn't own this) shows:

- newborn: `⏸ awaits human: review audition, then flip State → elementary`
  — this will migrate to `⏸ awaits human: run storacle, review out/,
  click Certificate` once the certificate flow is the sole promotion
  path.
- Future: a "latest certificate →" link per row that opens the
  archive dir.

## Related

- `~/writer/ui/project.coffee` — writer plugin certificate endpoints.
- `~/writer/ui/index.html` — Certificate panel + `refreshCertificate()`
  + `submitCertificate()`.
- `~/puppeteer/scripts/certificate_scan_ite.coffee` — the scanner.
- `~/puppeteer/config/hf_scan.yaml` — scanner wiring.
- `~/puppeteer/GPT/ui/project_plugin.md` — peer_pipes panel + states.
- `~/pipeline/config/newborn.yaml` — the recipe that produces the
  storacle output a newborn certificate attests to.
