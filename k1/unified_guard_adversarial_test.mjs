import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
for (let i=0;i<4;i++) {
  const bytes=await readFile(`cache_audit_${i}.wasm`);
  assert(WebAssembly.validate(bytes));
  const mod=await WebAssembly.compile(bytes);assert.deepEqual(WebAssembly.Module.imports(mod),[]);
  const f=new WebAssembly.Instance(mod).exports.f;
  for(const x of [0,1,4,4294967293,4294967294,4294967295]) {
    const expected=i===3?4294967295:i===2?(x<4294967294?x+2:x):x===4294967295?x:x+1;
    assert.equal(f(0,x)>>>0,expected>>>0,`case ${i} input ${x}`);
  }
}
console.log('independent unified proof execution passed');
