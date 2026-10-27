import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
for(let i=0;i<8;i++){const b=readFileSync(`ops-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of [0,1,2,7,8,255,256,0x7fffffff,0x80000000,0xffffffff]){const want=i===0?(x-1)>>>0:i===1?Math.imul(x,7)>>>0:i===2?(x&255):i===3?Number(x<=7):i===4?8:i===5?Number((x&4)<=2):i===6?1:(x===0xffffffff?x:(x+1)>>>0);assert.equal(f(0,x)>>>0,want>>>0);}}
console.log('scalar/loop unsigned operation boundary execution passed');
