import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
for(let i=0;i<2;i++){let b=await readFile(`typed-dispatch-${i}.wasm`);assert(WebAssembly.validate(b));let f=new WebAssembly.Instance(new WebAssembly.Module(b)).exports.f;for(const x of [0,1,2,3,4,5,6,50,0xffffffff])assert.equal(f(0,x)>>>0,(i===0?Math.min(x,5):2*Math.min(x,4))>>>0);}
console.log('old-first typed-loop dispatch target execution passed');
