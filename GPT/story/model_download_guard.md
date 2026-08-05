# Model download guard (BASE-fork of download_model)

Session: 2026-08-05.

## What was fragile

`node_modules/@jahbini/pipeline/scripts/model/download_model.coffee`
has three existing guards at the top of its action:

- Directory has weights + matching provenance → skip download.
- Directory has weights + wrong provenance     → throw.
- Directory has weights + NO provenance        → throw.

BUT: if the directory is present without a recognizable weight file
(a partially downloaded / interrupted state — exactly what a killed
LFS pull leaves behind), the code falls through to the retry loop
where `removeTargetDirectory targetDir` runs at the START of every
attempt. That auto-wipes the target with no confirmation. If a good
model happened to be there (e.g. weights renamed, or a directory
that wasn't a download in progress at all), the retry destroys it.

That gap is the story behind "I killed a download that wouldn't
die and now I don't know if the existing model is corrupt."

## Where the fix lives

Local fork at `scripts/model/download_model.coffee` (i.e.
`BASE/scripts/model/download_model.coffee`). The runner resolves
`run: model/download_model.coffee` in the order `[CWD, BASE, EXEC]`
(`pipeline_runner.coffee:144`), so the BASE fork shadows the
package copy for every pipe without editing node_modules.

## Guard semantics

After the "present + hasWeights + provenance-matches → skip" and
"present + hasWeights + provenance-mismatch → throw" branches, the
fork adds:

- If the target directory exists with ANY entries and the run has
  not opted in with `allow_overwrite: true`, throw a contextual
  error naming:
  - the directory path,
  - which state it appears to be in (partial download vs weights-
    without-matching-provenance),
  - the first ~8 directory entries so the human can eyeball,
  - the two ways forward: `rm -rf` the dir, or set
    `allow_overwrite: true` in the step's override.

Only `present && !allow_overwrite` throws. An empty target dir
(the fresh-pipe case) still proceeds normally through the retry
loop, and once inside the loop the intra-run remove-and-retry
behavior is unchanged — that's a robustness feature for LFS
flakiness within a single authorized run.

## Escape hatch

To authorize a wipe explicitly, in the pipe's override.yaml:

```yaml
download_model:
  allow_overwrite: true
```

Remove that key once the download completes so a future killed run
can't inherit the permission.

## Related

The bigger picture: `pipeline_runner.coffee:2077-2079` acknowledges
the runner has no clean cancellation protocol, so killed downloads
are common. The UI's kill button was also patched
(`ui_server.coffee:1269`, SIGTERM → SIGKILL escalation after 1 s)
so kills at least happen bounded-time. This guard covers what
happens to the on-disk state after such a kill.
