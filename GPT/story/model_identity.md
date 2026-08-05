# Model identity — where it lives

Session: 2026-08-05.

## Rule

**The model is a pipe fact, not a recipe fact.**

Recipes do NOT set `run.model`. Every pipe declares its own model
identity in its `override.yaml`:

```yaml
run:
  model: <org>/<model-name>
```

## Rationale

The old pattern hardcoded `run.model: Qwen/Qwen3-4B-Instruct-2507`
in each recipe's `run:` block, then relied on pipe-level overrides
to swap it. That produced two failure modes:

- A fresh pipe with no `run.model` override silently inherited
  `Qwen/...` from the recipe, downloaded the wrong model, and
  gave no visible clue what happened.
- Pipes were named after the model they *should* use (e.g.
  `pipes/Huihui-Qwen3-4B-Instruct-2507-abliterated`) but nothing
  enforced the correspondence — the recipe still won unless the
  override was explicitly present.

Naming-based inference isn't strong enough: some pipes
(`pipes/story`) don't encode a model in their name; some model ids
don't map cleanly to a pipe directory name.

## What changed (2026-08-05)

- `config/story.yaml` — stripped `run.model`. Comment marks the
  removal.
- `config/spystory.yaml` — stripped `run.model`. Same comment.
- `config/reset.yaml` — new BASE-fork at `writer/config/reset.yaml`
  shadowing `node_modules/@jahbini/pipeline/config/reset.yaml`
  (which still ships with the Qwen default). BASE fork strips it.
- `scripts/model/download_model.coffee` (existing BASE-fork) still
  throws `Missing model param` when no `run.model` is in the merged
  experiment — this is the loud-fail behavior the rule relies on.

## Provenance file (post-download record)

After a successful download, the step writes
`build/model/model_provenance.json` (VISIBLE — no leading dot) and
chmods it read-only (0o444). Renamed from `.model_provenance.json`
2026-08-05.

Constraints, all satisfied:

- **Name has no leading dot** — `ls` shows it without `-a`.
- **Read-only after write** — chmod 0o444 by the download step so
  a stray `cat > model_provenance.json` cannot silently corrupt
  the provenance. The write path chmods to 0o644 first if a
  read-only version already exists, writes, then re-chmods back.
- **Content unchanged** — same JSON payload
  (`{model_id, repo_url, recorded_at}`) that
  `readProvenance()` already understands.

Downstream consumers (the provenance-match guard) call
`provenancePathFor(targetDir)` which now returns the visible name;
the mismatch/no-provenance/skip-download branches all Just Work.

## Rename for existing installs

None here — the shared `build/model/` did not have any provenance
file at the time of the cutover, so nothing to rename. On any
machine where a pre-cutover `build/model/.model_provenance.json`
survives, rename it:

```sh
mv build/model/.model_provenance.json build/model/model_provenance.json
chmod 0444 build/model/model_provenance.json
```

The read helper looks up ONLY the new name — a legacy dot-file
will look like "no provenance recorded" and the download step will
throw the appropriate contextual error.

## Pipes currently in the tree

- `pipes/story/override.yaml` — no `run.model` set. story never
  invokes `download_model`, so this doesn't crash it today. If the
  human later runs `reset` in this pipe, they must add `run.model`
  to the override first.
- `pipes/story/override/spystory.yaml` — sets
  `run.model: huihui-ai/Huihui-Qwen3-4B-Instruct-2507-abliterated`.
- `pipes/Huihui-Qwen3-4B-Instruct-2507-abliterated/override.yaml` —
  sets `run.model: huihui-ai/Huihui-Qwen3-4B-Instruct-2507-abliterated`.
  Ready to run `reset` / `download_model` there.
