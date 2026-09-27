#!/bin/zsh

# Assemble the Rime shared data directory the host reads (RIME_SHARED_DATA_DIR):
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

echo "Rime shared data ready: $SHARED"
