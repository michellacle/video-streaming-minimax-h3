#!/usr/bin/env bash
# Launch and inspect long render jobs on a remote host without SSH session coupling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_HOST="${MMH3_REMOTE_HOST:-michel@gpus}"
REMOTE_REPO_DIR="${MMH3_REMOTE_REPO_DIR:-/home/michel/code/video-streaming-minimax-h3}"
REMOTE_JOB_ROOT="${MMH3_REMOTE_JOB_ROOT:-/home/michel/videos/minimax-h3/remote-jobs}"

usage() {
  cat <<'USAGE'
Usage:
  bash remote-render.sh start [--env NAME=VALUE ...] SCRIPT [SCRIPT_ARGUMENT ...]
  bash remote-render.sh status JOB_ID
  bash remote-render.sh logs JOB_ID

Environment:
  MMH3_REMOTE_HOST      Tailscale SSH host (default: michel@gpus)
  MMH3_REMOTE_REPO_DIR  Repository path on the remote host
  MMH3_REMOTE_JOB_ROOT  Persistent remote job directory

Jobs run under both setsid and nohup. They continue when the local SSH client
disconnects. Use status and logs after reconnecting.
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
    "$REMOTE_REPO_DIR" "$REMOTE_JOB_ROOT" "$job_id" "$local_script" "$argument_data" "$environment_data" <<'REMOTE'
set -euo pipefail

repo_dir="$1"
job_root="$2"
job_id="$3"
script_relative_path="$4"
argument_data="$5"
environment_data="$6"
remote_script="${repo_dir}/${script_relative_path}"
job_dir="${job_root}/${job_id}"

[ -f "$remote_script" ] || {
  echo "ERROR: Remote render script not found: $remote_script" >&2
  exit 1
}

mkdir -p "$job_dir"
printf '%s' "$argument_data" | base64 -d > "$job_dir/arguments.bin"
printf '%s' "$environment_data" | base64 -d > "$job_dir/environment.bin"
cat > "$job_dir/runner.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail

job_dir="$1"
render_script="$2"
shift 2

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'state=running\npid=%s\nstarted_at=%s\n' "$$" "$started_at" > "$job_dir/status"

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
printf 'state=%s\npid=%s\nstarted_at=%s\nfinished_at=%s\nexit_code=%s\n' \
  "$state" "$$" "$started_at" "$finished_at" "$exit_code" > "$job_dir/status"
exit "$exit_code"
RUNNER
chmod 700 "$job_dir/runner.sh"

mapfile -d '' -t render_args < "$job_dir/arguments.bin"
nohup setsid "$job_dir/runner.sh" "$job_dir" "$remote_script" "${render_args[@]}" \
  </dev/null > "$job_dir/launcher.log" 2>&1 &
pid="$!"
printf 'state=starting\npid=%s\nstarted_at=%s\n' "$pid" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$job_dir/status"

printf 'job_id=%s\njob_dir=%s\npid=%s\n' "$job_id" "$job_dir" "$pid"
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
