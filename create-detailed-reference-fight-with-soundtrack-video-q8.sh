#!/usr/bin/env bash
# Render a character-locked Ref2VA Q8 scene with explicit soundtrack direction.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/ref2va-q8-detailed-soundtrack}" \
  MMH3_RENDER_PROMPT="${MMH3_RENDER_PROMPT:-Use the man in <Picture 1> as the black-coated fighter and the man in <Picture 2> as the suited fighter. Preserve their distinct faces, hair, clothing, body proportions, and identities. Create a cinematic martial-arts fight in the same green digital simulation dojo: a punch is blocked, then the suited fighter throws a high kick. Include a polished black reflective floor, glowing green code columns, dark stone pillars, hanging cables, two computer consoles, scattered broken chairs, drifting paper, and sparks. Wide side-view camera, dramatic rim lighting, crisp detailed fabric, realistic motion, high-detail cinematic action. Soundtrack: loud tense electronic industrial score with a pulsing bassline, rhythmic taiko-style percussion, rising synthesizers, and the low hum of the digital room. Synchronize clear punch impacts, cloth movement, whooshes, hard footsteps on the tile, chair rattles, and paper flutter with the fight. No dialogue, no text, no subtitles, no watermark.}" \
  exec bash "${SCRIPT_DIR}/create-detailed-reference-fight-video-q8.sh" "$@"
