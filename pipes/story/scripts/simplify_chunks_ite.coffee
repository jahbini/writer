ResourceLedger = require '@jahbini/pipeline/tools/resource_ledger'

###
  simplify_chunks_ite.coffee — LORA training-pair generator
  =========================================================
  Reads `chunkSimplificationsMissing.jsonl` (kag chunks that don't
  yet have a plain-English paraphrase), splits each story into the
  same 5-group chunking that `collect_diary_kag_ite` uses, sends
  the target chunk to the HF router via a `*.hfchat` meta key, and
  stores the response as a `chunkSimplification{sid|idx}.json` row.

  Concurrency is governed by a local `ResourceLedger` instance
  (see resource_ledger.coffee). Chunks that don't get an
  immediate admission wait via a Promise the ledger's dispatch
  resolves. If the recipe's `resources.hf-api` block is absent,
  the ledger is skipped and the step behaves as it did before
  admission control landed.

  Pairing the resulting simple↔Jim-style texts at LoRA training
  time gives the adapter a supervised style-transfer signal.

  Iterative (`_ite`): processes up to `batch_size` chunks per
  invocation and is idempotent — a re-run picks up whichever
  chunks remain missing. Safe to `restart_here` mid-batch: any
  chunk with a persisted row is skipped next time.

  Model selection lives in `params/_global.yaml:hfchat_default_model`
  (per meta/hfchat contract). Step does not pin a model in the
  request; the default there is the single source of truth
  (including the provider policy suffix — :fastest, :cheapest,
  named provider).
###

# Duplicated from collect_diary_kag_ite.coffee — step scripts are
# location-anonymous (no path-relative requires; see
# GPT/CONVENTIONS.md). If you change the chunking formula, change
# it in BOTH places. Consumers of `kag_entries.chunk_index` must
# agree on this split or the simplified text won't line up with
# the Jim-style chunk the KAG points at.
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
    return [
      group_index: 1
      text: paragraphs.join "\n\n"
    ]

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

DEFAULT_SYSTEM_PROMPT = """
You rewrite literary passages in plain, simple English. Preserve
every event, character, and outcome; drop stylistic flourishes,
allusion, and unusual vocabulary. Match the passage's length
loosely — aim for a similar number of paragraphs. Return only the
rewritten passage, no preamble or commentary.
""".trim()

extractResponseText = (response) ->
  text = response?.choices?[0]?.message?.content
  throw new Error "hfchat response missing choices[0].message.content" unless typeof text is 'string' and text.length > 0
  text.trim()

# Build a ResourceLedger from a `resources:` block in _global.yaml.
# Returns null when no config → step bypasses admission control entirely
# (backward compat).
buildLedger = (L) ->
  globalP = L.theLowdown("params/_global.yaml")?.value ? {}
  resourcesCfg = globalP.resources
  return null unless resourcesCfg? and typeof resourcesCfg is 'object'

  ledger = new ResourceLedger()
  for own name, spec of resourcesCfg
    limits   = spec?.limits   ? {}
    windowed = spec?.windowed ? {}
    seed     = spec?.wallclock_seconds_seed ? 10
    ledger.addResource name, limits, windowed, seed
  for own owner, maxRunning of (globalP.owners ? {pipeline: 4})
    ledger.setOwnerLimit owner, maxRunning
  ledger

# Wraps one .hfchat round-trip in ledger admission. When no ledger,
# does the raw round-trip. Resolves with the parsed response or
# rejects with the hfchat error.
runOneChunk = (L, ledger, key, requestBody, owner, memoryMB) ->
  submit_t = Date.now() / 1000

  dispatchFetch = ->
    L.saveThis key, requestBody
    entry = L.theLowdown key
    p = if entry?.value? then Promise.resolve(entry.value) else entry.notifier
    p

  unless ledger?
    return dispatchFetch()

  new Promise (resolve, reject) ->
    settled = false
    finishOnce = (actuals) ->
      return if settled
      settled = true
      try ledger.finish key, actuals catch then null

    verdict = ledger.submit
      id: key
      owner: owner
      resource: "hf-api"
      needs: {concurrent: 1, memory_mb: memoryMB}
      dispatch: ->
        dispatchFetch().then (resp) ->
          finishOnce wallclock_seconds: (Date.now()/1000) - submit_t
          resolve resp
        , (err) ->
          finishOnce wallclock_seconds: (Date.now()/1000) - submit_t
          reject err

    if verdict is "rejected"
      finishOnce {}
      reject new Error "[simplify_chunks_ite] resource ledger rejected #{key} (see stderr)"
    else if verdict is "waiting"
      console.log "[simplify_chunks_ite] #{key} queued by resource ledger"

@step =
  desc: "Simplify KAG chunks via HF router; persist as training pairs"

  action: (L) ->
    batchSize = Number(L.param('batch_size', 25))
    throw new Error "[#{L.stepName}] batch_size must be a positive integer" unless Number.isFinite(batchSize) and batchSize > 0 and Math.floor(batchSize) is batchSize

    systemPrompt = String(L.param('system_prompt', DEFAULT_SYSTEM_PROMPT))

    missing = await L.need 'chunk_simplifications_missing'
    throw new Error "[#{L.stepName}] chunkSimplificationsMissing.jsonl must be an array" unless Array.isArray missing

    console.log "[simplify_chunks_ite] missing chunks: #{missing.length}; batch_size=#{batchSize}"

    if missing.length is 0
      console.log "[simplify_chunks_ite] nothing to simplify"
      L.make 'simplify_report',
        processed: 0
        remaining: 0
        completed_at: new Date().toISOString()
      L.done()
      return

    ledger = buildLedger L
    globalP = L.theLowdown("params/_global.yaml")?.value ? {}
    defaultOwner  = globalP.default_owner ? 'pipeline'
    defaultMemoryMB = globalP.hfchat_default_memory_mb ? 256
    console.log "[simplify_chunks_ite] resource_ledger: #{if ledger? then 'enabled' else 'disabled (no resources.hf-api config)'}"

    todo = missing.slice(0, batchSize)
    processed = 0
    failures = []

    for row, i in todo
      storyID  = String(row?.story_id ? '').trim()
      chunkIdx = Number(row?.chunk_index)
      storyText = row?.story_text ? ''

      unless storyID.length and Number.isFinite(chunkIdx) and chunkIdx > 0
        failures.push story_id: storyID, chunk_index: chunkIdx, reason: 'bad missing row'
        continue

      groups = buildStoryGroups storyText
      group  = groups[chunkIdx - 1]
      unless group?
        failures.push story_id: storyID, chunk_index: chunkIdx, reason: "chunk_index #{chunkIdx} out of range (#{groups.length} groups)"
        continue

      chunkText = group.text
      unless chunkText.length
        failures.push story_id: storyID, chunk_index: chunkIdx, reason: 'empty chunk_text after split'
        continue

      requestKey = "simplify.#{storyID}.#{chunkIdx}.hfchat"
      requestBody =
        messages: [
          { role: 'system', content: systemPrompt }
          { role: 'user',   content: chunkText }
        ]

      try
        response = await runOneChunk L, ledger, requestKey, requestBody, defaultOwner, defaultMemoryMB
      catch err
        console.error "[simplify_chunks_ite] #{storyID}|#{chunkIdx} hfchat failed: #{err?.message ? err}"
        failures.push story_id: storyID, chunk_index: chunkIdx, reason: String(err?.message ? err)
        continue

      try
        simpleText = extractResponseText response
      catch err
        failures.push story_id: storyID, chunk_index: chunkIdx, reason: String(err?.message ? err)
        continue

      L.saveThis "chunkSimplification{#{storyID}|#{chunkIdx}}.json",
        story_id: storyID
        chunk_index: chunkIdx
        simple_text: simpleText
        model: response?.model ? null
        created_at: new Date().toISOString()

      processed += 1
      console.log "[simplify_chunks_ite] #{i+1}/#{todo.length} #{storyID}|#{chunkIdx} ok (#{simpleText.length} chars)"

    remaining = missing.length - processed
    console.log "[simplify_chunks_ite] processed=#{processed} failed=#{failures.length} remaining=#{remaining}"

    L.make 'simplify_report',
      processed: processed
      failed: failures.length
      failures: failures
      remaining: remaining
      completed_at: new Date().toISOString()

    L.done()
    return
