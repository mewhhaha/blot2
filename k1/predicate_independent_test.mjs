import {strict as assert} from 'node:assert';import{readFileSync}from'node:fs';
for(let i=0;i<3;i++){let {instance}=await WebAssembly.instantiate(readFileSync(`predicate-independent-${i}.wasm`));for(let x of [0,1,6,7,8,0x7fffffff,0x80000000,0xffffffff])assert.equal(instance.exports.f(0,x)>>>0,Number(i===0?7<x:i===1?x<0xffffffff:false));}
console.log('independent predicate unsigned-boundary execution passed');
