import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
for(let arg=1;arg<=2;arg++)for(let res=1;res<=2;res++)for(let form=1;form<=2;form++){let i=(arg-1)*4+(res-1)*2+form-1;const b=readFileSync(`poly-canonical-${i}.wasm`);assert(WebAssembly.validate(b));const f=(await WebAssembly.instantiate(b)).instance.exports.f;for(const x of arg===1?[0,1,4,5,7,0xffffffff]:[0,1]){let flag=arg===1?x<5:x===1;assert.equal(f(0,x)>>>0,res===1?(flag?3:0):Number(flag));}}
console.log('all scalar/loop argument and result type pairs execute');
