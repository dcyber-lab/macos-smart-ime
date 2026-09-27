#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
BUILD_ROOT="$REPO_ROOT/build/ime-host"
# Spotlight skips *.noindex folders. Anywhere else it indexes a fresh app bundle and registers it with
# LaunchServices seconds later, and the system may then try to launch that copy instead of the installed one.
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData.noindex"
OUTPUT_APP="$BUILD_ROOT/Products.noindex/SmartIMEHost.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
BUILD_CONFIGURATION="Release"
DERIVED_APP="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/SmartIMEHost.app"

# Output from before the .noindex layout stays registered, so remove it.
for old_app in "$BUILD_ROOT/SmartIMEHost.app" "$BUILD_ROOT/DerivedData/Build/Products/$BUILD_CONFIGURATION/SmartIMEHost.app"; do
  [[ -d "$old_app" ]] && "$LSREGISTER" -u "$old_app" >/dev/null 2>&1 || true
done
rm -rf "$BUILD_ROOT/SmartIMEHost.app" "$BUILD_ROOT/DerivedData"

echo "Assembling Rime shared data..."
"$REPO_ROOT/scripts/rime/assemble-shared-data.sh"

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

mkdir -p "$(dirname "$OUTPUT_APP")"
rm -rf "$OUTPUT_APP"
rsync -a "$DERIVED_APP/" "$OUTPUT_APP/"

rsync -a --delete "$REPO_ROOT/build/rime-data/shared/" "$OUTPUT_APP/Contents/Resources/RimeData/"

echo "Signing SmartIMEHost..."
codesign --force --deep -s - "$OUTPUT_APP"

# xcodebuild registers its product with LaunchServices; left registered, it can shadow the installed input method.
"$LSREGISTER" -u "$DERIVED_APP" >/dev/null 2>&1 || true

echo "Build output ready:"
echo "  $OUTPUT_APP"
