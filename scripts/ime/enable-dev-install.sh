#!/bin/zsh

# One-time setup for development machines: make the system-level SmartIMEHost bundle
# owned by the developer account, so `./install.sh` and `scripts/ime/install-host.sh --system`
# can update it without sudo. `./install.sh` runs this on the first install.
#
# Trade-off: any process running as that account can modify the installed input method.
# A later `sudo scripts/ime/install-host.sh --system` restores root ownership.

set -euo pipefail

TARGET_APP="/Library/Input Methods/SmartIMEHost.app"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run with sudo: sudo scripts/ime/enable-dev-install.sh" >&2
  exit 1
fi

DEVELOPER="${SUDO_USER:-}"
if [[ -z "$DEVELOPER" || "$DEVELOPER" == "root" ]]; then
  echo "Run through sudo from the developer account, not as root directly." >&2
  exit 1
fi

if [[ ! -d "$TARGET_APP" ]]; then
  echo "SmartIMEHost is not installed at $TARGET_APP." >&2
  echo "Install it first: sudo scripts/ime/install-host.sh --system" >&2
  exit 1
fi

chown -R "$DEVELOPER":staff "$TARGET_APP"
echo "$TARGET_APP is now owned by $DEVELOPER."
echo "Update without sudo: ./install.sh"
