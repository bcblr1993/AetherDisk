"""Accept a real signed website update from the prepared, lower-version QA install."""
from vm_helpers import *
from update_snapshot import snapshot
import sys,hashlib
version,build=sys.argv[1:3];prefix=version.replace('.','');out=Path('outputs/logs')
before=snapshot();assert before['version']!=version
(out/(prefix+'-upgrade-before.json')).write_text(json.dumps(before,indent=2))
press('检查更新…')
for _ in range(25):
 time.sleep(1);s=ax()
 if '安装更新' in s and 'AetherDisk '+version in s:break
else:raise RuntimeError('No update offered: '+s[:1800])
(out/(prefix+'-upgrade-offer.txt')).write_text(s)
press('安装更新')
for _ in range(30):
 time.sleep(1);s=ax()
 if '安装并重启应用' in s:break
 if '更新错误' in s:raise RuntimeError(s[:1800])
else:raise RuntimeError('Download did not become installable')
(out/(prefix+'-upgrade-downloaded.txt')).write_text(s)
press('安装并重启应用')
for _ in range(30):
 time.sleep(1)
 try:
  after=snapshot()
  if after['version']==version and 'AXWindow' in ax():break
 except Exception:continue
else:raise RuntimeError('Replacement and relaunch failed')
(out/(prefix+'-upgrade-after.json')).write_text(json.dumps(after,indent=2))
for key in ['snapshot_sha256','protected_source_sha256','installer_sha256','automatic_checks']:assert before[key]==after[key],key
expected=Path('outputs/releases')/(version+'-'+build)/'AetherDisk.app/Contents/MacOS/AetherDisk'
assert after['binary_sha256']==hashlib.sha256(expected.read_bytes()).hexdigest() and after['build']==build
(out/(prefix+'-upgrade-relaunched.txt')).write_text(ax())
press('设置与应用更新');press('检查更新…')
for _ in range(20):
 time.sleep(1);s=ax()
 if '您使用的就是最新版' in s:break
else:raise RuntimeError('No-update result absent')
(out/(prefix+'-no-update.txt')).write_text(s);press('好')
# Only after proving data preservation, explicitly scan again to exercise old history decoding in the real GUI.
launch(page='changes');s=ax();assert '与上次扫描对比' in s and '再扫描一次' not in s
(out/(prefix+'-legacy-history-ui.txt')).write_text(s)
press('nav-types');s=ax();assert '视频' in s and '128 MiB' in s
(out/(prefix+'-updated-types-ui.txt')).write_text(s)
result={'from':before['version'],'to':version,'build':build,'real_install_and_relaunch':True,'binary_matches_release':True,'scan_history_preserved':True,'protected_source_preserved':True,'installer_preserved':True,'automatic_check_preference_preserved':True,'no_update_message':True,'legacy_history_loaded_by_new_app':True,'new_analysis_available_after_upgrade':True}
(out/(prefix+'-upgrade-gate.json')).write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
