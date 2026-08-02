Pipeline runner gotchas discovered during e1–e4
================================================

Learned the hard way this session. Save future-me the debug time.

## `[never]`-gated steps are PRUNED, not deferred

If a step in the recipe has `depends_on: [never]`, the pipeline
runner removes it AND its declared artifacts entirely from the
DAG. Anything else in the recipe that references that step by
name in its own `depends_on` will fail toposort with:

    Undefined dependency '<step>' (by '<other step>')

Anything that references its ARTIFACT via `needs:` will hang
waiting for a producer that will never run.

**Where this bites `story`:** the override at
`pipes/story/override/story.yaml` gates
`generate_diary_without_adapter_ite` to `[never]` on the adapter
path (and would gate the with-adapter one to `[never]` on the
base path). `state_extractor` and `archive_chapter` sit
downstream of "the generator" but the DAG only has ONE generator
step by name at any time.

**Fix pattern used**: name the enabled generator explicitly in
`state_extractor.depends_on` and `needs`, with a big recipe
comment flagging the two lines that must flip if the override
changes. The script itself uses `S.need` with a fallback list
(try adapter artifact, then base artifact), so on a flip only
the recipe needs an edit.

Better long-term fix (deferred): either a canonical
`chapter_text` artifact both generators produce, or a runner
feature that treats `needs` on a pruned artifact as "satisfied
by absence."

## `process.cwd()` in a step is NOT reliably the pipe dir

`story_outline.readAtomsLibrary` works fine with
`path.join(process.cwd(), 'data', 'jim_story_library.yaml')` —
resolves to `pipes/story/data/…`. But `state_extractor`'s
`path.join(process.cwd(), 'out', 'diary_adapted.txt')` FAILED
to find a file that definitely existed at
`pipes/story/out/diary_adapted.txt`.

Why the difference? Unknown. Might be step-scheduling context,
might be a subprocess boundary. Whatever it is, `process.cwd()`
is unreliable for disk reads inside a step action.

**Fix pattern used**: prefer `S.need('<artifact_name>')` for
reading upstream artifacts. The runner knows the authoritative
mapping. Fall back to a disk read only if S.need returns null,
and even then treat the disk read as a last resort with a
descriptive error.

For reading FILES that aren't declared artifacts (e.g. the
atoms library YAML), `process.cwd()` seems to work — but the
safer pattern is to declare them as artifacts too.

## `depends_on` gates step SCHEDULING, not artifact write flush

Setting `state_extractor.depends_on: [build_diary_prompt_ite]`
scheduled it in PARALLEL with the generator, not after. Even
after the generator wrote its file, the state_extractor had
already started (and failed) reading disk. `depends_on` needs to
point at the step whose completion is genuinely required, not a
convenient earlier ancestor.

**Fix pattern used**: name the actual step that produces the
required data as the `depends_on` target.

## `[never]` also prunes the step from UI dropdowns

Not confirmed but strongly suspected: the UI-side control_override
mechanism probably uses similar semantics, meaning a step gated
to `[never]` doesn't show up in the UI at all. If a user reports
"I don't see the checkbox for that step," check the override.

---

Session-relative dates: all captured 2026-08-01 while landing e4.
