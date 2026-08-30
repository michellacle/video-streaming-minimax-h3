#!/usr/bin/env bash
# Render the MiniMax-H3 FL2VA pruned Q8_0 stick-fighter test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_ASSET_DIR="${MMH3_RENDER_ASSET_DIR:-${HOME}/models/minimax-h3-render-q8}" \
  exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant fl2va-q8 "$@"
