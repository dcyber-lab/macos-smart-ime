#!/bin/zsh

set -euo pipefail

INSTALL_ROOT="$HOME/Library/Input Methods"

if [[ "${1:-}" == "--system" ]]; then
  INSTALL_ROOT="/Library/Input Methods"
fi

TARGET_APP="$INSTALL_ROOT/SmartIMEHost.app"

if [[ ! -e "$TARGET_APP" ]]; then
  echo "No installed SmartIMEHost app found at:"
  echo "  $TARGET_APP"
  exit 0
fi

rm -rf "$TARGET_APP"

echo "Removed SmartIMEHost:"
echo "  $TARGET_APP"
