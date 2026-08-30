#!/usr/bin/env bash
# Render the full MiniMax-H3 FL2VA Q8_0 stick-fighter test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant fl2va-q8 "$@"
