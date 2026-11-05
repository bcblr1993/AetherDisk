#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if ! tart list | awk '$2=="macos27" && $NF=="running"{found=1} END{exit !found}'; then
  nohup tart run macos27 >/tmp/tart-macos27-qa.log 2>&1 &
  sleep 8
fi
export AETHERDISK_VM_IP="${AETHERDISK_VM_IP:-$(tart ip --wait 30 macos27)}"
export AETHERDISK_QA_ROOT="/Users/chenxu/AetherDisk-Release-QA-20261104"
export AETHERDISK_QA_OWNER="/Users/chenxu/Applications/AetherDisk-Release-QA-20261104"
export AETHERDISK_AX_BIN="/tmp/AetherDiskAX-20261104"
export AETHERDISK_QA_OUT="$ROOT_DIR/outputs/qa-050"
mkdir -p "$AETHERDISK_QA_OUT"

SSH_OPTS=(-i "$HOME/.ssh/id_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="chenxu@$AETHERDISK_VM_IP"

echo "[1/5] Preparing isolated QA fixture on $REMOTE..."
ssh "${SSH_OPTS[@]}" "$REMOTE" "python3 -" <<'PY'
from pathlib import Path
import shutil
root=Path('/Users/chenxu/AetherDisk-Release-QA-20261104')
owner=Path('/Users/chenxu/Applications/AetherDisk-Release-QA-20261104')
if root.exists():
    for p in root.rglob('*'):
        try: p.chmod(0o700)
        except Exception: pass
    shutil.rmtree(root)
if owner.exists(): shutil.rmtree(owner)
root.mkdir(); owner.mkdir(parents=True)
prefs=Path.home()/'Library/Preferences/com.aethernative.AetherDisk.plist'
if prefs.exists(): (owner/'preferences-before.plist').write_bytes(prefs.read_bytes())
for name in ['Safe','Source','Installer']:
    p=root/'Developer'/name; p.mkdir(parents=True)
    (p/'Package.swift').write_text('// QA project marker')
    (p/'.build').mkdir()
(root/'Developer/Safe/.build/cache.data').write_bytes(b'x'*8*1024*1024)
(root/'Developer/Source/.build/main.swift').write_text('// protected source')
(root/'Developer/Installer/.build/Release.dmg').write_bytes(b'i'*8192)
for name in ['Documents','Empty','Restricted','.hidden','Media/deep/hub','Downloads','Sparse']:
    (root/name).mkdir(parents=True)
(root/'Documents/report.data').write_bytes(b'd'*16384)
(root/'Restricted/data').write_bytes(b'r'*4096); (root/'Restricted').chmod(0)
(root/'.hidden/cache.data').write_bytes(b'h'*8192)
(root/'outside-link').symlink_to('/Applications')
(root/'Media/deep/hub/Movie.mp4').write_bytes(b'm'*128*1024*1024)
(root/'Media/cover.png').write_bytes(b'p'*2*1024*1024)
(root/'Downloads/Release.dmg').write_bytes(b'i'*32*1024*1024)
(root/'Documents/notes.pdf').write_bytes(b'd'*3*1024*1024)
with (root/'Sparse/virtual.bin').open('wb') as f:
    f.truncate(1024*1024*1024)
print('Fixture ready')
PY

echo "[2/5] Copying AetherDisk.app and compiling AXDriver..."
scp "${SSH_OPTS[@]}" -r "$ROOT_DIR/outputs/AetherDisk.app" "$REMOTE:$AETHERDISK_QA_OWNER/AetherDisk.app"
scp "${SSH_OPTS[@]}" "$ROOT_DIR/scripts/qa/AXDriver.swift" "$REMOTE:/tmp/AXDriver-20261104.swift"
ssh "${SSH_OPTS[@]}" "$REMOTE" "swiftc /tmp/AXDriver-20261104.swift -o $AETHERDISK_AX_BIN && rm -f /tmp/AXDriver-20261104.swift"

cleanup_vm() {
    echo "[5/5] Restoring VM state and removing only test-owned paths..."
    ssh "${SSH_OPTS[@]}" "$REMOTE" "python3 -" <<'PY' || true
import subprocess,os,signal,shutil,hashlib
from pathlib import Path
owner='/Users/chenxu/Applications/AetherDisk-Release-QA-20261104'
root=Path('/Users/chenxu/AetherDisk-Release-QA-20261104')
for row in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
    parts=row.strip().split(None,1)
    if len(parts)==2 and parts[1].startswith(owner+'/') and parts[1].endswith('/Contents/MacOS/AetherDisk'):
        try: os.kill(int(parts[0]),signal.SIGTERM)
        except Exception: pass
prefs=Path.home()/'Library/Preferences/com.aethernative.AetherDisk.plist'
backup=Path(owner)/'preferences-before.plist'
if backup.exists(): prefs.write_bytes(backup.read_bytes())
elif prefs.exists(): prefs.unlink()
for target in [str(root), str(root/'Documents'), str(root/'Empty')]:
    prefix=hashlib.sha256(target.encode()).digest()[:12].hex()
    for suffix in ['.json', '-history.json']:
        snap=Path.home()/'Library/Application Support/AetherDisk/Scans'/(prefix+suffix)
        if snap.exists(): snap.unlink()
if root.exists():
    for p in root.rglob('*'):
        try: p.chmod(0o700)
        except Exception: pass
    shutil.rmtree(root)
if Path(owner).exists(): shutil.rmtree(owner)
ax=Path('/tmp/AetherDiskAX-20261104')
if ax.exists(): ax.unlink()
print('VM clean complete')
PY
    tart stop macos27 >/dev/null 2>&1 || true
    rm -f /tmp/tart-macos27-qa.log /tmp/tart-macos27-040.log
}
trap cleanup_vm EXIT

echo "[3/5] Running native UI regression gates and v0.3.0 assertions..."
ssh "${SSH_OPTS[@]}" "$REMOTE" "open --env AETHERDISK_QA=1 $AETHERDISK_QA_OWNER/AetherDisk.app --args --qa-root $AETHERDISK_QA_ROOT --qa-page overview"
sleep 2
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/function_gate.py"
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/navigation_gate.py"
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/analysis_gate.py"
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/ui_style_gate.py"

PYTHONPATH="$ROOT_DIR/scripts/qa" python3 - <<'PY'
from vm_helpers import *
import json
out=Path(os.environ['AETHERDISK_QA_OUT'])
checks=[]
def check(name,cond):
    checks.append({'name':name,'passed':bool(cond)})
    print(name,cond,flush=True)
    assert cond,name
launch(page='overview')
s=ax()
check('v0.3.0 ranking sort control visible','ranking-sort' in s)
press('文件数')
s=ax()
check('v0.3.0 ranking sort switches to file count','AXRadioButton |  | 文件数 | 1' in s and ' 文件 |  | 1' in s)
press('已分配')
check('v0.3.0 in-memory hierarchy browse button visible','展开 Media' in s)
press('展开 Media')
s=ax()
check('v0.3.0 in-memory browse shows breadcrumbs and child items','回到扫描根目录' in s and 'cover.png' in s)
press('回到扫描根目录')
s=ax()
check('v0.3.0 breadcrumb resets to root scope','回到扫描根目录' not in s and '展开 Media' in s)
press('nav-suggestions')
s=ax()
check('v0.3.0 suggestion filter controls visible','suggestion-search' in s and 'suggestion-filter' in s and 'suggestion-category' in s)
press('可检查')
s=ax()
check('v0.3.0 suggestion filter narrows to eligible items','Developer/Safe/.build' in s and 'Developer/Source/.build' not in s)
press('全部')
py("from pathlib import Path\nr=Path("+repr(ROOT)+")\n(r/'Documents/growth.data').write_bytes(b'g'*6*1024*1024)")
press('scan');time.sleep(1)
press('nav-changes')
s=ax()
check('v0.3.0 deep comparison toggle visible','comparison-depth' in s)
press('深层目录')
s=ax()
check('v0.3.0 deep comparison mode switches cleanly','Documents' in s)
press('顶层目录')
s=ax()
check('v0.4.0 comparison direction, search and baseline controls visible','comparison-direction' in s and 'comparison-search' in s and 'comparison-baseline' in s)
press('仅增长')
s=ax()
check('v0.4.0 comparison direction filters grown folders','Documents' in s and '+2.0 MiB' in s)
press('仅减少')
s=ax()
check('v0.4.0 comparison direction filters shrunk folders','Restricted' in s and 'Documents' not in s)
press('全部')
py("from pathlib import Path\nr=Path("+repr(ROOT)+")\n(r/'Documents/growth.data').write_bytes(b'g'*4*1024*1024)")
press('nav-projects')
s=ax()
check('v0.5.0 project workspace lens controls and detected projects visible','project-search' in s and 'project-sort' in s and 'Safe' in s)
(out/'v050-ui-gate.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
PY

echo "[4/5] Capturing light and dark appearance screenshots..."
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/capture_release.py" "0.5.0-preview"
rm -rf "$ROOT_DIR/outputs/screenshots/0.5.0-preview"
echo '{"status":"passed"}' > "$AETHERDISK_QA_OUT/summary.json"
echo "All VM QA gates and light/dark appearance captures succeeded!"
