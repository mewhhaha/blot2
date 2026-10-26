import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {invoke} from './i08_live_authority.mjs';
const target=readFileSync('live-worker.wasm');
for(let i=0;i<target.length;i++){const bad=Uint8Array.from(target);bad[i]^=1;assert.throws(()=>invoke(bad,new Uint8Array(),0,0),TypeError);}
for(let i=0;i<target.length;i++){assert.throws(()=>invoke(target.subarray(0,i),new Uint8Array(),0,0),TypeError);}
let traps=0;
class Hostile extends Uint8Array {get length(){traps++;throw Error('length');}get buffer(){traps++;throw Error('buffer');}
 get byteLength(){traps++;throw Error('byteLength');}get byteOffset(){traps++;throw Error('byteOffset');}
 subarray(){traps++;throw Error('subarray');}every(){traps++;throw Error('every');}[Symbol.iterator](){traps++;throw Error('iter');}}
const htarget=new Hostile(target.length);Uint8Array.prototype.set.call(htarget,target);const hinput=new Hostile(16);
const raw=new Uint8Array(16),view=new DataView(raw.buffer);for(let i=0;i<4;i++)view.setFloat32(i*4,i+1,true);Uint8Array.prototype.set.call(hinput,raw);
const first=invoke(htarget,hinput,1,.5);assert.equal(first.status,'Ok');assert.equal(first.calls,1);assert.equal(first.closed,true);assert.equal(traps,0);
const saved=Uint8Array.from(first.output);Uint8Array.prototype.fill.call(hinput,0);assert.deepEqual(first.output,saved);
const detached=new Uint8Array(16);structuredClone(detached,{transfer:[detached.buffer]});assert.throws(()=>invoke(target,detached,1,.5),TypeError);
assert.throws(()=>invoke(target,new Proxy(raw,{}),1,.5),TypeError);
let seed=0x31415926;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;},f=Math.fround;
for(let count=0;count<=8;count++)for(let k=0;k<50;k++){
 const arr=new Uint8Array(count*16),dv=new DataView(arr.buffer),vals=[];
 for(let i=0;i<count;i++){const row=[];for(let j=0;j<4;j++){const x=f(((rand()%2001)-1000)/16);row.push(x);dv.setFloat32(i*16+j*4,x,true);}vals.push(row);}
 const dt=f(((rand()%201)-100)/16),out=invoke(target,arr,count,dt);assert.equal(out.status,'Ok');assert.equal(out.calls,1);assert.equal(out.closed,true);
 const dvout=new DataView(out.output.buffer);for(let i=0;i<count;i++) {const [x,y,vx,vy]=vals[i];assert(Object.is(dvout.getFloat32(i*8,true),f(x+f(vx*dt))));assert(Object.is(dvout.getFloat32(i*8+4,true),f(y+f(vy*dt))));}
}
console.log('independent live-target corruption, hostile input and finite F32 controls passed');
