import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
for(let i=0;i<3;i++){const bytes=readFileSync(`generic-fn-${i}.wasm`);assert(WebAssembly.validate(bytes));const {instance}=await WebAssembly.instantiate(bytes);for(const x of (i===2?[0,1,2,7,99]:[0,1,2,7,99,0xffffffff]))assert.equal(instance.exports.f(0,x)>>>0,i===2?x>>>0:x===0xffffffff?x>>>0:(x+1)>>>0);}
console.log('private callable signatures executed equivalently');
