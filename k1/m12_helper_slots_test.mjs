import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
const mod=new WebAssembly.Module(readFileSync('private-invoke.wasm'));
for(let wanted=1;wanted<=4;wanted++)for(let n=0;n<=8;n++) {
 const e=new WebAssembly.Instance(mod).exports,m=new Uint8Array(e.memory.buffer),d=new DataView(m.buffer);
 assert.equal(e.frame_config(1024),0);assert.equal(e.frame_enter(),0);
 for(let i=1;i<wanted;i++)assert.equal(e.reserve(0),i);
 assert.equal(e.reserve(192),wanted);const gen=d.getUint32(16+(wanted-1)*32+16,true),ipd=256+(wanted-1)*16,opd=320+(wanted-1)*16;
 assert.equal(e.input_alloc(wanted,gen,n),0);const ip=d.getUint32(ipd+8,true);for(let i=0;i<n*4;i++)d.setFloat32(ip+i*4,i+1,true);
 assert.equal(e.input_freeze(wanted,gen),n);assert.equal(e.builder_alloc(wanted,gen,8),0);const op=d.getUint32(opd+8,true);
 assert.equal(e.project(wanted,gen,wanted,gen,.5),n);assert.equal(d.getUint32(opd,true),2);assert.equal(d.getUint32(opd+12,true),n);
 for(let i=0;i<n;i++){const base=i*4;assert.equal(d.getFloat32(op+i*8,true),base+1+(base+3)*.5);assert.equal(d.getFloat32(op+i*8+4,true),base+2+(base+4)*.5);}
 assert.equal(e.output_end(wanted,gen),0);assert.equal(e.input_end(wanted,gen),0);assert.equal(e.close(wanted,gen),0);
 for(let i=1;i<wanted;i++)assert.equal(e.close(i,1),0);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);assert.equal(d.getUint32(144,true),0);
}
console.log('independent owner-slot 1..4 lifecycle and F32 execution passed');
