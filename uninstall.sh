#!/usr/bin/env bash
# ===================================================================
# uninstall.sh -- remove the MiniMax-H3 systemd service
#
# Usage:
#   bash uninstall.sh                      # remove the current user's service
#   sudo bash uninstall.sh                 # remove the system-wide service
#   TARGET=dev-rtx4070 bash uninstall.sh --user-install
# ===================================================================
set -euo pipefail

TARGET="${TARGET:-dev-rtx4070}"
BASE_NAME="video-streaming-minimax-h3-${TARGET}"
INSTALL_MODE="auto"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user-install) INSTALL_MODE="user"; shift ;;
    --system)       INSTALL_MODE="system"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ "$INSTALL_MODE" = "auto" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    INSTALL_MODE="system"
  else
    INSTALL_MODE="user"
  fi
fi

run_systemctl() {
  if [ "$INSTALL_MODE" = "user" ]; then
    systemctl --user "$@"
  else
    systemctl "$@"
  fi
}

if [ "$INSTALL_MODE" = "system" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: System uninstall requires sudo. Re-run with sudo, or use --user-install." >&2
    exit 1
  fi
  UNIT_PATH="/etc/systemd/system/${BASE_NAME}.service"
  ENV_PATH="/etc/${BASE_NAME}.env"
  LOG_DIR="/var/log/${BASE_NAME}"
else
  if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Run --user-install without sudo as the target user." >&2
    exit 1
  fi
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
  XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
  UNIT_PATH="${XDG_CONFIG_HOME}/systemd/user/${BASE_NAME}.service"
  ENV_PATH="${XDG_CONFIG_HOME}/${BASE_NAME}.env"
  LOG_DIR="${XDG_STATE_HOME}/${BASE_NAME}"
fi

echo "=== Uninstalling ${BASE_NAME} ==="

if run_systemctl list-unit-files | grep -q "${BASE_NAME}"; then
  echo "  Stopping ..."
  run_systemctl stop "${BASE_NAME}.service" 2>/dev/null || true
  echo "  Disabling ..."
  run_systemctl disable "${BASE_NAME}.service" 2>/dev/null || true
fi

echo "  Removing unit file: $UNIT_PATH"
rm -f "$UNIT_PATH"

echo "  Removing environment file: $ENV_PATH"
rm -f "$ENV_PATH"

echo "  Removing log directory: $LOG_DIR"
rm -rf "$LOG_DIR"

run_systemctl daemon-reload
run_systemctl reset-failed

echo ""
echo "Done. Repo files (and the downloaded model) are untouched."
if [ "$INSTALL_MODE" = "user" ]; then
  echo "To reinstall: bash install.sh"
else
  echo "To reinstall: sudo bash install.sh"
fi
