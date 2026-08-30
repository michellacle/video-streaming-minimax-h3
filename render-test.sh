#!/usr/bin/env bash
# ===================================================================
# render-test.sh -- build a simple 30s MiniMax-H3 video render test
#
# The published MiniMax-H3 local flow supports up to ~15 seconds per
# generation, so this script renders two short segments and stitches
# them together into one clip with ffmpeg.
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=targets/lib.sh
source "${SCRIPT_DIR}/targets/lib.sh"

TARGET="${TARGET:-dev-rtx4070}"
load_target_env "$TARGET"

CHECK_ONLY=0
CUSTOM_DIFFUSION_FILE=""
CUSTOM_TEXT_ENCODER_FILE=""
CUSTOM_RENDER_HF_REPO=""
CUSTOM_BACKEND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=1; shift ;;
    --diffusion-file)
      CUSTOM_DIFFUSION_FILE="${2:-}"
      [ -n "$CUSTOM_DIFFUSION_FILE" ] || { echo "ERROR: --diffusion-file requires a filename." >&2; exit 1; }
      shift 2
      ;;
    --text-encoder-file)
      CUSTOM_TEXT_ENCODER_FILE="${2:-}"
      [ -n "$CUSTOM_TEXT_ENCODER_FILE" ] || { echo "ERROR: --text-encoder-file requires a filename." >&2; exit 1; }
      shift 2
      ;;
    --render-hf-repo)
      CUSTOM_RENDER_HF_REPO="${2:-}"
      [ -n "$CUSTOM_RENDER_HF_REPO" ] || { echo "ERROR: --render-hf-repo requires a repository." >&2; exit 1; }
      shift 2
      ;;
    --backend)
      CUSTOM_BACKEND="${2:-}"
      [ -n "$CUSTOM_BACKEND" ] || { echo "ERROR: --backend requires an assignment." >&2; exit 1; }
      shift 2
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

VENV_DIR="${SCRIPT_DIR}/.venv"
SD_CPP_DIR="${SCRIPT_DIR}/.stable-diffusion.cpp"
SD_CLI_BIN="${SD_CPP_DIR}/build/bin/sd-cli"

MMH3_RENDER_HF_REPO="${CUSTOM_RENDER_HF_REPO:-${MMH3_RENDER_HF_REPO:-leejet/MiniMax-H3-GGUF}}"
MMH3_RENDER_DIFFUSION_FILE="${CUSTOM_DIFFUSION_FILE:-${MMH3_RENDER_DIFFUSION_FILE:-minimax_h3_fl2va_pruned-Q4_K_M.gguf}}"
MMH3_RENDER_TEXT_ENCODER_FILE="${CUSTOM_TEXT_ENCODER_FILE:-${MMH3_RENDER_TEXT_ENCODER_FILE:-qwen3vl_32b_minimax_h3-Q2_K_M.gguf}}"
MMH3_RENDER_BACKEND="${CUSTOM_BACKEND:-${MMH3_RENDER_BACKEND:-}}"
MMH3_RENDER_AUX_REPO="${MMH3_RENDER_AUX_REPO:-Comfy-Org/MiniMax-H3}"
MMH3_RENDER_VIDEO_VAE_FILE="${MMH3_RENDER_VIDEO_VAE_FILE:-vae/minimax_h3_video_vae_fp16.safetensors}"
MMH3_RENDER_AUDIO_VAE_FILE="${MMH3_RENDER_AUDIO_VAE_FILE:-vae/minimax_h3_audio_vae_fp32.safetensors}"

MMH3_RENDER_ASSET_DIR="${MMH3_RENDER_ASSET_DIR:-${HOME}/models/minimax-h3-render}"
MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3}"
MMH3_RENDER_PROMPT="${MMH3_RENDER_PROMPT:-A simple stick-figure fight between Neo and Morpheus inside a green digital matrix dojo, minimalist black stick figures, glowing green code-rain background, clean silhouettes, clear punches, kicks, dodges, and jumps, side-view action, smooth continuous motion, cinematic timing, simple background, no gore, no subtitles, no watermark.}"
MMH3_RENDER_WIDTH="${MMH3_RENDER_WIDTH:-320}"
MMH3_RENDER_HEIGHT="${MMH3_RENDER_HEIGHT:-192}"
MMH3_RENDER_STEPS="${MMH3_RENDER_STEPS:-4}"
MMH3_RENDER_CFG_SCALE="${MMH3_RENDER_CFG_SCALE:-1.0}"
MMH3_RENDER_FPS="${MMH3_RENDER_FPS:-24}"
MMH3_RENDER_SEGMENT_SECONDS="${MMH3_RENDER_SEGMENT_SECONDS:-15}"
MMH3_RENDER_TOTAL_SECONDS="${MMH3_RENDER_TOTAL_SECONDS:-30}"
MMH3_RENDER_MAX_VRAM="${MMH3_RENDER_MAX_VRAM:--1}"
MMH3_RENDER_SEGMENTS="${MMH3_RENDER_SEGMENTS:-2}"

DIFFUSION_MODEL_PATH="${MMH3_RENDER_DIFFUSION_MODEL_PATH:-${MMH3_RENDER_ASSET_DIR}/${MMH3_RENDER_DIFFUSION_FILE}}"
TEXT_ENCODER_PATH="${MMH3_RENDER_TEXT_ENCODER_PATH:-${MMH3_RENDER_ASSET_DIR}/${MMH3_RENDER_TEXT_ENCODER_FILE}}"
VIDEO_VAE_PATH="${MMH3_RENDER_VIDEO_VAE_PATH:-${MMH3_RENDER_ASSET_DIR}/${MMH3_RENDER_VIDEO_VAE_FILE}}"
AUDIO_VAE_PATH="${MMH3_RENDER_AUDIO_VAE_PATH:-${MMH3_RENDER_ASSET_DIR}/${MMH3_RENDER_AUDIO_VAE_FILE}}"

if [ "$MMH3_RENDER_SEGMENTS" -ne 2 ]; then
  echo "ERROR: This simple test currently expects exactly 2 segments." >&2
  exit 1
fi

if [ "$MMH3_RENDER_TOTAL_SECONDS" -ne $((MMH3_RENDER_SEGMENT_SECONDS * MMH3_RENDER_SEGMENTS)) ]; then
  echo "ERROR: MMH3_RENDER_TOTAL_SECONDS must equal MMH3_RENDER_SEGMENT_SECONDS * MMH3_RENDER_SEGMENTS." >&2
  exit 1
fi

align_video_frames() {
  local requested="$1"
  local aligned=$((requested))
  while [ $(((aligned - 5) % 17)) -ne 0 ]; do
    aligned=$((aligned + 1))
  done
  echo "$aligned"
}

ensure_command() {
  local cmd="$1"
  local help="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Missing required command '$cmd'. ${help}" >&2
    exit 1
  fi
}

ensure_downloaded_file() {
  local repo="$1"
  local filename="$2"
  local target_path="$3"
  local suffix="/${filename}"
  local local_dir="${target_path%"$suffix"}"

  if [ -f "$target_path" ]; then
    echo "Asset present: $target_path"
    return 0
  fi

  echo "Downloading ${filename} from ${repo} ..."
  "${VENV_DIR}/bin/python3" "${SCRIPT_DIR}/download_model.py" \
    "$repo" \
    "$filename" \
    --local-dir "$local_dir"
}

SEGMENT_FRAMES=$(align_video_frames $((MMH3_RENDER_FPS * MMH3_RENDER_SEGMENT_SECONDS)))
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${MMH3_RENDER_OUTPUT_DIR}/${TIMESTAMP}"
SEGMENT_ONE="${RUN_DIR}/segment-1.webm"
SEGMENT_TWO="${RUN_DIR}/segment-2.webm"
FINAL_OUTPUT="${RUN_DIR}/neo-vs-morpheus-stick-figure-30s.webm"
CONCAT_LIST="${RUN_DIR}/concat.txt"

echo "=== MiniMax-H3 Render Test (${TARGET}) ==="
echo "Diffusion model: ${DIFFUSION_MODEL_PATH}"
echo "Text encoder:    ${TEXT_ENCODER_PATH}"
echo "Video VAE:       ${VIDEO_VAE_PATH}"
echo "Audio VAE:       ${AUDIO_VAE_PATH}"
echo "Output dir:      ${RUN_DIR}"
echo "Resolution:      ${MMH3_RENDER_WIDTH}x${MMH3_RENDER_HEIGHT}"
echo "FPS:             ${MMH3_RENDER_FPS}"
echo "Frames/segment:  ${SEGMENT_FRAMES}"
echo "Segments:        ${MMH3_RENDER_SEGMENTS} x ${MMH3_RENDER_SEGMENT_SECONDS}s"
if [ -n "$MMH3_RENDER_BACKEND" ]; then
  echo "Backend:         ${MMH3_RENDER_BACKEND}"
fi
echo ""

ensure_command python3 "Install Python 3 first."
ensure_command ffmpeg "Install ffmpeg first."
ensure_command nvidia-smi "Install NVIDIA drivers first."

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Pre-flight checks passed."
  exit 0
fi

if [ ! -x "$SD_CLI_BIN" ]; then
  ensure_command git "Install git first."
  ensure_command cmake "Install cmake and a C/C++ toolchain first."

  echo "Building stable-diffusion.cpp with CUDA and WebM support ..."
  if [ ! -d "$SD_CPP_DIR" ]; then
    git clone --recursive https://github.com/leejet/stable-diffusion.cpp "$SD_CPP_DIR"
  fi
  git -C "$SD_CPP_DIR" submodule update --init --recursive
  cmake -S "$SD_CPP_DIR" -B "${SD_CPP_DIR}/build" \
    -DSD_CUDA=ON \
    -DSD_WEBP=ON \
    -DSD_WEBM=ON \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "${SD_CPP_DIR}/build" --config Release -j "$(nproc)" --target sd-cli
fi

if [ ! -f "${VENV_DIR}/bin/python3" ]; then
  echo "Creating virtual environment for downloads ..."
  python3 -m venv "${VENV_DIR}"
fi

if ! "${VENV_DIR}/bin/python3" -c "import huggingface_hub" >/dev/null 2>&1; then
  "${VENV_DIR}/bin/pip" install --upgrade pip
  "${VENV_DIR}/bin/pip" install huggingface_hub
fi

mkdir -p "$MMH3_RENDER_ASSET_DIR" "$RUN_DIR"

ensure_downloaded_file "$MMH3_RENDER_HF_REPO" "$MMH3_RENDER_DIFFUSION_FILE" "$DIFFUSION_MODEL_PATH"
ensure_downloaded_file "$MMH3_RENDER_HF_REPO" "$MMH3_RENDER_TEXT_ENCODER_FILE" "$TEXT_ENCODER_PATH"
ensure_downloaded_file "$MMH3_RENDER_AUX_REPO" "$MMH3_RENDER_VIDEO_VAE_FILE" "$VIDEO_VAE_PATH"
ensure_downloaded_file "$MMH3_RENDER_AUX_REPO" "$MMH3_RENDER_AUDIO_VAE_FILE" "$AUDIO_VAE_PATH"

render_segment() {
  local segment_index="$1"
  local output_path="$2"
  local backend_args=()
  local memory_args=()

  if [ -n "$MMH3_RENDER_BACKEND" ]; then
    backend_args+=(--backend "$MMH3_RENDER_BACKEND")
  else
    memory_args+=(--offload-to-cpu --max-vram "$MMH3_RENDER_MAX_VRAM" --stream-layers)
  fi

  echo ""
  echo "=== Rendering segment ${segment_index}/${MMH3_RENDER_SEGMENTS} ==="

  "$SD_CLI_BIN" \
    -M vid_gen \
    --diffusion-model "$DIFFUSION_MODEL_PATH" \
    --vae "$VIDEO_VAE_PATH" \
    --audio-vae "$AUDIO_VAE_PATH" \
    --llm "$TEXT_ENCODER_PATH" \
    -p "$MMH3_RENDER_PROMPT" \
    --cfg-scale "$MMH3_RENDER_CFG_SCALE" \
    --steps "$MMH3_RENDER_STEPS" \
    -W "$MMH3_RENDER_WIDTH" \
    -H "$MMH3_RENDER_HEIGHT" \
    --fps "$MMH3_RENDER_FPS" \
    --video-frames "$SEGMENT_FRAMES" \
    --diffusion-fa \
    "${backend_args[@]}" \
    "${memory_args[@]}" \
    --rng cpu \
    --output "$output_path" \
    -v
}

render_segment 1 "$SEGMENT_ONE"
render_segment 2 "$SEGMENT_TWO"

printf "file '%s'\nfile '%s'\n" "$SEGMENT_ONE" "$SEGMENT_TWO" > "$CONCAT_LIST"

# sd-cli can produce PCM audio in each WebM segment, but WebM only supports
# Vorbis or Opus audio. Preserve the generated VP8 video and transcode audio.
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c:v copy -c:a libopus -b:a 128k "$FINAL_OUTPUT"

echo ""
echo "Done."
echo "Segment 1:  $SEGMENT_ONE"
echo "Segment 2:  $SEGMENT_TWO"
echo "Final clip: $FINAL_OUTPUT"
