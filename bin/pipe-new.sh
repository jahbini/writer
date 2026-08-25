#!/usr/bin/env bash
#
# pipe-new.sh — scaffold a new pipe under pipes/<name>/.
#
# Usage:
#   npm run pipe:new <name> <hf-model> [pipeline-name]
#   ./bin/pipe-new.sh <name> <hf-model> [pipeline-name]
#
# Examples:
#   npm run pipe:new my_pipe Qwen/Qwen3-4B-Instruct-2507
#   npm run pipe:new my_pipe huihui-ai/Huihui-Qwen3-4B-Instruct-2507-abliterated reset
#
# `hf-model` is the HuggingFace org/name written into override.yaml as
# `run.model`. Required — model_identity.md forbids recipe defaults.
# Default pipeline-name is `reset` (bootstrap: download + quantize +
# seed stories). Change afterward by editing pipes/<name>/override.yaml
# or by using the UI's recipe selector.
#
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:-}"
MODEL="${2:-}"
PIPELINE="${3:-reset}"

if [ -z "$NAME" ] || [ -z "$MODEL" ]; then
  echo "Usage: npm run pipe:new <name> <hf-model> [pipeline-name]"
  echo "       npm run pipe:new my_pipe Qwen/Qwen3-4B-Instruct-2507"
  echo "       npm run pipe:new my_pipe huihui-ai/Huihui-Qwen3-4B-Instruct-2507-abliterated reset"
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

mkdir -p "$PIPE_DIR"/{state,logs,data,out,override}

cat > "$PIPE_DIR/override.yaml" <<EOF
# pipes/$NAME/override.yaml — created by bin/pipe-new.sh
# Pipeline selector + model identity. See GPT/model_identity.md.
pipeline: $PIPELINE

run:
  model: $MODEL
EOF

# Recipe-scoped override stub — pipeline: only, NO run.model. Removes
# the readOverride lazy-materialize race when the UI restarts on this
# pipe. See ui_server.coffee handleCreatePipe for full rationale.
cat > "$PIPE_DIR/override/$PIPELINE.yaml" <<EOF
pipeline: $PIPELINE
EOF

cat > "$PIPE_DIR/README.md" <<EOF
# $NAME

Created by \`bin/pipe-new.sh\` on $(date -u +%Y-%m-%dT%H:%M:%SZ).

- **Base model**: \`$MODEL\`
- **Starting recipe**: \`$PIPELINE\`

Launch: \`cd $PIPE_DIR && npx pipeline\`, or select this pipe from the UI's
"Switch UI To Pipe" dropdown and press "Write Override And Run".
EOF

echo "Created $PIPE_DIR/"
echo "  override.yaml — pipeline: $PIPELINE, run.model: $MODEL"
echo "  state/ logs/ data/ out/ README.md"
echo
echo "Run it: cd $PIPE_DIR && npx pipeline"
