#!/usr/bin/env coffee
# adapter_fidelity.coffee — checkpoint save/load fidelity check.
#
# Loads a saved LoRA adapter through the SAME code path as inference
# (applyLoRA + loadAdapter from mlx/lora/wrap) and computes the trainer's
# exact validation loss (makeLossFn from mlx/lora/train) over valid.jsonl.
#
# Compare the reported number against the training-time valid loss for
# the same iter. If they match, the on-disk checkpoint is faithful and
# the bug is elsewhere. If they diverge, the save/load path is broken.
#
# Also runs base-model-only (no adapter) as a baseline for reference.
#
# Usage:
#   coffee scripts/adapter_fidelity.coffee \
#     --model build/model4 \
#     --adapter build/adapter/0000100_adapters.safetensors \
#     --valid /Users/jahbini/writeStory/pipes/Qwen_Qwen3-4B-Instruct-2507/build/train/valid.jsonl \
#     [--batch-size 4] [--max-seq 2048] [--batches 25] [--seed 0]

path      = require 'path'
fs        = require 'fs'

# Resolve library paths through the writer's node_modules so we hit the
# same pipeline copy the runner uses.
PIPE_ROOT = path.resolve __dirname, '..', 'node_modules', '@jahbini', 'pipeline'
{applyLoRA, loadAdapter} = require path.join(PIPE_ROOT, 'mlx', 'lora', 'wrap')
trainMod = require path.join(PIPE_ROOT, 'mlx', 'lora', 'train')
{loadJsonl, makeLossFn, buildBatch} = trainMod
# tokenizeCorpus isn't exported — pull it out of the module's compiled form.
# Fall back to a local re-implementation if the trainer ever changes shape.
tokenizeCorpus = trainMod.tokenizeCorpus ? (rows, tokenizer, maxSeqLen, eosId) ->
  out = []
  for text in rows
    ids = tokenizer.encode text
    if ids.length > maxSeqLen
      ids = ids[...maxSeqLen]
      ids[ids.length - 1] = eosId if eosId?
    out.push ids if ids.length >= 2
  out

{core: mx, nn}                = require '@frost-beta/mlx'
{Tokenizer, LLM}              = require '@frost-beta/llm'
{loadWeights, readJsonSync}   = require '@frost-beta/llm/dist/fs.js'

# Same model-type dispatch session_api uses.
LOCAL_MODELS =
  qwen3: -> require path.join(PIPE_ROOT, 'mlx', 'models', 'qwen3')

resolveModelClass = (modelType) ->
  return LOCAL_MODELS[modelType]().Model if LOCAL_MODELS[modelType]?
  try
    return require("@frost-beta/llm/dist/models/#{modelType}.js").Model
  catch
    throw new Error "Unsupported model_type: #{modelType}"

parseArgs = ->
  a = process.argv.slice 2
  o = {batchSize: 4, maxSeq: 2048, batches: 25, seed: 0}
  i = 0
  while i < a.length
    switch a[i]
      when '--model'      then o.model    = a[++i]
      when '--adapter'    then o.adapter  = a[++i]
      when '--valid'      then o.valid    = a[++i]
      when '--batch-size' then o.batchSize= +a[++i]
      when '--max-seq'    then o.maxSeq   = +a[++i]
      when '--batches'    then o.batches  = +a[++i]
      when '--seed'       then o.seed     = +a[++i]
      else throw new Error "unknown arg #{a[i]}"
    i++
  for k in ['model','valid']
    throw new Error "missing --#{k}" unless o[k]?
  o

loadModel = (modelDir) ->
  # Mirror session_api.createSession's model+tokenizer construction so we
  # exercise the exact same seam without needing the returned wrapper.
  modelDir = path.resolve modelDir
  config = readJsonSync path.join(modelDir, 'config.json')
  modelType = config.model_type
  mx.setCacheLimit 512 * 1024 * 1024

  ModelClass = resolveModelClass modelType
  model = new ModelClass(config)
  weights = loadWeights modelDir
  model.sanitize?(weights)
  if config.quantization
    {group_size, bits} = config.quantization
    predicate = (paramPath, mod) ->
      (mod instanceof nn.Linear or mod instanceof nn.Embedding) and "#{paramPath}.scales" of weights
    nn.quantize model, group_size, bits, predicate
  model.loadWeights Object.entries(weights)
  mx.eval model.parameters()

  tokenizer = new Tokenizer(modelDir)
  {model, tokenizer, config}

evalLoss = ({model, tokenized, batchSize, batches, padId, seed}) ->
  lossFn = makeLossFn model
  # Deterministic PRNG so BASE and ADAPTER see the same batches.
  s = seed ? 0
  rng = -> s = (s * 1664525 + 1013904223) % 4294967296; s / 4294967296
  total = 0
  n = 0
  for b in [0...batches]
    batch = buildBatch tokenized, batchSize, rng, padId
    [loss] = mx.tidy =>
      l = lossFn batch.inputs, batch.targets, batch.mask
      mx.eval l
      [l.item()]
    total += loss
    n += 1
    mx.dispose? [batch.inputs, batch.targets, batch.mask]
  {mean: total / Math.max(1, n), batches: n}

main = ->
  opts = parseArgs()

  console.log "=== adapter_fidelity ==="
  console.log "model:   #{opts.model}"
  console.log "adapter: #{opts.adapter ? '(none — base only)'}"
  console.log "valid:   #{opts.valid}"
  console.log ""

  # -------- Base session (no adapter) --------
  console.log "[1/2] loading base model (no adapter)…"
  baseInfo = loadModel opts.model
  tokenizer = baseInfo.tokenizer
  baseModel = baseInfo.model
  # Match the trainer's eosId resolution exactly (see train.coffee:250).
  eosId = tokenizer.eosToken ? tokenizer.tokenizer?.eos_token_id ? 0
  padId = eosId

  console.log "tokenizing #{opts.valid}…"
  rows = loadJsonl opts.valid
  tokenized = tokenizeCorpus rows, tokenizer, opts.maxSeq, eosId
  console.log "  #{tokenized.length} sequences (of #{rows.length}); eosId=#{eosId}"
  console.log ""

  console.log "running base-only eval over first #{opts.batches} batches of #{opts.batchSize}…"
  base = evalLoss {model: baseModel, tokenized, batchSize: opts.batchSize, batches: opts.batches, padId, seed: opts.seed}
  console.log "  BASE LOSS: #{base.mean.toFixed 4}  (#{base.batches} batches)"
  console.log ""

  # -------- Adapter session (fresh model, apply LoRA, load weights) --------
  return unless opts.adapter?

  console.log "[2/2] loading fresh model + adapter through the inference seam…"
  adInfo = loadModel opts.model
  adModel = adInfo.model
  # Read adapter_config for wrap params.
  cfgDir = if /\.safetensors$/.test(opts.adapter) then path.dirname(opts.adapter) else opts.adapter
  weightsPath = if /\.safetensors$/.test(opts.adapter) then opts.adapter else null
  cfg = JSON.parse fs.readFileSync path.join(cfgDir, 'adapter_config.json'), 'utf8'
  wrapOpts =
    rank:      cfg.rank
    alpha:     cfg.alpha
    dropout:   0        # eval — no dropout
    targets:   cfg.targets
    numLayers: cfg.num_layers
  wrappedInfo = applyLoRA adModel, wrapOpts
  loadRes = loadAdapter cfgDir, wrappedInfo, weightsPath
  console.log "  wrapped #{wrappedInfo.count} modules; loaded #{loadRes?.loaded ? '?'}/#{loadRes?.expected ? '?'} tensors"
  console.log ""

  console.log "running adapter eval over first #{opts.batches} batches of #{opts.batchSize}…"
  ad = evalLoss {model: adModel, tokenized, batchSize: opts.batchSize, batches: opts.batches, padId, seed: opts.seed}
  console.log "  ADAPTER LOSS: #{ad.mean.toFixed 4}  (#{ad.batches} batches)"
  console.log ""

  delta = ad.mean - base.mean
  console.log "SUMMARY"
  console.log "  base            : #{base.mean.toFixed 4}"
  console.log "  adapter         : #{ad.mean.toFixed 4}"
  console.log "  delta (ad-base) : #{delta.toFixed 4}"
  console.log ""
  console.log "Compare ADAPTER LOSS against the trainer's reported val loss"
  console.log "at the corresponding iter (~3.72 for step 100). If they match,"
  console.log "the checkpoint is faithful. If far worse than base, the save/"
  console.log "load path is dropping learned weights."

try
  main()
catch err
  console.error err.stack ? err
  process.exit 1
