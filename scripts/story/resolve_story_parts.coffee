###
  resolve_story_parts.coffee — PIPE-LOCAL SHADOW
  =====================================================
  Reason for the shadow: the shipped version emits each event as
  the raw library array (e.g., scene: [atom1, atom2, ...]), but
  build_diary_prompt_ite expects a single object with a `.text`
  field per event. Empty prompt slots result — the model sees
  `- scene: ` and hallucinates.

  Fix: pick one atom per event at random, coerce to
  `{text, ...}` shape, and add a `keyword` field from the recipe
  key so build_diary_prompt_ite's `.location`/`.character`/
  `.theme` reads have something meaningful.

  Randomness is deliberate (user opted in) — different atoms on
  each run make the diary vary. If reproducibility matters later,
  add per-event UI dropdowns and pipe the selection through
  `story_recipe`.

  Preserves the original arrays under `_atoms` for debugging /
  a future UI dropdown that lets the human pick a specific atom.
###

pickAtom = (arr) ->
  return null unless Array.isArray(arr) and arr.length > 0
  chosen = arr[Math.floor(Math.random() * arr.length)]
  if typeof chosen is 'string'
    { text: chosen }
  else if chosen? and typeof chosen is 'object' and typeof chosen.text is 'string'
    Object.assign {}, chosen
  else
    { text: String(chosen ? '') }

@step =
  desc: "Resolve story recipe keys into expanded story parts (one atom per event, random pick)"

  action: (M, stepName) ->
    readInput = (key) ->
      entry = M.theLowdown key
      value = entry?.value
      if value is undefined
        if typeof entry?.waitFor is 'function'
          value = await entry.waitFor()
        else if entry?.notifier?
          value = await entry.notifier
      throw new Error "[#{stepName}] Missing input key '#{key}'" if value is undefined
      value

    bundle = await readInput 'story_library'
    selected = await readInput 'story_recipe'

    lib = bundle?.library ? {}
    recipe = selected?.recipe ? {}

    needAtoms = (shelfName, keyName) ->
      shelf = lib?[shelfName] ? {}
      value = shelf?[keyName]
      unless value?
        throw new Error "[#{stepName}] Missing #{shelfName}.#{keyName}"
      unless Array.isArray(value)
        # Legacy library shape: single item, not an array. Wrap it.
        return [value]
      value

    sceneKey       = recipe?.scene
    arrivalKey     = recipe?.arrival
    disturbanceKey = recipe?.disturbance
    reflectionKey  = recipe?.reflection
    realizationKey = recipe?.realization

    sceneAtoms       = needAtoms 'scenes',        sceneKey
    arrivalAtoms     = needAtoms 'characters',    arrivalKey
    disturbanceAtoms = needAtoms 'disturbances',  disturbanceKey
    reflectionAtoms  = needAtoms 'reflections',   reflectionKey
    realizationAtoms = needAtoms 'realizations',  realizationKey

    # Pick one, then stamp the recipe key onto the atom so
    # build_diary_prompt_ite's keyword lookups have a value.
    scene       = Object.assign {location:  sceneKey},       pickAtom(sceneAtoms)
    arrival     = Object.assign {character: arrivalKey},     pickAtom(arrivalAtoms)
    disturbance = Object.assign {theme:     disturbanceKey}, pickAtom(disturbanceAtoms)
    reflection  = Object.assign {keyword:   reflectionKey},  pickAtom(reflectionAtoms)
    realization = Object.assign {keyword:   realizationKey}, pickAtom(realizationAtoms)

    out =
      story_id: selected?.story_id
      keys:
        scene:       sceneKey
        arrival:     arrivalKey
        disturbance: disturbanceKey
        reflection:  reflectionKey
        realization: realizationKey
      scene:       scene
      arrival:     arrival
      disturbance: disturbance
      reflection:  reflection
      realization: realization
      # Full arrays preserved for debugging / future per-atom UI dropdown.
      _atoms:
        scene:       sceneAtoms
        arrival:     arrivalAtoms
        disturbance: disturbanceAtoms
        reflection:  reflectionAtoms
        realization: realizationAtoms

    console.log "[#{stepName}] scene: #{scene.text}"
    console.log "[#{stepName}] arrival: #{arrival.text}"
    console.log "[#{stepName}] disturbance: #{disturbance.text}"
    console.log "[#{stepName}] reflection: #{reflection.text}"
    console.log "[#{stepName}] realization: #{realization.text}"

    M.saveThis "story_parts", out
    M.saveThis "done:#{stepName}", true
    return
