#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SOURCE_APP="$REPO_ROOT/build/ime-host/SmartIMEHost.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
INSTALL_ROOT="$HOME/Library/Input Methods"

if [[ "${1:-}" == "--system" ]]; then
  INSTALL_ROOT="/Library/Input Methods"
fi

TARGET_APP="$INSTALL_ROOT/SmartIMEHost.app"
SYSTEM_INSTALL=false

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Built app not found at: $SOURCE_APP" >&2
  echo "Run scripts/ime/build-host.sh first." >&2
  exit 1
fi

if [[ "${1:-}" == "--system" ]]; then
  SYSTEM_INSTALL=true
fi

mkdir -p "$TARGET_APP"
rsync -a --delete "$SOURCE_APP/" "$TARGET_APP/"

if [[ "$SYSTEM_INSTALL" == true ]]; then
  chown -R root:wheel "$TARGET_APP"
fi

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f -R -trusted "$TARGET_APP" >/dev/null
fi

swift -e '
import Carbon
import Foundation

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path) as CFURL
let status = TISRegisterInputSource(url)
if status != noErr {
  fputs("TISRegisterInputSource failed with status \\(status) for \\(path)\n", stderr)
  exit(Int32(status))
}
' "$TARGET_APP"

echo "Installed SmartIMEHost:"
echo "  $TARGET_APP"
