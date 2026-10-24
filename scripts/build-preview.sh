#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${AETHERDISK_BUILD_CONFIGURATION:-release}"
swift build -c "$CONFIG" --jobs 4
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="${AETHERDISK_APP_OUTPUT:-$ROOT/outputs/AetherDisk.app}"
if [ -e "$APP" ]; then
  echo 'Preview output already exists; set AETHERDISK_APP_OUTPUT to a fresh path.' >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/AetherDisk" "$APP/Contents/MacOS/AetherDisk"
cp "$BIN/aetherdisk-scan" "$APP/Contents/MacOS/aetherdisk-scan"
FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
/usr/bin/ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
APP_OUTPUT="$APP" AETHERDISK_VERSION="${AETHERDISK_VERSION:-$(cat VERSION)}" python3 - <<'PY'
import os,plistlib,base64,urllib.parse
from pathlib import Path
app=Path(os.environ['APP_OUTPUT'])
feed=os.environ.get('AETHERDISK_UPDATE_FEED','');key=os.environ.get('AETHERDISK_UPDATE_PUBLIC_KEY','')
if feed or key:
 u=urllib.parse.urlsplit(feed)
 assert u.scheme=='https' and u.hostname and not u.username and not u.password and not u.fragment
 assert len(base64.b64decode(key,validate=True))==32
info={'CFBundleExecutable':'AetherDisk','CFBundleIdentifier':'com.aethernative.AetherDisk','CFBundleName':'AetherDisk','CFBundleDisplayName':'AetherDisk','CFBundlePackageType':'APPL','CFBundleShortVersionString':os.environ['AETHERDISK_VERSION'],'CFBundleVersion':os.environ.get('AETHERDISK_BUILD','2026102407'),'LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'CFBundleLocalizations':['zh-Hans','en'],'NSPrincipalClass':'NSApplication','NSHumanReadableCopyright':'© 2026 AetherNative','SUEnableAutomaticChecks':bool(feed),'SUSendProfileInfo':False,'SUAutomaticallyUpdate':False,'SUAllowsAutomaticUpdates':False,'SUScheduledCheckInterval':86400,'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,'CFBundleIconFile':'AppIcon','AetherDiskRelease':os.environ.get('AETHERDISK_RELEASE')=='1','LSApplicationCategoryType':'public.app-category.utilities'}
if feed:info.update(SUFeedURL=feed,SUPublicEDKey=key)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
if [ -f "$ROOT/Resources/PrivacyInfo.xcprivacy" ]; then cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/"; fi
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
cp "$ROOT/Resources/Sparkle-LICENSE" "$APP/Contents/Resources/"
# Preview only: ad-hoc signing. No developer credentials or production keys used.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
