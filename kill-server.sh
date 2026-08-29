#!/bin/bash
# Kill any llama-server / MiniMax-H3 processes holding GPU memory
# Uses nvidia-smi --query-compute-apps to find PIDs, checks the command
# line, then kills matching processes.
set -uo pipefail

count=0

echo "=== Checking GPU processes ==="

gpu_ids=$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | sed 's/^ *//;s/ *$//')

[ -z "$gpu_ids" ] && { echo "nvidia-smi unavailable."; exit 1; }

for gpu_id in $gpu_ids; do
    gpu_name=$(nvidia-smi -i "$gpu_id" --query-gpu=name --format=csv,noheader 2>/dev/null | tr -d '[:space:]')

    pids=$(nvidia-smi -i "$gpu_id" --query-compute-apps=pid --format=csv,noheader 2>/dev/null | tr -d '[:space:]' 2>/dev/null || true)
    [ -z "$pids" ] && continue

    while IFS= read -r pid; do
        [ -z "$pid" ] && continue

        cmd=$(ps -p "$pid" -ocmd= 2>/dev/null || echo "")
        [ -z "$cmd" ] && continue

        if echo "$cmd" | grep -qiE 'llama-server|llama\.cpp|minimax'; then
            mem=$(nvidia-smi -i "$gpu_id" --query-compute-apps=used_memory --format=csv,noheader -s pid,used_memory 2>/dev/null | awk -v p="$pid" '$1==p{print $2}')
            [ -z "$mem" ] && mem="?"
            echo "GPU ${gpu_id} (${gpu_name}): PID=${pid} MEM=${mem}MB"
            echo "  CMD: ${cmd}"
            echo "  -> Killing..."
            kill -9 "$pid" 2>/dev/null && ((count++)) || echo "  -> already dead"
        fi
    done <<< "$pids"
done

echo ""
echo "Done. Killed $count process(es)."

echo "=== Remaining GPU memory usage ==="
nvidia-smi --query-compute-apps=pid,used_memory --format=csv 2>/dev/null || nvidia-smi 2>/dev/null
