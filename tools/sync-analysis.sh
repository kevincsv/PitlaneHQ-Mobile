#!/bin/sh
# Copies the web's lap analysis and coach (web/dist/pitwall-analysis.js of the Pitwall-test repository) into both apps:
# the copy they run until they download the newest one from pitlanehq.app. Run it whenever that file changes:
#   tools/sync-analysis.sh [path to the Pitwall-test repository, ../Pitwall-test by default]
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
src=${1:-$here/../Pitwall-test}/web/dist/pitwall-analysis.js
[ -f "$src" ] || { echo "no $src" >&2; exit 1; }
cp "$src" "$here/app/src/main/assets/pitwall-analysis.js"
cp "$src" "$here/ios/Resources/pitwall-analysis.js"
echo "pitwall-analysis.js copied to Android assets and iOS resources"
