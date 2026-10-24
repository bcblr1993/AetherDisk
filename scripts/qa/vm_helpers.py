import subprocess,json,time,shlex
from pathlib import Path
SSH=['ssh','-i',str(Path.home()/'.ssh/id_ed25519'),'-o','BatchMode=yes','chenxu@192.168.64.21']
OWNER='/Users/chenxu/Applications/AetherDisk-Release-QA-20261024'
ROOT='/Users/chenxu/AetherDisk-Release-QA-20261024'
def remote(command):return subprocess.run(SSH+[command],text=True,capture_output=True,check=True,timeout=55).stdout.strip()
def py(source):return subprocess.run(SSH+['python3 -'],input=source,text=True,capture_output=True,check=True,timeout=55).stdout.strip()
def ax(action='dump',target=None):return remote(' '.join(map(shlex.quote,['/tmp/AetherDiskAX-20261024',action]+([target] if target else []))))
def stop():
 return py('''import subprocess,os,signal
for row in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
 parts=row.strip().split(None,1)
 if len(parts)==2 and parts[1].startswith(OWNER+'/') and parts[1].endswith('/Contents/MacOS/AetherDisk'):
  os.kill(int(parts[0]),signal.SIGTERM)
'''.replace('OWNER',repr(OWNER)))
def launch(app='AetherDisk.app',page='overview',shot=None):
 stop();time.sleep(.5)
 args=['open','--env','AETHERDISK_QA=1',OWNER+'/'+app,'--args','--qa-root',ROOT,'--qa-page',page]
 if shot:args+=['--qa-output',shot]
 remote(' '.join(map(shlex.quote,args)));time.sleep(2)
def press(target):
 result=ax('press',target)
 assert result=='0' or (result=='-25204' and target in ['选择文件夹','检查更新…','安装并重启应用']),(target,result)
 time.sleep(.7)
def osa(source):return subprocess.run(SSH+['osascript -'],input=source,text=True,capture_output=True,check=True,timeout=55).stdout.strip()
