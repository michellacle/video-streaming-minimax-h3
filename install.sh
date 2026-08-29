#!/usr/bin/env bash
# ===================================================================
# install.sh -- install the MiniMax-H3 dev/test server as a systemd
#               service (target: dev-rtx4070, 1x RTX 4070, 8 GB VRAM)
#
# Builds llama.cpp (CUDA), downloads the Q2_K GGUF quant, and installs
# a systemd service that serves it with an OpenAI-compatible API.
#
# Usage:
#   bash install.sh [OPTIONS]       # install as the current user's systemd service
#   sudo bash install.sh [OPTIONS]  # install system-wide
#
# Options:
#   --target NAME      Deployment target (default: dev-rtx4070)
#   --model PATH       GGUF file path (default: ~/models/minimax-h3-gguf/<file>)
#   --hf-repo REPO     Hugging Face repo (default: from target config)
#   --gguf-file NAME   GGUF filename (default: from target config)
#   --port NUM         HTTP port (default: from target config)
#   --user NAME        System user to run as (system installs only)
#   --user-install     Install as the current user's systemd service
#   --system           Install as a system-wide service (requires sudo)
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
INSTALL_MODE="auto"

run_systemctl() {
  if [ "$INSTALL_MODE" = "user" ]; then
    systemctl --user "$@"
  else
    systemctl "$@"
  fi
}

# ---- parse args ---------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)        TARGET="$2";            shift 2 ;;
    --model)         CUSTOM_MODEL_PATH="$2"; shift 2 ;;
    --hf-repo)       CUSTOM_HF_REPO="$2";    shift 2 ;;
    --gguf-file)     CUSTOM_GGUF_FILE="$2";  shift 2 ;;
    --port)          CUSTOM_PORT="$2";       shift 2 ;;
    --user)          RUN_USER="$2";          shift 2 ;;
    --user-install)  INSTALL_MODE="user";    shift ;;
    --system)        INSTALL_MODE="system";  shift ;;
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

# ---- determine install mode / user --------------------------------
if [ "$INSTALL_MODE" = "auto" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    INSTALL_MODE="system"
  else
    INSTALL_MODE="user"
  fi
fi

if [ "$INSTALL_MODE" = "system" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: System install requires sudo. Re-run with sudo, or omit --system for a user install." >&2
    exit 1
  fi

  if [ -z "$RUN_USER" ]; then
    RUN_USER="${SUDO_USER:-$(find /home -maxdepth 1 -mindepth 1 -printf '%f\n' | head -1)}"
  fi

  RUN_HOME=$(eval echo "~${RUN_USER}")
  UNIT_PATH="/etc/systemd/system/${BASE_NAME}.service"
  ENV_PATH="/etc/${BASE_NAME}.env"
  LOG_DIR="/var/log/${BASE_NAME}"
  WANTED_BY_TARGET="multi-user.target"
  STATUS_CMD="systemctl status ${BASE_NAME}"
  LOGS_CMD="journalctl -u ${BASE_NAME} -f"
  RESTART_CMD="sudo bash ${SCRIPT_DIR}/restart.sh"
  UNINSTALL_CMD="sudo bash ${SCRIPT_DIR}/uninstall.sh"
else
  if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Run --user-install without sudo as the target user." >&2
    exit 1
  fi

  if [ -n "$RUN_USER" ] && [ "$RUN_USER" != "$(id -un)" ]; then
    echo "ERROR: --user-install only supports the current user ($(id -un))." >&2
    exit 1
  fi

  RUN_USER="$(id -un)"
  RUN_HOME="$HOME"
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${RUN_HOME}/.config}"
  XDG_STATE_HOME="${XDG_STATE_HOME:-${RUN_HOME}/.local/state}"
  UNIT_PATH="${XDG_CONFIG_HOME}/systemd/user/${BASE_NAME}.service"
  ENV_PATH="${XDG_CONFIG_HOME}/${BASE_NAME}.env"
  LOG_DIR="${XDG_STATE_HOME}/${BASE_NAME}"
  WANTED_BY_TARGET="default.target"
  STATUS_CMD="systemctl --user status ${BASE_NAME}"
  LOGS_CMD="journalctl --user -u ${BASE_NAME} -f"
  RESTART_CMD="bash ${SCRIPT_DIR}/restart.sh --user-install"
  UNINSTALL_CMD="bash ${SCRIPT_DIR}/uninstall.sh --user-install"
fi

MODEL_DIR="${RUN_HOME}/models/minimax-h3-gguf"
MODEL_PATH="${CUSTOM_MODEL_PATH:-${MODEL_DIR}/${GGUF_FILE}}"

echo "=== MiniMax-H3 Video Streaming Server Installer (target: ${TARGET}, scope: ${INSTALL_MODE}) ==="
echo ""

# ---- detect GPU ---------------------------------------------------
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

if [ -x "$LLAMA_SERVER_BIN" ]; then
  BUILD_PLAN="reuse existing llama-server at ${LLAMA_SERVER_BIN}"
else
  BUILD_PLAN="build llama.cpp with CUDA support"
fi

if [ -f "$MODEL_PATH" ]; then
  DOWNLOAD_PLAN="reuse existing model at ${MODEL_PATH}"
elif [ "$SKIP_DOWNLOAD" -eq 1 ]; then
  echo "ERROR: Model not found at $MODEL_PATH and --skip-download is set." >&2
  exit 1
else
  DOWNLOAD_PLAN="download ${GGUF_FILE} from ${HF_REPO}"
fi

echo "=== Install Plan ==="
echo "  Scope:      ${INSTALL_MODE}"
echo "  Service:    ${BASE_NAME}.service"
echo "  Run user:   ${RUN_USER}"
echo "  Model repo: ${HF_REPO}"
echo "  GGUF file:  ${GGUF_FILE}"
echo "  Model path: ${MODEL_PATH}"
echo "  Port:       ${PORT}"
echo "  Build:      ${BUILD_PLAN}"
echo "  Download:   ${DOWNLOAD_PLAN}"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--- DRY RUN complete ---"
  exit 0
fi

# ---- build llama.cpp (CUDA) --------------------------------------
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

# ---- create venv for the downloader -------------------------------
if [ ! -f "${VENV_DIR}/bin/python3" ]; then
  echo ""
  echo "Creating virtual environment for download_model.py ..."
  python3 -m venv "${VENV_DIR}"
fi

if ! "${VENV_DIR}/bin/python3" -c "import huggingface_hub" >/dev/null 2>&1; then
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install huggingface_hub
fi

# ---- download model -----------------------------------------------
if [ ! -f "$MODEL_PATH" ]; then
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

if [ "$INSTALL_MODE" = "user" ] && ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "ERROR: systemd user services are not available in this session." >&2
  echo "Log into a normal user session and try again, or use sudo for a system install." >&2
  exit 1
fi

# ---- write config -------------------------------------------------
mkdir -p "$(dirname "$ENV_PATH")" "$(dirname "$UNIT_PATH")" "$LOG_DIR"
chown "${RUN_USER}:${RUN_USER}" "$LOG_DIR" 2>/dev/null || true

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
WorkingDirectory=${SCRIPT_DIR}
EnvironmentFile=${ENV_PATH}
ExecStart=${SCRIPT_DIR}/daemon.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
EOF

if [ "$INSTALL_MODE" = "system" ]; then
  cat >> "$UNIT_PATH" <<EOF
User=${RUN_USER}
Group=${RUN_USER}
LogsDirectory=${BASE_NAME}
PIDFile=/run/${BASE_NAME}.pid
EOF
fi

cat >> "$UNIT_PATH" <<EOF

[Install]
WantedBy=${WANTED_BY_TARGET}
EOF

echo ""
echo "Reloading systemd (${INSTALL_MODE}) ..."
run_systemctl daemon-reload

echo "Enabling ${BASE_NAME}.service ..."
run_systemctl enable "${BASE_NAME}.service"

echo ""
echo "Starting ${BASE_NAME} ..."
run_systemctl start "${BASE_NAME}.service"

echo ""
echo "Waiting for server to start (model loading can take a minute) ..."

for attempt in $(seq 1 180); do
  if curl -sf "http://127.0.0.1:${PORT}/health" &>/dev/null; then
    echo ""
    echo "=== Server is healthy on http://0.0.0.0:${PORT} ==="
    echo ""
    echo "  systemd:  ${STATUS_CMD}"
    echo "  logs:     ${LOGS_CMD}"
    echo "  restart:  ${RESTART_CMD}"
    echo "  test:     bash ${SCRIPT_DIR}/test.sh http://localhost:${PORT}"
    echo "  stop:     ${UNINSTALL_CMD}"
    if [ "$INSTALL_MODE" = "user" ]; then
      echo ""
      echo "  note:     run 'sudo loginctl enable-linger ${RUN_USER}' if you want the user service to survive logout/reboot without an active login session"
    fi
    echo ""
    echo "  vRAM:"
    nvidia-smi --query-gpu=index,memory.used,memory.total \
      --format=csv,noheader,nounits 2>/dev/null | \
      while IFS=',' read -r idx used total; do
        echo "    GPU${idx}: ${used} / ${total} GB"
      done
    exit 0
  fi

  if run_systemctl is-failed "${BASE_NAME}" &>/dev/null; then
    echo ""
    echo "ERROR: Service failed to start."
    echo "Check logs: ${LOGS_CMD}"
    exit 1
  fi

  sleep 2
done

echo ""
echo "WARNING: Server did not become healthy within 6 minutes."
echo "Check logs: ${LOGS_CMD}"
exit 1
