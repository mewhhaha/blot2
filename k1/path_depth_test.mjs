import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
for(let n=118;n<128;n++){let b=readFileSync(`path-depth-${n}.wasm`);assert(WebAssembly.validate(b));let f=(await WebAssembly.instantiate(b)).instance.exports.f;for(let x of [0,1,4,5,0xffffffff])assert.equal(f(0,x)>>>0,Number(x<5));}console.log('long short-circuit chain runtime controls passed');
