import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
for(const v of [0,1,2])for(const n of [1,30,60,100,120]){const b=readFileSync(`iter-${v}-${n}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of [0,1,2,3,4,0xfffffffe,0xffffffff])assert.equal(f(0,x)>>>0,Number(x<0xffffffff&&x+1<5));}
console.log('deep predecessor chain target execution passed');
