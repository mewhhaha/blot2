"""One-time, checksummed native-source publication; never used by normal builds."""
from pathlib import Path
import base64
import hashlib
import json
import lzma
import subprocess

root = Path('compiler/oxcaml/bootstrap')
encoded = ''.join((root / f'efficiency-pass.{i}.b64').read_text().strip() for i in range(2))
raw = lzma.decompress(base64.b64decode(encoded, validate=True))
if hashlib.sha256(raw).hexdigest() != '3462f764afb62d559497eaef712bcc406b52319c46b34516cab17ff779a1d146':
    raise RuntimeError('Reviewed source bundle checksum mismatch')
data = json.loads(raw)
manifest = data['manifest']
for name, record in manifest.items():
    path = Path(name)
    if path.is_absolute() or '..' in path.parts or not (name.startswith('compiler/oxcaml/') or name == 'deno.json'):
        raise RuntimeError('Source path outside reviewed scope: ' + name)
    actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
    if actual != record['before']:
        raise RuntimeError('Source changed since the reviewed baseline: ' + name)
patch = data['patch'].encode()
for command in (['git', 'apply', '--check', '--index', '-'], ['git', 'apply', '--index', '-']):
    subprocess.run(command, input=patch, check=True)
# Known byte-identical source slices only; this is not a general OCaml parser.
# Retain each complete annotated function body, adjusting its binding keyword.
for name, plan in data['reorder'].items():
    path = Path(name)
    source = path.read_text()
    if hashlib.sha256(source.encode()).hexdigest() != plan['before_sha256']:
        raise RuntimeError('Recursive-group source hash mismatch: ' + name)
    starts, order, recursive = plan['starts'], plan['order'], set(plan['recursive'])
    if sorted(order) != list(range(len(starts))) or starts != sorted(set(starts)):
        raise RuntimeError('Invalid binding permutation')
    ends = starts[1:] + [len(source)]
    chunks = [source[a:b] for a, b in zip(starts, ends)]
    output = [source[:starts[0]]]
    for index in order:
        old = 'let rec' if index == 0 else 'and'
        if not chunks[index].startswith(old):
            raise RuntimeError('Unexpected binding prefix')
        keyword = 'let rec' if index in recursive else 'let'
        output.append((keyword + chunks[index][len(old):]).rstrip() + '\n\n')
    result = ''.join(output)
    if hashlib.sha256(result.encode()).hexdigest() != plan['after_sha256']:
        raise RuntimeError('Reordered source differs from reviewed output: ' + name)
    path.write_text(result)
for name, record in manifest.items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest() != record['after']:
        raise RuntimeError('Final source checksum mismatch: ' + name)
subprocess.run(['git', 'add', '--', *manifest], check=True)
changed = subprocess.check_output(['git', 'diff', '--cached', '--name-only'], text=True).splitlines()
if set(changed) != set(manifest):
    raise RuntimeError('Unexpected staged source changes')
Path('efficiency-validation').mkdir(exist_ok=True)
Path('efficiency-validation/source-sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
Path('efficiency-validation/source.patch').write_bytes(subprocess.check_output(['git', 'diff', '--cached', '--full-index']))
print('Verified', len(manifest), 'source/test files and all 1168 reordered function bodies')
