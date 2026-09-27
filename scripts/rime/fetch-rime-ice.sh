#!/bin/zsh

# Download the rime-ice (雾凇拼音) Chinese tables used by the smartime_pinyin schema from a pinned
# commit, and verify every file's SHA-256. Files are cached under build/rime-data/rime-ice and
# reused when they already match. The data is GPL-3.0 and is not committed to this repository.
#
# To update: change RIME_ICE_COMMIT, download the files, and replace the checksums below.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
DEST="$REPO_ROOT/build/rime-data/rime-ice"
RIME_ICE_COMMIT="3aea6d3694fb3d94ec663641f021f788822897ad"
BASE_URL="https://raw.githubusercontent.com/iDvel/rime-ice/$RIME_ICE_COMMIT"

typeset -A CHECKSUMS
CHECKSUMS=(
  cn_dicts/8105.dict.yaml   1f9a42b91dea6982baee2551981780271aeffd78876662b9c9f324e56b37b120
  cn_dicts/base.dict.yaml   19f6f96f5dfe553545f36c979001a12e3f3c0316f4e23f4382960a13e93e7550
  cn_dicts/ext.dict.yaml    f3843fecd2ec69ab823360383e8a07b4a69f4189133a87186f1702b350c1db2e
  cn_dicts/others.dict.yaml c7475d773e619f61b88d47fa8ec789aba02aa0d1c98edaed309e53487b048b32
  LICENSE                   3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986
)

matches() {
  [[ -f "$1" ]] && [[ "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$2" ]]
}

mkdir -p "$DEST/cn_dicts"
for file in ${(k)CHECKSUMS}; do
  target="$DEST/$file"
  expected="${CHECKSUMS[$file]}"
  if matches "$target" "$expected"; then
    continue
  fi
  echo "Downloading rime-ice $file..."
  curl -sSfL --retry 2 -o "$target.download" "$BASE_URL/$file"
  if ! matches "$target.download" "$expected"; then
    rm -f "$target.download"
    echo "SHA-256 mismatch for rime-ice $file (commit $RIME_ICE_COMMIT)." >&2
    exit 1
  fi
  mv "$target.download" "$target"
done

echo "rime-ice tables ready: $DEST (commit ${RIME_ICE_COMMIT:0:10})"
