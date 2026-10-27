import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
const mod=new WebAssembly.Module(readFileSync('private-invoke.wasm'));
for(const top of [1,4,16,255,768,1024,3328,4096,0xffffffff]){
 const e=new WebAssembly.Instance(mod).exports,m=new Uint8Array(e.memory.buffer),d=new DataView(m.buffer),p=32768;
 d.setUint32(p,0x4b310001,true);d.setUint32(p+4,91,true);d.setUint32(p+12,28,true);d.setUint32(p+32,1,true);d.setUint32(p+36,12,true);d.setFloat32(p+40,.5,true);
 for(let i=0;i<4;i++)d.setFloat32(p+44+i*4,i+1,true);d.setUint32(404,top,true);m.fill(0xa5,36864,37120);
 const before=Uint8Array.from(m),status=e.invoke(91,60,224);assert.equal(status,5);assert.equal(d.getUint32(404,true),top);assert.equal(d.getUint32(416,true),0);
 const h=Array.from({length:8},(_,i)=>d.getUint32(36864+4*i,true));assert.deepEqual(h,[0x4b310001,91,5,0,0,0,0,0]);
 for(let i=0;i<m.length;i++)if(i<36864||i>=36896)assert.equal(m[i],before[i]);
 d.setUint32(416,1,true);const busy=Uint8Array.from(m);assert.equal(e.invoke(91,60,224),4);assert.deepEqual(m,busy);
}
console.log('independent zero-frontier pre-effect and Busy controls passed');
