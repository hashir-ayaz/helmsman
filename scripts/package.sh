#!/usr/bin/env bash
#
# package.sh — build Helmsman into a distributable .app + .dmg with the Go
# backend embedded as a sidecar, signed and (optionally) notarized.
#
# Pipeline: universal Go binary -> unsigned app build -> embed binary ->
#           sign inside-out -> DMG -> notarize + staple.
#
# Configuration (all overridable via environment):
#   SCHEME              Xcode scheme            (default: k67s)
#   CONFIGURATION       build configuration     (default: Release)
#   VOLNAME             DMG/volume name         (default: Helmsman)
#   DMG_ICON            .icns for DMG volume    (default: build/assets/Helmsman.icns)
#   DEVELOPER_ID_APP    signing identity, e.g.
#                       "Developer ID Application: Jane Doe (TEAMID)"
#                       If empty -> ad-hoc signing (local only, NOT notarizable).
#   NOTARY_PROFILE      notarytool keychain profile name created via
#                       `xcrun notarytool store-credentials`. If empty (or no
#                       DEVELOPER_ID_APP) notarization is skipped.
#
set -euo pipefail

SCHEME="${SCHEME:-k67s}"
CONFIGURATION="${CONFIGURATION:-Release}"
VOLNAME="${VOLNAME:-Helmsman}"
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_ICON="${DMG_ICON:-$REPO_ROOT/build/assets/Helmsman.icns}"
API_DIR="$REPO_ROOT/helmsman-api"
XCODEPROJ="$REPO_ROOT/helmsman-frontend/k67s.xcodeproj"
ENTITLEMENTS="$REPO_ROOT/helmsman-frontend/k67s/k67s.entitlements"
BUILD_DIR="$REPO_ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
DIST="$BUILD_DIR/dist"

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

echo "==> [1/6] Building universal Go backend"
make -C "$API_DIR" build-universal

echo "==> [2/6] Building app ($CONFIGURATION, unsigned)"
xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

SRC_APP="$DERIVED/Build/Products/$CONFIGURATION/$SCHEME.app"
APP="$DIST/$SCHEME.app"
cp -R "$SRC_APP" "$APP"

echo "==> [3/6] Embedding backend into $APP/Contents/Resources"
cp "$API_DIR/bin/helmsman-api" "$APP/Contents/Resources/helmsman-api"
chmod +x "$APP/Contents/Resources/helmsman-api"

echo "==> [4/6] Signing (inside-out)"
if [[ -n "$DEVELOPER_ID_APP" ]]; then
  SIGN=(--sign "$DEVELOPER_ID_APP" --options runtime --timestamp)
else
  echo "    WARNING: DEVELOPER_ID_APP not set — ad-hoc signing. The DMG will run"
  echo "             locally but CANNOT be notarized or distributed to other Macs."
  SIGN=(--sign -)
fi
# The embedded binary must be signed before the enclosing app.
codesign --force "${SIGN[@]}" "$APP/Contents/Resources/helmsman-api"
codesign --force "${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> [5/6] Building DMG"
DMG="$DIST/$VOLNAME.dmg"
if command -v create-dmg >/dev/null 2>&1; then
  CREATE_DMG_ARGS=(--volname "$VOLNAME" --app-drop-link 450 180)
  if [[ -f "$DMG_ICON" ]]; then
    CREATE_DMG_ARGS+=(--volicon "$DMG_ICON")
  else
    echo "    WARNING: $DMG_ICON not found — DMG will use the default volume icon."
  fi
  create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG" "$APP" || true
fi
if [[ ! -f "$DMG" ]]; then
  # Fallback: hdiutil with an /Applications drop target.
  STAGING="$DIST/staging"
  rm -rf "$STAGING"; mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
  rm -rf "$STAGING"
fi

if [[ -n "$DEVELOPER_ID_APP" && -n "$NOTARY_PROFILE" ]]; then
  echo "==> [6/6] Notarizing + stapling"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "==> [6/6] Skipping notarization (set DEVELOPER_ID_APP and NOTARY_PROFILE to enable)."
fi

echo ""
echo "Done: $DMG"
