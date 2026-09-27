#!/bin/zsh

# Build a self-contained LinguaType release: the app with librime and its Homebrew dependencies bundled, an
# installer that needs neither Xcode nor Homebrew, and the third-party licenses, zipped into
# build/release.noindex/. Runs the unit tests first. CI (.github/workflows/build.yml) runs this same script.
#
# Usage: scripts/release/package.sh [--publish]
#   --publish  also upload the zip as GitHub release v<version> (needs an authenticated gh)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
BUILT_APP="$REPO_ROOT/build/ime-host/Products.noindex/SmartIMEHost.app"
RELEASE_ROOT="$REPO_ROOT/build/release.noindex"
PUBLISH=false

for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

fail() { print -u2 "Error: $1"; exit 1 }

# A published release is tagged at HEAD, so it must be built from exactly that commit.
if $PUBLISH; then
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || fail "--publish needs a clean working tree"
  git -C "$REPO_ROOT" branch -r --contains HEAD | grep -q . || fail "--publish needs HEAD pushed to GitHub first"
fi

mkdir -p "$REPO_ROOT/build/ime-host"
echo "Running unit tests..."
swift test --package-path "$REPO_ROOT" > "$REPO_ROOT/build/unit-tests.log" 2>&1 \
  || { tail -n 40 "$REPO_ROOT/build/unit-tests.log" >&2; fail "unit tests failed; see build/unit-tests.log"; }
grep -E 'Executed [0-9]+ tests' "$REPO_ROOT/build/unit-tests.log" | tail -n 1

echo "Building..."
"$REPO_ROOT/scripts/ime/build-host.sh" > "$REPO_ROOT/build/ime-host/build.log" 2>&1 \
  || { tail -n 30 "$REPO_ROOT/build/ime-host/build.log" >&2; fail "build failed; see build/ime-host/build.log"; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")
ARCHS=$(lipo -archs "$BUILT_APP/Contents/MacOS/SmartIMEHost" | tr ' ' '-')
NAME="LinguaType-$VERSION-macOS-$ARCHS"
STAGE="$RELEASE_ROOT/$NAME"
APP="$STAGE/SmartIMEHost.app"
FRAMEWORKS="$APP/Contents/Frameworks"

rm -rf "$STAGE" "$STAGE.zip"
mkdir -p "$STAGE"
rsync -a "$BUILT_APP/" "$APP/"
mkdir -p "$FRAMEWORKS" "$STAGE/licenses"

echo "Bundling libraries..."
is_system_library() { [[ "$1" == /usr/lib/* || "$1" == /System/* ]] }
typeset -A bundled
min_os="0"
queue=("$APP/Contents/MacOS/SmartIMEHost")
while (( ${#queue} )); do
  file=${queue[1]}
  shift queue
  for dep in $(otool -L "$file" | tail -n +2 | awk '{print $1}'); do
    is_system_library "$dep" && continue
    [[ "$dep" == @* ]] && continue
    name=$(basename "$dep")
    if [[ -z "${bundled[$name]:-}" ]]; then
      source_path=$(realpath "$dep")
      bundled[$name]=$source_path
      cp "$source_path" "$FRAMEWORKS/$name"
      chmod u+w "$FRAMEWORKS/$name"
      install_name_tool -id "@rpath/$name" "$FRAMEWORKS/$name" 2>/dev/null
      install_name_tool -add_rpath "@loader_path" "$FRAMEWORKS/$name" 2>/dev/null || true
      queue+=("$FRAMEWORKS/$name")
      lib_min_os=$(vtool -show-build "$source_path" | awk '/minos/{print $2; exit}')
      [[ -n "$lib_min_os" ]] && min_os=$(printf '%s\n%s\n' "$min_os" "$lib_min_os" | sort -V | tail -1)
      # Homebrew keeps each formula's license files next to its lib directory.
      formula_dir=${source_path%/lib/*}
      formula=$(basename "$(dirname "$formula_dir")")
      mkdir -p "$STAGE/licenses/$formula"
      find "$formula_dir" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) \
        -exec cp {} "$STAGE/licenses/$formula/" \;
    fi
    install_name_tool -change "$dep" "@rpath/$name" "$file" 2>/dev/null
  done
done
if ! otool -l "$APP/Contents/MacOS/SmartIMEHost" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/SmartIMEHost"
fi
echo "  ${(k)bundled}"

# The bundled Homebrew libraries set the oldest macOS the release runs on.
app_min_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")
min_os=$(printf '%s\n%s\n' "$min_os" "$app_min_os" | sort -V | tail -1)
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $min_os" "$APP/Contents/Info.plist"

echo "Signing..."
for dylib in "$FRAMEWORKS"/*.dylib; do
  codesign --force --sign - "$dylib" >/dev/null 2>&1
done
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "Checking the bundle..."
for macho in "$APP/Contents/MacOS/SmartIMEHost" "$FRAMEWORKS"/*.dylib; do
  for dep in $(otool -L "$macho" | tail -n +2 | awk '{print $1}'); do
    if [[ "$dep" == @rpath/* ]]; then
      [[ -f "$FRAMEWORKS/${dep#@rpath/}" ]] || fail "$(basename "$macho") needs ${dep#@rpath/}, which is not bundled"
    elif ! is_system_library "$dep"; then
      fail "$(basename "$macho") still references $dep"
    fi
  done
done
codesign --verify --deep --strict "$APP" || fail "code signature check failed"

# Load the bundled librime and data the way the app does, and make sure nothing comes from Homebrew.
PROBE_DIR="$RELEASE_ROOT/probe"
rm -rf "$PROBE_DIR"
mkdir -p "$PROBE_DIR/user"
clang -o "$PROBE_DIR/rime-probe" "$SCRIPT_DIR/rime-probe.c" \
  -I"$(brew --prefix librime)/include" "$FRAMEWORKS/librime.1.dylib" -Wl,-rpath,"$FRAMEWORKS"
DYLD_PRINT_LIBRARIES=1 "$PROBE_DIR/rime-probe" "$APP/Contents/Resources/RimeData" "$PROBE_DIR/user" \
  > "$PROBE_DIR/probe.log" 2>&1 || { cat "$PROBE_DIR/probe.log" >&2; fail "the bundled librime did not produce 你好 for nihao"; }
if grep -E '/opt/homebrew|/usr/local' "$PROBE_DIR/probe.log" >&2; then
  fail "the bundled librime loaded the libraries above from outside the app"
fi
grep 'first candidate' "$PROBE_DIR/probe.log"

cp "$REPO_ROOT/scripts/ime/install-host.sh" "$STAGE/install-host.sh"
cp "$SCRIPT_DIR/install.command" "$STAGE/install.command"
chmod +x "$STAGE/install-host.sh" "$STAGE/install.command"
cp "$REPO_ROOT/third_party/librime-data/smartime/NOTICE.md" "$STAGE/licenses/rime-ice-NOTICE.md"
cp "$APP/Contents/Resources/RimeData/cn_dicts/LICENSE.rime-ice" "$STAGE/licenses/rime-ice-LICENSE"
cp "$REPO_ROOT/packages/english-engine/DATA_LICENSE.md" "$STAGE/licenses/english-data-LICENSE.md"
cat > "$STAGE/README.txt" <<EOF
LinguaType $VERSION (灵译输入法)

Requirements: macOS $min_os or later on Apple Silicon ($ARCHS).

Install or update:
  1. Unzip this archive.
  2. In Terminal, run:  zsh install.command
     It asks for the administrator password, installs into /Library/Input Methods, and enables LinguaType.
  3. Select LinguaType (灵译输入法) from the input menu.

If an app that was open during an update shows no candidates, quit and reopen it.

Uninstall:
  sudo rm -rf "/Library/Input Methods/SmartIMEHost.app"
  then remove LinguaType in System Settings › Keyboard › Input Sources.

The Chinese dictionary comes from rime-ice (GPL-3.0); it is included in source form in
SmartIMEHost.app/Contents/Resources/RimeData/cn_dicts. Licenses of all bundled components are in licenses/.
EOF

ZIP="$RELEASE_ROOT/$NAME.zip"
ditto -c -k --keepParent "$STAGE" "$ZIP"
echo "Release ready: $ZIP ($(du -h "$ZIP" | cut -f1))"

if $PUBLISH; then
  gh release create "v$VERSION" "$ZIP" --repo dcyber-lab/macos-smart-ime --target "$(git -C "$REPO_ROOT" rev-parse HEAD)" \
    --title "LinguaType $VERSION" --notes-file "$STAGE/README.txt"
fi
