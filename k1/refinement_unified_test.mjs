import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
for(let i=0;i<7;i++){
 const mod=await WebAssembly.compile(await readFile(`refinement-${i}.wasm`));assert.deepEqual(WebAssembly.Module.imports(mod),[]);
 const f=new WebAssembly.Instance(mod).exports.f;
 for(const x of [0,1,3,4,0x7fffffff,0xfffffffe,0xffffffff]){
  let expected=(i===0 ? (x<0xffffffff && x+1<5 ? x+1:x) : i===5 ? x : (x<0xffffffff ? x+1:x));
  assert.equal(f(0,x)>>>0,expected);
 }
}
console.log('unified refinement Wasm execution passed');
