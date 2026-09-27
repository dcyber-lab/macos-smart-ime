#!/bin/zsh

# Install or update LinguaType from this checkout in one step.
#
#   ./install.sh          build this checkout and install it (first install) or update the installed copy
#   ./install.sh --pull   pull the latest code first (fast-forward only)
#   ./install.sh --test   run the smoke test afterwards (takes over keyboard and mouse for about 40 seconds)
#
# The first install asks for the administrator password once: it installs into /Library/Input Methods and
# hands the bundle to your account, so later updates need no password.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
SYSTEM_APP="/Library/Input Methods/SmartIMEHost.app"
USER_APP="$HOME/Library/Input Methods/SmartIMEHost.app"
LOG_DIR="$REPO_ROOT/build/ime-host"
PULL=false
TEST=false

for arg in "$@"; do
  case "$arg" in
    --pull) PULL=true ;;
    --test) TEST=true ;;
    -h|--help) sed -n '3,10p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "Unknown option: $arg (see ./install.sh --help)" >&2; exit 2 ;;
  esac
done

step() { print -P "%B==> $1%b" }
fail() { print -u2 "Error: $1"; exit 1 }

step "Checking prerequisites"
[[ "$(uname)" == Darwin ]] || fail "LinguaType only runs on macOS."
xcodebuild -version >/dev/null 2>&1 \
  || fail "Full Xcode is required. Install it, then run: sudo xcode-select -s /Applications/Xcode.app"
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 \
  || fail "Xcode has not finished its first-launch setup. Run: sudo xcodebuild -runFirstLaunch"
command -v brew >/dev/null 2>&1 || fail "Homebrew is required: https://brew.sh"
missing=()
for formula in librime xcodegen pkgconf; do
  brew list --versions "$formula" >/dev/null 2>&1 || missing+=("$formula")
done
if (( ${#missing} )); then
  step "Installing ${missing[*]} with Homebrew"
  brew install "${missing[@]}"
fi

if $PULL; then
  step "Pulling the latest code"
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
    || fail "The checkout has local changes. Commit or stash them, or run without --pull."
  git -C "$REPO_ROOT" pull --ff-only
fi

step "Building (the first build also downloads the rime-ice Chinese tables, about 28 MB)"
mkdir -p "$LOG_DIR"
if ! "$REPO_ROOT/scripts/ime/build-host.sh" >"$LOG_DIR/build.log" 2>&1; then
  tail -n 30 "$LOG_DIR/build.log" >&2
  fail "The build failed. Full log: build/ime-host/build.log"
fi

# A per-user copy is never launched by the system and shows up as a second, broken input source.
if [[ -d "$USER_APP" ]]; then
  step "Removing the old per-user copy in ~/Library/Input Methods"
  rm -rf "$USER_APP"
fi

if [[ -w "$SYSTEM_APP" ]]; then
  step "Updating LinguaType"
  "$REPO_ROOT/scripts/ime/install-host.sh" --system
else
  step "Installing LinguaType (asks for your administrator password once)"
  sudo "$REPO_ROOT/scripts/ime/install-host.sh" --system
  sudo "$REPO_ROOT/scripts/ime/enable-dev-install.sh" >/dev/null
fi

if $TEST; then
  step "Running the smoke test: keep your hands off the keyboard and mouse for about 40 seconds"
  "$REPO_ROOT/scripts/ime/build-e2e.sh" >/dev/null
  "$LOG_DIR/e2e/SmartIMEDriver" "$LOG_DIR/e2e/SmartIMETestClient.app"
fi

step "Done"
echo "Select LinguaType (灵译输入法) from the input menu and start typing."
echo "If an app that was open during the update shows no candidates, quit and reopen it."
