import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
let random=0x9137abfc;
function rand(){random^=random<<13;random^=random>>>17;random^=random<<5;return random>>>0;}
for (let n=2;n<=16;n++) {
 const bytes=await readFile(`abi-inst-${n}.wasm`);
 const instance=new WebAssembly.Instance(new WebAssembly.Module(bytes));
 const {memory,apply}=instance.exports, data=new DataView(memory.buffer), all=new Uint8Array(memory.buffer);
 for(let run=0;run<100;run++){
  const src=1024+4*(rand()%2000), dst=32768+4*(rand()%2000);
  all.fill(0xa5,dst-4,dst+4*n+4);
  const vals=Array.from({length:n},()=>rand());
  vals.forEach((v,i)=>data.setUint32(src+4*i,v,true));
  apply(0,dst,src);
  vals.forEach((v,i)=>{assert.equal(data.getUint32(dst+4*i,true),v);assert.equal(data.getUint32(src+4*i,true),v);});
  assert.equal(data.getUint32(dst-4,true),0xa5a5a5a5);assert.equal(data.getUint32(dst+4*n,true),0xa5a5a5a5);
 }
}
console.log('1,500 independent tuple call, input preservation and output-bound controls passed');
