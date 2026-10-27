import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
let seed=0x12345678;
for(let i=5;i<=8;i++){let b=readFileSync(`path-${i}.wasm`);assert(WebAssembly.validate(b));let f=(await WebAssembly.instantiate(b)).instance.exports.f;let inputs=[0,1,2,3,4,5,0xfffffffd,0xfffffffe,0xffffffff];for(let j=0;j<1000;j++){seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;inputs.push(seed>>>0);}for(let x of inputs){let expected=i===5||i===8?Number(x===0xffffffff||x+1<5):i===6?Number(x<=0xfffffffe&&x+1<5):1;assert.equal(f(0,x)>>>0,expected,`${i} ${x}`);}}
console.log('independent false-edge, alias and dead-branch execution passed');
