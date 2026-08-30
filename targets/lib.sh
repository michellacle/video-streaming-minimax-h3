#!/usr/bin/env bash
# ===================================================================
# targets/lib.sh -- shared helpers for selecting a deployment target
#
# Sourced by the top-level scripts (serve.sh, daemon.sh, install.sh, ...).
# Selecting a target only requires setting TARGET (default: dev-rtx4070);
# no other script needs to change when a new target is added.
# ===================================================================

# Resolve the repo root relative to this file.
MMH3_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMH3_REPO_ROOT="$(cd "${MMH3_LIB_DIR}/.." && pwd)"

# load_target_env TARGET -- export the config for the given target.
#
# Looks for, in order:
#   targets/<TARGET>/<TARGET>.env           (local override, gitignored)
#   targets/<TARGET>/<TARGET>.env.example   (checked-in defaults)
load_target_env() {
  local target="$1"
  local target_dir="${MMH3_REPO_ROOT}/targets/${target}"
  local env_file="${target_dir}/${target}.env"
  local example_file="${target_dir}/${target}.env.example"
  local name value
  local -A inherited_env=()

  # Command-line environment assignments override target defaults. This also
  # preserves the documented ability to configure scripts without an env file.
  while IFS='=' read -r name value; do
    case "$name" in
      MMH3_*|HF_TOKEN) inherited_env["$name"]="$value" ;;
    esac
  done < <(env)

  if [ ! -d "$target_dir" ]; then
    echo "ERROR: Unknown target '${target}' (no directory at targets/${target})." >&2
    exit 1
  fi

  if [ -f "$env_file" ]; then
    echo "[config] Loading targets/${target}/${target}.env" >&2
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  elif [ -f "$example_file" ]; then
    echo "[config] targets/${target}/${target}.env not found; using checked-in defaults from ${target}.env.example" >&2
    echo "[config] Copy it to ${target}.env and edit for a persistent local override." >&2
    set -a
    # shellcheck disable=SC1090
    source "$example_file"
    set +a
  else
    echo "ERROR: No config found for target '${target}' (expected ${target}.env or ${target}.env.example)." >&2
    exit 1
  fi

  for name in "${!inherited_env[@]}"; do
    export "$name=${inherited_env[$name]}"
  done
}
