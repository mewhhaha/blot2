import {strict as assert} from 'node:assert';import {readFileSync}from'node:fs';
for(let i=0;i<80;i++){const {instance}=await WebAssembly.instantiate(readFileSync(`predgen-${i}.wasm`));const k=(i*7919)%300000,kind=i%4;for(const x of [0,1,k>0?k-1:0,k,k+1,0x7fffffff,0xfffffffe,0xffffffff]){const q=kind===0?x<0xffffffff&&x+1<k:kind===1?x<=0xfffffffe&&x+1<=k:kind===2?x<k:0xfffffffe<x||x+1<k;assert.equal(instance.exports.f(0,x)>>>0,Number(q),`case ${i}, x ${x}`);}}
console.log('generated Bool-return U32 boundary oracle passed');
