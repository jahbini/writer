---
name: elementary-sat
description: Elementary SAT — pass/fail gate for one generated diary letter. Cheap floor of 4 free checks + 2 stubbed LLM checks. Foundation of the three-tier grading ladder.
metadata: 
  node_type: memory
  type: project
  originSessionId: d0eb8cb2-39e1-4813-b17d-dda7493cfc5d
---

Elementary SAT grades one diary letter (Jim → Friend, 5 paragraphs in fixed order: scene/arrival/disturbance/reflection/realization). Pass/fail gate for the ablation ladder — outputs that fail elementary do not proceed to graduate SAT.

**Location:** `~/pipeline/scripts/elementary_sat.coffee`

**Usage:**
```
coffee ~/pipeline/scripts/elementary_sat.coffee \
  --letter out/diary_adapted.txt \
  --prompt out/diary_prompt.txt \
  [--premise out/story_description.txt] \
  [--verbose] [--with-llm]
```
Exit 0 = pass, 1 = fail. JSON verdict on stdout with per-check details.

**Six checks (four cheap + two LLM):**
1. `structure_count` — exactly 5 body paragraphs between greeting/sign-off. Sign-off peeling is aggressive (catches "So there you have it..." transitions plus "Yours, Jim").
2. `character_lock` — regex enumeration of capitalized non-sentence-start words, filtered by allowedNames list + BUILTIN_STOP + COMMON_ADVERBS + COMMON_PLACES. False positives possible (place-name compounds like `St. John's`).
3. `freshness_copy` — flags any ≥ 6-token substring verbatim from past-writing scraps. Deadly on remix output.
4. `premise_adherence` — matches nouns from `--premise` (or from invariants text as fallback) against letter body. Weak signal; needs ≥ 3 matches out of ~8 nouns.
5. `structure_order` — LLM: classify each of 5 paragraphs' role, compare against expected position. STUB — wire via helper `grade_role` capability.
6. `invariant_preserving` — LLM: given the "must stay true" invariants, judge each preserved/absent/partial in the letter. STUB — wire via helper `grade_invariants` capability.

**Sample-letter self-test (2026-09-17):**
The MuseCycle/Malibu/Lightning remix letter fails 3/4 cheap checks:
- structure_count ✓ (after signoff peel)
- character_lock ✗ (MuseCycle, Tommy, Malibu, Lena, Machado)
- freshness_copy ✗ ("an undigestible beet in our society's alimentary canal" — 8 verbatim tokens)
- premise_adherence ✗ (1/8 premise nouns matched)

**Known caveat — pipeline bug upstream:** The invariants extracted from the prompt INVERT the premise. `story_description` in `story_outline` step says Jim was the CUSTOMER who almost stiffed his mechanic; the invariants in the prompt say Jim STIFFED his friend and OVERCHARGED the mechanic. Inversion happens somewhere in `story_beats`/`scene_planner`/`chapter_context`. Fix upstream; the grader is fine.

**Design decisions locked in:**
- CoffeeScript `for … in matchAll(…)` doesn't iterate an iterator; use `for … from matchAll(…)`. Bit us during self-test.
- Chunk = one paragraph (one segment), aligned via paragraph position (0-4 = scene/arrival/disturbance/reflection/realization).
- Grading is always relative for graduate SAT; elementary is absolute pass/fail.

Related: [[helper-reason-mining-findings]] (grading rubric derived from failure-mode analysis), [[helper-kag-design]] (retrieval that KAG-on config uses in ablations).
