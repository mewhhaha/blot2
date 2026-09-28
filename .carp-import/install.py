#!/usr/bin/env python3
"""One-shot, checksum-locked transport of the locally validated Carp source.

This script creates Git objects, never updates refs. The authorized connector
advances the PR only after the exact staged tree/parent have been inspected.
The import files and workflow do not exist in the staged final tree.
"""
import base64
import hashlib
import json
import lzma
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path.cwd()
IMPORT = ROOT / '.carp-import'
CONFIG = json.loads((IMPORT / 'manifest.json').read_text())
REPO = 'mewhhaha/blot2'
BRANCH = 'experiment/carp-compiler'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args]).decode().strip()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_generated():
    path = ROOT / 'compiler/carp/port/generated/manifest.json'
    require(sha(path.read_bytes()) == CONFIG['generated_manifest_sha256'],
            'regenerated manifest differs from the locally verified source')
    manifest = json.loads(path.read_text())
    for name, expected in manifest['files'].items():
        require(Path(name).name == name, 'invalid generated file path')
        require(sha((path.parent/name).read_bytes()) == expected,
                'generated file differs: '+name)


def api(method, endpoint, data=None):
    payload = None if data is None else json.dumps(data).encode()
    request = urllib.request.Request(
        'https://api.github.com/repos/'+REPO+'/'+endpoint, data=payload,
        method=method, headers={
            'Authorization': 'Bearer '+os.environ['GH_TOKEN'],
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'Content-Type': 'application/json',
        })
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            retry = error.headers.get('Retry-After')
            if attempt == 3 or not (error.code in (429, 502, 503, 504) or retry):
                raise RuntimeError(f'GitHub {method} {endpoint}: HTTP {error.code}') from None
            time.sleep(int(retry) if retry else 2**(attempt+1))
    raise AssertionError('unreachable')


def apply():
    subprocess.run(['git', 'merge-base', '--is-ancestor', CONFIG['base_commit'], 'HEAD'], check=True)
    subprocess.run(['git', 'diff', '--quiet', CONFIG['base_commit'], 'HEAD', '--', '.',
                    ':(exclude).carp-import/**', ':(exclude).github/workflows/carp-import.yml'], check=True)
    packed = b''.join((IMPORT/name).read_bytes() for name in CONFIG['parts'])
    require(sha(packed) == CONFIG['compressed_sha256'], 'compressed patch checksum mismatch')
    decoder = lzma.LZMADecompressor(memlimit=256*1024*1024)
    patch = decoder.decompress(packed, max_length=CONFIG['patch_bytes']+1)
    require(decoder.eof and not decoder.unused_data and len(patch) == CONFIG['patch_bytes'],
            'invalid compressed patch length')
    require(sha(patch) == CONFIG['patch_sha256'], 'source patch checksum mismatch')
    subprocess.run(['git', 'apply', '--check', '-'], input=patch, check=True)
    subprocess.run(['git', 'apply', '-'], input=patch, check=True)
    print('Verified and applied authored source patch.')


def stage():
    require(os.environ.get('GITHUB_REPOSITORY') == REPO, 'unexpected repository')
    require(os.environ.get('GITHUB_REF') == 'refs/heads/'+BRANCH, 'unexpected branch')
    parent = os.environ['EXPECTED_HEAD']
    require(git('rev-parse', 'HEAD') == parent, 'checkout does not match expected head')
    require(api('GET', 'git/ref/heads/'+BRANCH)['object']['sha'] == parent,
            'PR branch moved; refusing to stage against stale input')
    verify_generated()
    shutil.rmtree(IMPORT)
    (ROOT/'.github/workflows/carp-import.yml').unlink()
    subprocess.run(['git', 'add', '-A'], check=True)
    local_tree = git('write-tree')
    require(local_tree == CONFIG['final_tree'], 'final local tree differs from validated source')
    records = subprocess.check_output(['git', 'diff', '--cached', '--name-status', '-z', '--no-renames']).split(b'\0')
    entries = []
    for i in range(0, len(records)-1, 2):
        status, name = records[i].decode(), records[i+1].decode()
        if status == 'D':
            entries.append({'path': name, 'mode': '100644', 'type': 'blob', 'sha': None})
            continue
        require(status in ('A', 'M', 'T'), 'unexpected diff status')
        metadata = subprocess.check_output(['git', 'ls-files', '--stage', '--', name]).split(b'\t')[0].split()
        mode, expected_blob = metadata[0].decode(), metadata[1].decode()
        require(mode in ('100644', '100755'), 'unexpected file mode')
        contents = (ROOT/name).read_bytes()
        blob = api('POST', 'git/blobs', {'content': base64.b64encode(contents).decode(), 'encoding': 'base64'})['sha']
        require(blob == expected_blob, 'uploaded blob does not match the index')
        entries.append({'path': name, 'mode': mode, 'type': 'blob', 'sha': blob})
        print('Staged '+name, flush=True)
        # Keep content-generating requests below the documented secondary limit.
        time.sleep(0.9)
    base_tree = api('GET', 'git/commits/'+parent)['tree']['sha']
    tree = api('POST', 'git/trees', {'base_tree': base_tree, 'tree': entries})['sha']
    require(tree == local_tree, 'uploaded tree differs from the local index')
    commit = api('POST', 'git/commits', {
        'message': 'Port full compiler semantics to Carp and reduce allocation and rebuild overhead',
        'tree': tree, 'parents': [parent],
    })['sha']
    output = {'repository': REPO, 'branch': BRANCH, 'parent': parent, 'tree': tree,
              'commit': commit, 'source_patch_sha256': CONFIG['patch_sha256']}
    (Path(os.environ['RUNNER_TEMP'])/'carp-import-commit.json').write_text(json.dumps(output, indent=2)+'\n')
    print(json.dumps(output, indent=2))


if sys.argv[1:] == ['apply']:
    apply()
elif sys.argv[1:] == ['vendor']:
    require(sha((ROOT/'compiler/carp/port/vendor/acorn.cjs').read_bytes()) == CONFIG['vendor_sha256'],
            'Acorn source checksum mismatch')
elif sys.argv[1:] == ['generated']:
    verify_generated()
elif sys.argv[1:] == ['stage']:
    stage()
else:
    raise SystemExit('usage: install.py apply|vendor|generated|stage')
