import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
for(let i=0;i<5;i++){
 const bytes=await readFile(`relation-direct-${i}.wasm`);assert(WebAssembly.validate(bytes));
 const mod=await WebAssembly.compile(bytes);assert.deepEqual(WebAssembly.Module.imports(mod),[]);
 const f=new WebAssembly.Instance(mod).exports.f;
 for(const x of [0,1,5,2147483647,2147483648,4294967293,4294967294,4294967295]){
  const expected=i===2?x:(x===4294967295?x:x+1);assert.equal(f(0,x)>>>0,expected);
 }
}
console.log('strict U32 relation Wasm execution passed');
