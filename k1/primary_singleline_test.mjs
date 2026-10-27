import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
for(const a of ['x','0','7','4294967295']) for(const b of ['x','0','7','4294967295']) {
 const bytes=readFileSync(`single-${a}-${b}.wasm`);assert(WebAssembly.validate(bytes));
 const fn=(await WebAssembly.instantiate(bytes)).instance.exports.pred;
 for(const x of [0,1,6,7,8,0xfffffffe,0xffffffff]) {
  const v=s=>s==='x'?x:Number(s);assert.equal(fn(0,x)>>>0,Number(v(a)<v(b)));
 }
}
console.log('single-line predicate boundary execution passed');
