###
  heckle_story.coffee — post-process a story text with hecklers
  =============================================================

  Recipe: heckled_story.yaml (see ~/writer/config/heckled_story.yaml
  for the full contract and knob list).

  V1 mechanic: read the selected source text artifact, split into
  sentences, and interleave lines pulled from the heckler pool at
  every trigger boundary. Output goes to the story_heckled_text
  artifact plus a machine-readable events jsonl for tuning.

  V2 will replace this whole step with a streaming call that emits
  hecklers into session_api's token loop as tokens arrive. The
  recipe's `personas`, `trigger_mode`, `alternate`, and `curtain`
  knobs will carry over unchanged.

  Location-anonymous — no path-relative requires, no fs use outside
  the meta layer's dispatched artifact reads.
###

@step =
  desc: "Inject Statler/Waldorf-style hecklers into a story text"

  action: (S) ->
    # ---- resolve inputs -------------------------------------------------
    sourceArtifactName = String(S.param('source_artifact') ? 'diary_with_adapter_text')
    sourceText = String((await S.need sourceArtifactName) ? '').trim()
    unless sourceText.length
      throw new Error "[heckle_story] source artifact '#{sourceArtifactName}' is empty"

    pool = (await S.need 'heckler_pool') ? {}
    personasMap = pool?.personas ? {}

    selected = S.param('personas', 'Statler+Waldorf')
    activePersonaNames = String(selected).split('+').map (s) -> s.trim()
    activePersonas =
      for name in activePersonaNames when personasMap[name]?
        {name: name, lines: personasMap[name]}
    unless activePersonas.length
      throw new Error "[heckle_story] no active personas resolve — check 'personas' param and pool"

    triggerMode      = String(S.param('trigger_mode', 'every_n_sentences'))
    everyN           = Math.max 1, Number(S.param('every_n_sentences', 3))
    triggerPhrases   = S.param('trigger_phrases', []) ? []
    cooldownWords    = Math.max 0, Number(S.param('cooldown_words', 15))
    seed             = S.param 'seed', null
    alternate        = S.param('alternate', true) is true
    curtain          = S.param('curtain',   true) is true

    # ---- deterministic RNG ---------------------------------------------
    # Small LCG so `seed: 42` reproduces byte-for-byte. Math.random is
    # not seedable in Node without a helper — this keeps the step
    # location-anonymous (no extra package requires).
    rngState =
      if seed?
        h = (Number(seed) | 0) or 0x9E3779B1
        h
      else
        Math.floor(Math.random() * 0x7FFFFFFF)
    nextRand = ->
      # Numerical Recipes LCG constants — good enough for pick-a-line.
      rngState = (rngState * 1664525 + 1013904223) | 0
      ((rngState >>> 0) % 1_000_000) / 1_000_000

    pickPersona = (previousName) ->
      candidates =
        if alternate and activePersonas.length > 1 and previousName?
          activePersonas.filter (p) -> p.name isnt previousName
        else
          activePersonas
      candidates[Math.floor(nextRand() * candidates.length)]

    pickLine = (persona) ->
      lines = persona.lines
      lines[Math.floor(nextRand() * lines.length)]

    # ---- sentence split ------------------------------------------------
    # Simple splitter — .!? followed by whitespace, but keep the
    # punctuation attached to the previous sentence. Paragraph breaks
    # (double newline) are preserved as their own tokens so the
    # every_paragraph trigger can see them.
    tokenize = (text) ->
      out = []
      buf = ''
      i = 0
      while i < text.length
        ch = text[i]
        if ch is '\n' and text[i + 1] is '\n'
          out.push {type: 'sentence', text: buf.trim()} if buf.trim().length
          out.push {type: 'paragraph_break'}
          buf = ''
          i += 2
          i += 1 while text[i] is '\n'
          continue
        buf += ch
        if /[.!?]/.test(ch) and (text[i + 1] is undefined or /\s/.test(text[i + 1]))
          out.push {type: 'sentence', text: buf.trim()}
          buf = ''
        i += 1
      out.push {type: 'sentence', text: buf.trim()} if buf.trim().length
      out

    tokens = tokenize sourceText
    console.log "[heckle_story] source=#{sourceArtifactName} sentences=#{tokens.filter((t) -> t.type is 'sentence').length}"

    # ---- interleave ----------------------------------------------------
    outLines = []
    events   = []
    sentenceCount = 0
    wordsSinceLast = Infinity
    lastPersonaName = null

    shouldFire = (tok) ->
      return false if wordsSinceLast < cooldownWords
      switch triggerMode
        when 'every_n_sentences'
          tok.type is 'sentence' and (sentenceCount % everyN) is 0
        when 'every_paragraph'
          tok.type is 'paragraph_break'
        when 'trigger_phrases'
          return false unless tok.type is 'sentence'
          text = tok.text.toLowerCase()
          for phrase in triggerPhrases
            return true if text.includes(String(phrase).toLowerCase())
          false
        else false

    emitHeckler = ->
      persona = pickPersona(lastPersonaName)
      return unless persona?
      line = pickLine persona
      outLines.push "[#{persona.name}] #{line}"
      events.push
        persona:      persona.name
        line:         line
        after_sentence: sentenceCount
      lastPersonaName = persona.name
      wordsSinceLast  = 0

    for tok in tokens
      if tok.type is 'sentence'
        outLines.push tok.text
        sentenceCount += 1
        wordsSinceLast += tok.text.split(/\s+/).filter((w) -> w.length).length
        if shouldFire(tok)
          emitHeckler()
      else if tok.type is 'paragraph_break'
        if shouldFire(tok)
          emitHeckler()
        outLines.push ''   # preserves the blank line

    if curtain and lastPersonaName?
      # Bookend with the OTHER persona so the applause isn't from
      # the same voice that just spoke.
      other = pickPersona(lastPersonaName)
      if other?
        outLines.push "[#{other.name}] #{pickLine(other)}"
        events.push {persona: other.name, line: outLines[outLines.length - 1], after_sentence: sentenceCount, curtain: true}

    # ---- publish -------------------------------------------------------
    heckledText = outLines.join('\n').replace(/\n{3,}/g, '\n\n') + '\n'
    S.make 'story_heckled_text', heckledText
    S.make 'story_heckled_events', events
    console.log "[heckle_story] emitted #{events.length} heckler line(s); output=#{heckledText.length} chars"
    S.done()
