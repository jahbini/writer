@step =
  desc: "Write mlx_lm.lora --config YAML (lora_parameters: rank/scale/dropout)"

  action: (M, stepName) ->
    # Params with mlx-lm's own defaults as fallback so an under-specified
    # override still produces a valid config. Each is overridable per pipe
    # in override/lora_ite.yaml under the `build_lora_config_ite:` block.
    # No prescreens (per CONVENTIONS): a bad value falls naturally through
    # the yaml writer / mlx-lm's config parser, where the real trace tells
    # us what was actually wrong.
    rank    = M.getStepParam(stepName, 'rank')    ? 8
    scale   = M.getStepParam(stepName, 'scale')   ? 20.0
    dropout = M.getStepParam(stepName, 'dropout') ? 0.0

    # Match the structure mlx_lm/lora.py's `-c/--config` consumes:
    # lora_parameters: { rank, scale, dropout }. Anything else here would
    # ride mlx-lm defaults — by design this step ONLY exposes the three
    # knobs that have no CLI flag. Other training params stay in the
    # step's `mlx:` block (num-layers, learning-rate, iters, etc.).
    config =
      lora_parameters:
        rank: rank
        scale: scale
        dropout: dropout

    M.saveThis "lora_config", config
    console.log "[#{stepName}] rank=#{rank} scale=#{scale} dropout=#{dropout}"
    M.saveThis "done:#{stepName}", true
    return
