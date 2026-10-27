import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
for(let i=0;i<3;i++){let {instance}=await WebAssembly.instantiate(readFileSync(`leaf-resource-${i}.wasm`));for(let n of [0,1,4,5,6,0xffffffff]){let expected=i===1?Math.min(n,5):n;assert.equal(instance.exports.f(0,n)>>>0,expected);}}
console.log('source/target-validated leaf bodies execute');
