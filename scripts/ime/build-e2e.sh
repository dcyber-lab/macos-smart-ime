#!/bin/zsh

# Build the IME smoke test: the throwaway SmartIMETestClient.app and the SmartIMEDriver binary.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
OUTPUT_DIR="$REPO_ROOT/build/ime-host/e2e"
CLIENT_APP="$OUTPUT_DIR/SmartIMETestClient.app"

rm -rf "$CLIENT_APP"
mkdir -p "$CLIENT_APP/Contents/MacOS"
cp "$SCRIPT_DIR/e2e/TestClient-Info.plist" "$CLIENT_APP/Contents/Info.plist"
swiftc -O -o "$CLIENT_APP/Contents/MacOS/SmartIMETestClient" "$SCRIPT_DIR/e2e/TestClient.swift"
codesign --force -s - "$CLIENT_APP" >/dev/null
swiftc -O -o "$OUTPUT_DIR/SmartIMEDriver" "$SCRIPT_DIR/e2e/Driver.swift"

echo "Smoke test ready: $OUTPUT_DIR/SmartIMEDriver $CLIENT_APP"
