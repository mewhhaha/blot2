import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
for(let arg=1;arg<=2;arg++)for(let res=1;res<=2;res++)for(let form=1;form<=2;form++){let i=(arg-1)*4+(res-1)*2+form-1;const b=readFileSync(`short-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of arg===1?[0,1,4,5,7,0xffffffff]:[0,1]){let flag=arg===1?x<5:x===1;assert.equal(f(0,x)>>>0,res===1?(flag?3:0):Number(flag));}}
console.log('all scalar/loop argument and result type pairs execute');
const am=readFileSync('short-mutant-and.wasm');assert(WebAssembly.validate(am));const af=(await WebAssembly.instantiate(am)).instance.exports.f;assert.equal(af(0,7),0);assert.throws(()=>af(0,1),WebAssembly.RuntimeError);
const om=readFileSync('short-mutant-or.wasm');assert(WebAssembly.validate(om));const of=(await WebAssembly.instantiate(om)).instance.exports.f;assert.equal(of(0,1),3);assert.throws(()=>of(0,7),WebAssembly.RuntimeError);
console.log('short-circuit branch trap probes and target rejection passed');
