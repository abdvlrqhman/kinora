#!/usr/bin/env bash
# Downloads the libtorrent static libs built by the `engine` workflow into the
# locations the Android CMake build and the iOS podspec expect.
# Usage: tool/fetch_prebuilt.sh [run-id]   (default: latest successful app run on main)
set -euo pipefail
cd "$(dirname "$0")/.."
repo=abdvlrqhman/kinora
run=${1:-$(gh run list -R "$repo" --workflow app.yml --branch main --status success -L 1 --json databaseId -q '.[0].databaseId')}
for triplet in arm64-android arm-neon-android x64-android x64-linux x64-windows-static-md; do
  rm -rf "prebuilt/$triplet"
  gh run download "$run" -R "$repo" -n "libtorrent-$triplet" -D "prebuilt/$triplet" || echo "skip $triplet"
done
rm -rf ios/prebuilt
gh run download "$run" -R "$repo" -n libtorrent-arm64-ios -D ios/prebuilt || echo "skip arm64-ios"
