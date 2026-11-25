from vm_helpers import *
import shutil, sys

version = sys.argv[1] if len(sys.argv) > 1 else "300-release"
shots = OWNER + '/Screenshots-' + version
remote('rm -rf ' + shlex.quote(shots) + ' && mkdir -p ' + shlex.quote(shots))
py("from pathlib import Path\np=Path(" + repr(ROOT + '/Documents/growth.data') + ")\nprev=p.read_bytes() if p.exists() else b''\np.write_bytes(prev+b'g'*1024*1024)")

CAPTURES = [
    ('smartcare-light', 'smartcare', 'light', False, None),
    ('smartcare-dark', 'smartcare', 'dark', False, None),
    ('bubble-light', 'overview', 'light', False, 'bubble'),
    ('bubble-dark', 'overview', 'dark', False, 'bubble'),
    ('overview-light', 'overview', 'light', False, 'sunburst'),
    ('overview-dark', 'overview', 'dark', False, 'sunburst'),
    ('treemap-light', 'overview', 'light', False, 'treemap'),
    ('treemap-dark', 'overview', 'dark', False, 'treemap'),
    ('columns-light', 'overview', 'light', False, 'columns'),
    ('suggestions-light', 'suggestions', 'light', False, None),
    ('suggestions-dark', 'suggestions', 'dark', False, None),
    ('cloud-light', 'suggestions', 'light', False, None, 'cloudStorage'),
    ('cloud-dark', 'suggestions', 'dark', False, None, 'cloudStorage'),
    ('protection-light', 'protection', 'light', False, None),
    ('protection-dark', 'protection', 'dark', False, None),
    ('confirmation-light', 'suggestions', 'light', True, None),
    ('confirmation-dark', 'suggestions', 'dark', True, None),
    ('large-light', 'large', 'light', False, None),
    ('large-dark', 'large', 'dark', False, None),
    ('clutter-duplicates-light', 'large', 'light', False, None, 'duplicates'),
    ('clutter-duplicates-dark', 'large', 'dark', False, None, 'duplicates'),
    ('applications-light', 'applications', 'light', False, None),
    ('applications-dark', 'applications', 'dark', False, None),
    ('performance-light', 'performance', 'light', False, None),
    ('performance-dark', 'performance', 'dark', False, None),
    ('types-light', 'types', 'light', False, None),
    ('types-dark', 'types', 'dark', False, None),
    ('projects-light', 'projects', 'light', False, None),
    ('changes-light', 'changes', 'light', False, None),
    ('updates-light', 'settings', 'light', False, None),
    ('updates-dark', 'settings', 'dark', False, None),
]

for entry in CAPTURES:
    name, page, appearance, preview = entry[:4]
    view_mode = entry[4] if len(entry) > 4 else None
    subtab = entry[5] if len(entry) > 5 else None
    stop()
    time.sleep(.3)
    args = [
        'open', '--env', 'AETHERDISK_QA=1', OWNER + '/AetherDisk.app', '--args',
        '--qa-root', ROOT, '--qa-page', page, '--appearance', appearance,
        '--qa-output', shots + '/' + name + '.png',
    ]
    if view_mode:
        args += ['--qa-view-mode', view_mode]
    if subtab:
        args += ['--qa-subtab', subtab]
    if preview:
        args += ['--qa-preview']
    remote(' '.join(map(shlex.quote, args)))
    for _ in range(35):
        if remote('test -f ' + shlex.quote(shots + '/' + name + '.png') + ' && echo ready || true') == 'ready':
            break
        time.sleep(.5)
    else:
        raise RuntimeError('Screenshot timeout: ' + name)
    print(name, flush=True)

# Remove temporary .scan.json files before copying clean PNG screenshots
remote('rm -f ' + shlex.quote(shots) + '/*.scan.json')

out = Path('outputs/screenshots') / version
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True, exist_ok=True)
subprocess.run(
    ['scp', '-i', str(Path.home() / '.ssh/id_ed25519'), '-o', 'StrictHostKeyChecking=accept-new', '-r', f'chenxu@{VM_IP}:{shots}/.', str(out)],
    check=True,
)
