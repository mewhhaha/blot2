import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
for(let i=0;i<8;i++){
 const bytes=await readFile(`ule-${i}.wasm`);assert(WebAssembly.validate(bytes));
 const mod=await WebAssembly.compile(bytes);assert.deepEqual(WebAssembly.Module.imports(mod),[]);
 const f=new WebAssembly.Instance(mod).exports.f;
 for(const x of [0,1,4,5,9,10,11,0x7fffffff,0xfffffffd,0xfffffffe,0xffffffff]){
  const expected=i===6?Number(x<=10):i===7?(x===0?1:x):i===3?(x<=0xfffffffe && x+1<=5?x+1:x):(x<0xffffffff?x+1:x);
  assert.equal(f(0,x)>>>0,expected,`case ${i}, value ${x}`);
 }
}
console.log('unsigned <= and false-edge Wasm execution passed');
