#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(cd "${1:?usage: generate-appcast.sh <release-directory>}" && pwd)"
APP="$OUT/AetherDisk.app"
DMG="${AETHERDISK_RELEASE_DMG:?Set the notarized final DMG path}"
PREFIX="${AETHERDISK_DOWNLOAD_PREFIX:?Set the public HTTPS download prefix}"
GEN="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
test -d "$APP" && test -f "$DMG" && test -x "$GEN"
python3 - "$APP/Contents/Info.plist" "$PREFIX" <<'PY'
import plistlib,sys,urllib.parse,base64
p=plistlib.load(open(sys.argv[1],'rb'));u=urllib.parse.urlsplit(sys.argv[2]);feed=urllib.parse.urlsplit(p.get('SUFeedURL',''))
assert u.scheme=='https' and u.hostname and not u.username and not u.password
assert feed.scheme=='https' and feed.hostname
assert p.get('SURequireSignedFeed') is True and p.get('SUVerifyUpdateBeforeExtraction') is True
assert len(base64.b64decode(p['SUPublicEDKey'],validate=True))==32
PY
codesign --verify --deep --strict "$APP"
spctl --assess --type execute "$APP"
xcrun stapler validate "$DMG"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/aetherdisk-appcast.XXXXXX")"
# The trap owns only this invocation's new staging directory.
trap 'rm -rf "$STAGE"' EXIT
cp "$DMG" "$STAGE/"
"$GEN" --account AetherDisk --download-url-prefix "$PREFIX" "$STAGE"
python3 - "$STAGE/appcast.xml" "$DMG" <<'PY'
import sys,os,xml.etree.ElementTree as E
p,dmg=sys.argv[1:];ns={'s':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items=E.parse(p).findall('./channel/item');assert len(items)==1
enc=items[0].find('enclosure');assert enc.get('{'+ns['s']+'}edSignature')
assert int(enc.get('length'))==os.path.getsize(dmg)
assert '<!-- sparkle-signatures:' in open(p).read()
PY
test ! -e "$OUT/appcast.xml" || { echo 'Existing appcast preserved; use a fresh release directory.' >&2; exit 1; }
cp "$STAGE/appcast.xml" "$OUT/appcast.xml"
printf '%s\n' "$OUT/appcast.xml"
