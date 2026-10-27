import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
for(let i=0;i<2;i++){const b=readFileSync(`common-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of [0,1,99,100,0xffffffff])assert.equal(f(0,x)>>>0,i===0?(x===0xffffffff?x:(x+1)>>>0):Number(x<99));}
for(let i=0;i<2;i++){const b=readFileSync(`common-bool-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of [0,1])assert.equal(f(0,x)>>>0,i===0?(x?17:42):1);}
console.log('common scalar argument/result executions passed');
