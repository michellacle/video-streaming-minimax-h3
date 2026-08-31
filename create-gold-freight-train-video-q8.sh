#!/usr/bin/env bash
# Render a five-second freight-train scene using the approved FL2VA Q8 settings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3/fl2va-q8-gold-freight-train}" \
  MMH3_RENDER_AUDIO_FILTER="${MMH3_RENDER_AUDIO_FILTER:-loudnorm=I=-8:TP=-1.5:LRA=11}" \
  MMH3_RENDER_MIN_AUDIO_MEAN_DB="${MMH3_RENDER_MIN_AUDIO_MEAN_DB:--15}" \
  MMH3_RENDER_PROMPT="${MMH3_RENDER_PROMPT:-A long modern North American freight train led by three powerful diesel-electric locomotives runs steadily along a curving mountain railway through a vast majestic evergreen forest. Low tracking side-view camera follows the locomotives as they round a rocky hillside above a clear river valley. Towering pine and fir trees, granite mountain peaks, a wooden trestle bridge in the distance, morning mist, warm golden sunlight, realistic locomotive details, crisp steel rails, naturally moving train cars, cinematic landscape photography, high-detail realistic motion. Soundtrack: expansive cinematic orchestral score with deep strings and gentle percussion, synchronized diesel engine rumble, steel wheel rhythm on rails, locomotive horn far in the valley, wind through forest trees, and distant birds. No people, no dialogue, no text, no subtitles, no watermark.}" \
  exec bash "${SCRIPT_DIR}/create-detailed-matrix-fight-video-q8.sh" "$@"
