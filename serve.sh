#!/usr/bin/env bash
# ===================================================================
# serve.sh -- start MiniMax-H3 (GGUF, llama.cpp server) manually
#
# Usage:
#   bash serve.sh                    # start the default target (dev-rtx4070)
#   TARGET=dev-rtx4070 bash serve.sh # explicit target selection
#   MMH3_CHECK_ONLY=1 bash serve.sh  # pre-flight check only, don't start
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=targets/lib.sh
source "${SCRIPT_DIR}/targets/lib.sh"

TARGET="${TARGET:-dev-rtx4070}"
load_target_env "$TARGET"

LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-${SCRIPT_DIR}/.llama.cpp/build/bin/llama-server}"
MODEL_PATH="${MMH3_MODEL_PATH:-${HOME}/models/minimax-h3-gguf/${MMH3_GGUF_FILE}}"

PORT="${MMH3_PORT:-8188}"
HOST="${MMH3_HOST:-0.0.0.0}"
GPU_LAYERS="${MMH3_GPU_LAYERS:--1}"
CTX_SIZE="${MMH3_CTX_SIZE:-8192}"
PARALLEL="${MMH3_PARALLEL:-1}"
BATCH_SIZE="${MMH3_BATCH_SIZE:-512}"
UBATCH_SIZE="${MMH3_UBATCH_SIZE:-128}"
PID_FILE="/tmp/minimax-h3-${PORT}.pid"

is_running() {
  local pid
  pid=$(cat -- "$PID_FILE" 2>/dev/null) || return 1
  kill -0 "$pid" 2>/dev/null
}

# ---- pre-flight checks --------------------------------------------
if ! command -v nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi not found — no GPU visible." >&2
  exit 1
fi

nvidia-smi -L &>/dev/null || {
  echo "ERROR: nvidia-smi failed (no driver?)" >&2
  exit 1
}

if [ ! -x "$LLAMA_SERVER_BIN" ]; then
  echo "ERROR: llama-server binary not found at ${LLAMA_SERVER_BIN}." >&2
  echo "Run 'bash install.sh' first, or set LLAMA_SERVER_BIN." >&2
  exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
  echo "ERROR: Model file not found at ${MODEL_PATH}." >&2
  echo "Download it with: python3 download_model.py ${MMH3_HF_REPO} ${MMH3_GGUF_FILE} --local-dir $(dirname "$MODEL_PATH")" >&2
  exit 1
fi

if [ -n "${MMH3_CHECK_ONLY:-}" ]; then
  echo "Pre-flight checks passed."
  exit 0
fi

# ---- stop any previous instance -----------------------------------
if is_running; then
  echo "MiniMax-H3 already running on port ${PORT} (pid=$(cat "$PID_FILE"))." >&2
  read -rp "Kill existing instance? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    old_pid=$(cat "$PID_FILE")
    echo "Stopping pid ${old_pid} ..."
    kill "$old_pid" 2>/dev/null || true
    sleep 2
    kill -9 "$old_pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    sleep 1
    echo "Existing instance stopped."
  else
    echo "Aborted." >&2
    exit 0
  fi
elif [ -f "$PID_FILE" ]; then
  rm -f "$PID_FILE"   # stale pid file
fi

# ---- launch -------------------------------------------------------
echo "Starting MiniMax-H3 (${MMH3_GGUF_FILE}) on ${HOST}:${PORT} [target=${TARGET}] ..."

nohup "$LLAMA_SERVER_BIN" \
  --model "$MODEL_PATH" \
  --host "$HOST" \
  --port "$PORT" \
  --n-gpu-layers "$GPU_LAYERS" \
  --ctx-size "$CTX_SIZE" \
  --parallel "$PARALLEL" \
  --batch-size "$BATCH_SIZE" \
  --ubatch-size "$UBATCH_SIZE" \
  --alias "MiniMax-H3" \
  2>&1 &> /tmp/minimax-h3-serve.log &

MMH3_PID=$!
echo "$MMH3_PID" > "$PID_FILE"
echo "MiniMax-H3 started (pid ${MMH3_PID}). Waiting for health check ..."

# wait for /health to return 200
for i in $(seq 1 180); do
  if curl -sf "http://127.0.0.1:${PORT}/health" &>/dev/null; then
    echo "MiniMax-H3 is healthy on http://0.0.0.0:${PORT}"
    echo ""
    echo "  vRAM:"
    nvidia-smi --query-gpu=index,memory.used,memory.total \
      --format=csv,noheader,nounits 2>/dev/null | \
      while IFS=',' read -r idx used total; do
        echo "    GPU${idx}: ${used} / ${total} GB"
      done
    exit 0
  fi
  if ! kill -0 "$MMH3_PID" 2>/dev/null; then
    echo "ERROR: MiniMax-H3 process died. Check /tmp/minimax-h3-serve.log" >&2
    exit 1
  fi
  sleep 1
done

echo "ERROR: health check timed out after 180s." >&2
echo "Check logs: /tmp/minimax-h3-serve.log" >&2
exit 1
