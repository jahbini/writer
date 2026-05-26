#!/usr/bin/env bash
#
# pipe-new.sh — scaffold a new pipe under pipes/<name>/.
#
# Usage:
#   npm run pipe:new <name> [pipeline-name]
#   ./bin/pipe-new.sh <name> [pipeline-name]
#
# Default pipeline-name is `test` (the shipped 9-step demo). Override
# with any recipe that exists in @jahbini/pipeline's config/, or
# replace pipes/<name>/override.yaml with your own afterward.
#
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:-}"
PIPELINE="${2:-test}"

if [ -z "$NAME" ]; then
  echo "Usage: npm run pipe:new <name> [pipeline-name]"
  echo "       npm run pipe:new my_experiment"
  echo "       npm run pipe:new my_lora_run lora_ite"
  exit 1
fi

if [[ "$NAME" =~ [/\\] ]] || [ "$NAME" = "." ] || [ "$NAME" = ".." ]; then
  echo "Error: pipe name must not contain slashes or be . or .."
  exit 1
fi

PIPE_DIR="pipes/$NAME"

if [ -d "$PIPE_DIR" ]; then
  echo "Error: pipes/$NAME already exists."
  exit 1
fi

mkdir -p "$PIPE_DIR"
ln -s ../../.venv "$PIPE_DIR/.venv"

# Start from the shipped override.test.yaml as the template, then
# rewrite its `pipeline:` line to whatever the caller asked for.
cp node_modules/@jahbini/pipeline/override.test.yaml "$PIPE_DIR/override.yaml"
# Cross-platform-ish sed: write to a temp and move back.
sed "s|^pipeline:.*|pipeline: $PIPELINE|" "$PIPE_DIR/override.yaml" > "$PIPE_DIR/override.yaml.tmp"
mv "$PIPE_DIR/override.yaml.tmp" "$PIPE_DIR/override.yaml"

echo "Created $PIPE_DIR/"
echo "  .venv → ../../.venv (symlink to shared venv)"
echo "  override.yaml — pipeline: $PIPELINE"
echo
echo "Run it: cd $PIPE_DIR && npx pipeline"
