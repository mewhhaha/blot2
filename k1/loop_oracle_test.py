#!/usr/bin/env python3
"""Independent repeated-run oracle for the private U32 carry-loop fixture.

This is not I08 source qualification, general loop analysis, K1 View/Builder
ABI or a proof of ownership, cleanup and frame resource accounting.
"""
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile

SOURCE = ('pub let copy_into: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => '
          'Fn[static, Many, (View[r,U32,n,d], Builder[s,U32,0,c,Append]), Builder[s,U32,n,c,Append]] '
          '! {read r, write s} requires [Le(n,c)] resources {depth: 1, frame: 256} = fn (source,initial) => do:\n'
          '  let built = for i in 0..n carry (b = initial)\n'
          '    invariant [Eq(Init(b),i)] do:\n'
          '      next (builder.append(b, source[i]))\n'
          '  return built\n')


def main():
    rng = random.Random(0x2319a41b)
    lengths = [0, 1, 2, 127, 128] + [rng.randrange(0, 129) for _ in range(11)]
    inputs = [[rng.getrandbits(32) for _ in range(length)] for length in lengths]
    source_dir = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='k1-loop-oracle-') as tmp:
        root = Path(tmp)
        k1 = root / 'k1'
        k1.mkdir()
        for path in source_dir.glob('*.goose'):
            (k1 / path.name).symlink_to(path.resolve())
        # SOURCE is expressed with literal newline escapes here; json.dumps
        # expects real newlines to write valid Goose string literals.
        source = SOURCE.replace('\\n', '\n')
        lines = [
            'import os;', 'import loop_core;', 'import loop_parse;', 'import loop_validate;', 'import loop_wasm;',
            'fn main() { let source=' + json.dumps(source) + ';',
            'let ctx=loop_core::Context { owner: 1,input: 2,input_version: 3,input_region: 4,input_domain: 5,length: 6,builder: 7,builder_version: 8,output_region: 9,capacity: 10,index: 11,next_builder: 12,next_version: 14,result: 13,result_version: 15 };',
            'var c,status=loop_parse::parse(source,ctx); assert(status==0 && loop_validate::verify(c,source,ctx));',
        ]
        for index, data in enumerate(inputs):
            literal = ','.join(str(v) for v in data)
            lines.append(f'{{ let a: u32[{len(data)}] = [{literal}]; '
                         f'let w=loop_wasm::emit(c,source,ctx,a); assert(w.len>0 && write_file("loop_{index}.wasm",w)); }}')
        lines.extend(['print("generated loop fixtures emitted");', '}'])
        generated = k1 / 'generated_loop_oracle.goose'
        generated.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        (root / 'expected.json').write_text(json.dumps(inputs), encoding='utf-8')
        js = r'''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const inputs=JSON.parse(readFileSync('expected.json'));
let seed=0x9e72a451, good=0, rejected=0;
function random() { seed^=seed<<13; seed^=seed>>>17; seed^=seed<<5; return seed>>>0; }
for(let i=0;i<inputs.length;i++) {
  const values=inputs[i], b=readFileSync(`loop_${i}.wasm`);
  assert(WebAssembly.validate(b)); const m=new WebAssembly.Module(b);
  assert.deepEqual(WebAssembly.Module.imports(m),[]);
  assert.deepEqual(WebAssembly.Module.exports(m).map(x=>[x.name,x.kind]),[['run','function'],['at','function'],['length','function'],['capacity','function']]);
  const e=new WebAssembly.Instance(m).exports; let expected=[], cap=0;
  for(let j=0;j<500;j++) {
    const n=random()%133, c=random()%133, allowed=n<=values.length && c<=128 && n<=c;
    const status=e.run(n,c);
    if(allowed) { good++; assert.equal(status,n); expected=values.slice(0,n); cap=c; }
    else { rejected++; assert.equal(status,-1); }
    assert.equal(e.length(),expected.length); assert.equal(e.capacity(),cap);
    for(let k=0;k<expected.length;k++) assert.equal(e.at(k)>>>0,expected[k]>>>0);
    assert.throws(()=>e.at(expected.length),WebAssembly.RuntimeError);
  }
}
assert(good>0 && rejected>0);
console.log(`${inputs.length} repeated-run carry loops match independent state reference (${good} valid, ${rejected} rejected)`);
'''
        oracle = root / 'oracle.mjs'
        oracle.write_text(js, encoding='utf-8')
        goose = os.environ.get('GOOSE', 'goose')
        for level in (0, 2):
            subprocess.run([goose, '--debug', f'-O{level}', str(generated)], cwd=root, check=True)
            subprocess.run(['node', str(oracle)], cwd=root, check=True)


if __name__ == '__main__':
    main()
