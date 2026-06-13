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

apply_dmg_volume_icon() {
  local dmg="$1"
  local icns="$2"
  local volname="${3:-$VOLNAME}"
  [[ -f "$dmg" && -f "$icns" ]] || return 0
  if ! command -v SetFile >/dev/null 2>&1; then
    echo "    WARNING: SetFile not found — DMG volume will keep the default icon."
    return 0
  fi

  local rw_dmg="${dmg%.dmg}-rw.dmg"
  local mount_dir=""
  rm -f "$rw_dmg"
  # Detach stale mounts (e.g. user opened an older DMG) so we can write .VolumeIcon.icns.
  while IFS= read -r vol; do
    hdiutil detach "$vol" -quiet 2>/dev/null || true
  done < <(mount | awk -v name="$volname" '$3 ~ "/Volumes/" name {print $3}')

  hdiutil convert "$dmg" -format UDRW -o "$rw_dmg" -quiet
  mount_dir="$(hdiutil attach -readwrite -noverify -noautoopen "$rw_dmg" | awk '/\/Volumes\// {print $3; exit}')"
  cp "$icns" "$mount_dir/.VolumeIcon.icns"
  SetFile -a C "$mount_dir"
  sync
  hdiutil detach "$mount_dir" -quiet
  rm -f "$dmg"
  hdiutil convert "$rw_dmg" -format UDZO -o "$dmg" -quiet
  rm -f "$rw_dmg"
}

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

echo "==> [1/7] Syncing app icon from build/assets"
MASTER_ICON="$REPO_ROOT/build/assets/helmsman-app-icon-1024.png"
if [[ -f "$MASTER_ICON" ]]; then
  bash "$REPO_ROOT/scripts/build-icns.sh" "$MASTER_ICON" "$DMG_ICON"
fi
bash "$REPO_ROOT/scripts/sync-app-icon.sh" "$DMG_ICON"

echo "==> [2/7] Building universal Go backend"
make -C "$API_DIR" build-universal

echo "==> [3/7] Building app ($CONFIGURATION, unsigned)"
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

echo "==> [4/7] Embedding backend into $APP/Contents/Resources"
cp "$API_DIR/bin/helmsman-api" "$APP/Contents/Resources/helmsman-api"
chmod +x "$APP/Contents/Resources/helmsman-api"

echo "==> [5/7] Signing (inside-out)"
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

echo "==> [6/7] Building DMG"
DMG="$DIST/$VOLNAME.dmg"
if command -v create-dmg >/dev/null 2>&1; then
  CREATE_DMG_ARGS=(--volname "$VOLNAME" --app-drop-link 450 180)
  if [[ -f "$DMG_ICON" ]]; then
    CREATE_DMG_ARGS+=(--volicon "$DMG_ICON")
  else
    echo "    WARNING: $DMG_ICON not found — DMG will use the default volume icon."
  fi
  rm -f "$DMG"
  if ! create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG" "$APP"; then
    echo "    create-dmg failed — falling back to hdiutil."
    rm -f "$DMG"
  fi
fi
if [[ ! -f "$DMG" ]]; then
  # Fallback: hdiutil with an /Applications drop target.
  STAGING="$DIST/staging"
  rm -rf "$STAGING"; mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
  rm -rf "$STAGING"
  apply_dmg_volume_icon "$DMG" "$DMG_ICON"
fi

if [[ -n "$DEVELOPER_ID_APP" && -n "$NOTARY_PROFILE" ]]; then
  echo "==> [7/7] Notarizing + stapling"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "==> [7/7] Skipping notarization (set DEVELOPER_ID_APP and NOTARY_PROFILE to enable)."
fi

echo ""
echo "Done: $DMG"
