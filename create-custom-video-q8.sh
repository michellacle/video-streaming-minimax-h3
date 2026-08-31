#!/usr/bin/env bash
# Render a custom FL2VA Q8 scene. Supply MMH3_RENDER_PROMPT and optional quality overrides.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -n "${MMH3_RENDER_PROMPT:-}" ] || {
  echo "ERROR: Set MMH3_RENDER_PROMPT to describe the scene to render." >&2
  exit 1
}

MMH3_RENDER_ASSET_DIR="${MMH3_RENDER_ASSET_DIR:-${HOME}/models/minimax-h3-render-q8}" \
  MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/fl2va-q8-custom}" \
  MMH3_RENDER_WIDTH="${MMH3_RENDER_WIDTH:-1024}" \
  MMH3_RENDER_HEIGHT="${MMH3_RENDER_HEIGHT:-576}" \
  MMH3_RENDER_STEPS="${MMH3_RENDER_STEPS:-20}" \
  MMH3_RENDER_SEGMENT_SECONDS="${MMH3_RENDER_SEGMENT_SECONDS:-5}" \
  MMH3_RENDER_TOTAL_SECONDS="${MMH3_RENDER_TOTAL_SECONDS:-5}" \
  MMH3_RENDER_SEGMENTS="${MMH3_RENDER_SEGMENTS:-1}" \
  MMH3_RENDER_AUDIO_FILTER="${MMH3_RENDER_AUDIO_FILTER:-loudnorm=I=-8:TP=-1.5:LRA=11}" \
  MMH3_RENDER_MIN_AUDIO_MEAN_DB="${MMH3_RENDER_MIN_AUDIO_MEAN_DB:--15}" \
  exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant fl2va-q8 "$@"
