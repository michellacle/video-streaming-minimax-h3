#!/usr/bin/env bash
# Render the verified MiniMax-H3 FL2VA pruned Q4 stick-fighter test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant fl2va-pruned-q4 "$@"
