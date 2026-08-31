#!/usr/bin/env bash
# Preserve the detailed FL2VA visual baseline while normalizing only final audio.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/fl2va-q8-detailed-normalized-audio}" \
  MMH3_RENDER_AUDIO_FILTER="${MMH3_RENDER_AUDIO_FILTER:-loudnorm=I=-8:TP=-1.5:LRA=11}" \
  MMH3_RENDER_MIN_AUDIO_MEAN_DB="${MMH3_RENDER_MIN_AUDIO_MEAN_DB:--15}" \
  exec bash "${SCRIPT_DIR}/create-detailed-matrix-fight-video-q8.sh" "$@"
