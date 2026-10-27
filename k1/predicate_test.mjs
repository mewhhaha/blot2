import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
for(let i=0;i<2;i++){const b=readFileSync(`predicate-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of [0,1,6,7,8,0x7fffffff,0x80000000,0xffffffff])assert.equal(f(0,x)>>>0,x<7?1:0);}
console.log('source-bound U32 -> Bool callable execution passed');
