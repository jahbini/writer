# ─── Stub Story Parts (Increment e7) ──────────────────────────────────
# The vendored `generate_diary_*_ite` steps hard-require a story_parts
# artifact (`await L.need 'story_parts'` + object type check). The
# legacy path that filled this artifact — `select_story_recipe` +
# `resolve_story_parts` — was 5 UI dropdowns of dead weight from the
# pre-outline pipeline.
#
# This stub replaces them with an empty object. Satisfies the vendored
# generators without dragging the 5-beat UI back into the recipe.

@step =
  desc: "Stub: emit empty story_parts to satisfy vendored generator's L.need check"

  action: (S) ->
    S.make 'story_parts', {}
    S.done()
    return
