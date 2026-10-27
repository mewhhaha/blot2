import {readFileSync} from 'node:fs';import assert from 'node:assert/strict';
for(let i=0;i<2;i++){const bytes=readFileSync(`bool-fn-${i}.wasm`);assert(WebAssembly.validate(bytes));const {instance}=await WebAssembly.instantiate(bytes);assert.equal(instance.exports.f(0,0)>>>0,42);assert.equal(instance.exports.f(0,1)>>>0,11);}
console.log('private Bool callable targets execute on canonical Bool inputs');
