#!/usr/bin/env bash
# Render the next Q8 quality-test scene at 1024x576.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_ASSET_DIR="${MMH3_RENDER_ASSET_DIR:-${HOME}/models/minimax-h3-render-q8}" \
  MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/fl2va-q8-1024x576}" \
  MMH3_RENDER_WIDTH="${MMH3_RENDER_WIDTH:-1024}" \
  MMH3_RENDER_HEIGHT="${MMH3_RENDER_HEIGHT:-576}" \
  MMH3_RENDER_STEPS="${MMH3_RENDER_STEPS:-20}" \
  MMH3_RENDER_SEGMENT_SECONDS="${MMH3_RENDER_SEGMENT_SECONDS:-5}" \
  MMH3_RENDER_TOTAL_SECONDS="${MMH3_RENDER_TOTAL_SECONDS:-5}" \
  MMH3_RENDER_SEGMENTS="${MMH3_RENDER_SEGMENTS:-1}" \
  exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant fl2va-q8 "$@"
