###
  celarien_generate_ite.coffee — Chapter-by-chapter generator for the
  Celarien recipe. Reads the Phase 3 directives artifact and calls
  L.callLLM once per chapter, accumulating actual chapter texts.

  Reads:
    celarien_directives_jsonl  — one JSON per line, from Phase 3
                                 { chapter_key, class, aperture, directive }

  Emits:
    celarien_chapter_actuals_json  — { <chapter_key>: <actual_text> }
                                     — the artifact celarien_audit_ite
                                     reads to grade each chapter.

  Params (all L.param, override-able):
    quantized_model_dir  — model dir (defaults ${MODELS}/${run.model}-mlx4)
    adapter_dir          — optional LoRA
    temperature          — default 0.85 (novelistic)
    top_p                — default 0.9
    max_tokens           — default 1500 per chapter
    max_chapters         — default 3 (bounded first run; crank up in
                           the pipe override once you know the cost)
    system_prompt        — default "You are writing a chapter of a
                           maritime series..."

  Gate: use_celarien_arc (same as the rest of the celarien pipeline).
  Off = no-op.
###

stripText = (rawText, seed = null) ->
  s = String(rawText ? '')
  m = s.match /[\s\S]*<\/think>\s*([\s\S]*)$/
  s = m[1] if m
  s = s.replace(/<\|im_end\|>[\s\S]*$/, '').trim()
  # Defensive: a NON-thinking (instruct) model can echo the prefilled
  # steer seed verbatim at the head of its answer instead of treating it
  # as hidden reasoning. If the seed appears leading, cut through it.
  if seed? and seed.length and (j = s.indexOf(seed)) >= 0 and j < 8
    s = s.slice(j + seed.length).trim()
  s

callWithThinkRescue = (L, llmArgs) ->
  resp = await L.callLLM llmArgs
  raw = String(resp?.rawText ? resp?.text ? '')
  return raw if raw.indexOf('</think>') >= 0
  rescue = "\n\nOK, time is up. Answering now.\n</think>\n\n"
  args2 = Object.assign {}, llmArgs,
    prompt:    llmArgs.prompt + raw + rescue
    maxTokens: Math.max(400, Math.floor((llmArgs.maxTokens ? 512) / 2))
  resp2 = await L.callLLM args2
  raw2 = String(resp2?.rawText ? resp2?.text ? '')
  raw + rescue + raw2

@step =
  desc: "Celarien chapter generator — one callLLM per directive"
  action: (L) ->
    unless L.param('use_celarien_arc', false) is true
      console.log "[celarien_generate_ite] gate use_celarien_arc=false — skipping"
      L.done()
      return

    # Directives can arrive from either:
    #   - a first-class artifact key `celarien_directives_jsonl`
    #     (present when this step is chained after Phase 3 directly
    #     in a single-recipe run), OR
    #   - a source-only file `out/celarien_directives.jsonl`
    #     scp-pushed by the puppeteer's celarien_fanout_ite (the
    #     peer-side celarien_run wiring).
    # Try the file path first — that's the wired-fanout normal.
    # jsonl meta may return either an array or the raw string.
    raw = null
    try
      raw = L.theLowdown('out/celarien_directives.jsonl')?.value ? null
    catch _err
      raw = null
    unless raw?
      raw = await L.need 'celarien_directives_jsonl'
    directives = []
    if Array.isArray(raw)
      directives = raw.filter (r) -> r? and typeof r is 'object'
    else
      for line in String(raw ? '').split(/\n/)
        trimmed = line.trim()
        continue unless trimmed.length
        try
          directives.push JSON.parse(trimmed)
        catch _err
          null

    # Loud signal on starvation — the most common "silent failure" is an
    # empty/garbled directives artifact (e.g. shipped as `[object Object]`
    # or char-split). Don't throw (empty is a valid state), but make it
    # impossible to miss in the log instead of logging a cheery "0 of 0".
    if directives.length is 0
      console.error "[celarien_generate_ite] ⚠️  0 directives parsed from celarien_directives_jsonl — NOTHING to generate. Check the directives artifact is valid JSONL. Emitting an empty actuals map."

    modelDir = L.param 'quantized_model_dir', L.param('model_dir', null)
    throw new Error "[celarien_generate_ite] quantized_model_dir required" unless modelDir?
    adapter    = L.param 'adapter_dir', null
    temp       = Number L.param('temperature', 0.85)
    topP       = Number L.param('top_p', 0.9)
    maxTok     = Number L.param('max_tokens', 1500)
    maxCh      = Number L.param('max_chapters', 3)
    sysPrompt  = L.param 'system_prompt',
      "You are writing one chapter of a serial maritime story about the ship Celarien, a trireme carrying an ensemble crew through the last years of the sea empire. Third person past tense. Prose, no headings. Follow the directive."

    actuals = {}
    useSteer = L.param('use_lepa_steer', false) is true
    for d, i in directives when i < maxCh
      # Gated LEPA steer: a CLOSED <think> seed at the assistant turn head
      # (the beat-level lever). Default off → byte-identical to the pre-LEPA
      # baseline. Closed (not open) so a NON-thinking instruct model can't
      # trail the seed into visible prose; we skip the think-rescue when
      # seeded (there is no open think to rescue) and defensively strip any
      # verbatim echo. Thinking models simply see thinking already done.
      steerText = if useSteer and d.steer? and String(d.steer).trim().length then String(d.steer).trim() else null
      steerSeed = if steerText? then "<think>\n#{steerText}\n</think>\n\n" else ""
      prompt = "<|im_start|>system\n#{sysPrompt}<|im_end|>\n<|im_start|>user\n#{d.directive}<|im_end|>\n<|im_start|>assistant\n#{steerSeed}"
      llmArgs =
        op:          'generate'
        modelDir:    modelDir
        prompt:      prompt
        maxTokens:   maxTok
        temperature: temp
        topP:        topP
        raw:         true
      llmArgs.adapterPath = adapter if adapter?
      raw =
        if steerText?
          r = await L.callLLM llmArgs      # think pre-closed → no rescue
          String(r?.rawText ? r?.text ? '')
        else
          await callWithThinkRescue L, llmArgs
      actuals[d.chapter_key] = stripText raw, steerText
      console.log "[celarien_generate_ite] #{d.chapter_key} (#{d.class}/#{d.aperture}) chars=#{actuals[d.chapter_key].length}"

    nMade = Object.keys(actuals).length
    console.log "[celarien_generate_ite] generated #{nMade} of #{directives.length} chapters (max_chapters=#{maxCh})"
    # Loud signal: we HAD directives but produced no text. That means every
    # callLLM came back empty (model-load failure, OOM) or the run was
    # killed mid-generation — exactly the "fails silently" case. Surface it.
    if directives.length > 0 and nMade is 0
      console.error "[celarien_generate_ite] ⚠️  generated 0 of #{directives.length} chapters — every generation produced empty text (model load / OOM / killed mid-run). Actuals is EMPTY; downstream audit will have nothing to check."
    L.make 'celarien_chapter_actuals_json', actuals
    L.done()
    return
