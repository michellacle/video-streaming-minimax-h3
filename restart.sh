#!/usr/bin/env bash
# ===================================================================
# restart.sh -- restart the systemd service and show status
#
# Usage:
#   bash restart.sh                       # restart the current user's service
#   sudo bash restart.sh                  # restart the system-wide service
#   TARGET=dev-rtx4070 bash restart.sh --user-install
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

if [ "$INSTALL_MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: System restart requires sudo. Re-run with sudo, or use --user-install." >&2
  exit 1
fi

if [ "$INSTALL_MODE" = "user" ] && [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: Run --user-install without sudo as the target user." >&2
  exit 1
fi

echo "Restarting ${BASE_NAME} ..."
run_systemctl restart "${BASE_NAME}"
sleep 2
run_systemctl status "${BASE_NAME}" --no-pager
