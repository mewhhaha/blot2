#!/usr/bin/env python3
"""Run the actual Gdev main entry through Pen; never invoked automatically."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PEN = ROOT.parent / 'pen/target/release/pen'
PROJECT = ROOT.parent / 'gdev'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--launch', action='store_true', help='Launch after the candidate builds successfully.')
parser.add_argument('--output', type=Path, help='New output directory; default is a unique attempt directory beside this script.')
args = parser.parse_args()
if not args.launch:
    raise SystemExit('Prepared only. Run with --launch after the candidate builds successfully.')
if args.output is None:
    parent = ROOT / 'build/storage-integration/gdev-one-frame'
    parent.mkdir(parents=True, exist_ok=True)
    OUT = Path(tempfile.mkdtemp(prefix='attempt-', dir=parent))
else:
    OUT = args.output.resolve()
    OUT.mkdir(parents=True, exist_ok=False)
print(f'Artifacts: {OUT}', flush=True)
# A fresh process must start without a player save or stale completion artifacts.
data = OUT / 'data'
if data.exists():
    raise SystemExit('Use a fresh artifact directory: data already exists; preserving previous evidence.')
for name in ('frame.png', 'frames.trace', 'run.log', 'result.json'):
    if (OUT / name).exists():
        raise SystemExit(f'Preserving previous evidence: {name} already exists.')
env = dict(os.environ)
for name in ('PEN_PROFILE_FRAMES', 'PEN_PROFILE_WARMUP', 'PEN_SMOKE_FRAMES', 'PEN_OVERLAY', 'PEN_CRASH_TEST'):
    env.pop(name, None)
env.update(PEN_STARTUP='1', PEN_FRAME_TIMES='1', PEN_REPORTS='off', WGPU_BACKEND='vulkan')
# Preserve an explicitly configured Vulkan driver; use Chrome's SwiftShader
# only when this machine has it and the caller has not selected a driver.
swiftshader = Path('/opt/google/chrome/vk_swiftshader_icd.json')
if swiftshader.exists() and not env.get('VK_DRIVER_FILES') and not env.get('VK_ICD_FILENAMES'):
    env.update(VK_DRIVER_FILES=str(swiftshader), VK_ICD_FILENAMES=str(swiftshader))
command = [str(PEN), 'run', '--project', str(PROJECT), '--headless', '--software', '--mute',
           '--frames', '1', '--fps', '60', '--size', '640x480', '--data', str(data),
           '--trace', str(OUT / 'frames.trace'), '--screenshot', str(OUT / 'frame.png')]
identity = {'pen_sha256': hashlib.sha256(PEN.read_bytes()).hexdigest(), 'command': command,
            'entry': 'src/main.blot:main', 'project': str(PROJECT)}
project_config = json.loads((PROJECT / 'pen.json').read_text())
compiler = (PROJECT / project_config['plugins']['blot']['run']['blotc']).resolve()
identity.update(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                storage=project_config['compiler']['settings']['storage'])
(OUT / 'command.json').write_text(json.dumps(identity, indent=2) + '\n')
with (OUT / 'run.log').open('wb') as log:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
text = (OUT / 'run.log').read_text(errors='replace')
trace = (OUT / 'frames.trace').read_text().splitlines() if (OUT / 'frames.trace').exists() else []
png = (OUT / 'frame.png').read_bytes() if (OUT / 'frame.png').exists() else b''
checks = {'exit_zero': result.returncode == 0,
          'one_completed_guest_trace': len(trace) == 1 and re.fullmatch(r'\d+ [0-9a-f]{16} [0-9a-f]{16}', trace[0]) is not None,
          'one_headless_step': 'headless: 1 frames ' in text,
          'first_guest_frame': "startup: game's first frame " in text,
          'complete_render': 'startup: first complete frame ' in text,
          'screenshot_640x480': png[:8] == b'\x89PNG\r\n\x1a\n' and len(png) >= 24 and int.from_bytes(png[16:20], 'big') == 640 and int.from_bytes(png[20:24], 'big') == 480}
report = dict(identity, returncode=result.returncode, checks=checks, success=all(checks.values()))
(OUT / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
raise SystemExit(0 if report['success'] else 1)
