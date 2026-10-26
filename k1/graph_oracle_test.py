#!/usr/bin/env python3
"""Independent raw-data graph execution oracle; not K1 source qualification."""
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile


def main():
    rng = random.Random(21827)
    cases = []
    for _ in range(80):
        n = rng.randrange(1, 13)
        m = rng.randrange(0, 13)
        nodes = [rng.getrandbits(32) for _ in range(n)]
        edges = [(rng.randrange(n), rng.randrange(n)) for _ in range(m)]
        raw = (struct.pack('<II', n, m) + b''.join(struct.pack('<I', v) for v in nodes)
               + b''.join(struct.pack('<II', a, b) for a, b in edges))
        cases.append((raw, [[nodes[a], nodes[b]] for a, b in edges]))
    source_dir = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='k1-graph-oracle-') as temp:
        root = Path(temp)
        k1 = root / 'k1'
        k1.mkdir()
        for path in source_dir.glob('*.goose'):
            (k1 / path.name).symlink_to(path.resolve())
        lines = ['import os;', 'import graph_core;', 'import graph_build;',
                 'import graph_validate;', 'import graph_wasm;', 'fn main() { var clock=graph_core::Clock {};']
        for i, (raw, _) in enumerate(cases):
            literal = ','.join(str(byte) for byte in raw)
            lines.append(f'{{ let s: u8[{len(raw)}] = [{literal}]; '
                         f'var g,r=graph_build::make(clock,s); assert(r.status==0 && graph_validate::verify(g,s,g.ticket)); '
                         f'let w=graph_wasm::emit(g,s,g.ticket); assert(w.len>0 && write_file("graph_{i}.wasm",w)); }}')
        lines.extend(['print("generated graphs emitted");', '}'])
        generated = k1 / 'generated_graph_oracle.goose'
        generated.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        (root / 'expected.json').write_text(json.dumps([expected for _, expected in cases]), encoding='utf-8')
        oracle = r'''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const xs=JSON.parse(readFileSync('expected.json'));
for (let i=0; i<xs.length; i++) {
  const bytes=readFileSync(`graph_${i}.wasm`); assert(WebAssembly.validate(bytes));
  const mod=new WebAssembly.Module(bytes);
  assert.deepEqual(WebAssembly.Module.imports(mod), []);
  assert(!WebAssembly.Module.exports(mod).some(x=>x.kind==='memory'));
  const e=new WebAssembly.Instance(mod).exports;
  for (let k=0; k<xs[i].length; k++) {
    assert.equal(e.source(k)>>>0,xs[i][k][0]);
    assert.equal(e.target(k)>>>0,xs[i][k][1]);
  }
  assert.throws(()=>e.source(xs[i].length),WebAssembly.RuntimeError);
}
console.log('80 generated graphs match independent stored-endpoint oracle');
'''
        runner = root / 'oracle.mjs'
        runner.write_text(oracle, encoding='utf-8')
        goose = os.environ.get('GOOSE', 'goose')
        for level in (0, 2):
            subprocess.run([goose, '--debug', f'-O{level}', str(generated)], cwd=root, check=True)
            subprocess.run(['node', str(runner)], cwd=root, check=True)


if __name__ == '__main__':
    main()
