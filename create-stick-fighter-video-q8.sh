#!/usr/bin/env bash
# Render the MiniMax-H3 FL2VA pruned Q8_0 stick-fighter test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_ASSET_DIR="${MMH3_RENDER_ASSET_DIR:-${HOME}/models/minimax-h3-render-q8}" \
  MMH3_RENDER_WIDTH="${MMH3_RENDER_WIDTH:-864}" \
  MMH3_RENDER_HEIGHT="${MMH3_RENDER_HEIGHT:-480}" \
  MMH3_RENDER_STEPS="${MMH3_RENDER_STEPS:-20}" \
  MMH3_RENDER_SEGMENT_SECONDS="${MMH3_RENDER_SEGMENT_SECONDS:-5}" \
  MMH3_RENDER_TOTAL_SECONDS="${MMH3_RENDER_TOTAL_SECONDS:-5}" \
  MMH3_RENDER_SEGMENTS="${MMH3_RENDER_SEGMENTS:-1}" \
  exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant fl2va-q8 "$@"
