#!/usr/bin/env python3
"""Independent generated F32 oracle for the private expression fixture.

This tests only the fixed expression environment, not K1 function/loop
admission, ABI, ownership, or the full specified NaN payload sets. All source,
Wasm and oracle inputs below are generated locally and live in a temp directory.
"""
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile


rng = random.Random(7731)
LEAVES = [('p.x', 'a'), ('p.y', 'b'), ('p.vx', 'c'), ('p.vy', 'd'), ('dt', 'e')]


def expression(depth):
    if depth == 0 or rng.random() < 0.34:
        return rng.choice(LEAVES)
    left, left_js = expression(depth - 1)
    right, right_js = expression(depth - 1)
    op = rng.choice(['+', '*'])
    return f'({left} {op} {right})', f'Math.fround(({left_js}) {op} ({right_js}))'


cases = [expression(6) for _ in range(120)]
cases.extend([
    ('p.x + p.vx * dt', 'Math.fround(a+Math.fround(c*e))'),
    ('p.x + p.y + p.vx + p.vy', 'Math.fround(Math.fround(Math.fround(a+b)+c)+d)'),
    ('p.x * dt + p.y * p.vx', 'Math.fround(Math.fround(a*e)+Math.fround(b*c))'),
])


def main():
    source_dir = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='k1-particle-expr-oracle-') as tmp:
        root = Path(tmp)
        k1 = root / 'k1'
        k1.mkdir()
        for source in source_dir.glob('*.goose'):
            (k1 / source.name).symlink_to(source.resolve())
        goose_src = [
            'import os;', 'import particle_expr_parse;',
            'import particle_expr_validate;', 'import particle_expr_wasm;', 'fn main() {'
        ]
        for index, (source, _) in enumerate(cases):
            goose_src.append(
                '{ let c, status = particle_expr_parse::parse(' + json.dumps(source) + '); '
                'assert(status == 0 && particle_expr_validate::verify(c)); '
                'let bytes = particle_expr_wasm::emit(c); '
                f'assert(bytes.len > 0 && write_file("{index}.wasm",bytes)); }}'
            )
        goose_src.extend(['print("generated expression cases emitted");', '}'])
        source_file = k1 / 'generated_expr_oracle.goose'
        source_file.write_text('\n'.join(goose_src) + '\n', encoding='utf-8')
        oracle = '''
const fs = require('node:fs');
const round = Math.fround;
let seed = 0x81ac2221;
function randomFloat() {
  seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
  const b = Buffer.alloc(4); b.writeUInt32LE(seed >>> 0); return b.readFloatLE();
}
const inputs = [
  [0, -0, 1, -1, Number.MIN_VALUE],
  [Infinity, -Infinity, NaN, 0, 1],
  [1.401298464324817e-45, 3.4028234663852886e38, -0, 2, -1],
];
for (let i = 0; i < 100; i++) inputs.push([randomFloat(), randomFloat(), randomFloat(), randomFloat(), randomFloat()]);
const references = [
''' + ',\n'.join('(a,b,c,d,e) => ' + js for _, js in cases) + '''
];
for (let i = 0; i < references.length; i++) {
  const bytes = fs.readFileSync(i + '.wasm');
  if (!WebAssembly.validate(bytes)) throw Error('invalid wasm ' + i);
  const fn = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports.expr;
  for (let [a, b, c, d, e] of inputs) {
    [a, b, c, d, e] = [a, b, c, d, e].map(round);
    const expected = references[i](a, b, c, d, e);
    const actual = fn(a, b, c, d, e);
    if (!(Object.is(expected, actual) || (Number.isNaN(expected) && Number.isNaN(actual))))
      throw Error('expression ' + i + ': expected ' + expected + ', got ' + actual);
  }
}
console.log('independent generated F32 oracle passed: ' + references.length + ' expressions * ' + inputs.length + ' vectors');
'''
        js_file = root / 'oracle.cjs'
        js_file.write_text(oracle, encoding='utf-8')
        goose = os.environ.get('GOOSE', 'goose')
        for level in (0, 2):
            subprocess.run([goose, '--debug', f'-O{level}', str(source_file)], cwd=root, check=True)
            subprocess.run(['node', str(js_file)], cwd=root, check=True)


if __name__ == '__main__':
    main()
