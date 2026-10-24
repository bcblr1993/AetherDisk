#!/bin/bash
# Creates a fresh signed candidate; never overwrites an existing release.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${AETHERDISK_UPDATE_FEED:?Set HTTPS production feed}"
: "${AETHERDISK_UPDATE_PUBLIC_KEY:?Set production public key}"
VERSION="${AETHERDISK_VERSION:-$(cat VERSION)}"
BUILD="${AETHERDISK_BUILD:-2026102405}"
OUT="$PWD/outputs/releases/$VERSION-$BUILD"
IDENTITY='Developer ID Application: YanNan Chen (5984KQD4D7)'
PROFILE="${NOTARY_PROFILE:-AetherRoute-Notary}"
mkdir -p "$(dirname "$OUT")"
mkdir "$OUT"
AETHERDISK_RELEASE=1 AETHERDISK_BUILD="$BUILD" AETHERDISK_VERSION="$VERSION" AETHERDISK_APP_OUTPUT="$OUT/AetherDisk.app" scripts/build-preview.sh
APP="$OUT/AetherDisk.app"
FW="$APP/Contents/Frameworks/Sparkle.framework"
for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
 codesign --force --options runtime --timestamp --sign "$IDENTITY" "$FW/Versions/B/$component"
done
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$FW"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/aetherdisk-scan"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
notarize() {
 xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --timeout 15m --output-format json > "$2"
 python3 - "$2" <<'PY'
import sys,json
r=json.load(open(sys.argv[1])); assert r.get('status')=='Accepted',r
PY
}
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/notarization.zip"
notarize "$OUT/notarization.zip" "$OUT/notarization-app.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
STAGE="$OUT/dmg-stage"
mkdir "$STAGE"
ditto "$APP" "$STAGE/AetherDisk.app"
ln -s /Applications "$STAGE/Applications"
printf 'AetherDisk %s\n将 AetherDisk 拖入 Applications 后打开。\n需要 Apple 芯片、macOS 14 或更新版本。\n清理前始终需要确认，仅移入废纸篓。\nhttps://aethernative.com/apps/aetherdisk/\n' "$VERSION" > "$STAGE/安装说明.txt"
DMG="$OUT/AetherDisk-$VERSION-arm64.dmg"
hdiutil create -volname "AetherDisk $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
codesign --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG" "$OUT/notarization-dmg.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
# Only the staging copy and temporary notarization upload belong to this invocation.
rm -rf "$STAGE"
rm "$OUT/notarization.zip"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
printf '%s\n' "$OUT"
