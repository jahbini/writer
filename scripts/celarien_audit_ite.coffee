###
  celarien_audit_ite.coffee — Phase 4 audit step per CELARIEN.md.

  Extends state_extractor for celarien runs. Companion file — does NOT
  modify writer/scripts/state_extractor.coffee (which serves the JIM
  story pipeline and feeds actuals into next chapter's plan).
  Celarien has the OPPOSITE contract: no chapter-to-chapter state
  passing. This step audits each chapter against its pre-planned
  spread and emits regeneration triggers, never inherited state.

  Reads:
    celarien_filled_arc_json       — Phase 3 output, planned spread
                                     per chapter
    celarien_chapter_actuals_json  — { chapter_key → actual_text }
                                     from a downstream generator step;
                                     supplied by the recipe once
                                     celarien is wired to a generator
                                     pipe. If missing, step is a no-op
                                     (nothing to audit yet).

  Emits:
    celarien_audit_json — one entry per chapter:
      {
        chapter_key,
        planned: { class, aperture, fortune, ... }, # subset for audit trail
        invariants_intact: bool,
        invariant_breaches: [ "..." ],              # human-readable
        success_criterion:  "met" | "honestly_missed" | "silent",
        tip_landed:         "yes" | "no" | "reversed",
        regen_needed:       bool,                   # true iff invariant breach
        notes:              "..."
      }

  Gate: use_celarien_arc (default false). Off = no-op.

  HARD INVARIANT (from CELARIEN.md): the audit result MUST NOT
  propagate into any later chapter's plan. This step emits an
  audit artifact only; the next chapter's directive still comes
  from the pre-planned filled arc, byte-for-byte.

  Grading uses an LLM judge — the writer pipe's quantized model
  via L.callLLM, same shape sat_story_ite.coffee's grader uses.

  Report: writer/GPT/story/celarien_status.md.
###

fs   = require 'fs'
path = require 'path'
yaml = require 'js-yaml'

# ── LLM judge scaffolding (same pattern as sat_story_ite.coffee) ──

stripJson = (rawText) ->
  s = String(rawText ? '')
  m = s.match /[\s\S]*<\/think>\s*([\s\S]*)$/
  s = m[1] if m
  s = s.replace(/<\|im_end\|>[\s\S]*$/, '')
  brace = s.indexOf '{'
  return null if brace < 0
  depth = 0
  for i in [brace..s.length - 1]
    switch s[i]
      when '{' then depth += 1
      when '}'
        depth -= 1
        return s.slice brace, i + 1 if depth is 0
  null

# Thinking-budget rescue, same shape as elsewhere.
callWithThinkRescue = (L, llmArgs) ->
  resp = await L.callLLM llmArgs
  raw = String(resp?.rawText ? resp?.text ? '')
  return raw if raw.indexOf('</think>') >= 0
  rescue = "\n\nOK, time is up. Answering now.\n</think>\n\n"
  args2 = Object.assign {}, llmArgs,
    prompt:    llmArgs.prompt + raw + rescue
    maxTokens: Math.max(200, Math.floor((llmArgs.maxTokens ? 512) / 2))
  resp2 = await L.callLLM args2
  raw2 = String(resp2?.rawText ? resp2?.text ? '')
  raw + rescue + raw2

# ── Per-chapter judge calls ───────────────────────────────────────

INVARIANTS_PROMPT = (chapterText, planned) ->
  """
  You are auditing a chapter for four chapter-contract invariants:
    1. Crew survives — the captain, the amazons, and the athlete
       cannot die, be maimed beyond recovery, or be written off
       the ship.
    2. The voyage continues — the ship is afloat and the next
       chapter is reachable.
    3. At most one mythic aperture — no more than one oracle
       consultation or underworld descent in this chapter.
    4. No new named characters beyond the chapter's planned
       passenger (planned passenger for this chapter: #{planned?.passenger ? 'none'}).

  Reply with exactly one JSON object, no prose, no code fences:
    {"intact": true|false,
     "breaches": ["invariant text", ...],
     "notes": "one sentence"}

  Chapter:
  #{chapterText}

  Output:
  """

SUCCESS_PROMPT = (chapterText, criterion) ->
  """
  You are auditing whether a chapter meets its pre-planned success
  criterion. Meeting the criterion is not the only positive outcome
  — an "honestly missed" chapter (attempts but visibly falls short)
  is also a valid grading. "Silent" means the chapter neither
  attempts nor addresses the criterion at all.

  Reply with exactly one JSON object, no prose, no code fences:
    {"status": "met" | "honestly_missed" | "silent",
     "note":   "one sentence"}

  Planned success criterion:
  #{criterion ? '(none)'}

  Chapter:
  #{chapterText}

  Output:
  """

TIP_PROMPT = (chapterText, tip) ->
  """
  You are auditing whether the chapter's ending fortune matches the
  pre-planned tip. Compare the chapter's actual ending fortune
  (win / neutral / loss and its magnitude) against the plan.

  Reply with exactly one JSON object, no prose, no code fences:
    {"landed": "yes" | "no" | "reversed",
     "note":   "one sentence"}

  Planned tip: #{tip ? '(none)'}

  Chapter:
  #{chapterText}

  Output:
  """

judge = (L, prompt, opts = {}) ->
  modelDir = L.param('grader_model_dir', L.param('quantized_model_dir', null))
  throw new Error "[celarien_audit_ite] grader_model_dir (or quantized_model_dir) required" unless modelDir?
  wrapped = "<|im_start|>user\n#{prompt}<|im_end|>\n<|im_start|>assistant\n"
  raw = await callWithThinkRescue L,
    op:          'generate'
    modelDir:    modelDir
    prompt:      wrapped
    maxTokens:   opts.maxTokens ? 1500
    temperature: opts.temperature ? 0.1
    topP:        0.8
    raw:         true
  jt = stripJson(raw)
  return null unless jt
  try JSON.parse(jt) catch then null

# ── Whole-arc audit ───────────────────────────────────────────────

auditArc = (L, filledArc, actualsMap) ->
  chapterKeys = Object.keys(filledArc?.chapters ? {}).sort()
  results = []
  for chapterKey in chapterKeys
    chapter = filledArc.chapters[chapterKey]
    actualText = actualsMap?[chapterKey]
    unless actualText? and String(actualText).trim().length
      results.push
        chapter_key:        chapterKey
        planned:            {class: chapter.class, aperture: chapter.aperture, fortune: chapter.fortune}
        invariants_intact:  null
        invariant_breaches: []
        success_criterion:  'unaudited'
        tip_landed:         'unaudited'
        regen_needed:       false
        notes:              'no actual text supplied — chapter not yet generated'
      continue

    invJudged = await judge L, INVARIANTS_PROMPT(actualText, chapter)
    sucJudged = await judge L, SUCCESS_PROMPT(actualText, chapter.spread?.sword?.success)
    tipJudged = await judge L, TIP_PROMPT(actualText, chapter.spread?.sword?.tip)

    intact = invJudged?.intact is true
    results.push
      chapter_key:        chapterKey
      planned:            {class: chapter.class, aperture: chapter.aperture, fortune: chapter.fortune}
      invariants_intact:  intact
      invariant_breaches: (invJudged?.breaches ? [])
      success_criterion:  (sucJudged?.status ? 'unparsable')
      tip_landed:         (tipJudged?.landed ? 'unparsable')
      regen_needed:       (not intact)   # CELARIEN.md: invariant
                                          # breach is a regeneration
                                          # trigger, not a drift note
      notes:              [invJudged?.notes, sucJudged?.note, tipJudged?.note].filter((s) -> s?.length).join(' | ')

  results

# ── The step ──────────────────────────────────────────────────────

@step =
  desc: "Celarien Phase 4: audit each chapter against its pre-planned spread"
  action: (L) ->
    unless L.param('use_celarien_arc', false) is true
      console.log "[celarien_audit_ite] gate use_celarien_arc=false — skipping"
      L.done()
      return

    filledArc = await L.need 'celarien_filled_arc_json'
    # Actuals map is OPTIONAL — if the generator hasn't fired yet,
    # this step no-ops per chapter (see auditArc's unaudited branch).
    actualsMap = {}
    try
      actualsMap = (await L.need 'celarien_chapter_actuals_json') ? {}
    catch _err
      actualsMap = {}

    results = await auditArc(L, filledArc, actualsMap)
    regens = (r for r in results when r.regen_needed).length
    console.log "[celarien_audit_ite] audited #{results.length} chapters, #{regens} regen trigger(s)"

    L.make 'celarien_audit_json', results
    L.done()
    return

# Don't reassign module.exports — the runner reads @step from the
# current module.exports (pipeline_runner.coffee:1680). Coffee's
# `@step = ...` sets `module.exports.step`; reassignment drops it.
exports.auditArc = auditArc
