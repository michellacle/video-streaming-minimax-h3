#!/usr/bin/env bash
# ===================================================================
# install.sh -- install the MiniMax-H3 dev/test server as a systemd
#               service (target: dev-rtx4070, 1x RTX 4070, 8 GB VRAM)
#
# Builds llama.cpp (CUDA), downloads the Q2_K GGUF quant, and installs
# a systemd service that serves it with an OpenAI-compatible API.
#
# Usage: sudo bash install.sh [OPTIONS]
#
# Options:
#   --target NAME      Deployment target (default: dev-rtx4070)
#   --model PATH       GGUF file path (default: ~/models/minimax-h3-gguf/<file>)
#   --hf-repo REPO     Hugging Face repo (default: from target config)
#   --gguf-file NAME   GGUF filename (default: from target config)
#   --port NUM         HTTP port (default: from target config)
#   --user NAME        System user to run as (default: current sudo user)
#   --skip-download    Skip model download (must already exist)
#   --dry-run          Show what would be done without making changes
#
# Hugging Face token (only needed if the repo/file requires one):
#   Set HF_TOKEN environment variable, or the script will prompt you.
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=targets/lib.sh
source "${SCRIPT_DIR}/targets/lib.sh"

TARGET="dev-rtx4070"
RUN_USER=""
DRY_RUN=0
SKIP_DOWNLOAD=0
CUSTOM_PORT=""
CUSTOM_HF_REPO=""
CUSTOM_GGUF_FILE=""
CUSTOM_MODEL_PATH=""

# ---- parse args ---------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)        TARGET="$2";           shift 2 ;;
    --model)         CUSTOM_MODEL_PATH="$2"; shift 2 ;;
    --hf-repo)       CUSTOM_HF_REPO="$2";    shift 2 ;;
    --gguf-file)     CUSTOM_GGUF_FILE="$2";  shift 2 ;;
    --port)          CUSTOM_PORT="$2";       shift 2 ;;
    --user)          RUN_USER="$2";          shift 2 ;;
    --skip-download) SKIP_DOWNLOAD=1;        shift ;;
    --dry-run)       DRY_RUN=1;              shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

load_target_env "$TARGET"

HF_REPO="${CUSTOM_HF_REPO:-${MMH3_HF_REPO}}"
GGUF_FILE="${CUSTOM_GGUF_FILE:-${MMH3_GGUF_FILE}}"
PORT="${CUSTOM_PORT:-${MMH3_PORT:-8188}}"
BASE_NAME="video-streaming-minimax-h3-${TARGET}"
VENV_DIR="${SCRIPT_DIR}/.venv"
LLAMA_CPP_DIR="${SCRIPT_DIR}/.llama.cpp"
LLAMA_SERVER_BIN="${LLAMA_CPP_DIR}/build/bin/llama-server"

# ---- determine user -----------------------------------------------
if [ -z "$RUN_USER" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    RUN_USER="${SUDO_USER:-$(find /home -maxdepth 1 -mindepth 1 -printf '%f\n' | head -1)}"
  else
    echo "ERROR: Run with sudo: sudo bash install.sh" >&2
    exit 1
  fi
fi

RUN_HOME=$(eval echo "~${RUN_USER}")
MODEL_DIR="${RUN_HOME}/models/minimax-h3-gguf"
MODEL_PATH="${CUSTOM_MODEL_PATH:-${MODEL_DIR}/${GGUF_FILE}}"

echo "=== MiniMax-H3 Video Streaming Server Installer (target: ${TARGET}) ==="
echo ""

# ---- detect GPU -----------------------------------------------------
if ! command -v nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi not found. Are NVIDIA drivers installed?" >&2
  exit 1
fi

TOTAL_GPUS=$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | sed 's/^ *//' | wc -l)
echo "Detected $TOTAL_GPUS GPU(s):"
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null | \
  while IFS=',' read -r idx name mem; do
    printf "  GPU %s: %s (%s)\n" "$(echo "$idx" | xargs)" "$(echo "$name" | xargs)" "$(echo "$mem" | xargs)"
  done
echo ""

UNIT_PATH="/etc/systemd/system/${BASE_NAME}.service"
ENV_PATH="/etc/${BASE_NAME}.env"

echo "=== Install Plan ==="
echo "  Service:    ${BASE_NAME}.service"
echo "  Model repo: ${HF_REPO}"
echo "  GGUF file:  ${GGUF_FILE}"
echo "  Model path: ${MODEL_PATH}"
echo "  Port:       ${PORT}"
echo ""

# ---- build llama.cpp (CUDA) ----------------------------------------
if [ ! -x "$LLAMA_SERVER_BIN" ]; then
  echo "llama-server not found. Building llama.cpp with CUDA support ..."
  if [ ! -d "$LLAMA_CPP_DIR" ]; then
    git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_CPP_DIR"
  fi
  cmake -S "$LLAMA_CPP_DIR" -B "${LLAMA_CPP_DIR}/build" -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
  cmake --build "${LLAMA_CPP_DIR}/build" --config Release -j "$(nproc)" --target llama-server
  echo "llama-server built at ${LLAMA_SERVER_BIN}"
else
  echo "llama-server: already built at ${LLAMA_SERVER_BIN}"
fi

# ---- create venv for the downloader ---------------------------------
if [ ! -f "${VENV_DIR}/bin/python3" ]; then
  echo ""
  echo "Creating virtual environment for download_model.py ..."
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install huggingface_hub
fi

# ---- download model -----------------------------------------------
if [ ! -f "$MODEL_PATH" ]; then
  if [ "$SKIP_DOWNLOAD" -eq 1 ]; then
    echo "ERROR: Model not found at $MODEL_PATH and --skip-download is set." >&2
    exit 1
  fi

  echo ""
  echo "Model not found at $MODEL_PATH"
  echo "Downloading ${GGUF_FILE} from Hugging Face: ${HF_REPO}"
  echo ""

  HF_TOKEN="${HF_TOKEN:-}"
  DOWNLOAD_ARGS=("$HF_REPO" "$GGUF_FILE" --local-dir "$(dirname "$MODEL_PATH")")
  if [ -n "$HF_TOKEN" ]; then
    DOWNLOAD_ARGS+=(--token "$HF_TOKEN")
  fi

  "${VENV_DIR}/bin/python3" "${SCRIPT_DIR}/download_model.py" "${DOWNLOAD_ARGS[@]}"

  chown -R "${RUN_USER}:${RUN_USER}" "$(dirname "$MODEL_PATH")" 2>/dev/null || true
  echo ""
  echo "Model downloaded successfully."
else
  echo "Model: $MODEL_PATH (already exists)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "--- DRY RUN complete ---"
  exit 0
fi

# ---- write config ---------------------------------------------------
mkdir -p "/var/log/${BASE_NAME}"
chown "${RUN_USER}:${RUN_USER}" "/var/log/${BASE_NAME}" 2>/dev/null || true

echo ""
echo "Writing $ENV_PATH ..."
cat > "$ENV_PATH" <<EOF
MMH3_HF_REPO=${HF_REPO}
MMH3_GGUF_FILE=${GGUF_FILE}
MMH3_MODEL_PATH=${MODEL_PATH}
MMH3_PORT=${PORT}
MMH3_HOST=${MMH3_HOST:-0.0.0.0}
MMH3_GPU_LAYERS=${MMH3_GPU_LAYERS:--1}
MMH3_CTX_SIZE=${MMH3_CTX_SIZE:-8192}
MMH3_PARALLEL=${MMH3_PARALLEL:-1}
MMH3_BATCH_SIZE=${MMH3_BATCH_SIZE:-512}
MMH3_UBATCH_SIZE=${MMH3_UBATCH_SIZE:-128}
LLAMA_SERVER_BIN=${LLAMA_SERVER_BIN}
EOF
chmod 640 "$ENV_PATH"

echo "Writing $UNIT_PATH ..."
cat > "$UNIT_PATH" <<EOF
[Unit]
Description=MiniMax-H3 Video Streaming Server (${TARGET})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${SCRIPT_DIR}
EnvironmentFile=${ENV_PATH}
ExecStart=${SCRIPT_DIR}/daemon.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
LogsDirectory=${BASE_NAME}
PIDFile=/run/${BASE_NAME}.pid

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "Reloading systemd ..."
systemctl daemon-reload

echo "Enabling ${BASE_NAME}.service ..."
systemctl enable "${BASE_NAME}.service"

echo ""
echo "Starting ${BASE_NAME} ..."
systemctl start "${BASE_NAME}.service"

echo ""
echo "Waiting for server to start (model loading can take a minute) ..."

for attempt in $(seq 1 180); do
  if curl -sf "http://127.0.0.1:${PORT}/health" &>/dev/null; then
    echo ""
    echo "=== Server is healthy on http://0.0.0.0:${PORT} ==="
    echo ""
    echo "  systemd:  systemctl status ${BASE_NAME}"
    echo "  logs:     journalctl -u ${BASE_NAME} -f"
    echo "  restart:  sudo bash ${SCRIPT_DIR}/restart.sh"
    echo "  test:     bash ${SCRIPT_DIR}/test.sh http://localhost:${PORT}"
    echo "  stop:     sudo bash ${SCRIPT_DIR}/uninstall.sh"
    echo ""
    echo "  vRAM:"
    nvidia-smi --query-gpu=index,memory.used,memory.total \
      --format=csv,noheader,nounits 2>/dev/null | \
      while IFS=',' read -r idx used total; do
        echo "    GPU${idx}: ${used} / ${total} GB"
      done
    exit 0
  fi

  if systemctl is-failed "${BASE_NAME}" &>/dev/null; then
    echo ""
    echo "ERROR: Service failed to start."
    echo "Check logs: journalctl -u ${BASE_NAME} -f"
    exit 1
  fi

  sleep 2
done

echo ""
echo "WARNING: Server did not become healthy within 6 minutes."
echo "Check logs: journalctl -u ${BASE_NAME} -f"
exit 1
