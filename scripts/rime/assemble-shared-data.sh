#!/bin/zsh

# Assemble the Rime shared data that build-host.sh copies into the app (Contents/Resources/RimeData):
#   third_party/librime-data/smartime  project schema, dictionary manifest and default.yaml
#   build/rime-data/rime-ice/cn_dicts  rime-ice tables fetched by fetch-rime-ice.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
SHARED="$REPO_ROOT/build/rime-data/shared"

"$SCRIPT_DIR/fetch-rime-ice.sh"

rm -rf "$SHARED"
mkdir -p "$SHARED"
cp "$REPO_ROOT"/third_party/librime-data/smartime/* "$SHARED/"
cp -R "$REPO_ROOT/build/rime-data/rime-ice/cn_dicts" "$SHARED/cn_dicts"
cp "$REPO_ROOT/build/rime-data/rime-ice/LICENSE" "$SHARED/cn_dicts/LICENSE.rime-ice"

# Precompile the tables into shared/build, librime's default prebuilt data directory.
DEPLOYER_USER="$REPO_ROOT/build/rime-data/deployer-user"
rm -rf "$DEPLOYER_USER"
mkdir -p "$DEPLOYER_USER"
rime_deployer --build "$DEPLOYER_USER" "$SHARED" "$SHARED/build" > "$REPO_ROOT/build/rime-data/deploy.log" 2>&1 \
  || { echo "rime_deployer failed; see build/rime-data/deploy.log" >&2; exit 1; }
[[ -f "$SHARED/build/smartime_pinyin.table.bin" ]] \
  || { echo "rime_deployer did not produce smartime_pinyin.table.bin; see build/rime-data/deploy.log" >&2; exit 1; }

echo "Rime shared data ready: $SHARED"
