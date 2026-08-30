#!/usr/bin/env bash
# Verify whether a host can run the official MiniMaxAI/MiniMax-H3 BF16 release.
#
# The official release is a sharded Diffusers/SGLang deployment, not an sd-cli
# GGUF render. This preflight intentionally refuses to download assets when the
# host cannot provide the required aggregate VRAM and system-memory headroom.
set -euo pipefail

REQUIRED_VRAM_GIB=160
REQUIRED_RAM_GIB=150
REQUIRED_DISK_GIB=150

gib_from_mib() {
  awk -v mib="$1" 'BEGIN { printf "%.1f", mib / 1024 }'
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Missing required command '$1'." >&2
    exit 1
  fi
}

require_command nvidia-smi
require_command free
require_command df

gpu_memory_mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits \
  | awk '{ total += $1 } END { print total }')
gpu_count=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l)
ram_available_kib=$(free --kibi | awk '/^Mem:/ { print $7 }')
disk_available_kib=$(df -Pk "$HOME" | awk 'NR == 2 { print $4 }')

gpu_memory_gib=$(gib_from_mib "$gpu_memory_mib")
ram_available_gib=$(awk -v kib="$ram_available_kib" 'BEGIN { printf "%.1f", kib / 1024 / 1024 }')
disk_available_gib=$(awk -v kib="$disk_available_kib" 'BEGIN { printf "%.1f", kib / 1024 / 1024 }')

echo "=== MiniMax-H3 Official BF16 Preflight ==="
echo "Source: https://huggingface.co/MiniMaxAI/MiniMax-H3"
echo "GPUs: ${gpu_count}, ${gpu_memory_gib} GiB aggregate VRAM"
echo "RAM available: ${ram_available_gib} GiB"
echo "Disk available: ${disk_available_gib} GiB"
echo ""
echo "Required for one official BF16 variant:"
echo "  VRAM: >= ${REQUIRED_VRAM_GIB} GiB"
echo "  RAM:  >= ${REQUIRED_RAM_GIB} GiB"
echo "  Disk: >= ${REQUIRED_DISK_GIB} GiB"
echo ""

if [ "$gpu_memory_mib" -lt $((REQUIRED_VRAM_GIB * 1024)) ] \
  || [ "$ram_available_kib" -lt $((REQUIRED_RAM_GIB * 1024 * 1024)) ] \
  || [ "$disk_available_kib" -lt $((REQUIRED_DISK_GIB * 1024 * 1024)) ]; then
  echo "RESULT: NOT READY"
  echo "This host should use the quantized stable-diffusion.cpp render scripts instead."
  exit 1
fi

echo "RESULT: READY"
echo "This host meets the capacity floor. Install the official SGLang runtime and use:"
echo "  sglang serve --model-path MiniMaxAI/MiniMax-H3 --num-gpus 4 --ulysses-degree 4 --performance-mode speed --model-variant fl2va"
