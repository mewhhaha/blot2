import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {create} from './i08_same_bridge.mjs';
const bytes=readFileSync('particle-lower-a.wasm');
const wasm=new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
const mem=new Uint8Array(wasm.memory.buffer),view=new DataView(mem.buffer);
for(let count=0;count<=8;count++) {
 const id=wasm.reserve(count*24);assert(id>0);const gen=view.getUint32(16+(id-1)*32+16,true);
 assert.equal(wasm.input_alloc(id,gen,count),0);
 const ip=view.getUint32(256+(id-1)*16+8,true);
 if(count) {assert(ip>=4096);assert(ip+16*count<=mem.length);}
 assert.equal(wasm.input_freeze(id,gen),count);
 assert.equal(wasm.builder_alloc(id,gen,count),0);
 const op=view.getUint32(320+(id-1)*16+8,true);
 if(count) {assert(op>=ip+16*count);assert(op+8*count<=mem.length);}
 assert.equal(wasm.project(id,gen,id,gen,0.25),count);
 assert.equal(wasm.output_end(id,gen),0);assert.equal(wasm.input_end(id,gen),0);assert.equal(wasm.close(id,gen),0);
 assert.equal(view.getUint32(144,true),0);
}
let traps=0;
class Hostile extends Uint8Array {
 get length(){traps++;throw Error('length');} get byteLength(){traps++;throw Error('byteLength');}
 get buffer(){traps++;throw Error('buffer');} get byteOffset(){traps++;throw Error('byteOffset');}
 subarray(){traps++;throw Error('subarray');} every(){traps++;throw Error('every');}
 [Symbol.iterator](){traps++;throw Error('iterator');}
}
const target=new Hostile(bytes.length);Uint8Array.prototype.set.call(target,bytes);const bridge=create(target);
const input=new Hostile(60);const base=new Uint8Array(60),d=new DataView(base.buffer);
d.setUint32(0,0x4b310001,true);d.setUint32(4,91,true);d.setUint32(12,28,true);d.setFloat32(32,1,true);d.setUint32(36,1,true);d.setUint32(40,12,true);
d.setFloat32(44,1,true);d.setFloat32(48,2,true);d.setFloat32(52,3,true);d.setFloat32(56,4,true);
Uint8Array.prototype.set.call(input,base);
const result=bridge.call(input,16);assert.equal(result.status,'Ok');assert.equal(traps,0);assert.equal(bridge.inspect().calls,1);assert.equal(bridge.inspect().lastClosed,true);
for(let capacity=0;capacity<=18;capacity++){const count=bridge.inspect().calls;const r=bridge.call(input,capacity);assert.equal(r.status,capacity<16?'OutputTooSmall':'Ok');assert.equal(bridge.inspect().calls,count+1);assert.equal(bridge.inspect().lastClosed,true);}
const detached=new Uint8Array(44);structuredClone(detached,{transfer:[detached.buffer]});
assert.equal(bridge.call(detached,16).status,'InvalidInput');assert.equal(bridge.inspect().lastClosed,true);
const proxy=new Proxy(input,{});assert.throws(()=>bridge.call(proxy,16),TypeError);assert.equal(bridge.inspect().running,false);assert.equal(bridge.inspect().lastClosed,true);
console.log('range/descriptor/hostile input controls passed');
