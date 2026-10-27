import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
for(let i=0;i<5;i++){const b=readFileSync(`typed-canonical-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of [0,1,2,7,30]){const want=i===0?x:i===1?x*(x-1)/2:i===2?x:i===3?(x<7?17:42):Math.min(x,5);assert.equal(f(0,x)>>>0,want>>>0);}if(i===3||i===4)assert.equal(f(0,0xffffffff)>>>0,i===3?42:5);}
console.log('typed scalar/loop lexical Wasm execution passed');
