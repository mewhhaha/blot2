import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
for(let i=0;i<3;i++){
 const bytes=await readFile(`relation-path-${i}.wasm`);assert(WebAssembly.validate(bytes));const m=await WebAssembly.compile(bytes);assert.deepEqual(WebAssembly.Module.imports(m),[]);const f=new WebAssembly.Instance(m).exports.f;
 for(const x of [0,1,10,0x7fffffff,0xfffffffc,0xfffffffd,0xfffffffe,0xffffffff]){
  const y=(x+1)>>>0,z=(y+1)>>>0;
  const yes=i===0?(x<=y && y<0xffffffff):i===1?(!(y<x) && y<0xffffffff):(x<=y && y<=z && z<0xffffffff);
  assert.equal(f(0,x)>>>0,yes?x+1:x,`case ${i}, x ${x}`);
 }
}
console.log('source-bound transitive relation Wasm execution passed');
