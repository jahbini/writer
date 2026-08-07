# Collaboration Conventions

Rules the human has stated explicitly. Read this at session start.

## Working surface

- Freely edit `ui/`, `ui_server.coffee`, `scripts/`, `config/` without asking
  permission. These are the normal working surface.
- Do NOT edit `config/*.yaml` recipe files for tuning — use
  `override/<recipe>.yaml` instead. See `GPT/README.md`.
- Reserve confirmation for genuinely destructive actions: deleting committed
  data, force-pushing, dropping database tables.

## No parameter prescreens (longstanding human directive)

- Do NOT add defensive shape/type checks of the form
  `throw new Error "X must be an array" unless Array.isArray(x)`,
  `throw "X must be a positive integer"`, etc., at the TOP of a step
  before the value is used.
- Let the parameter fail at its actual point of use: arithmetic,
  indexing, iteration, subprocess argv construction, etc. produce a
  *rich* trace — the value, the operation, the call site — which is
  exactly what's wanted during debugging.
- A shallow prescreen replaces that rich trace with a useless tautology
  (`"X must be an array"` tells us nothing about what X *was*, where it
  came from, or what the system was about to do with it).
- This rule is universal — applies to step scripts, runner helpers,
  UI handlers, and merge tooling alike. The first writeStory variants
  of these scripts honored it; later contributors have repeatedly
  re-introduced the prescreens. They should be removed when noticed.
- The single legitimate exception is a check that produces a meaningful,
  contextual error message a downstream system genuinely cannot produce
  (e.g. cross-artifact consistency checks). Those are rare and should
  read more like a diagnostic than a tautology.

## Technology stack

- C++, Node.js, CoffeeScript, Bash only.
- Never Python for any task — no python3 one-liners, no pip, no venv
  references in scripts.
- Never launch Xcode GUI. CLI tools (xcrun, xcodebuild, clang) from the
  terminal are fine.

## File access

- Full read access to everything tracked in `.git` — no need to ask.
- `test/` is gitignored scratch space. Use it freely for temp files, test
  scripts, probes, synthetic data. No cleanup obligation.
- `mlx/` is an up-to-date checkout of the MLX source from GitHub. Use it
  directly for exploring the C++ API, headers, kernel implementations,
  and op signatures. Do not modify it.

## File system access — always through the meta devices

**Hard rule.** Every filesystem read and write inside a step's action
goes through the meta devices — `L.theLowdown(key)?.value` for reads,
`L.saveThis(key, value)` (or `L.make(artifactName, value)`) for writes.
Never `fs.readFileSync`, `fs.writeFileSync`, `fs.existsSync +
fs.readFileSync`, or `new DatabaseSync(...)` directly.

Meta covers everything: YAML (`meta/yaml.coffee`), JSON (`meta/json.coffee`),
JSONL, TXT (`.txt` / `.md`), CSV, and SQLite request keys
(`storyByID{X}.json`, `kagByKeyword{K}.jsonl`, `partsFor{X}.jsonl`, …
see `meta/sqlite.coffee`). If a device for your case doesn't exist,
add one to `meta/` — don't route around.

**Why this is chiseled in stone.** The Memo can only be trusted to
memoize, invalidate, fire notifiers/waiters, and swap backends
(sqlite instead of file; remote instead of local; snapshot instead of
live) when EVERY read passes through it. A raw `fs` read is a hole
the Memo can't see — the cache stays stale, notifiers don't fire,
`experiment.yaml` no longer describes what the run actually did, and
downstream steps race against invisible state changes. Reliability
and responsiveness both collapse the moment one script cheats.

**Helper modules** (e.g. `pipes/story/scripts/lepa.coffee`,
`pipes/story/scripts/iching.coffee`) accept the ledger as an optional
first argument and use `L.theLowdown` when it's present; the fs
fallback is ONLY for standalone / probe callers that have no memo.
Steps in the action never take the fallback — always pass `S` / `L`.

**Path form is CWD-relative.** `L.theLowdown('data/foo.yaml')`, not
absolute paths, not `process.cwd()` gymnastics. The meta yaml device
handles the EXEC fallback for you.

**Files that don't live in the pipe.** If a data file lives outside
the pipe dir (e.g. a project-wide reference under `GPT/`), symlink it
into `pipes/<pipe>/data/` so the meta device (CWD-only for most
rules) can find it. Example:
`pipes/story/data/lepa_updated.json → GPT/lepa-ite/lepa_updated.json`.

## Notes and memory

- ALL working notes go in `GPT/` or `gypsy/` so they are committed to the
  repo and visible across machines and branches.
- Do not use hidden directories (`.claude/`, etc.) as the sole home for
  notes. The hidden system may be used as a secondary index, but the
  canonical content lives in the repo.
- Update the relevant `GPT/<area>/*.md` file in the same session where the
  knowledge was gained — not the next morning.
