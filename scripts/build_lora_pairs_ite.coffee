###
  build_lora_pairs_ite.coffee — LORA training-pair builder
  =========================================================
  Reads (story, chunk) rows and their oracle-generated plain-English
  rewrites from `chunk_simplifications`, emits chat-formatted
  training rows shaped as (plain → jim). Replaces the completion-
  style output of the shipped `build_lora_dataset_ite`.

  Prerequisite: oracle_ite has run with `rewrite_prompt_text` on,
  populating the chunk_simplifications table.

  Row shape: {text: "<chat template rendered turn><eot>"} — matches
  what the LoRA trainer consumes. Uses Qwen chat markers directly
  (this project's base is Qwen3-Instruct family — Huihui abliterated
  is a fine-tune of Qwen3). If a non-Qwen base is ever adopted,
  swap the CHAT_TEMPLATE_* constants.

  Filter (2026-08-20): Qwen produces variable amounts of preamble
  before the actual rewrite. Common markers stripped before pair
  emission. Rows whose cleaned simple_text falls below
  `min_simple_chars` are dropped (surface via stats).

  Bucketing: identical story-level train/valid/test split as the
  original dataset builder — 8 : 1 : 1 by sorted story id, no RNG.
###
fs   = require 'fs'
path = require 'path'

resolveEotToken = (modelDir) ->
  cfgPath = path.join modelDir, 'tokenizer_config.json'
  throw new Error "[build_lora_pairs_ite] tokenizer_config.json not found at #{cfgPath}" unless fs.existsSync cfgPath
  cfg = JSON.parse fs.readFileSync(cfgPath, 'utf8')
  eot = cfg.eos_token
  eot = eot.content if eot? and typeof eot is 'object'
  throw new Error "[build_lora_pairs_ite] no usable eos_token in #{cfgPath}" unless eot? and typeof eot is 'string' and eot.length > 0
  eot

# Chunking — identical formula to simplify_chunks_ite AND
# build_lora_dataset_ite so `chunk_simplifications.chunk_index` lines
# up exactly with the jim-side chunk we pair it with.
splitParagraphs = (text) ->
  paragraphs = []
  return paragraphs unless text?
  for block in String(text).split(/\n\s*\n/)
    trimmed = block.trim()
    paragraphs.push(trimmed) if trimmed.length
  paragraphs

buildStoryGroups = (text) ->
  paragraphs = splitParagraphs text
  return [] unless paragraphs.length

  if paragraphs.length < 5
    return [ { group_index: 1, text: paragraphs.join "\n\n" } ]

  groups = []
  total = paragraphs.length
  baseSize = Math.floor(total / 5)
  remainder = total % 5
  startIndex = 0
  for groupIndex in [0...5]
    groupSize = baseSize
    groupSize += 1 if groupIndex < remainder
    selected = paragraphs.slice startIndex, startIndex + groupSize
    groups.push
      group_index: groupIndex + 1
      text: selected.join "\n\n"
    startIndex += groupSize
  groups

# Preamble strippers — Qwen3 doesn't always obey "no preamble".
# Take the tail after the LAST matching marker; model sometimes
# retries and we want the final version.
PREAMBLE_MARKERS = [
  /Here is the rewritten passage:?\s*/gi
  /Rewritten passage:\s*/gi
  /Rewritten version:?\s*/gi
  /Here'?s the rewrite:?\s*/gi
]

cleanSimpleText = (raw) ->
  return null unless raw?
  txt = String(raw).trim()
  lastCut = -1
  for re in PREAMBLE_MARKERS
    re.lastIndex = 0
    while (m = re.exec(txt))?
      cut = m.index + m[0].length
      lastCut = cut if cut > lastCut
  txt = txt.slice(lastCut).trim() if lastCut > 0
  txt

DEFAULT_SYSTEM_PROMPT = """
You rewrite plain-English passages in Jim's voice — literary,
atmospheric, Portland weird-fiction. Preserve every event,
character, and outcome from the source; add stylistic
particularity, sensory detail, and voice. Return only the
rewritten passage.
""".trim()

# Qwen3 chat template markers (matches tokenizer's chat_template.jinja
# for the Qwen family). Rendered manually so we don't need a jinja
# runtime. If the base model swaps to a non-Qwen tokenizer, adjust.
renderQwenChat = (systemPrompt, userText, assistantText) ->
  """
  <|im_start|>system
  #{systemPrompt}<|im_end|>
  <|im_start|>user
  #{userText}<|im_end|>
  <|im_start|>assistant
  #{assistantText}<|im_end|>
  """

# Story-level 8/1/1 split. Identical to build_lora_dataset_ite so
# swapping between the two dataset builders never puts a story's
# chunks on both sides of the train/valid boundary.
splitStoryIds = (storyIds, trainOut = 8, validOut = 1, testOut = 1) ->
  total = trainOut + validOut + testOut
  sorted = storyIds.slice().sort()
  buckets = { train: [], valid: [], test: [] }
  for id, i in sorted
    bucket = i % total
    if bucket < trainOut
      buckets.train.push id
    else if bucket < trainOut + validOut
      buckets.valid.push id
    else
      buckets.test.push id
  buckets

@step =
  desc: "Build LoRA (plain → jim) training pairs from chunk_simplifications"

  action: (L) ->
    systemPrompt = String(L.param('system_prompt', DEFAULT_SYSTEM_PROMPT))
    minSimpleChars = Number(L.param('min_simple_chars', 100))
    throw new Error "[#{L.stepName}] min_simple_chars must be a non-negative number" unless Number.isFinite(minSimpleChars) and minSimpleChars >= 0

    modelDir = L.param 'model_dir', null
    throw new Error "[#{L.stepName}] model_dir is required (needed for tokenizer eot_token)" unless modelDir?
    eotToken = resolveEotToken modelDir

    selectedStoryIDs = await L.need 'selected_story_ids'
    throw new Error "[#{L.stepName}] selected_story_ids must be an array" unless Array.isArray selectedStoryIDs

    if selectedStoryIDs.length is 0
      console.log "[#{L.stepName}] no selected stories; writing empty datasets"
      L.make 'train_rows', []
      L.make 'valid_rows', []
      L.make 'test_rows',  []
      L.done()
      return

    rowsByStory = {}
    processedStoryIds = []
    stats =
      chunks_expected: 0
      pairs_emitted: 0
      skipped_no_simplification: 0
      skipped_too_short: 0
      preamble_stripped: 0

    for storyID in selectedStoryIDs
      continue unless storyID?

      storyEntry = L.theLowdown "storyByID{#{storyID}}.json"
      story = storyEntry?.value
      if story is undefined
        if typeof storyEntry?.waitFor is 'function'
          story = await storyEntry.waitFor()
        else if storyEntry?.notifier?
          story = await storyEntry.notifier
      throw new Error "[#{L.stepName}] missing storyByID for #{storyID}" unless story?

      fullText = String(story.text ? '').trim()
      continue unless fullText.length > 0

      groups = buildStoryGroups fullText
      continue unless groups.length > 0

      storyRows = []
      for group in groups
        stats.chunks_expected += 1
        simKey = "chunkSimplification{#{storyID}|#{group.group_index}}.json"
        simEntry = L.theLowdown simKey
        simRow = simEntry?.value
        # No blocking wait: if the simplification isn't there, skip.
        # oracle_ite is a prerequisite; we don't try to backfill here.
        unless simRow?.simple_text?
          stats.skipped_no_simplification += 1
          continue

        rawSimple = String(simRow.simple_text)
        cleaned = cleanSimpleText rawSimple
        if cleaned? and cleaned.length isnt rawSimple.trim().length
          stats.preamble_stripped += 1

        unless cleaned? and cleaned.length >= minSimpleChars
          stats.skipped_too_short += 1
          continue

        jimText = group.text
        continue unless jimText.length > 0

        rendered = renderQwenChat systemPrompt, cleaned, jimText
        rendered += eotToken unless rendered.endsWith(eotToken)
        storyRows.push text: rendered
        stats.pairs_emitted += 1

      if storyRows.length > 0
        rowsByStory[storyID] = storyRows
        processedStoryIds.push storyID

    if processedStoryIds.length is 0
      console.error "[#{L.stepName}] no usable pairs (chunks_expected=#{stats.chunks_expected} no_simplification=#{stats.skipped_no_simplification} too_short=#{stats.skipped_too_short}). Did oracle_ite run with rewrite_prompt_text on?"
      L.make 'train_rows', []
      L.make 'valid_rows', []
      L.make 'test_rows',  []
      L.done()
      return

    buckets = splitStoryIds processedStoryIds
    # Same rescue as build_lora_dataset_ite: with ≥3 stories,
    # guarantee valid/test aren't empty.
    if processedStoryIds.length >= 3
      buckets.valid.push buckets.train.pop() if buckets.valid.length is 0
      buckets.test.push  buckets.train.pop() if buckets.test.length  is 0

    collect = (ids) ->
      out = []
      for id in ids
        continue unless rowsByStory[id]?
        for row in rowsByStory[id]
          out.push row
      out

    trainRows = collect buckets.train
    validRows = collect buckets.valid
    testRows  = collect buckets.test

    console.log "[#{L.stepName}] stories: #{buckets.train.length} train / #{buckets.valid.length} valid / #{buckets.test.length} test"
    console.log "[#{L.stepName}] pairs:   #{trainRows.length} train / #{validRows.length} valid / #{testRows.length} test"
    console.log "[#{L.stepName}] filter:  expected=#{stats.chunks_expected} emitted=#{stats.pairs_emitted} preamble_stripped=#{stats.preamble_stripped} skipped_no_simplification=#{stats.skipped_no_simplification} skipped_too_short=#{stats.skipped_too_short}"

    L.make 'train_rows', trainRows
    L.make 'valid_rows', validRows
    L.make 'test_rows',  testRows
    L.done()
    return
