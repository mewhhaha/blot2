import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const programs=[0,1,2].map(i=>{const data=readFileSync(`mix${i}.wasm`);assert(WebAssembly.validate(data));return new WebAssembly.Instance(new WebAssembly.Module(data)).exports.f;});
for(const x of [0,1,2,3,4,16,64,257]) {
 let a=0,b=5,c=0;
 for(let i=0;i<x;i++)a=(a+i)>>>0;
 for(let i=0;i<x;i++){b=(b+i)>>>0;if(i>=2){b=(b+1)>>>0;break;}}b=(b+x)>>>0;
 for(let i=0;i<x;i++)for(let j=0;j<2;j++)c=(c+i)>>>0;
 for(const [id,expected] of [a,b,c].entries())assert.equal(programs[id](0,x)>>>0,expected,`function ${id}, x=${x}`);
}
console.log('mixed scalar/loop Wasm matches independent oracles');
