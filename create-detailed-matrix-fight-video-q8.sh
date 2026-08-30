#!/usr/bin/env bash
# Render a detailed human-fighter Q8 scene under the established quality conditions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_ASSET_DIR="${MMH3_RENDER_ASSET_DIR:-${HOME}/models/minimax-h3-render-q8}" \
  MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/fl2va-q8-detailed}" \
  MMH3_RENDER_WIDTH="${MMH3_RENDER_WIDTH:-1024}" \
  MMH3_RENDER_HEIGHT="${MMH3_RENDER_HEIGHT:-576}" \
  MMH3_RENDER_STEPS="${MMH3_RENDER_STEPS:-20}" \
  MMH3_RENDER_SEGMENT_SECONDS="${MMH3_RENDER_SEGMENT_SECONDS:-5}" \
  MMH3_RENDER_TOTAL_SECONDS="${MMH3_RENDER_TOTAL_SECONDS:-5}" \
  MMH3_RENDER_SEGMENTS="${MMH3_RENDER_SEGMENTS:-1}" \
  MMH3_RENDER_PROMPT="${MMH3_RENDER_PROMPT:-Two adult human martial artists fighting in a cinematic green digital simulation dojo. Fighter one wears a long black coat, black shirt, and combat boots; fighter two wears a dark tailored suit, sunglasses, and a flowing long coat. Clear human faces, hands, arms, and legs; athletic realistic anatomy; a choreographed punch, block, and high kick. The environment has a polished black reflective floor, glowing green code columns, dark stone pillars, hanging cables, two computer consoles, scattered broken chairs, drifting paper, and sparks. Wide side-view camera, dramatic rim lighting, crisp detailed fabric, realistic motion, high-detail cinematic action, no text, no subtitles, no watermark.}" \
  exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant fl2va-q8 "$@"
