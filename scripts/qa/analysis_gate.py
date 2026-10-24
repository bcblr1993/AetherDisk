"""0.2.0 native feature acceptance; only the known macos27 test fixture is modified."""
from vm_helpers import *
OUT=Path('outputs/logs');checks=[]
def check(name,value):
 checks.append({'name':name,'passed':bool(value)});print(name,value,flush=True);(OUT/'020-analysis-gate.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2));assert value,name
def dump(name):
 s=ax();(OUT/('020-ui-'+name+'.txt')).write_text(s);return s
def type_in(identifier,value):
 assert ax('focus',identifier)=='0'
 osa('tell application "System Events"\nkeystroke "a" using command down\n'+('keystroke '+json.dumps(value) if value else 'key code 51')+'\nend tell');time.sleep(.4)
launch(page='large')
s=dump('large-physical');check('deep physical large file appears and sparse file does not','Movie.mp4' in s and '128 MiB' in s and 'virtual.bin' not in s)
type_in('large-search','missing-qa');s=dump('empty-search');check('live path search filters results','没有符合' in s)
type_in('large-search','movie');s=dump('search');check('case-insensitive large-file search','Movie.mp4' in s)
type_in('large-search','')
press('large-basis');press('逻辑大小');s=dump('large-logical');check('logical-size ranking exposes sparse 1 GiB file','virtual.bin' in s and '1.0 GiB' in s)
press('图片');s=dump('category-empty');check('category filter and minimum threshold combine','没有符合' in s)
press('large-minimum');press('1 MiB');s=dump('category-image');check('lower threshold reveals image','cover.png' in s and 'Movie.mp4' not in s)
press('nav-types');s=dump('types');check('file-type usage includes all read files','视频' in s and '128 MiB' in s and '安装包与归档' in s and '文档' in s)
press('1 个路径未能读取');s=dump('issues');check('permission sheet exposes actual unreadable path',ROOT+'/Restricted' in s and '前 50 条' in s);press('完成')
press('设置与应用更新');s=dump('settings')
protect=ROOT+'/Developer/Safe/.build'
# Remove the fixture's previous preview setting first; do not clear unrelated protections.
if 'Developer/Safe/.build' in s:press('移除保护 '+protect)
press('add-protection');osa('tell application "System Events"\nkeystroke "g" using {command down, shift down}\ndelay 0.3\nkeystroke "'+protect+'"\nkey code 36\nend tell');time.sleep(.8);press('保护此目录');press('nav-suggestions')
s=dump('protected');check('native protection folder chooser blocks candidate',s.count('AXCheckBox |  | 选择 .build | 0 |  | 0')==3 and '自定义保护' in s)
launch(page='suggestions');s=dump('protection-restart');check('custom protection survives restart',s.count('AXCheckBox |  | 选择 .build | 0 |  | 0')==3)
press('导出扫描报告');s=dump('save-default');check('report save defaults to Documents','Documents' in s or '文稿' in s)
press('取消');check('export cancellation does not create file',remote('test ! -f '+OWNER+'/disk-report-020-final.csv && echo yes')=='yes')
press('导出扫描报告');osa('tell application "System Events"\nkeystroke "g" using {command down, shift down}\ndelay 0.3\nkeystroke "'+OWNER+'"\nkey code 36\nend tell');time.sleep(.7)
type_in('saveAsNameTextField','disk-report-020-final.csv');press('保存');time.sleep(.8)
verified=py('''from pathlib import Path
import csv,json
p=Path.home()/'Applications/AetherDisk-Release-QA-20261024/disk-report-020-final.csv'
r=list(csv.DictReader(p.open(encoding='utf-8-sig',newline='')))
assert all(len(row)==10 for row in r)
assert any(row['section']=='large_file' and row['name']=='Movie.mp4' for row in r)
assert any(row['section']=='file_type' for row in r) and any(row['section']=='unreadable' for row in r)
assert any(row['path'].endswith('/Developer/Safe/.build') and 'user' in row['protection'] for row in r)
assert r[0]['status']=='partial'
print('valid')
''')
check('CSV export parses correctly and includes protection, types and permission gaps',verified=='valid')
press('设置与应用更新');press('移除保护 '+protect);press('nav-suggestions');s=dump('unprotected')
check('removing custom protection keeps source and installer protected',s.count('AXCheckBox |  | 选择 .build | 0 |  | 0')==2 and s.count('AXCheckBox |  | 选择 .build | 0 |  | 1')==1)
print(json.dumps(checks,ensure_ascii=False))
