#!/usr/bin/env bash
# Render a distinct fight beat using the approved FL2VA Q8 quality settings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/fl2va-q8-gold-round-two}" \
  MMH3_RENDER_AUDIO_FILTER="${MMH3_RENDER_AUDIO_FILTER:-loudnorm=I=-8:TP=-1.5:LRA=11}" \
  MMH3_RENDER_MIN_AUDIO_MEAN_DB="${MMH3_RENDER_MIN_AUDIO_MEAN_DB:--15}" \
  MMH3_RENDER_PROMPT="${MMH3_RENDER_PROMPT:-Two adult human martial artists in a cinematic green digital simulation dojo. The black-coated fighter smoothly dodges a spinning high kick from the suited fighter, pivots low, and lands a controlled palm strike that sends a burst of green sparks across the polished black reflective floor. Both have clear human faces, hands, arms, and legs, with athletic realistic anatomy. The black-coated fighter wears a long black coat, black shirt, and combat boots; the other wears a dark tailored suit, sunglasses, and a flowing long coat. Include glowing green code columns, dark stone pillars, hanging cables, two computer consoles, scattered broken chairs, drifting paper, and sparks. Wide side-view camera, dramatic rim lighting, crisp detailed fabric, realistic motion, high-detail cinematic action. Loud tense electronic industrial score with pulsing bass, rhythmic percussion, rising synthesizers, punch impact, whoosh, footsteps, chair rattle, and paper flutter. No dialogue, no text, no subtitles, no watermark.}" \
  exec bash "${SCRIPT_DIR}/create-detailed-matrix-fight-video-q8.sh" "$@"
