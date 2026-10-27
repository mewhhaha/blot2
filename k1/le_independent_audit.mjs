import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';let state=0x92172abc;
for(let n=1;n<=12;n++){const b=await readFile(`ind-le-${n}.wasm`),f=new WebAssembly.Instance(new WebAssembly.Module(b)).exports.f;let xs=[0,1,0xfffffffe,0xffffffff];for(let j=0;j<100;j++){state=(Math.imul(state,1664525)+1013904223)>>>0;xs.push(state);}for(const x of xs)assert.equal(f(0,x)>>>0,x===0xffffffff?x:(x+1)>>>0);}
console.log('independent guarded successor alias-chain execution passed');
