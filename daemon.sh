#!/usr/bin/env bash
# ===================================================================
# daemon.sh -- run llama-server directly (no interactive prompts)
# Called by systemd. For manual use, run serve.sh instead.
#
# Environment variables (set via the target's .env file):
#   MMH3_MODEL_PATH   - path to the GGUF file (required)
#   MMH3_PORT         - HTTP port (default: 8188)
#   MMH3_HOST         - bind address (default: 0.0.0.0)
#   MMH3_GPU_LAYERS   - number of layers to offload to GPU (default: -1 = max)
#   MMH3_CTX_SIZE     - context window in tokens (default: 8192)
#   MMH3_PARALLEL     - concurrent request slots (default: 1)
#   MMH3_BATCH_SIZE   - prompt batch size (default: 512)
#   MMH3_UBATCH_SIZE  - micro-batch size (default: 128)
#   LLAMA_SERVER_BIN  - path to llama-server binary
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-${SCRIPT_DIR}/.llama.cpp/build/bin/llama-server}"
MODEL_PATH="${MMH3_MODEL_PATH:?MMH3_MODEL_PATH must be set}"

exec "$LLAMA_SERVER_BIN" \
  --model "$MODEL_PATH" \
  --host "${MMH3_HOST:-0.0.0.0}" \
  --port "${MMH3_PORT:-8188}" \
  --n-gpu-layers "${MMH3_GPU_LAYERS:--1}" \
  --ctx-size "${MMH3_CTX_SIZE:-8192}" \
  --parallel "${MMH3_PARALLEL:-1}" \
  --batch-size "${MMH3_BATCH_SIZE:-512}" \
  --ubatch-size "${MMH3_UBATCH_SIZE:-128}" \
  --alias "MiniMax-H3"
