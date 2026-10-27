import {strict as assert} from 'node:assert';import {readFileSync} from 'node:fs';
for(let i=0;i<4;i++){const {instance}=await WebAssembly.instantiate(readFileSync(`predflow-${i}.wasm`));for(const x of [0,1,98,99,100,0x7fffffff,0xfffffffe,0xffffffff]){const expected=i<2?Number(x<99):i===2?0:1;assert.equal(instance.exports.f(0,x)>>>0,expected);}}
console.log('Bool-return short-circuit boundary and canonical results passed');
