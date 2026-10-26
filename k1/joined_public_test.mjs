import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
for (let i=0;i<3;i++) {
 const m=await WebAssembly.instantiate(readFileSync(`joined_${i}.wasm`));const f=m.instance.exports.f;
 for(const x of [0,1,2,7,100]) {const expected=i===0 ? x+1 : i===1 ? (x===0 ? 17 : x-1) : x;assert.equal(f(0,x)>>>0,expected>>>0);}
 if(i===0) assert.equal(f(0,-1)>>>0,0xffffffff);
}
console.log('joined public-shaped scalar and loop execution passed');
