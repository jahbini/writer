#!/usr/bin/env bash
#
# pipes-init.sh — recreate the canonical set of pipes for this project.
#
# Since `pipes/*` is fully gitignored (see writer/.gitignore and
# GPT/README.md), a fresh clone or a wiped tree has no pipes. This
# script is the durable record of "which pipes exist and what model
# each uses" — the version-controlled counterpart to that ephemeral
# state.
#
# Idempotent: if a pipe directory already exists, pipe-new.sh will
# refuse to overwrite (409). Delete pipes/<name>/ first if you want
# this script to recreate it.
#
# Usage:
#   ./bin/pipes-init.sh              # create all canonical pipes
#   ./bin/pipes-init.sh <name>...    # create only the named pipes
#
# Adding a new canonical pipe: append a `mk <name> <hf-model> <pipeline>`
# line below and commit. That's the whole workflow.
#
set -euo pipefail
cd "$(dirname "$0")/.."

# Restrict to a subset if names given on the command line.
WANTED=("$@")
want() {
  [ ${#WANTED[@]} -eq 0 ] && return 0
  local name="$1"
  for w in "${WANTED[@]}"; do [ "$w" = "$name" ] && return 0; done
  return 1
}

mk() {
  local name="$1" model="$2" pipeline="${3:-reset}"
  if ! want "$name"; then
    return 0
  fi
  if [ -d "pipes/$name" ]; then
    echo "skip $name (pipes/$name/ exists)"
    return 0
  fi
  echo "create $name — $model — pipeline: $pipeline"
  ./bin/pipe-new.sh "$name" "$model" "$pipeline"
}

# =====================================================================
# Canonical pipes
# =====================================================================
# One line per pipe: mk <name> <hf-model-id> [<default-pipeline>]
# Pipeline defaults to `reset` (the download + quantize + seed bootstrap).
# `run.model` is written into pipes/<name>/override.yaml verbatim.

# ---- Qwen3.5 family (2026-08 bring-up) ----------------------------
mk small   Qwen/Qwen3.5-0.8B-Base           reset
mk q35_4   Qwen/Qwen3.5-4B                  reset
mk qwen3.8 mlx-community/Qwen3.8-27B-4bit   reset

# ---- Abliterated Qwen3-4B (writer production pipe) ----------------
mk Huihui-Qwen3-4B-Instruct-2507-abliterated \
   huihui-ai/Huihui-Qwen3-4B-Instruct-2507-abliterated \
   reset

# ---- Manual / non-standard pipes ----------------------------------
# These aren't created by pipe-new.sh because they don't follow the
# "single HF model + reset pipeline" shape. Recreate by hand if needed.
#
#   pipes/sample/   — the `test` demo recipe. No model. Create with:
#                       mkdir -p pipes/sample/{state,logs,out,override}
#                       cp <a copy of the sample override.yaml>  pipes/sample/override.yaml
#
#   pipes/story/    — historical scratch. Recreate only if you need it;
#                     confirm model + pipeline first (last-seen empty).

echo "done."
