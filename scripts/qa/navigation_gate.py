from vm_helpers import *
OUT=Path('outputs/logs');checks=[]
def check(n,ok):
 checks.append({'name':n,'passed':bool(ok)});print(n,ok,flush=True);(OUT/'vm-navigation-gate.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2));assert ok,n
def dump(n):
 s=ax();(OUT/('ui-'+n+'.txt')).write_text(s);return s
launch()
# History from actual metadata changes, including removed directories.
py("from pathlib import Path\nr=Path("+repr(ROOT)+")\n(r/'Documents/growth.data').write_bytes(b'g'*2*1024*1024)\n(r/'Removed').mkdir(exist_ok=True)\n(r/'Removed/value.data').write_bytes(b'r'*8192)")
press('scan');time.sleep(1)
py("from pathlib import Path\nimport shutil\nr=Path("+repr(ROOT)+")\n(r/'Documents/growth.data').write_bytes(b'g'*4*1024*1024)\nshutil.rmtree(r/'Removed')")
press('scan');time.sleep(1);press('nav-changes');s=dump('history')
check('history includes growth and removed folder','Documents' in s and '+2.0 MiB' in s and 'Removed' in s and '−8.0 KiB' in s)
press('设置与应用更新');s=dump('settings')
check('production updater ready','更新检查已就绪' in s and '自动检查更新' in s and '检查更新…' in s)

if 'AXCheckBox |  | 自动检查更新 | 1' in s:press('自动检查更新')
s=dump('settings-toggle');check('automatic-check preference changes','AXCheckBox |  | 自动检查更新 | 0' in s)
# Actual native directory picker, keyboard path entry and confirmation.
press('选择文件夹');time.sleep(1)
osa('tell application "System Events"\nkeystroke "g" using {command down, shift down}\ndelay 0.3\nkeystroke "'+ROOT+'/Empty"\nkey code 36\nend tell');time.sleep(1)
s=dump('folder-picker')
press('扫描此文件夹');time.sleep(1);press('nav-overview');s=dump('empty-folder')
check('folder chooser scans selected empty folder','~/AetherDisk-Release-QA-20261024/Empty' in s and '0 个文件' in s)
press('扫描上一级');time.sleep(1);s=dump('parent-folder')
check('parent folder navigation','~/AetherDisk-Release-QA-20261024 |' in s)
# Scan the VM home read-only and immediately cancel; do not store a partial history snapshot.
press('个人文件夹');press('停止扫描');time.sleep(1);s=dump('cancel')
check('cancel scan displays explicit partial state','扫描已停止 · 部分结果' in s)
launch(page='overview')
print(json.dumps(checks,ensure_ascii=False))
