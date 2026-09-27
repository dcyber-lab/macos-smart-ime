#!/bin/zsh

# Build, install system-wide without sudo, and run the smoke test in a throwaway test client.
# Requires a one-time `sudo scripts/ime/enable-dev-install.sh`.
#
# Usage: scripts/ime/dev-cycle.sh [--no-test]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
E2E_DIR="$REPO_ROOT/build/ime-host/e2e"

"$SCRIPT_DIR/build-host.sh"
"$SCRIPT_DIR/install-host.sh" --system

if [[ "${1:-}" == "--no-test" ]]; then
  exit 0
fi

"$SCRIPT_DIR/build-e2e.sh"
"$E2E_DIR/SmartIMEDriver" "$E2E_DIR/SmartIMETestClient.app"
