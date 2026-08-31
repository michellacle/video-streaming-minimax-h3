#!/usr/bin/env bash
# Launch and inspect long render jobs on a remote host without SSH session coupling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_HOST="${MMH3_REMOTE_HOST:-michel@gpus}"
REMOTE_REPO_DIR="${MMH3_REMOTE_REPO_DIR:-/home/michel/code/video-streaming-minimax-h3}"
REMOTE_JOB_ROOT="${MMH3_REMOTE_JOB_ROOT:-/home/michel/videos/minimax-h3/remote-jobs}"
REMOTE_MAX_USED_VRAM_MIB="${MMH3_REMOTE_MAX_USED_VRAM_MIB:-512}"

usage() {
  cat <<'USAGE'
Usage:
  bash remote-render.sh start [--gpu auto|GPU_INDEX] [--env NAME=VALUE ...] SCRIPT [SCRIPT_ARGUMENT ...]
  bash remote-render.sh status JOB_ID
  bash remote-render.sh logs JOB_ID

Environment:
  MMH3_REMOTE_HOST      Tailscale SSH host (default: michel@gpus)
  MMH3_REMOTE_REPO_DIR  Repository path on the remote host
  MMH3_REMOTE_JOB_ROOT  Persistent remote job directory
  MMH3_REMOTE_MAX_USED_VRAM_MIB
                         Maximum used VRAM for automatic GPU selection

Jobs run under both setsid and nohup. They continue when the local SSH client
disconnects. The default --gpu auto selects and reserves an idle GPU. Use
status and logs after reconnecting.
USAGE
}

remote_job_dir() {
  printf '%s/%s' "$REMOTE_JOB_ROOT" "$1"
}

start_job() {
  local local_script="$1"
  shift

  case "$local_script" in
    /*|../*|*/../*|.|..)
      echo "ERROR: SCRIPT must be a repository-relative path." >&2
      exit 1
      ;;
  esac
  [ -f "${SCRIPT_DIR}/${local_script}" ] || {
    echo "ERROR: Render script not found: ${local_script}" >&2
    exit 1
  }

  local job_id="render-$(date -u +%Y%m%d-%H%M%S)-$$"
  local argument_data
  local environment_data
  argument_data="$(printf '%s\0' "$@" | base64 -w 0)"
  environment_data="$(printf '%s\0' "${ENVIRONMENT_ASSIGNMENTS[@]}" | base64 -w 0)"

  tailscale ssh "$REMOTE_HOST" bash -s -- \
    "$REMOTE_REPO_DIR" "$REMOTE_JOB_ROOT" "$job_id" "$local_script" "$argument_data" "$environment_data" \
    "$REQUESTED_GPU" "$REMOTE_MAX_USED_VRAM_MIB" <<'REMOTE'
set -euo pipefail

repo_dir="$1"
job_root="$2"
job_id="$3"
script_relative_path="$4"
argument_data="$5"
environment_data="$6"
requested_gpu="$7"
max_used_vram_mib="$8"
remote_script="${repo_dir}/${script_relative_path}"
job_dir="${job_root}/${job_id}"

[ -f "$remote_script" ] || {
  echo "ERROR: Remote render script not found: $remote_script" >&2
  exit 1
}

mkdir -p "$job_dir"
exec 9>"${job_root}/dispatcher.lock"
flock -x 9

select_gpu() {
  local candidate_index candidate_used

  while IFS=, read -r candidate_index candidate_used; do
    candidate_index="${candidate_index//[[:space:]]/}"
    candidate_used="${candidate_used//[[:space:]]/}"
    [ "$candidate_used" -le "$max_used_vram_mib" ] || continue
    flock -n "${job_root}/gpu-${candidate_index}.lock" -c true 2>/dev/null || continue
    printf '%s' "$candidate_index"
    return 0
  done < <(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits)

  return 1
}

if [ "$requested_gpu" = "auto" ]; then
  assigned_gpu="$(select_gpu)" || {
    echo "ERROR: No GPU has <= ${max_used_vram_mib} MiB used VRAM and no active render reservation." >&2
    exit 1
  }
elif [[ "$requested_gpu" =~ ^[0-9]+$ ]]; then
  assigned_gpu="$requested_gpu"
  gpu_used_vram="$(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits | awk -F, -v gpu="$assigned_gpu" '$1 + 0 == gpu { gsub(/ /, "", $2); print $2 }')"
  [ -n "$gpu_used_vram" ] || {
    echo "ERROR: GPU ${assigned_gpu} does not exist." >&2
    exit 1
  }
  [ "$gpu_used_vram" -le "$max_used_vram_mib" ] || {
    echo "ERROR: GPU ${assigned_gpu} is using ${gpu_used_vram} MiB VRAM; refusing to overlap renders." >&2
    exit 1
  }
  flock -n "${job_root}/gpu-${assigned_gpu}.lock" -c true 2>/dev/null || {
    echo "ERROR: GPU ${assigned_gpu} is reserved by another remote render job." >&2
    exit 1
  }
else
  echo "ERROR: --gpu must be auto or a non-negative GPU index." >&2
  exit 1
fi

printf '%s' "$argument_data" | base64 -d > "$job_dir/arguments.bin"
printf '%s' "$environment_data" | base64 -d > "$job_dir/environment.bin"
cat > "$job_dir/runner.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail

job_dir="$1"
render_script="$2"
assigned_gpu="$3"
shift 3

job_root="$(dirname "$job_dir")"
exec 9>"${job_root}/gpu-${assigned_gpu}.lock"
if ! flock -n 9; then
  printf 'state=failed\npid=%s\ngpu=%s\nexit_code=1\n' "$$" "$assigned_gpu" > "$job_dir/status"
  exit 1
fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'state=running\npid=%s\ngpu=%s\nstarted_at=%s\n' "$$" "$assigned_gpu" "$started_at" > "$job_dir/status"
printf '%s\n' "$assigned_gpu" > "$job_dir/gpu-assigned"
export CUDA_VISIBLE_DEVICES="$assigned_gpu"

set +e
mapfile -d '' -t environment_assignments < "$job_dir/environment.bin"
for assignment in "${environment_assignments[@]}"; do
  [ -n "$assignment" ] || continue
  variable_name="${assignment%%=*}"
  case "$variable_name" in
    ''|*[!A-Za-z0-9_]*|[0-9]*)
      echo "ERROR: Invalid environment variable assignment." >&2
      exit 2
      ;;
  esac
  export "$assignment"
done

bash "$render_script" "$@" > "$job_dir/render.log" 2>&1
exit_code="$?"
set -e

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$exit_code" -eq 0 ]; then
  state="completed"
else
  state="failed"
fi
printf 'state=%s\npid=%s\ngpu=%s\nstarted_at=%s\nfinished_at=%s\nexit_code=%s\n' \
  "$state" "$$" "$assigned_gpu" "$started_at" "$finished_at" "$exit_code" > "$job_dir/status"
exit "$exit_code"
RUNNER
chmod 700 "$job_dir/runner.sh"

mapfile -d '' -t render_args < "$job_dir/arguments.bin"
printf 'state=starting\ngpu=%s\nstarted_at=%s\n' "$assigned_gpu" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$job_dir/status"
nohup setsid "$job_dir/runner.sh" "$job_dir" "$remote_script" "$assigned_gpu" "${render_args[@]}" \
  </dev/null > "$job_dir/launcher.log" 2>&1 &
pid="$!"
printf 'state=starting\npid=%s\ngpu=%s\nstarted_at=%s\n' "$pid" "$assigned_gpu" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$job_dir/status"

for _ in $(seq 1 50); do
  if [ -f "$job_dir/gpu-assigned" ]; then
    break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    cat "$job_dir/status" >&2
    exit 1
  fi
  sleep 0.1
done
[ -f "$job_dir/gpu-assigned" ] || {
  echo "ERROR: Timed out while reserving GPU ${assigned_gpu}." >&2
  exit 1
}
flock -u 9

printf 'job_id=%s\njob_dir=%s\npid=%s\ngpu=%s\n' "$job_id" "$job_dir" "$pid" "$assigned_gpu"
REMOTE
}

show_status() {
  local job_id="$1"
  local job_dir
  job_dir="$(remote_job_dir "$job_id")"

  tailscale ssh "$REMOTE_HOST" bash -s -- "$job_dir" <<'REMOTE'
set -euo pipefail

job_dir="$1"
[ -f "$job_dir/status" ] || {
  echo "ERROR: Unknown job: $job_dir" >&2
  exit 1
}
cat "$job_dir/status"
pid="$(awk -F= '$1 == "pid" { print $2 }' "$job_dir/status")"
if kill -0 "$pid" 2>/dev/null; then
  echo "process=running"
else
  echo "process=not-running"
fi
REMOTE
}

show_logs() {
  local job_id="$1"
  local job_dir
  job_dir="$(remote_job_dir "$job_id")"

  tailscale ssh "$REMOTE_HOST" bash -s -- "$job_dir" <<'REMOTE'
set -euo pipefail

job_dir="$1"
[ -f "$job_dir/render.log" ] || {
  echo "ERROR: No render log for job: $job_dir" >&2
  exit 1
}
tail -n 100 "$job_dir/render.log"
REMOTE
}

[ "$#" -ge 1 ] || {
  usage >&2
  exit 1
}

case "$1" in
  start)
    shift
    ENVIRONMENT_ASSIGNMENTS=()
    REQUESTED_GPU="auto"
    if [ "$#" -gt 0 ] && [ "$1" = "--gpu" ]; then
      [ "$#" -ge 2 ] || {
        echo "ERROR: --gpu requires auto or a GPU index." >&2
        exit 1
      }
      REQUESTED_GPU="$2"
      shift 2
    fi
    while [ "$#" -gt 0 ] && [ "$1" = "--env" ]; do
      [ "$#" -ge 2 ] || {
        echo "ERROR: --env requires NAME=VALUE." >&2
        exit 1
      }
      case "$2" in
        *=*) ENVIRONMENT_ASSIGNMENTS+=("$2") ;;
        *)
          echo "ERROR: --env requires NAME=VALUE." >&2
          exit 1
          ;;
      esac
      shift 2
    done
    [ "$#" -ge 1 ] || {
      usage >&2
      exit 1
    }
    start_job "$@"
    ;;
  status)
    [ "$#" -eq 2 ] || {
      usage >&2
      exit 1
    }
    show_status "$2"
    ;;
  logs)
    [ "$#" -eq 2 ] || {
      usage >&2
      exit 1
    }
    show_logs "$2"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "ERROR: Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
