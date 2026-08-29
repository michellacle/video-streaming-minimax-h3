#!/usr/bin/env bash
# ===================================================================
# uninstall.sh -- remove the MiniMax-H3 systemd service
#
# Usage:
#   sudo bash uninstall.sh                 # remove the default target
#   TARGET=dev-rtx4070 sudo bash uninstall.sh
# ===================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run with sudo: sudo bash uninstall.sh" >&2
  exit 1
fi

TARGET="${TARGET:-dev-rtx4070}"
BASE_NAME="video-streaming-minimax-h3-${TARGET}"
UNIT_PATH="/etc/systemd/system/${BASE_NAME}.service"
ENV_PATH="/etc/${BASE_NAME}.env"

echo "=== Uninstalling ${BASE_NAME} ==="

if systemctl list-unit-files | grep -q "${BASE_NAME}"; then
  echo "  Stopping ..."
  systemctl stop "${BASE_NAME}.service" 2>/dev/null || true
  echo "  Disabling ..."
  systemctl disable "${BASE_NAME}.service" 2>/dev/null || true
fi

echo "  Removing unit file: $UNIT_PATH"
rm -f "$UNIT_PATH"

echo "  Removing environment file: $ENV_PATH"
rm -f "$ENV_PATH"

echo "  Removing log directory: /var/log/${BASE_NAME}"
rm -rf "/var/log/${BASE_NAME}"

rm -f "/run/${BASE_NAME}.pid"

systemctl daemon-reload
systemctl reset-failed

echo ""
echo "Done. Repo files (and the downloaded model) are untouched."
echo "To reinstall: sudo bash install.sh"
