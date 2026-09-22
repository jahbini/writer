###
  broadcast_ite.coffee — 0.6B-hosted step that produces headlines +
  epilogues for a completed story, plus platform-formatted bundles.

  Input params:
    spine       : name of spine under data/spines/<name>.txt (optional)
    story_file  : path to completed story text (relative to CWD)
    n_candidates: how many candidates per output type (default 5)
    platforms   : list of platform slugs to format for
                  ('twitter', 'facebook', 'email', 'newsletter')

  Emits artifacts:
    broadcast_headlines_jsonl — N candidates with temperature + chars
    broadcast_epilogues_jsonl — N candidates
    broadcast_bundle_json     — per-platform packages ready to paste

  Design: 0.6B is the punctuation model (see writer/GPT/story/model_roles.md).
  Uses shotgun generation with temperature spread — moderate temps
  reliably beat single-shot high temp per 2026-09-22 caption test.
###

fs   = require 'fs'
path = require 'path'

escapeHtml = (s) ->
  String(s ? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')

# Review page — human picks winner headline + winner epilogue.
# Submits to the puppeteer's /api/broadcast_pick endpoint which
# writes the choice to ~/puppeteer/state/broadcast_queue.jsonl.
renderReviewHtml = (bundleId, storyPath, hook, closer, headlines, epilogues, platforms) ->
  head = (h, i, checked) ->
    """<label class="cand">
<input type="radio" name="headline" value="#{i}" #{if checked then 'checked' else ''}>
<span class="text">#{escapeHtml h.text}</span>
<span class="meta">T=#{h.temperature} · #{h.chars} chars</span>
</label>"""
  epi = (e, i, checked) ->
    """<label class="cand">
<input type="radio" name="epilogue" value="#{i}" #{if checked then 'checked' else ''}>
<span class="text">#{escapeHtml e.text}</span>
<span class="meta">T=#{e.temperature} · #{e.chars} chars</span>
</label>"""
  headsHtml = headlines.map((h, i) -> head(h, i, i is 0)).join('\n')
  episHtml  = epilogues.map((e, i) -> epi(e, i, i is 0)).join('\n')
  platformsJson = JSON.stringify(platforms).replace(/</g, '\\u003c')
  headlinesJson = JSON.stringify(headlines.map((h) -> h.text)).replace(/</g, '\\u003c')
  epiloguesJson = JSON.stringify(epilogues.map((e) -> e.text)).replace(/</g, '\\u003c')
  """<!doctype html>
<meta charset="utf-8">
<title>Broadcast Review · #{escapeHtml bundleId}</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 20px; background:#fafafa; max-width: 900px; }
  h1 { font-size: 20px; margin: 0 0 4px 0; }
  h3 { font-size: 14px; margin: 20px 0 8px 0; color:#333; font-family: ui-monospace, monospace; }
  .subhead { color:#666; font-size: 13px; margin-bottom: 20px; }
  .excerpt { background:#fff; border:1px solid #ddd; border-radius:6px; padding:10px 14px; margin-bottom:8px; font-size:12px; color:#555; }
  .excerpt b { color:#333; font-family: ui-monospace, monospace; font-size: 11px; }
  .cand {
    display: block;
    padding: 10px 14px;
    background: white;
    border: 1px solid #ddd;
    border-radius: 6px;
    margin-bottom: 6px;
    cursor: pointer;
  }
  .cand:hover { background: #f6f8fa; border-color: #0366d6; }
  .cand input:checked ~ .text { color: #0366d6; font-weight: bold; }
  .cand .text { font-family: Georgia, serif; font-size: 15px; margin-left: 8px; }
  .cand .meta { color: #888; font-size: 11px; font-family: ui-monospace, monospace; margin-left: 12px; }
  .preview { background:#fff; border:1px solid #ddd; border-radius:6px; padding:12px 16px; margin-top:8px; margin-bottom:12px; }
  .preview h4 { margin:0 0 6px 0; font-size:12px; color:#333; font-family: ui-monospace, monospace; }
  .preview .out { font-family: Georgia, serif; font-size:14px; color:#222; white-space: pre-wrap; }
  .preview .count { font-size: 11px; color: #888; font-family: ui-monospace, monospace; margin-top: 4px; }
  .actions { margin-top: 24px; padding: 16px; background: white; border: 1px solid #ddd; border-radius: 6px; text-align: center; }
  .actions button { font-size: 14px; padding: 10px 24px; background: #0366d6; color: white; border: 0; border-radius: 5px; cursor: pointer; font-family: ui-monospace, monospace; }
  .actions button:hover { background: #0353b8; }
  .status { margin-top: 8px; font-family: ui-monospace, monospace; font-size: 12px; }
</style>
<script>
  const HEADLINES = #{headlinesJson};
  const EPILOGUES = #{epiloguesJson};
  const PLATFORMS = #{platformsJson};
  const BUNDLE_ID = #{JSON.stringify(bundleId)};
  const STORY_PATH = #{JSON.stringify(storyPath)};

  function selectedIdx(name) {
    const el = document.querySelector('input[name="' + name + '"]:checked');
    return el ? Number(el.value) : 0;
  }

  function fmt(platform, h, e) {
    const limits = { twitter: 280, facebook: 500, email: 120, newsletter: 200 };
    let out;
    switch (platform) {
      case 'twitter': {
        const combined = h + ' — ' + e;
        out = combined.length <= 280 ? combined : h;
        break;
      }
      case 'facebook': out = h + '\\n\\n' + e; break;
      case 'email':    out = h.slice(0, limits.email); break;
      case 'newsletter': {
        const combined = h + ' — ' + e;
        out = combined.length <= limits.newsletter ? combined : h;
        break;
      }
      default: out = h;
    }
    return { out, limit: limits[platform] || null };
  }

  function updatePreview() {
    const h = HEADLINES[selectedIdx('headline')] || '';
    const e = EPILOGUES[selectedIdx('epilogue')] || '';
    for (const platform of PLATFORMS) {
      const el = document.getElementById('preview-' + platform);
      if (!el) continue;
      const { out, limit } = fmt(platform, h, e);
      const outEl = el.querySelector('.out');
      outEl.textContent = out;
      const countEl = el.querySelector('.count');
      countEl.textContent = out.length + ' chars' + (limit ? ' (limit ' + limit + ')' : '');
      countEl.style.color = (limit && out.length > limit) ? '#a33' : '#888';
    }
  }

  async function saveSelection() {
    const hIdx = selectedIdx('headline');
    const eIdx = selectedIdx('epilogue');
    const status = document.getElementById('save-status');
    status.textContent = 'saving…';
    try {
      const resp = await fetch('http://localhost:4300/api/broadcast_pick', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          bundle_id: BUNDLE_ID,
          story_path: STORY_PATH,
          headline_idx: hIdx,
          headline: HEADLINES[hIdx],
          epilogue_idx: eIdx,
          epilogue: EPILOGUES[eIdx],
          platforms: PLATFORMS,
          formatted: Object.fromEntries(PLATFORMS.map(p => [p, fmt(p, HEADLINES[hIdx], EPILOGUES[eIdx]).out]))
        })
      });
      const data = await resp.json();
      if (!data.ok) throw new Error(data.error || 'save failed');
      status.textContent = '✓ queued (' + data.queue_size + ' pending in ~/puppeteer/state/broadcast_queue.jsonl)';
      status.style.color = '#22863a';
    } catch (err) {
      status.textContent = '✗ ' + (err.message || err);
      status.style.color = '#a33';
    }
  }

  window.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('input[type=radio]').forEach(el => el.addEventListener('change', updatePreview));
    updatePreview();
  });
</script>

<h1>Broadcast Review · <code>#{escapeHtml bundleId}</code></h1>
<div class="subhead">Pick one headline and one epilogue. Preview updates live. Save queues the choice for later publishing.</div>

<div class="excerpt"><b>story hook:</b><br>#{escapeHtml hook}</div>
<div class="excerpt"><b>story closer:</b><br>#{escapeHtml closer}</div>

<h3>Headlines (#{headlines.length} candidates)</h3>
#{headsHtml}

<h3>Epilogues (#{epilogues.length} candidates)</h3>
#{episHtml}

<h3>Preview</h3>
#{platforms.map((p) -> """<div class="preview" id="preview-#{p}">
<h4>#{p}</h4>
<div class="out"></div>
<div class="count"></div>
</div>""").join('\n')}

<div class="actions">
  <button onclick="saveSelection()">Queue for publishing</button>
  <div class="status" id="save-status"></div>
</div>
"""

# ─── prompt builders ─────────────────────────────────────────────

buildHeadlinePrompt = (storyHook, spineText, maxWords) ->
  # Include spine name/first-line as structural anchor, story hook
  # as content anchor, examples as shape anchors.
  spineTitle = ''
  if spineText? and spineText.length
    # First non-blank line as a proxy for spine identity.
    for line in spineText.split(/\n/)
      trimmed = line.trim()
      if trimmed.length and not trimmed.startsWith('#')
        spineTitle = trimmed
        break

  """A headline is one line, #{maxWords} words or fewer. Specific image or one observation, never a summary.

Examples:
"Woman keeps a room. Room keeps her."
"Serf spoke once too loud. World stopped listening."
"Baby born mid-jam. Mother's victory lap."

Story hook:
#{storyHook}

Headline:
"""

buildEpiloguePrompt = (storyCloser) ->
  """An epilogue is one or two short lines — a thought the reader carries after the piece ends. Not a summary.

Examples:
"She did."
"That's all."
"Some things you just say."
"It wasn't a single battle, it was a lifetime of waiting."

Ending of the piece:
#{storyCloser}

Epilogue:
"""

# ─── extraction ──────────────────────────────────────────────────

extractHook = (storyText, maxChars = 500) ->
  s = String(storyText ? '').trim()
  paras = s.split(/\n\s*\n/).map((p) -> p.trim()).filter (p) -> p.length
  return '' unless paras.length
  # Skip a leading "Hi, Friend," style greeting — take the substantive first paragraph.
  first = paras[0]
  if first.length < 40 and paras.length > 1
    first = paras[1]
  return first if first.length <= maxChars
  # Trim to sentence boundary before the limit.
  cut = first.slice(0, maxChars)
  lastPeriod = cut.lastIndexOf('.')
  return cut.slice(0, lastPeriod + 1) if lastPeriod > maxChars * 0.5
  cut

extractCloser = (storyText, maxChars = 400) ->
  s = String(storyText ? '').trim()
  paras = s.split(/\n\s*\n/).map((p) -> p.trim()).filter (p) -> p.length
  return '' unless paras.length
  last = paras[paras.length - 1]
  return last if last.length <= maxChars
  # For a long final paragraph, keep the last N chars ending at a sentence boundary.
  tail = last.slice(-maxChars)
  firstPeriod = tail.indexOf('.')
  return tail.slice(firstPeriod + 1).trim() if firstPeriod isnt -1 and firstPeriod < maxChars * 0.5
  tail

# Clean a candidate's first line — strip surrounding quotes,
# collapse whitespace, drop garbage after the first sentence.
cleanCandidate = (rawText, maxWords) ->
  s = String(rawText ? '').trim()
  return '' unless s.length
  # Take the first non-blank line only.
  for line in s.split(/\n/)
    trimmed = line.trim()
    if trimmed.length
      s = trimmed
      break
  # Strip surrounding quotes if present.
  s = s.slice(1, -1).trim() if s.length > 1 and s[0] in ['"', '“'] and s[s.length - 1] in ['"', '”']
  s = s.slice(1, -1).trim() if s.length > 1 and s[0] in ['"', '“'] and s[s.length - 1] in ['"', '”']
  # Word cap — take first N words if the model overshoots.
  words = s.split(/\s+/)
  s = words.slice(0, maxWords).join(' ') if words.length > maxWords and maxWords > 0
  s

# ─── platform bundling ──────────────────────────────────────────

PLATFORM_LIMITS =
  twitter:    280
  facebook:   500
  email:      120     # subject line
  newsletter: 200     # preheader

formatForPlatform = (platform, headline, epilogue) ->
  switch platform
    when 'twitter'
      # Headline + optional epilogue as second sentence, respecting 280 chars.
      first = headline
      combined = "#{headline} — #{epilogue}"
      if combined.length <= 280 then combined else first
    when 'facebook'
      # More room; use both, separated.
      "#{headline}\n\n#{epilogue}"
    when 'email'
      # Subject line — headline only, hard cap.
      headline.slice(0, PLATFORM_LIMITS.email)
    when 'newsletter'
      # Preheader-scale — headline + short cue.
      combined = "#{headline} — #{epilogue}"
      if combined.length <= PLATFORM_LIMITS.newsletter then combined else headline
    else
      headline

@step =
  desc: 'Broadcast headlines + epilogues from a story + its spine (0.6B, shotgun).'

  action: (L) ->
    spineName    = L.param 'spine', null
    storyRel     = L.param 'story_file', null
    unless storyRel? and String(storyRel).length
      throw new Error "[#{L.stepName}] story_file (path relative to CWD) required"
    nCandidates  = Number L.param('n_candidates', 5)
    headlineWords = Number L.param('headline_max_words', 15)
    platforms    = L.param 'platforms', ['twitter', 'facebook', 'email', 'newsletter']
    platforms    = [platforms] if typeof platforms is 'string'

    modelDir = String L.param('quantized_model_dir', '')
    unless modelDir.length and fs.existsSync(path.join(modelDir, 'config.json'))
      throw new Error "[#{L.stepName}] quantized_model_dir invalid: #{modelDir}"

    cwd = process.env.CWD ? process.cwd()
    storyPath = if path.isAbsolute(storyRel) then storyRel else path.join(cwd, storyRel)
    throw new Error "[#{L.stepName}] story_file not found: #{storyPath}" unless fs.existsSync(storyPath)
    storyText = fs.readFileSync(storyPath, 'utf8')

    # Optional spine — pulled via meta layer (data/spines/<name>.txt).
    spineText = null
    if spineName? and String(spineName).length
      key = "data/spines/#{spineName}.txt"
      spineText = L.theLowdown(key)?.value ? null

    hook   = extractHook(storyText)
    closer = extractCloser(storyText)

    headlinePrompt = buildHeadlinePrompt(hook, spineText, headlineWords)
    epiloguePrompt = buildEpiloguePrompt(closer)

    console.log "[#{L.stepName}] story:  #{storyPath} (#{storyText.length} chars)"
    console.log "[#{L.stepName}] spine:  #{if spineName? then spineName else '(none)'}"
    console.log "[#{L.stepName}] shotgun: #{nCandidates} each × 2 (headlines, epilogues)"

    shotgun = (label, prompt, maxWords, maxTokens) ->
      candidates = []
      # Temperature spread — moderate-to-high; the caption test showed
      # moderate temps produce cleaner winners than pure high-temp.
      temps = for i in [0...nCandidates]
        0.85 + i * ((1.05 - 0.85) / Math.max(1, nCandidates - 1))
      for temp, i in temps
        try
          resp = await L.callLLM
            op:                 'generate'
            modelDir:           modelDir
            prompt:             prompt
            maxTokens:          maxTokens
            temperature:        temp
            topP:               0.9
            raw:                true
            repetition_penalty: 1.3
          raw = String(resp?.text ? resp?.rawText ? '')
          text = cleanCandidate raw, maxWords
          candidates.push {i, temperature: Number(temp.toFixed(2)), chars: text.length, text: text, raw: raw.slice(0, 200)} if text.length
          console.log "[#{L.stepName}] #{label}[#{i}] T=#{temp.toFixed(2)}: #{text}"
        catch err
          console.log "[#{L.stepName}] #{label}[#{i}] failed: #{err?.message ? err}"
      candidates

    headlines = await shotgun 'headline', headlinePrompt, headlineWords, 40
    epilogues = await shotgun 'epilogue', epiloguePrompt, 25,          60

    # For platform bundles, use candidate #0 of each (temperature 0.85 —
    # the caption test winner). Downstream selection / judging can pick
    # a different candidate.
    bestHead = headlines[0]?.text ? ''
    bestEpi  = epilogues[0]?.text ? ''
    bundle = {}
    for platform in platforms
      bundle[platform] =
        headline:  bestHead
        epilogue:  bestEpi
        formatted: formatForPlatform(platform, bestHead, bestEpi)
        char_limit: PLATFORM_LIMITS[platform] ? null

    L.make 'broadcast_headlines_jsonl', headlines
    L.make 'broadcast_epilogues_jsonl', epilogues
    L.make 'broadcast_bundle_json',
      story_file:  storyRel
      spine:       spineName
      hook:        hook
      closer:      closer
      candidates_headlines: headlines.length
      candidates_epilogues: epilogues.length
      bundle:      bundle

    console.log "[#{L.stepName}] emitted #{headlines.length} headlines, #{epilogues.length} epilogues"
    for platform in platforms
      console.log "[#{L.stepName}] #{platform}: #{bundle[platform].formatted}"

    # Emit the human-facing review HTML. Written to out/broadcast_review.html
    # so the puppeteer UI can list + link to it. bundle_id = story basename
    # + timestamp for uniqueness (one review per broadcast run).
    stamp = new Date().toISOString().replace(/[:.]/g,'-').slice(0,16)
    storyBase = path.basename(storyRel).replace(/\.[^.]+$/, '')
    bundleId = "#{storyBase}_#{stamp}"
    html = renderReviewHtml bundleId, storyRel, hook, closer, headlines, epilogues, platforms
    fs.writeFileSync path.join(cwd, 'out', 'broadcast_review.html'), html, 'utf8'
    # Also archive to a stable location under out/broadcasts/<bundleId>.html
    archiveDir = path.join(cwd, 'out', 'broadcasts')
    fs.mkdirSync archiveDir, { recursive: true }
    fs.writeFileSync path.join(archiveDir, "#{bundleId}.html"), html, 'utf8'
    console.log "[#{L.stepName}] review: out/broadcasts/#{bundleId}.html"

    L.done()
    return
