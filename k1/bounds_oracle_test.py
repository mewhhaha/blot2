#!/usr/bin/env python3
"""Independent generated guarded-read oracle for the private bounds fixture.

Tests bounded fixture behavior only; it does not establish K1 source binding,
View authority, caller region/domain identity, or full function contracts.
"""
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile


def main():
    rng = random.Random(0x62428195)
    fallbacks = [0, 1, 127, 128, 0x7fffffff, 0x80000000, 0xffffffff]
    fallbacks += [rng.getrandbits(32) for _ in range(45)]
    cases = []
    for index, fallback in enumerate(fallbacks):
        values = [rng.getrandbits(32) for _ in range(rng.randrange(0, 100))]
        indent = '  '  # K1 suites use exactly two additional spaces.
        sep = ' ' if index % 2 else ''
        source = (f'if i{sep}<{sep}v . length:\n{indent}return v[ i ]\n'
                  f'else:\n{indent}return {fallback}\n')
        cases.append((source, values, fallback))
    source_dir = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='k1-bounds-oracle-') as temp:
        root = Path(temp)
        k1 = root / 'k1'
        k1.mkdir()
        for path in source_dir.glob('*.goose'):
            (k1 / path.name).symlink_to(path.resolve())
        lines = [
            'import os;', 'import bounds_core;', 'import bounds_parse;', 'import bounds_validate;', 'import bounds_wasm;',
            'fn main() { let context = bounds_core::Context { owner: 1, view: 2, view_version: 3, index: 4, index_version: 5, length: 6, domain: 7 };'
        ]
        for i, (source, values, _) in enumerate(cases):
            literal = ','.join(str(v) for v in values)
            lines.append(
                '{ let source = ' + json.dumps(source) + '; '
                'var program,status=bounds_parse::parse(source,context); '
                f'if status!=0 {{ print("bounds case {i} parse status ",status); }} '
                'assert(status==0 && bounds_validate::verify(program,source,context)); '
                f'let values: u32[{len(values)}] = [{literal}]; '
                'let wasm=bounds_wasm::emit(program,source,context,values); '
                f'assert(wasm.len>0 && write_file("bounds_{i}.wasm",wasm)); }}'
            )
        lines.extend(['print("generated guarded reads emitted");', '}'])
        generated = k1 / 'generated_bounds_oracle.goose'
        generated.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        (root / 'expected.json').write_text(json.dumps([[values, fallback] for _, values, fallback in cases]), encoding='utf-8')
        js = r'''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const cases=JSON.parse(readFileSync('expected.json'));
for(let i=0;i<cases.length;i++) {
  const [values,fallback]=cases[i], bytes=readFileSync(`bounds_${i}.wasm`);
  assert(WebAssembly.validate(bytes)); const mod=new WebAssembly.Module(bytes);
  assert.deepEqual(WebAssembly.Module.imports(mod),[]);
  assert.deepEqual(WebAssembly.Module.exports(mod).map(x=>[x.name,x.kind]),[['read','function']]);
  const read=new WebAssembly.Instance(mod).exports.read;
  for(const n of new Set([0,Math.min(1,values.length),Math.floor(values.length/2),values.length])) {
    for(const index of new Set([0,Math.max(0,n-1),n,n+1,0xffffffff]))
      assert.equal(read(n,index)>>>0,(index<n ? values[index] : fallback)>>>0,`case=${i} n=${n} i=${index}`);
  }
  assert.throws(()=>read(values.length+1,0),WebAssembly.RuntimeError);
}
console.log(`${cases.length} generated guarded-read cases match independent reference`);
'''
        oracle = root / 'oracle.mjs'
        oracle.write_text(js, encoding='utf-8')
        goose = os.environ.get('GOOSE', 'goose')
        for level in (0, 2):
            subprocess.run([goose, '--debug', f'-O{level}', str(generated)], cwd=root, check=True)
            subprocess.run(['node', str(oracle)], cwd=root, check=True)


if __name__ == '__main__':
    main()
