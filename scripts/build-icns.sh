#!/usr/bin/env bash
#
# build-icns.sh — build Helmsman.icns from a square 1024×1024 master PNG
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="${1:-$REPO_ROOT/build/assets/helmsman-app-icon-1024.png}"
OUT_ICNS="${2:-$REPO_ROOT/build/assets/Helmsman.icns}"
TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

if [[ ! -f "$MASTER" ]]; then
  echo "error: master icon not found: $MASTER" >&2
  exit 1
fi

read -r W H < <(sips -g pixelWidth -g pixelHeight "$MASTER" 2>/dev/null \
  | awk '/pixelWidth|pixelHeight/ {print $2}' | paste - -)
if [[ "$W" != "$H" ]]; then
  echo "error: master must be square (got ${W}x${H})" >&2
  exit 1
fi
if [[ "$W" -lt 1024 ]]; then
  echo "error: master must be at least 1024×1024 (got ${W}x${H})" >&2
  exit 1
fi

mkdir "$ICONSET"
sips -z 16 16   "$MASTER" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   "$MASTER" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   "$MASTER" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   "$MASTER" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns -o "$OUT_ICNS" "$ICONSET"
echo "Built $OUT_ICNS from $MASTER"
