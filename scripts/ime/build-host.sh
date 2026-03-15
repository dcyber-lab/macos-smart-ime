#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
BUILD_ROOT="$REPO_ROOT/build/ime-host"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
OUTPUT_APP="$BUILD_ROOT/SmartIMEHost.app"
BUILD_CONFIGURATION="Release"
DERIVED_APP="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/SmartIMEHost.app"

echo "Generating Xcode project..."
cd "$REPO_ROOT"
xcodegen generate

echo "Building SmartIMEHost..."
xcodebuild \
  -project macos-smart-ime.xcodeproj \
  -scheme SmartIMEHost \
  -configuration "$BUILD_CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ENABLE_DEBUG_DYLIB=NO \
  build

if [[ ! -d "$DERIVED_APP" ]]; then
  echo "Build succeeded but app bundle was not found at: $DERIVED_APP" >&2
  exit 1
fi

mkdir -p "$BUILD_ROOT"
rm -rf "$OUTPUT_APP"
rsync -a "$DERIVED_APP/" "$OUTPUT_APP/"

echo "Signing SmartIMEHost..."
codesign --force --deep -s - "$OUTPUT_APP"

echo "Build output ready:"
echo "  $OUTPUT_APP"
