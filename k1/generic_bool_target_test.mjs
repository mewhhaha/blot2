import {strict as assert} from 'node:assert';import {readFileSync} from 'node:fs';
for(let i=0;i<3;i++){const bytes=readFileSync(`bool-target-${i}.wasm`);assert(WebAssembly.validate(bytes));const f=(await WebAssembly.instantiate(bytes)).instance.exports.f;assert.equal(f(0,0)>>>0,42);assert.equal(f(0,1)>>>0,11);}
const bad=readFileSync('bool-valid-mutation.wasm');assert(WebAssembly.validate(bad));const f=(await WebAssembly.instantiate(bad)).instance.exports.f;assert.equal(f(0,1)>>>0,12);console.log('canonical Bool execution and valid Wasm mutation controls passed');
