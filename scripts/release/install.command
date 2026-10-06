#!/bin/zsh

# Install LinguaType from this folder. In Terminal: zsh install.command (asks for the administrator password).

set -euo pipefail

cd "$(dirname "$0")"
# Files from a downloaded zip are quarantined; the installer and the app must not be.
xattr -dr com.apple.quarantine . 2>/dev/null || true
sudo ./install-host.sh --system SmartIMEHost.app

echo
echo "LinguaType is installed. Select LinguaType from the input menu and start typing."
echo "If it is missing there, add it in System Settings › Keyboard › Input Sources."
