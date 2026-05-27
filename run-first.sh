#!/usr/bin/env bash
#
# run-first.sh — one-command bootstrap for pipeline-pipes.
#
# Run this once after `git clone`. It does, in order:
#
#   1. npm install         — pulls @jahbini/pipeline from GitHub
#   2. shared .venv        — creates ./.venv at the project root and
#                             pip-installs MLX (mlx, mlx-lm, mlx-metal
#                             at pinned versions)
#   3. sample pipe         — sets up pipes/sample/ with a symlink to
#                             the shared .venv and a fresh override.yaml
#                             pointing at the test pipeline
#
# After this, four things are available:
#
#   npm run download -- Qwen/Qwen3-4B-Instruct-2507
#                         # downloads + quantizes a model into build/
#
#   cd pipes/sample && npx pipeline
#                         # runs the sample pipe (the test pipeline)
#
#   npm run pipe:new <name> [pipeline-name]
#                         # adds a new pipe; default pipeline is `test`
#
#   npm run ui            # open the multi-pipe UI at http://127.0.0.1:4311
#
set -euo pipefail
cd "$(dirname "$0")"

banner() {
  echo
  echo "════════════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "════════════════════════════════════════════════════════════════════"
}

banner "1/3  npm install — pulling @jahbini/pipeline from GitHub"
npm install

banner "2/3  Setting up the venv with MLX at the project base (./.venv)"
# The venv lives at the project BASE — stable, outside the npm tree.
# Pipeline steps are CWD-agnostic; the runner's resolvePython() resolves
# the interpreter from <CWD>/.venv, then <BASE>/.venv, then <EXEC>/.venv,
# so a single base venv serves every pipe with no per-pipe .venv and
# nothing venv-related inside the npm-wiped node_modules.
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip setuptools wheel
  .venv/bin/pip install -r node_modules/@jahbini/pipeline/requirements.txt
else
  echo "  .venv already present — skipping (rm -rf .venv to redo)"
fi

banner "3/3  Setting up sample pipe at pipes/sample/"
# No per-pipe .venv: a pipe is a working directory, not an environment.
mkdir -p pipes/sample build
cd pipes/sample
if [ -f override.yaml ]; then
  mv override.yaml "override.yaml.$(date +%Y-%m-%d_%H-%M-%S).bak"
fi
cp ../../node_modules/@jahbini/pipeline/override.test.yaml override.yaml
cd ../..

echo
echo "Done. Four things to try next:"
echo
echo "  npm run model -- Qwen/Qwen3-4B-Instruct-2507"
echo "      # activates the download_model recipe to fetch + quantize"
echo "      # a HuggingFace model into build/model and build/model4."
echo "      # The recipe runs through the pipeline, not via raw HF cli"
echo "      # — the quantized output is self-contained and offline-usable."
echo
echo "  cd pipes/sample && npx pipeline"
echo "      # run the sample pipe end-to-end (test pipeline, no model needed)"
echo
echo "  npm run pipe:new my_experiment"
echo "      # scaffold a new pipe under pipes/my_experiment/"
echo
echo "  npm run ui"
echo "      # open the multi-pipe UI on http://127.0.0.1:4311"
