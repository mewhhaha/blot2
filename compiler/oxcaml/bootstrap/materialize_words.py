#!/usr/bin/env python3
"""One-time checked native-word migration; never part of a normal compiler build.

Only OCaml code tokens in the allowlisted native files are transformed. String
literals, character literals and nested comments are retained byte for byte.
A complete source hash manifest must match the locally tested candidate before
this staging branch is allowed to build or publish a commit.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = '03ae9c90d494330f0ec6d103ad9c4372542c7504cb2f06c3e9cde80ebfa4aae2'


def code_tokens(source, transform):
    pieces = []
    i = start = 0
    n = len(source)
    while i < n:
        if source.startswith('(*', i):
            pieces.append(transform(source[start:i]))
            j, depth = i + 2, 1
            while depth:
                if j >= n:
                    raise ValueError('unterminated comment')
                if source.startswith('(*', j):
                    depth += 1
                    j += 2
                elif source.startswith('*)', j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            pieces.append(source[i:j])
            i = start = j
        elif source[i] == '"':
            pieces.append(transform(source[start:i]))
            j = i + 1
            while True:
                if j >= n:
                    raise ValueError('unterminated string')
                if source[j] == '\\':
                    j += 2
                elif source[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            pieces.append(source[i:j])
            i = start = j
        elif source[i] == "'" and (match := re.match(
                r"'(?:\\(?:[0-9]{3}|x[0-9a-fA-F]{2}|.)|[^'\\])'", source[i:])):
            pieces.append(transform(source[start:i]))
            j = i + len(match[0])
            pieces.append(source[i:j])
            i = start = j
        else:
            i += 1
    pieces.append(transform(source[start:]))
    return ''.join(pieces)


def words(source):
    source = re.sub(r'(?<![.\w])int32\b', 'Base.word32', source)
    def literal(match):
        text = match[0][:-1].replace('_', '')
        value = int(text, 16 if 'x' in text.lower() else 10) & 0xffffffff
        return f'(Base.W32 0x{value:x})'
    return re.sub(r'(?<![\w.])-?(?:0[xX][0-9A-Fa-f_]+|[0-9][0-9_]*)l\b', literal, source)


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f'expected exactly one occurrence: {old!r}')
    return source.replace(old, new)


def rewrite(path, operation):
    file = ROOT / path
    original = file.read_text()
    file.write_text(operation(original))


def main():
    model = (ROOT / 'core/ox_model.ml').read_text()
    if 'int32' not in model or 'Base.word32' in model:
        raise RuntimeError('expected unmigrated native core')
    for file in sorted((ROOT / 'core').glob('*.ml')):
        file.write_text(code_tokens(file.read_text(), words))
    rewrite('core/ox_native_request.ml', lambda s: replace_once(s,
        'Chr (Bytes.get_int32_le cursor.bytes (offset * 4))',
        'Chr (Base.W32 (unsigned_word cursor.bytes offset))'))
    rewrite('core/ox_index.ml', lambda s: replace_once(s,
        'Int32.to_int value', 'Base.u32_to_nat value'))
    def transport(source):
        for old, new in [
            ('u32_to_nat (Bytes.get_int32_le prefix 0)',
             'Int32.to_int (Bytes.get_int32_le prefix 0) land 0xffff_ffff'),
            ('Int32.of_int count', 'Base.W32 count'),
            ('Bytes.set_int32_le buffer !used value',
             'Bytes.set_int32_le buffer !used (Base.word_to_int32 value)'),
            ('Int32.to_int value', 'Base.u32_to_nat value'),
        ]:
            source = replace_once(source, old, new)
        return source
    rewrite('ox_native_transport.ml', transport)
    def test_words(source):
        source = code_tokens(source, words)
        for old, new in [
            ('Int32.max_int', '(Base.W32 0x7fff_ffff)'),
            ('Int32.min_int', '(Base.W32 0x8000_0000)'),
            ('Int32.minus_one', '(Base.W32 0xffff_ffff)'),
            ('Int32.equal', 'Base.u32_is_eq'),
            ('Int32.of_int', 'Base.word_of_int'),
        ]:
            source = source.replace(old, new)
        return source
    for name in ['test_names.ml', 'test_runtime.ml', 'bench_names.ml']:
        rewrite(name, test_words)
    rewrite('test_names.ml', lambda s: replace_once(s, 'allocated < 49.', 'allocated < 25.'))
    rewrite('test_build.py', lambda s: replace_once(s,
        "'test_names', 'test_parallel'",
        "'test_names', 'test_builders', 'test_scalars', 'test_packet', 'test_parallel_stress', 'bench_parallel', 'test_parallel', 'test_parallel'".replace("'test_parallel', 'test_parallel'", "'test_parallel'")))
    rewrite('test_existing.py', lambda s: replace_once(s,
        "'.git', '_build', '__pycache__'", "'.git', '_build*', '__pycache__'"))
    files = sorted({*ROOT.glob('*.ml'), *ROOT.glob('core/*.ml'),
                    *ROOT.glob('*.py'), *ROOT.glob('*.ts'), ROOT / 'Makefile'})
    hashes = {str(file.relative_to(ROOT)): hashlib.sha256(file.read_bytes()).hexdigest()
              for file in files}
    canonical = ''.join(f'{name}\0{digest}\n' for name, digest in hashes.items()).encode()
    actual = hashlib.sha256(canonical).hexdigest()
    out = ROOT.parents[1] / 'native-migration-results'
    out.mkdir(exist_ok=True)
    (out / 'source-manifest.json').write_text(json.dumps({
        'expected': EXPECTED, 'actual': actual, 'matches': actual == EXPECTED,
        'files': hashes}, indent=2) + '\n')
    if actual != EXPECTED:
        raise RuntimeError(f'native source hash mismatch: {actual} != {EXPECTED}')
    print(f'Verified {len(files)} native source files: {actual}')


if __name__ == '__main__':
    main()
