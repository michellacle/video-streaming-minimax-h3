#!/usr/bin/env bash
# ===================================================================
# restart.sh -- restart the systemd service and show status
#
# Usage:
#   sudo bash restart.sh                  # restart the default target
#   TARGET=dev-rtx4070 sudo bash restart.sh
# ===================================================================
set -euo pipefail

TARGET="${TARGET:-dev-rtx4070}"
BASE_NAME="video-streaming-minimax-h3-${TARGET}"

echo "Restarting ${BASE_NAME} ..."
sudo systemctl restart "${BASE_NAME}"
sleep 2
sudo systemctl status "${BASE_NAME}" --no-pager
