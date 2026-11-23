#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if ! tart list | awk '$2=="macos27" && $NF=="running"{found=1} END{exit !found}'; then
  nohup tart run macos27 >/tmp/tart-macos27-qa.log 2>&1 &
  sleep 8
fi
export AETHERDISK_VM_IP="${AETHERDISK_VM_IP:-$(tart ip --wait 30 macos27)}"
export AETHERDISK_QA_ROOT="/Users/chenxu/AetherDisk-Release-QA-20261123"
export AETHERDISK_QA_OWNER="/Users/chenxu/Applications/AetherDisk-Release-QA-20261123"
export AETHERDISK_AX_BIN="/tmp/AetherDiskAX-20261123"
export AETHERDISK_QA_OUT="$ROOT_DIR/outputs/qa-200"
rm -rf "$AETHERDISK_QA_OUT"
mkdir -p "$AETHERDISK_QA_OUT"

SSH_OPTS=(-i "$HOME/.ssh/id_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="chenxu@$AETHERDISK_VM_IP"

echo "[1/6] Preparing isolated QA fixture on $REMOTE..."
ssh "${SSH_OPTS[@]}" "$REMOTE" "AETHERDISK_QA_ROOT='$AETHERDISK_QA_ROOT' AETHERDISK_QA_OWNER='$AETHERDISK_QA_OWNER' python3 -" <<'PY'
import os, shutil, signal, subprocess, time
from pathlib import Path

root = Path(os.environ['AETHERDISK_QA_ROOT'])
owner = Path(os.environ['AETHERDISK_QA_OWNER'])
owner_str = str(owner)

def kill_qa_apps():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = []
        for row in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
            parts = row.strip().split(None, 1)
            if len(parts) == 2 and parts[1].startswith(owner_str + '/') and parts[1].endswith('/Contents/MacOS/AetherDisk'):
                pids.append(int(parts[0]))
        if not pids:
            break
        for pid in pids:
            try: os.kill(pid, sig)
            except Exception: pass
        time.sleep(0.5)

kill_qa_apps()
saved_state = Path.home() / 'Library/Saved Application State/com.aethernative.AetherDisk.savedState'
if saved_state.exists():
    shutil.rmtree(saved_state, ignore_errors=True)
if root.exists():
    for p in root.rglob('*'):
        try: p.chmod(0o700)
        except Exception: pass
    shutil.rmtree(root)
if owner.exists():
    shutil.rmtree(owner)
root.mkdir(parents=True)
owner.mkdir(parents=True)

prefs = Path.home() / 'Library/Preferences/com.aethernative.AetherDisk.plist'
if prefs.exists():
    (owner / 'preferences-before.plist').write_bytes(prefs.read_bytes())

for name in ['Safe', 'Source', 'Installer']:
    p = root / 'Developer' / name
    p.mkdir(parents=True)
    (p / 'Package.swift').write_text('// QA project marker')
    (p / '.build').mkdir()
(root / 'Developer/Safe/.build/cache.data').write_bytes(b'x' * 8 * 1024 * 1024)
(root / 'Developer/Source/.build/main.swift').write_text('// protected source')
(root / 'Developer/Installer/.build/Release.dmg').write_bytes(b'i' * 8192)

for name in ['Documents', 'Empty', 'Restricted', '.hidden', 'Media/deep/hub', 'Downloads', 'Sparse']:
    (root / name).mkdir(parents=True)
(root / 'Documents/report.data').write_bytes(b'd' * 16384)
(root / 'Documents/notes.pdf').write_bytes(b'd' * 3 * 1024 * 1024)
(root / 'Documents/notes-copy.pdf').write_bytes(b'd' * 3 * 1024 * 1024)
(root / 'Restricted/data').write_bytes(b'r' * 4096)
(root / 'Restricted').chmod(0)
(root / '.hidden/cache.data').write_bytes(b'h' * 8192)
(root / 'outside-link').symlink_to('/Applications')
(root / 'Media/deep/hub/Movie.mp4').write_bytes(b'm' * 128 * 1024 * 1024)
(root / 'Media/cover.png').write_bytes(b'p' * 2 * 1024 * 1024)
(root / 'Downloads/Release.dmg').write_bytes(b'i' * 32 * 1024 * 1024)
with (root / 'Sparse/virtual.bin').open('wb') as f:
    f.truncate(1024 * 1024 * 1024)
print('Fixture ready')
PY

echo "[2/6] Copying AetherDisk.app and compiling AXDriver..."
scp "${SSH_OPTS[@]}" -r "$ROOT_DIR/outputs/AetherDisk.app" "$REMOTE:$AETHERDISK_QA_OWNER/AetherDisk.app"
scp "${SSH_OPTS[@]}" "$ROOT_DIR/scripts/qa/AXDriver.swift" "$REMOTE:/tmp/AXDriver-20261123.swift"
ssh "${SSH_OPTS[@]}" "$REMOTE" "swiftc /tmp/AXDriver-20261123.swift -o $AETHERDISK_AX_BIN && rm -f /tmp/AXDriver-20261123.swift"

cleanup_vm() {
    echo "[6/6] Restoring VM state and removing only test-owned paths..."
    ssh "${SSH_OPTS[@]}" "$REMOTE" "AETHERDISK_QA_ROOT='$AETHERDISK_QA_ROOT' AETHERDISK_QA_OWNER='$AETHERDISK_QA_OWNER' AETHERDISK_AX_BIN='$AETHERDISK_AX_BIN' python3 -" <<'PY' || true
import hashlib, os, shutil, signal, subprocess, time
from pathlib import Path

owner = os.environ['AETHERDISK_QA_OWNER']
root = Path(os.environ['AETHERDISK_QA_ROOT'])
ax = Path(os.environ['AETHERDISK_AX_BIN'])

for sig in (signal.SIGTERM, signal.SIGKILL):
    pids = []
    for row in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
        parts = row.strip().split(None, 1)
        if len(parts) == 2 and parts[1].startswith(owner + '/') and parts[1].endswith('/Contents/MacOS/AetherDisk'):
            pids.append(int(parts[0]))
    if not pids:
        break
    for pid in pids:
        try: os.kill(pid, sig)
        except Exception: pass
    time.sleep(0.5)

saved_state = Path.home() / 'Library/Saved Application State/com.aethernative.AetherDisk.savedState'
if saved_state.exists():
    shutil.rmtree(saved_state, ignore_errors=True)

prefs = Path.home() / 'Library/Preferences/com.aethernative.AetherDisk.plist'
backup = Path(owner) / 'preferences-before.plist'
if backup.exists():
    prefs.write_bytes(backup.read_bytes())
elif prefs.exists():
    prefs.unlink()

for target in [str(root), str(root / 'Documents'), str(root / 'Empty'), str(root / 'Media')]:
    prefix = hashlib.sha256(target.encode()).digest()[:12].hex()
    for suffix in ['.json', '-history.json']:
        snap = Path.home() / 'Library/Application Support/AetherDisk/Scans' / (prefix + suffix)
        if snap.exists():
            snap.unlink()

if root.exists():
    for p in root.rglob('*'):
        try: p.chmod(0o700)
        except Exception: pass
    shutil.rmtree(root)
if Path(owner).exists():
    shutil.rmtree(owner)
if ax.exists():
    ax.unlink()
print('VM clean complete')
PY
    tart stop macos27 >/dev/null 2>&1 || true
    rm -f /tmp/tart-macos27-qa.log /tmp/tart-macos27-040.log
}
trap cleanup_vm EXIT

echo "[3/6] Running existing native UI regression gates..."
ssh "${SSH_OPTS[@]}" "$REMOTE" "for _ in 1 2 3 4 5; do pgrep -f '$AETHERDISK_QA_OWNER/AetherDisk.app/Contents/MacOS/AetherDisk' >/dev/null || break; pkill -f '$AETHERDISK_QA_OWNER/AetherDisk.app/Contents/MacOS/AetherDisk' >/dev/null 2>&1 || true; sleep 0.5; done; open --env AETHERDISK_QA=1 $AETHERDISK_QA_OWNER/AetherDisk.app --args --qa-root $AETHERDISK_QA_ROOT --qa-page overview"
sleep 2
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/function_gate.py"
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/navigation_gate.py"
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/analysis_gate.py"
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/ui_style_gate.py"

echo "[4/6] Running v0.5.0 regression & v2.0.0 native UI gate..."
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 - <<'PY'
from vm_helpers import *
import json

out = Path(os.environ['AETHERDISK_QA_OUT'])

# 1) v0.3-v0.5 baseline UI regression checks
v050_checks = []
def check050(name, cond):
    v050_checks.append({'name': name, 'passed': bool(cond)})
    (out / 'v050-ui-gate.json').write_text(json.dumps(v050_checks, ensure_ascii=False, indent=2))
    print(name, cond, flush=True)
    assert cond, name

launch(page='overview')
s = ax()
check050('v0.3.0 ranking sort control visible', 'ranking-sort' in s)
press('文件数')
s = ax()
check050('v0.3.0 ranking sort switches to file count', 'AXRadioButton |  | 文件数 | 1' in s and ' 文件 |  | 1' in s)
press('已分配')
check050('v0.3.0 in-memory hierarchy browse button visible', '展开 Media' in s)
press('展开 Media')
s = ax()
check050('v0.3.0 in-memory browse shows breadcrumbs and child items', '回到扫描根目录' in s and 'cover.png' in s)
press('回到扫描根目录')
s = ax()
check050('v0.3.0 breadcrumb resets to root scope', '回到扫描根目录' not in s and '展开 Media' in s)

press('nav-suggestions')
s = ax()
check050('v0.3.0 suggestion filter controls visible', 'suggestion-search' in s and 'suggestion-filter' in s and 'suggestion-category' in s)
press('可检查')
s = ax()
check050('v0.3.0 suggestion filter narrows to eligible items', 'Developer/Safe/.build' in s and 'Developer/Source/.build' not in s)
press('全部')

py("from pathlib import Path\nr=Path(" + repr(ROOT) + ")\n(r/'Documents/growth.data').write_bytes(b'g'*6*1024*1024)")
press('scan')
time.sleep(1)
press('nav-changes')
s = ax()
check050('v0.3.0 deep comparison toggle visible', 'comparison-depth' in s)
press('深层目录')
s = ax()
check050('v0.3.0 deep comparison mode switches cleanly', 'Documents' in s)
press('顶层目录')
s = ax()
check050('v0.4.0 comparison direction, search and baseline controls visible', 'comparison-direction' in s and 'comparison-search' in s and 'comparison-baseline' in s)
press('仅增长')
s = ax()
check050('v0.4.0 comparison direction filters grown folders', 'Documents' in s and '+2.0 MiB' in s)
press('仅减少')
s = ax()
(out / 'v050-ui-shrunk.txt').write_text(s)
check050('v0.4.0 comparison direction filters shrunk folders',
         'Restricted' in s and '−4.0 KiB' in s and 'AXStaticText |  |  | Documents |' not in s)
press('全部')
py("from pathlib import Path\nr=Path(" + repr(ROOT) + ")\n(r/'Documents/growth.data').write_bytes(b'g'*4*1024*1024)")

press('nav-projects')
s = ax()
check050('v0.5.0 project workspace lens controls and detected projects visible', 'project-search' in s and 'project-sort' in s and 'Safe' in s)

# 2) v2.0.0 native UI gate
v200_checks = []
def check200(name, cond):
    v200_checks.append({'name': name, 'passed': bool(cond)})
    (out / 'v200-ui-gate.json').write_text(json.dumps(v200_checks, ensure_ascii=False, indent=2))
    print(name, cond, flush=True)
    assert cond, name

def dump200(name):
    s = ax()
    (out / ('v200-ui-' + name + '.txt')).write_text(s)
    return s

launch(page='overview')
s = dump200('overview-sunburst')
check200('v2.0.0 overview-visual-mode & visual-color-mode & volume-switcher visible',
         'overview-visual-mode' in s and 'visual-color-mode' in s and 'volume-switcher' in s)
check200('v2.0.0 sunburst-canvas visible by default', 'sunburst-canvas' in s)

press('树状图')
s = dump200('overview-treemap')
check200('v2.0.0 visual mode switches to treemap-canvas', 'treemap-canvas' in s)

press('分栏树')
s = dump200('overview-columns')
check200('v2.0.0 visual mode switches to miller-columns', 'miller-columns' in s)

press('占比条')
s = dump200('overview-bar')
check200('v2.0.0 visual mode switches to space-map', 'space-map' in s)

press('旭日图')
s = dump200('overview-back-sunburst')
check200('v2.0.0 visual mode switches back to sunburst-canvas', 'sunburst-canvas' in s)

press('apfs-snapshots-button')
s = dump200('apfs-snapshots')
check200('v2.0.0 APFS snapshots sheet opens with read-only notice',
         'AXSheet' in s and '只读' in s and ('绝不删除' in s or '不会自动删除' in s))
press('完成')
s = ax()
check200('v2.0.0 APFS snapshots sheet closes cleanly', 'AXSheet' not in s)

press('nav-large')
s = dump200('large-default')
check200('v2.0.0 large-duplicates-toggle visible', 'large-duplicates-toggle' in s)
press('large-duplicates-toggle')
s = dump200('large-duplicates')
check200('v2.0.0 large-duplicates-toggle reveals metadata-only duplicate clues',
         '疑似重复大文件线索' in s and '绝不读取文件内容' in s and 'notes.pdf' in s and 'notes-copy.pdf' in s)
press('large-duplicates-toggle')

press('nav-changes')
s = dump200('changes')
check200('v2.0.0 changes page displays comparison and snapshot-trend-chart',
         '与上次扫描对比' in s and 'snapshot-trend-chart' in s)

press('设置与应用更新')
s = dump200('settings')
check200('v2.0.0 settings displays scan-profile-picker', 'scan-profile-picker' in s)
press('节能低 I/O')
s = dump200('settings-eco')
check200('v2.0.0 scan-profile-picker switches to eco',
         'AXRadioButton |  | 节能低 I/O | 1' in s and '单线程 + 系统磁盘限流' in s)
press('均衡并发')
s = dump200('settings-balanced')
check200('v2.0.0 scan-profile-picker switches back to balanced',
         'AXRadioButton |  | 均衡并发 | 1' in s)
PY

echo "[5/6] Capturing light and dark appearance 2.0.0 screenshots..."
PYTHONPATH="$ROOT_DIR/scripts/qa" python3 "$ROOT_DIR/scripts/qa/capture_release.py" "200-release"
echo '{"status":"passed"}' > "$AETHERDISK_QA_OUT/summary.json"
echo "All VM QA gates and 2.0.0 light/dark appearance captures succeeded!"
