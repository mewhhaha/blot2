import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
for(let i=0;i<5;i++) {
  const bytes=readFileSync(`guard_${i}.wasm`);assert(WebAssembly.validate(bytes));
  const mod=new WebAssembly.Module(bytes);assert.deepEqual(WebAssembly.Module.imports(mod),[]);
  const f=new WebAssembly.Instance(mod).exports.f;
  for(const x of [0,1,9,10,2147483648,4294967293,4294967294,4294967295]) {
    const y=(x+1)>>>0;
    const expected=i===4?(y<4294967295?(y+1)>>>0:x):(x<4294967295?(x+1)>>>0:x);
    assert.equal(f(0,x)>>>0,expected,`case ${i}, value ${x}`);
  }
}
console.log('guarded successor and alias Wasm execution passed');
