#!/usr/bin/env python3
"""Independent all-prefix Wasm witness for the private copy-loop fixture.

These are poisoned test instances, not recoverable K1 runtime failures, a
host ABI, or qualification of general builder/loop ownership.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

from loop_oracle_test import SOURCE


def main():
    source_dir = Path(__file__).resolve().parent
    values = [((i * 65537) ^ 0xA5A5A5A5) & 0xFFFFFFFF for i in range(128)]
    source = SOURCE.replace('\\n', '\n')
    with tempfile.TemporaryDirectory(prefix='k1-loop-prefix-') as tmp:
        root = Path(tmp)
        k1 = root / 'k1'
        k1.mkdir()
        for path in source_dir.glob('*.goose'):
            (k1 / path.name).symlink_to(path.resolve())
        generated = k1 / 'generated_prefix_oracle.goose'
        generated.write_text('\n'.join([
            'import std;', 'import os;', 'import loop_core;', 'import loop_parse;', 'import loop_wasm;',
            'fn main() {', 'let source=' + json.dumps(source) + ';',
            'let ctx=loop_core::Context { owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,builder:7,builder_version:8,output_region:9,capacity:10,index:11,next_builder:12,next_version:14,result:13,result_version:15 };',
            'var core,status=loop_parse::parse(source,ctx); assert(status==0);',
            'let values:u32[128]=[' + ','.join(str(value) for value in values) + '];',
            'let normal=loop_wasm::emit(core,source,ctx,values); assert(normal.len>0 && write_file("normal.wasm",normal));',
            'for hook in 257 { let data=loop_wasm::emit_test(core,source,ctx,values,hook); assert(data.len>0 && write_file(str("hook_",hook,".wasm"),data)); }',
            'print("all prefix hook modules emitted");', '}']), encoding='utf-8')
        (root / 'values.json').write_text(json.dumps(values), encoding='utf-8')
        oracle = root / 'oracle.mjs'
        oracle.write_text(r'''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const values=JSON.parse(readFileSync('values.json'));
function instance(name) {
  const bytes=readFileSync(name); assert(WebAssembly.validate(bytes));
  const module=new WebAssembly.Module(bytes); assert.deepEqual(WebAssembly.Module.imports(module),[]);
  assert.deepEqual(WebAssembly.Module.exports(module).map(x=>[x.name,x.kind]),[['run','function'],['at','function'],['length','function'],['capacity','function']]);
  return new WebAssembly.Instance(module).exports;
}
function checkPrefix(e, len, cap) {
  assert.equal(e.length(),len); assert.equal(e.capacity(),cap);
  for(let i=0;i<len;i++) assert.equal(e.at(i)>>>0,values[i]);
  assert.throws(()=>e.at(len),WebAssembly.RuntimeError);
}
for(let hook=0;hook<=256;hook++) {
  const e=instance(`hook_${hook}.wasm`);
  // Exercise a successful earlier publication when the chosen hook permits it.
  const prior=hook===0 ? -1 : hook<=128 ? hook-1 : hook-129;
  if(prior>=0) {assert.equal(e.run(prior,prior),prior);checkPrefix(e,prior,prior);}
  const beforeLength=e.length(),beforeCapacity=e.capacity();
  assert.equal(e.run(129,128),-1);checkPrefix(e,beforeLength,beforeCapacity);
  assert.throws(()=>e.run(128,128),WebAssembly.RuntimeError);
  // Hooks 129..256 trap after storing item i but before publishing it.
  const visible=hook<=128?hook:hook-129;
  checkPrefix(e,visible,128);
  // A real wrapper must poison a trapped instance; this test discards it.
}
const e=instance('normal.wasm');let lastLen=0,lastCap=0;
for(let n=0;n<=130;n++)for(let cap=0;cap<=130;cap++) {
  const ok=n<=128 && cap<=128 && n<=cap;
  assert.equal(e.run(n,cap),ok?n:-1);
  if(ok){lastLen=n;lastCap=cap;} checkPrefix(e,lastLen,lastCap);
}
for(const [n,c] of [[-1,128],[-2147483648,128],[0,-1],[0,-2147483648]]) {
  assert.equal(e.run(n,c),-1);checkPrefix(e,lastLen,lastCap);
}
console.log('257 trap prefixes and 17,161 preflight pairs match the independent prefix model');
''', encoding='utf-8')
        goose = os.environ.get('GOOSE', 'goose')
        for level in (0, 2):
            subprocess.run([goose, '--debug', f'-O{level}', str(generated)], cwd=root, check=True)
            subprocess.run(['node', str(oracle)], cwd=root, check=True)


if __name__ == '__main__':
    main()
