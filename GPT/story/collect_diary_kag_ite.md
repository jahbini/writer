Step: `collect_diary_kag_ite`
Recipe: `story`
Script: `pipes/story/scripts/collect_diary_kag_ite.coffee` (LOCAL FORK)
Original: `node_modules/@jahbini/pipeline/scripts/diary_ite/collect_diary_kag_ite.coffee`
Repo of record: `~/writer`

## Purpose

Fetches Jim's own paragraphs from the KAG store (SQLite
`kag_entries` table via `kagByKeyword{<emotion>}.jsonl`) and
attaches them to five diary phases. The paragraphs are consumed
by `build_diary_prompt_ite` as voice-register anchors ("Some
scraps of your own past writing").

## Increment e6 — beats now drive KAG emotions

**Before e6:** the user picked five emotion keywords by hand
(`scene_emotion`, `arrival_emotion`, …) in the UI. KAG returned
paragraphs tagged with those emotions regardless of the chapter's
actual dramatic arc. Picking "contentment" for a chapter about
miserliness returned bar-bet paragraphs.

**Since e6:** the fork reads `story_beats_json` and DERIVES each
kind's emotion from the corresponding beat's `dramatic_function`.
Mapping table (uses only keywords present in the corpus):

| dramatic_function | derived emotion |
|---|---|
| `establish_need` | `frustration` |
| `introduce_opportunity` | `surprise` |
| `escalate_pressure` | `anxiety` |
| `force_a_decision` | `fear` |
| `reveal_information` | `surprise` |
| `lose_an_opportunity` | `sadness` |
| `make_consequence_physical` | `shame` |
| `resolve_a_question` | `contentment` |

Fallback: `neutral`. If dramatic_function is unrecognized, uses
`DEFAULT_EMOTION`.

Beat → kind assignment is **position-based**: beat[0] → scene,
beat[1] → arrival, beat[2] → disturbance, beat[3] → reflection,
beat[4] → realization. If there are fewer than 5 beats, later
slots reuse the last beat's emotion.

## UI overrides preserved

The five UI dropdowns (`scene_emotion` etc.) still exist. When
non-empty, they OVERRIDE the derived emotion for that kind.
Leave blank to use the beat-derived value.

## Output

Artifact `diary_kag` → `out/diary_kag.json`. Same shape as
before, plus a provenance stamp:

```
{
  events: {
    scene: {
      kind: 'scene',
      selected_emotion: 'frustration',
      source: { source: 'beat[0]', dramatic_function: 'establish_need' },
      matches: [ ... paragraphs ... ]
    },
    ...
  },
  _emotion_source: { scene: {...}, arrival: {...}, ... }
}
```

`source.source` is one of:
- `beat[N]` — derived from that beat's dramatic_function
- `beat[N] (reused)` — beats ran out, last beat's emotion used
- `ui_override` — user set the UI param

## Where the paragraphs go in the final prompt

`build_diary_prompt_ite` reads `diary_kag.events[kind].matches`
and renders them in the "Some scraps of your own past writing"
section, grouped by kind (still labeled scene/arrival/etc.).
Each match's `chunk_text` becomes one paragraph excerpt.

## Vocabulary

The KAG corpus (SQLite `kag_entries`) currently has 12 emotion
keywords: `anger, anxiety, contentment, disgust, fear,
frustration, grief, joy, neutral, sadness, shame, surprise`. The
mapping table above only uses these — if `story_beats` emits a
`dramatic_function` we don't have a mapping for, we default to
`neutral`.
