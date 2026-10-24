from vm_helpers import *
import sys
version = sys.argv[1] if len(sys.argv) > 1 else "release"
shots=OWNER+'/Screenshots-'+version;remote('mkdir -p '+shots)
py("from pathlib import Path\np=Path("+repr(ROOT+'/Documents/growth.data')+")\np.write_bytes(p.read_bytes()+b'g'*1024*1024)")
for name,page,appearance,preview in [('large-light','large','light',False),('large-dark','large','dark',False),('types-light','types','light',False),('types-dark','types','dark',False),('changes-light','changes','light',False),('overview-light','overview','light',False),('overview-dark','overview','dark',False),('suggestions-dark','suggestions','dark',False),('confirmation-light','suggestions','light',True),('updates-light','settings','light',False),('confirmation-dark','suggestions','dark',True),('updates-dark','settings','dark',False)]:
 stop();time.sleep(.3)
 args=['open','--env','AETHERDISK_QA=1',OWNER+'/AetherDisk.app','--args','--qa-root',ROOT,'--qa-page',page,'--appearance',appearance,'--qa-output',shots+'/'+name+'.png']
 if preview:args+=['--qa-preview']
 remote(' '.join(map(shlex.quote,args)))
 for _ in range(30):
  if remote('test -f '+shots+'/'+name+'.png && echo ready || true')=='ready':break
  time.sleep(.5)
 else:raise RuntimeError('Screenshot timeout: '+name)
 print(name,flush=True)
out=Path('outputs/screenshots')/version;out.mkdir(exist_ok=True)
subprocess.run(['scp','-i',str(Path.home()/'.ssh/id_ed25519'),'-r','chenxu@192.168.64.21:'+shots+'/.',str(out)],check=True)
