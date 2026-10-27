import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
for(let n=0;n<10;n++){const {instance}=await WebAssembly.instantiate(readFileSync(`wrapper-audit-${n}.wasm`));for(let x of [0,1,Math.max(0,n-1),n,n+1,0xffffffff])assert.equal(instance.exports.f(0,x)>>>0,Math.min(x,n));}console.log('independent execution of ten newly accepted loop thresholds passed');
