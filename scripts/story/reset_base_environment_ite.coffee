@step =
  desc: "No-op: preserve sqlite training history (stories, kag, lora_story_usage) and adapter across full_cycle_ite cycles"

  # Was: sqliteResetAll + rm -rf build/adapter, build/train, out/lora_*, etc.
  # That wiped lora_story_usage every cycle so select_lora_stories_ite
  # always picked the same first batch. Iterative full_cycle_ite needs
  # cross-cycle DB state to skip already-trained stories and to resume
  # the adapter from the prior run.
  action: (S) ->
    S.done()
    return
