import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const bytes=readFileSync('frame-arena.wasm'),module=new WebAssembly.Module(bytes);
let seed=0x319afed3;function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;}
for(let i=0;i<1500;i++) {
 const e=new WebAssembly.Instance(module).exports,d=new DataView(e.memory.buffer);
 const cap=rnd()%4600,top=rnd()%4600;d.setUint32(400,cap,true);d.setUint32(404,top,true);const before=Buffer.from(new Uint8Array(e.memory.buffer));
 const valid=cap<=4096 && top<=cap && cap-top>=768,status=e.frame_enter();
 assert.equal(status,valid?0:-5);
 if(!valid){assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer)),before);continue;}
 assert.equal(e.frame_top(),top+768);const active=Buffer.from(new Uint8Array(e.memory.buffer));
 assert.equal(e.frame_enter(),-4);assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer)),active);
 assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),top);
}
for(const top of [0,1,3328,3329,4095,4096,0xffffffff]){
 const e=new WebAssembly.Instance(module).exports,d=new DataView(e.memory.buffer);d.setUint32(400,4096,true);d.setUint32(404,top,true);
 const s=e.frame_enter();assert.equal(s,top<=3328?0:-5);if(!s){assert.equal(e.frame_top(),top+768);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),top);}
}
// Zero-byte owners have no bitmap allocation; all slots must be checked.
{
 const e=new WebAssembly.Instance(module).exports,d=new DataView(e.memory.buffer);
 assert.equal(e.frame_config(768),0);assert.equal(e.frame_enter(),0);assert.equal(e.reserve(192),1);
 assert.equal(e.frame_leave(),-4);assert.equal(d.getUint32(36,true),1);assert.equal(e.close(1,1),0);assert.equal(e.frame_leave(),0);
}
{
 const e=new WebAssembly.Instance(module).exports,d=new DataView(e.memory.buffer);assert.equal(e.frame_config(768),0);assert.equal(e.frame_enter(),0);
 for(let i=1;i<=4;i++)assert.equal(e.reserve(0),i);assert.equal(d.getUint32(144,true),0);assert.equal(e.frame_leave(),-4);
 for(let i=1;i<=4;i++){assert.equal(e.close(i,1),0);if(i<4)assert.equal(e.frame_leave(),-4);}
 assert.equal(e.frame_leave(),0);
}
{
 const e=new WebAssembly.Instance(module).exports,d=new DataView(e.memory.buffer);assert.equal(e.frame_config(768),0);
 d.setUint32(32,0xfffffffe,true);assert.equal(e.reserve(0),1);assert.equal(e.close(1,-1),0);assert.equal(d.getUint32(36,true),3);
 assert.equal(e.frame_enter(),0);assert.equal(e.frame_leave(),0);
}
console.log('independent frame boundary/zero-owner/retired controls passed');
