#!/usr/bin/env python3
"""Run the actual Gdev main entry through Pen; never invoked automatically."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PEN = ROOT.parent / 'pen/target/release/pen'
PROJECT = ROOT.parent / 'gdev'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--launch', action='store_true', help='Launch after the candidate builds successfully.')
parser.add_argument('--output', type=Path, help='New output directory; default is a unique attempt directory beside this script.')
parser.add_argument('--compiled-main', type=Path, help='Load a previously built actual main through Pen bundle mode, without recompiling.')
parser.add_argument('--expected-wasm-sha256', help='Required with --compiled-main: the reviewed build artifact hash.')
args = parser.parse_args()
if bool(args.compiled_main) != bool(args.expected_wasm_sha256):
    parser.error('--compiled-main and --expected-wasm-sha256 must be supplied together')
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
# The onboarding sysroot is optional; respect explicit driver selection.
sysroot = ROOT.parent / '.dev-tools/sysroot'
mesa = sysroot / 'usr/share/vulkan/icd.d/lvp_icd.json'
if mesa.exists() and not env.get('VK_DRIVER_FILES') and not env.get('VK_ICD_FILENAMES'):
    libraries = str(sysroot / 'usr/lib/x86_64-linux-gnu')
    env['VK_DRIVER_FILES'] = str(mesa)
    env['LD_LIBRARY_PATH'] = os.pathsep.join(filter(None, [libraries, env.get('LD_LIBRARY_PATH')]))
if not env.get('XDG_RUNTIME_DIR'):
    runtime = OUT / 'xdg-runtime'
    runtime.mkdir(mode=0o700)
    env['XDG_RUNTIME_DIR'] = str(runtime)
project_config = json.loads((PROJECT / 'pen.json').read_text())
compiled = None
if args.compiled_main:
    source = args.compiled_main.resolve()
    expected = args.expected_wasm_sha256.lower()
    if not re.fullmatch('[0-9a-f]{64}', expected):
        parser.error('--expected-wasm-sha256 must contain 64 hexadecimal digits')
    if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
        raise SystemExit('Compiled main does not match its reviewed SHA-256; preserving existing artifacts.')
    bundle = OUT / 'game'
    bundle.mkdir()
    compiled = bundle / 'game.wasm'
    shutil.copy2(source, compiled)
    if hashlib.sha256(compiled.read_bytes()).hexdigest() != expected:
        raise SystemExit('Compiled main copy does not match its reviewed SHA-256.')
    game = project_config.get('game', {})
    name = game.get('name', PROJECT.name)
    (bundle / 'game.json').write_text(json.dumps({
        'name': name, 'title': game.get('title', name), 'players': game.get('players', 1)
    }, indent=2) + '\n')
    if (PROJECT / 'src/main.scene').is_file():
        shutil.copy2(PROJECT / 'src/main.scene', bundle / 'main.scene')
    # Keep the source assets' lexical parent: it also supplies text/locales/presets.
    command = [str(PEN), '--game', str(bundle), '--assets', str(PROJECT / 'src/assets')]
else:
    command = [str(PEN), 'run', '--project', str(PROJECT)]
command += ['--headless', '--software', '--mute',
           '--frames', '1', '--fps', '60', '--size', '640x480', '--data', str(data),
           '--trace', str(OUT / 'frames.trace'), '--screenshot', str(OUT / 'frame.png')]
identity = {'pen_sha256': hashlib.sha256(PEN.read_bytes()).hexdigest(), 'command': command,
            'entry': 'src/main.blot:main', 'project': str(PROJECT)}
compiler = (PROJECT / project_config['plugins']['blot']['run']['blotc']).resolve()
identity.update(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                storage=project_config['compiler']['settings']['storage'],
                compile_invoked=compiled is None,
                graphics_environment={name: env[name] for name in (
                    'VK_DRIVER_FILES', 'VK_ICD_FILENAMES', 'LD_LIBRARY_PATH',
                    'XDG_RUNTIME_DIR', 'PEN_GRAPHICS_TIER') if name in env})
if compiled:
    identity.update(compiled_main_source=str(source), wasm_sha256=expected,
                    scene_sha256=hashlib.sha256((bundle / 'main.scene').read_bytes()).hexdigest()
                    if (bundle / 'main.scene').is_file() else None,
                    assets=str(PROJECT / 'src/assets'))
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
unchanged = compiled is None or hashlib.sha256(compiled.read_bytes()).hexdigest() == expected
report = dict(identity, returncode=result.returncode, checks=checks,
              compiled_wasm_unchanged=unchanged, success=all(checks.values()) and unchanged)
(OUT / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
raise SystemExit(0 if report['success'] else 1)
