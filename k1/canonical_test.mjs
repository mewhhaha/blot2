import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
for(let i=0;i<3;i++){const b=readFileSync(`canonical-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of [0,1,2,7,30])assert.equal(f(0,x)>>>0,(i===0?x:i===1?x*(x-1)/2:x)>>>0);}
console.log('source-owned scalar/loop arena executes checked targets');
