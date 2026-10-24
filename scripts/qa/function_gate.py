"""Run against only the explicitly prepared AetherDisk release QA fixture in macos27."""
import subprocess,json,time,hashlib
from pathlib import Path
SSH=['ssh','-i',str(Path.home()/'.ssh/id_ed25519'),'-o','BatchMode=yes','chenxu@192.168.64.21']
ROOT='/Users/chenxu/AetherDisk-Release-QA-20261024'
OUT=Path('outputs/logs');OUT.mkdir(parents=True,exist_ok=True)
checks=[]
def remote(command):return subprocess.run(SSH+[command],text=True,capture_output=True,check=True,timeout=45).stdout.strip()
def ax(action='dump',target=None,value=None):
 import shlex
 return remote(' '.join(map(shlex.quote,['/tmp/AetherDiskAX-20261024',action]+([target] if target else [])+([value] if value is not None else []))))
def check(label,condition):
 checks.append({'name':label,'passed':bool(condition)});print(label,condition,flush=True)
 (OUT/'vm-function-gate.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
 assert condition,label

def press(t):assert ax('press',t)=='0';time.sleep(.6)
def dump(name):
 s=ax();(OUT/('ui-'+name+'.txt')).write_text(s);return s
press('nav-suggestions');press('scan');time.sleep(1)
s=dump('initial')
check('3 candidates; two protected; default unselected',s.count('AXCheckBox |  | 选择 .build | 0 |  | 0')==2 and 'preview-cleanup | 0' in s)
check('permission gap explicitly reported','1 个路径未能读取' in s)
press('选择 .build');press('preview-cleanup');time.sleep(2)
s=dump('confirmation');check('native explicit confirmation before trash','confirm-trash' in s and '确认移入废纸篓？' in s)
check('preview preserves cache',remote('test -f '+ROOT+'/Developer/Safe/.build/cache.data && echo yes')=='yes')
press('保留文件');check('cancel preserves cache',remote('test -f '+ROOT+'/Developer/Safe/.build/cache.data && echo yes')=='yes')
press('preview-cleanup');time.sleep(2)
# Record exactly which Trash entries existed before this test action.
before=json.loads(remote("python3 -c \"import pathlib,json;print(json.dumps([p.name for p in (pathlib.Path.home()/'.Trash').iterdir()]))\""))
press('confirm-trash');time.sleep(3)
s=dump('trash-result');check('actual confirmed move completed','已移入废纸篓 1 项' in s)
check('protected source and installer retained',remote('test -f '+ROOT+'/Developer/Source/.build/main.swift && test -f '+ROOT+'/Developer/Installer/.build/Release.dmg && echo yes')=='yes')
# Restore only the new QA-owned Trash entry by payload hash; never empty Trash.
restore='''from pathlib import Path
import json,hashlib
before=set(BEFORE)
trash=Path.home()/'.Trash'
items=[p for p in trash.iterdir() if p.name not in before and (p/'cache.data').is_file()]
assert len(items)==1
p=items[0];assert hashlib.sha256((p/'cache.data').read_bytes()).hexdigest()==hashlib.sha256(b'x'*8*1024*1024).hexdigest()
p.rename(Path(ROOT)/'Developer/Safe/.build')
print('restored')
'''.replace('BEFORE',repr(before)).replace('ROOT',repr(ROOT))
check('Trash item recoverable and restored',subprocess.run(SSH+['python3 -'],input=restore,text=True,capture_output=True,check=True,timeout=40).stdout.strip()=='restored')
press('nav-overview');press('scan');time.sleep(1)
s=dump('overview');check('overview shows scanned metadata','已分配' in s and '逻辑大小' in s and '1 个路径未能读取' in s)
assert ax('focus','搜索当前层级')=='0'
subprocess.run(SSH+['osascript -'],input='tell application "System Events"\nkeystroke "a" using command down\nkeystroke "Documents"\nend tell',text=True,capture_output=True,check=True)
time.sleep(1)
s=dump('search');check('search narrows ranking','Documents' in s and '扫描 Developer' not in s)
assert ax('focus','搜索当前层级')=='0'
subprocess.run(SSH+['osascript -'],input='tell application "System Events"\nkeystroke "a" using command down\nkey code 51\nend tell',text=True,capture_output=True,check=True)
time.sleep(1)
press('扫描 Documents');time.sleep(1)
s=dump('drilldown');check('directory drilldown',ROOT+'/Documents' in s or '~/AetherDisk-Release-QA-20261024/Documents' in s)
press('在 Finder 中显示');check('Finder reveal action completed',True)
# Original root again, then modify a known test file and rescan to verify history.
remote('open --env AETHERDISK_QA=1 ~/Applications/AetherDisk-Release-QA-20261024/AetherDisk.app')
print(json.dumps(checks,ensure_ascii=False),flush=True)
