#!/usr/bin/env bash
# ===================================================================
# render-quant-tests.sh -- render the MiniMax-H3 quant test matrix
#
# Each configuration delegates to render-test.sh, which builds sd-cli,
# downloads only missing assets, renders two segments, and joins them.
# ===================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage:
  bash render-quant-tests.sh --quant NAME
  bash render-quant-tests.sh --all
  bash render-quant-tests.sh --list

Available quant tests:
  fl2va-pruned-q4  MiniMax-H3 first/last-frame pruned Q4_K_M (verified)
  ref2va-pruned-q6 MiniMax-H3 reference-to-video pruned Q6_K
EOF
}

QUANT=""
RUN_ALL=0
LIST_ONLY=0
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quant)
      QUANT="${2:-}"
      [ -n "$QUANT" ] || { echo "ERROR: --quant requires a name." >&2; exit 1; }
      shift 2
      ;;
    --all) RUN_ALL=1; shift ;;
    --list) LIST_ONLY=1; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ "$LIST_ONLY" -eq 1 ]; then
  usage
  exit 0
fi

if [ "$RUN_ALL" -eq 1 ] && [ -n "$QUANT" ]; then
  echo "ERROR: Use either --all or --quant, not both." >&2
  exit 1
fi

if [ "$RUN_ALL" -eq 0 ] && [ -z "$QUANT" ]; then
  echo "ERROR: Select a test with --quant NAME or --all." >&2
  usage >&2
  exit 1
fi

run_quant() {
  local quant="$1"
  local diffusion_file
  local text_encoder_file
  local render_args=()

  case "$quant" in
    fl2va-pruned-q4)
      diffusion_file="minimax_h3_fl2va_pruned-Q4_K_M.gguf"
      text_encoder_file="qwen3vl_32b_minimax_h3-Q2_K_M.gguf"
      ;;
    ref2va-pruned-q6)
      diffusion_file="minimax_h3_ref2va_pruned-Q6_K.gguf"
      text_encoder_file="qwen3vl_32b_minimax_h3-Q4_K_M.gguf"
      ;;
    *)
      echo "ERROR: Unknown quant test '${quant}'." >&2
      usage >&2
      exit 1
      ;;
  esac

  if [ "$CHECK_ONLY" -eq 1 ]; then
    render_args+=(--check-only)
  fi

  echo "=== Running quant test: ${quant} ==="
  MMH3_RENDER_OUTPUT_DIR="${MMH3_RENDER_OUTPUT_DIR:-${HOME}/videos/minimax-h3}/${quant}" \
    bash "${SCRIPT_DIR}/render-test.sh" \
      --diffusion-file "$diffusion_file" \
      --text-encoder-file "$text_encoder_file" \
      "${render_args[@]}"
}

if [ "$RUN_ALL" -eq 1 ]; then
  run_quant fl2va-pruned-q4
  run_quant ref2va-pruned-q6
else
  run_quant "$QUANT"
fi
