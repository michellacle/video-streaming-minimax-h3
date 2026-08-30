#!/usr/bin/env bash
# Render the MiniMax-H3 Ref2VA pruned Q6 stick-fighter test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/render-quant-tests.sh" --quant ref2va-pruned-q6 "$@"
