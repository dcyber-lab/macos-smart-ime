#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SOURCE_APP="$REPO_ROOT/build/ime-host/SmartIMEHost.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
INSTALL_ROOT="$HOME/Library/Input Methods"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID=""

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

TARGET_UID=$(id -u "$TARGET_USER")

run_for_target_user() {
  if [[ "$EUID" -eq 0 ]]; then
    sudo -u "$TARGET_USER" "$@"
  else
    "$@"
  fi
}

# Kill any running SmartIMEHost process BEFORE replacing the bundle on disk.
# A stale process holding a broken IMKServer connection will prevent the
# system from switching to the input method after reinstallation.
if pgrep -x SmartIMEHost >/dev/null 2>&1; then
  echo "Stopping existing SmartIMEHost process..."
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

PREFS_PLIST=$(run_for_target_user mktemp -t smartime-hitoolbox)
run_for_target_user defaults export com.apple.HIToolbox "$PREFS_PLIST"

run_for_target_user swift -e '
import Foundation

let path = CommandLine.arguments[1]
let bundleID = "lab.dcyber.inputmethod.smartime"

func keyboardMethodEntry(for bundleID: String) -> [String: Any] {
    [
        "Bundle ID": bundleID,
        "InputSourceKind": "Keyboard Input Method",
    ]
}

func normalizeEntries(_ value: Any?, bundleID: String) -> [[String: Any]] {
    let input = (value as? [[String: Any]]) ?? []
    var output: [[String: Any]] = []
    var seenSmartIME = false

    for entry in input {
        let kind = entry["InputSourceKind"] as? String
        let candidateBundleID = entry["Bundle ID"] as? String

        if kind == "Keyboard Input Method" && candidateBundleID == nil {
            continue
        }

        if candidateBundleID == bundleID && kind == "Keyboard Input Method" {
            if seenSmartIME {
                continue
            }

            seenSmartIME = true
            output.append(keyboardMethodEntry(for: bundleID))
            continue
        }

        output.append(entry)
    }

    if !seenSmartIME {
        output.append(keyboardMethodEntry(for: bundleID))
    }

    return output
}

let url = URL(fileURLWithPath: path)
let data = try Data(contentsOf: url)
var format = PropertyListSerialization.PropertyListFormat.xml
guard var root = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
    fatalError("Expected com.apple.HIToolbox plist root dictionary")
}

root["AppleEnabledInputSources"] = normalizeEntries(root["AppleEnabledInputSources"], bundleID: bundleID)
root["AppleInputSourceHistory"] = normalizeEntries(root["AppleInputSourceHistory"], bundleID: bundleID)

let normalized = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
try normalized.write(to: url)
' "$PREFS_PLIST"

run_for_target_user defaults import com.apple.HIToolbox "$PREFS_PLIST"
run_for_target_user rm -f "$PREFS_PLIST"

run_for_target_user swift -e '
import Carbon

let bundleID = "lab.dcyber.inputmethod.smartime" as CFString
let properties: [CFString: Any] = [kTISPropertyBundleID: bundleID]
let filter = properties as CFDictionary
let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as NSArray

guard let source = list.firstObject else {
    fatalError("SmartIMEHost input source not found after registration")
}

let status = TISEnableInputSource((source as! TISInputSource))
if status != noErr {
    fatalError("TISEnableInputSource failed with status \\(status)")
}
'

if [[ "$EUID" -eq 0 ]]; then
  launchctl asuser "$TARGET_UID" killall TextInputMenuAgent >/dev/null 2>&1 || true
  launchctl asuser "$TARGET_UID" killall TextInputSwitcher >/dev/null 2>&1 || true
  launchctl asuser "$TARGET_UID" killall SystemUIServer >/dev/null 2>&1 || true
else
  killall TextInputMenuAgent >/dev/null 2>&1 || true
  killall TextInputSwitcher >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true
fi

sleep 2

# Verify the input source is selectable after installation.
run_for_target_user swift -e '
import Carbon
import Foundation

let bundleID = "lab.dcyber.inputmethod.smartime" as CFString
let filter: [CFString: Any] = [kTISPropertyBundleID: bundleID]
let list = TISCreateInputSourceList(filter as CFDictionary, false).takeRetainedValue() as! [TISInputSource]

guard let src = list.first else {
    fputs("Verification FAILED: SmartIMEHost not found in enabled sources.\n", stderr)
    exit(1)
}

func getStr(_ key: CFString) -> String {
    guard let ptr = TISGetInputSourceProperty(src, key) else { return "nil" }
    return "\(Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue())"
}

let enabled = getStr(kTISPropertyInputSourceIsEnabled)
let selectable = getStr(kTISPropertyInputSourceIsSelectCapable)
let name = getStr(kTISPropertyLocalizedName)

if enabled == "1" && selectable == "1" {
    fputs("Verified: \(name) is enabled and selectable.\n", stderr)
} else {
    fputs("Verification WARNING: enabled=\(enabled) selectable=\(selectable)\n", stderr)
}
'

echo "Installed SmartIMEHost:"
echo "  $TARGET_APP"
