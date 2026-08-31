#!/usr/bin/env bash
# Render a Q8 Ref2VA scene using two generated character-reference crops.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFERENCE_DIR="${SCRIPT_DIR}/assets/reference-images"
MMH3_RENDER_ASSET_DIR="${MMH3_RENDER_ASSET_DIR:-${HOME}/models/minimax-h3-render-q8}" \
  MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/ref2va-q8-detailed}" \
  MMH3_RENDER_WIDTH="${MMH3_RENDER_WIDTH:-1024}" \
  MMH3_RENDER_HEIGHT="${MMH3_RENDER_HEIGHT:-576}" \
  MMH3_RENDER_STEPS="${MMH3_RENDER_STEPS:-20}" \
  MMH3_RENDER_SEGMENT_SECONDS="${MMH3_RENDER_SEGMENT_SECONDS:-5}" \
  MMH3_RENDER_TOTAL_SECONDS="${MMH3_RENDER_TOTAL_SECONDS:-5}" \
  MMH3_RENDER_SEGMENTS="${MMH3_RENDER_SEGMENTS:-1}" \
  MMH3_RENDER_PROMPT="${MMH3_RENDER_PROMPT:-Use the man in <Picture 1> as the black-coated fighter and the man in <Picture 2> as the suited fighter. Preserve their distinct faces, hair, clothing, body proportions, and identities. Create a cinematic martial-arts fight in the same green digital simulation dojo: a punch is blocked, then the suited fighter throws a high kick. Include a polished black reflective floor, glowing green code columns, dark stone pillars, hanging cables, two computer consoles, scattered broken chairs, drifting paper, and sparks. Wide side-view camera, dramatic rim lighting, crisp detailed fabric, realistic motion, high-detail cinematic action, no text, no subtitles, no watermark.}" \
  exec bash "${SCRIPT_DIR}/render-quant-tests.sh" \
    --quant ref2va-q8 \
    --ref-image "${REFERENCE_DIR}/black-coated-fighter.png" \
    --ref-image "${REFERENCE_DIR}/suited-fighter.png" \
    "$@"
