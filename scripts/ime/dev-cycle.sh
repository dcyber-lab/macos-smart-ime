#!/bin/zsh

# Build, install system-wide without sudo, and run the TextEdit smoke test.
# Requires a one-time `sudo scripts/ime/enable-dev-install.sh`.
#
# Usage: scripts/ime/dev-cycle.sh [--no-test]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
E2E_BINARY="$REPO_ROOT/build/ime-host/e2e-textedit"

"$SCRIPT_DIR/build-host.sh"
"$SCRIPT_DIR/install-host.sh" --system

if [[ "${1:-}" == "--no-test" ]]; then
  exit 0
fi

echo "Compiling the TextEdit smoke test..."
swiftc -O -o "$E2E_BINARY" "$SCRIPT_DIR/e2e-textedit.swift"
"$E2E_BINARY"
