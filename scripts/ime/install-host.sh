#!/bin/zsh

# Install a built SmartIMEHost.app and enable it for the current user.
#
# Usage: install-host.sh [--system] [APP]
#   --system  install into /Library/Input Methods (the only location imklaunchagent launches from reliably)
#   APP       the app bundle to install; defaults to the build output of scripts/ime/build-host.sh
#
# Needs no Swift toolchain or Homebrew, so the release package ships it as its installer.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SOURCE_APP="$REPO_ROOT/build/ime-host/Products.noindex/SmartIMEHost.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
INSTALL_ROOT="$HOME/Library/Input Methods"
TARGET_USER="${SUDO_USER:-$USER}"
SYSTEM_INSTALL=false

for arg in "$@"; do
  case "$arg" in
    --system) SYSTEM_INSTALL=true; INSTALL_ROOT="/Library/Input Methods" ;;
    *) SOURCE_APP=$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg") ;;
  esac
done

TARGET_APP="$INSTALL_ROOT/SmartIMEHost.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "App not found at: $SOURCE_APP" >&2
  echo "Run scripts/ime/build-host.sh first." >&2
  exit 1
fi

# Without sudo, a system install only works after scripts/ime/enable-dev-install.sh
# made the installed bundle owned by the developer account.
if [[ "$SYSTEM_INSTALL" == true && "$EUID" -ne 0 && ! -w "$TARGET_APP" ]]; then
  echo "Cannot update $TARGET_APP without sudo." >&2
  echo "Either run: sudo scripts/ime/install-host.sh --system" >&2
  echo "or once:    sudo scripts/ime/enable-dev-install.sh (later installs need no sudo)" >&2
  exit 1
fi

TARGET_UID=$(id -u "$TARGET_USER")

run_for_target_user() {
  if [[ "$EUID" -eq 0 ]]; then
    sudo -u "$TARGET_USER" "$@"
  else
    "$@"
  fi
}

mkdir -p "$TARGET_APP"
rsync -a --delete "$SOURCE_APP/" "$TARGET_APP/"

# A downloaded release is quarantined, and a quarantined input method is never launched.
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

if [[ "$SYSTEM_INSTALL" == true && "$EUID" -eq 0 ]]; then
  chown -R root:wheel "$TARGET_APP"
fi

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f -R -trusted "$TARGET_APP" >/dev/null
fi

run_for_target_user "$TARGET_APP/Contents/MacOS/SmartIMEHost" --install

if [[ "$EUID" -eq 0 ]]; then
  launchctl asuser "$TARGET_UID" killall TextInputMenuAgent >/dev/null 2>&1 || true
  launchctl asuser "$TARGET_UID" killall TextInputSwitcher >/dev/null 2>&1 || true
  launchctl asuser "$TARGET_UID" killall SystemUIServer >/dev/null 2>&1 || true
else
  killall TextInputMenuAgent >/dev/null 2>&1 || true
  killall TextInputSwitcher >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true
fi

# imklaunchagent launches the input method by bundle ID and fails when LaunchServices resolves it to a build
# copy (xcodebuild registers its product), so only the installed copy stays registered.
for build_copy in "$REPO_ROOT/build/ime-host/Products.noindex/SmartIMEHost.app" \
  "$REPO_ROOT/build/ime-host/DerivedData.noindex/Build/Products/Release/SmartIMEHost.app"; do
  [[ -d "$build_copy" ]] && "$LSREGISTER" -u "$build_copy" >/dev/null 2>&1 || true
done

# Stop the old instance only now that the new bundle is in place; imklaunchagent launches the new one on the
# next keystroke. Never restart imklaunchagent itself: an agent restarted with killall keeps handing apps a dead
# endpoint for about 40 seconds after the input method exits, and until the next login.
if pgrep -x SmartIMEHost >/dev/null 2>&1; then
  echo "Stopping the previous SmartIMEHost process..."
  killall SmartIMEHost >/dev/null 2>&1 || true
  for i in 1 2 3 4 5; do
    pgrep -x SmartIMEHost >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -x SmartIMEHost >/dev/null 2>&1; then
    echo "Warning: SmartIMEHost did not exit cleanly; force killing." >&2
    killall -9 SmartIMEHost >/dev/null 2>&1 || true
    sleep 1
  fi
fi

echo "Installed SmartIMEHost:"
echo "  $TARGET_APP"
