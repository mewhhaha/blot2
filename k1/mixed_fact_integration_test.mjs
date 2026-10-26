import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const f=[0,1,2].map(i=>{const b=readFileSync(`fact${i}.wasm`);assert(WebAssembly.validate(b));return new WebAssembly.Instance(new WebAssembly.Module(b)).exports.f});
for(const x of [0,1,2,42,2147483647,4294967292,4294967293,4294967294,4294967295]) {
 const inc=(n,k)=>Math.min(4294967295,n+k)>>>0;
 assert.equal(f[0](0,x)>>>0,inc(x,3));
 assert.equal(f[1](0,x)>>>0,x>>>0);
 assert.equal(f[2](0,x)>>>0,inc(x,2));
}
console.log('guarded loop Wasm matched boundary reference');
