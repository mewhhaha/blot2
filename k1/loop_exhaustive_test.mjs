// Exhaustive small fixed-capacity state oracle for loop-max.wasm, which is
// emitted by loop_test.goose into the current test directory. This checks the
// private raw fixture only, not K1 borrow/frame or general loop qualification.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
const bytes = readFileSync('loop-max.wasm'); assert(WebAssembly.validate(bytes));
const module = new WebAssembly.Module(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
assert(!WebAssembly.Module.exports(module).some(item => item.kind === 'memory'));
const e = new WebAssembly.Instance(module).exports;
const values = Array.from({length:128}, (_,i) => (Math.imul(i,65537)^0xa5a5a5a5)>>>0);
let length=0,capacity=0,accepted=0,rejected=0;
for(let n=0;n<=128;n++) for(let c=0;c<=128;c++) {
  const result=e.run(n,c);
  if(n<=c) { assert.equal(result,n); length=n; capacity=c; accepted++; }
  else { assert.equal(result,-1); rejected++; }
  assert.equal(e.length(),length); assert.equal(e.capacity(),capacity);
  for(let i=0;i<length;i++) assert.equal(e.at(i)>>>0,values[i]);
  assert.throws(()=>e.at(length),WebAssembly.RuntimeError);
}
assert.equal(accepted,8385); assert.equal(rejected,8256);
assert.equal(e.run(129,128),-1); assert.equal(e.run(0,129),-1);
assert.equal(e.length(),length); assert.equal(e.capacity(),capacity);
for(let i=0;i<length;i++) assert.equal(e.at(i)>>>0,values[i]);
console.log('private carry loop: all 16,641 (n,c) boundary pairs passed');
