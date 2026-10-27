import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const max=0xffffffff;
for(let i=0;i<7;i++) {const bytes=readFileSync(`offset-${i}.wasm`);assert(WebAssembly.validate(bytes));const f=(await WebAssembly.instantiate(bytes)).instance.exports.f;
for(const x of [0,1,5,10,98,99,100,max-6,max-5,max-4,max-1,max]) {let expected=x;if(i<=3||i===6){if(x<=max-5)expected=x+5;}else if(i===4){if(x<100)expected=x+4294967196;}else if(x===0)expected=max;assert.equal(f(0,x)>>>0,expected>>>0,`case ${i} x ${x}`);}}
console.log('guarded offset U32 boundary execution passed');
