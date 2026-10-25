from vm_helpers import *
def snapshot():
 return json.loads(py('''from pathlib import Path
import hashlib,json,plistlib
home=Path.home();root=home/'AetherDisk-Release-QA-20261024'
app=home/'Applications/AetherDisk-Release-QA-20261024/AetherDisk.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
key=hashlib.sha256(str(root).encode()).digest()[:12].hex()
snap=home/'Library/Application Support/AetherDisk/Scans'/(key+'.json')
pref=home/'Library/Preferences/com.aethernative.AetherDisk.plist'
settings=plistlib.loads(pref.read_bytes()) if pref.exists() else {}
print(json.dumps({'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'binary_sha256':hashlib.sha256((app/'Contents/MacOS/AetherDisk').read_bytes()).hexdigest(),'snapshot_sha256':hashlib.sha256(snap.read_bytes()).hexdigest(),'protected_source_sha256':hashlib.sha256((root/'Developer/Source/.build/main.swift').read_bytes()).hexdigest(),'installer_sha256':hashlib.sha256((root/'Developer/Installer/.build/Release.dmg').read_bytes()).hexdigest(),'automatic_checks':settings.get('SUEnableAutomaticChecks'),'protected_paths':settings.get('ProtectedPaths',[])}))
'''))
if __name__=='__main__':print(json.dumps(snapshot(),ensure_ascii=False,indent=2))
