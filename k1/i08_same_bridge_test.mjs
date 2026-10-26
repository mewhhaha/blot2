import { strict as assert } from 'node:assert';
import {readFileSync} from 'node:fs';
import {create} from './i08_same_bridge.mjs';
const bytes=readFileSync('particle-lower-a.wasm');
function pack(rows,dt,pad=0) {
 const off=12+pad,len=32+off+16*rows.length,b=new Uint8Array(len),d=new DataView(b.buffer);
 d.setUint32(0,0x4b310001,true);d.setUint32(4,91,true);d.setUint32(12,len-32,true);
 d.setFloat32(32,dt,true);d.setUint32(36,rows.length,true);d.setUint32(40,off,true);
 rows.forEach((r,i)=>r.forEach((v,j)=>d.setFloat32(32+off+16*i+4*j,v,true)));return b;
}
const f=create(bytes),rows=[[1,-2,3,4],[5,6,-2,-3]],input=pack(rows,0.5,4),before=Uint8Array.from(input);
let out=f.call(input,24);assert.equal(out.status,'Ok');assert.deepEqual(input,before);
const data=new DataView(out.payload.buffer);assert.equal(data.getUint32(0,true),2);assert.equal(data.getUint32(4,true),8);
assert.deepEqual([0,1,2,3].map(i=>data.getFloat32(8+4*i,true)),[2.5,0,4,4.5]);assert.equal(f.inspect().lastClosed,true);
const old=Uint8Array.from(out.payload);assert.deepEqual(f.call(input,23),{status:'OutputTooSmall',required:24,count:2});
assert.deepEqual(out.payload,old);assert.equal(f.inspect().lastClosed,true);
assert.equal(f.call(pack([],0),8).status,'Ok');assert.equal(f.inspect().lastClosed,true);
for(let i=0;i<7;i++) {
 const invalid=Uint8Array.from(input),d=new DataView(invalid.buffer);
 if(i===0)d.setUint32(0,0,true);if(i===1)d.setUint32(8,1,true);if(i===2)d.setUint32(36,9,true);
 if(i===3)d.setUint32(40,13,true);if(i===4)d.setUint32(40,4,true);if(i===5)invalid[44]=1;
 if(i===6)d.setUint32(40,250,true);
 const calls=f.inspect().calls;assert.equal(f.call(invalid,224).status,'InvalidInput');assert.equal(f.inspect().calls,calls);assert.equal(f.inspect().lastClosed,true);
}
for(const [fault,status] of [[1,'ReservationFailed'],[2,'InjectedCopyFailure'],[3,'InjectedSetupFailure'],[4,'InjectedLanguageFailure'],[5,'InjectedPostCallFailure']]) {
 const broken=create(bytes,fault),r=broken.call(input,224);
 assert.equal(r.status,status);assert.equal(broken.inspect().lastClosed,true);
 assert.equal(broken.inspect().calls,fault===5?1:0);
}
class Spoof extends Uint8Array {get length(){return bytes.length} every(){return true}}
const fake=new Spoof(bytes.length-1);fake.set(bytes.subarray(0,bytes.length-1));assert.throws(()=>create(fake),TypeError);
for(let n=0;n<=8;n++)for(let j=0;j<100;j++) {
 const rows=Array.from({length:n},(_,i)=>[i+1,j+1,i-j,j-i]),dt=.25;
 const r=f.call(pack(rows,dt),224);assert.equal(r.status,'Ok');const d=new DataView(r.payload.buffer);
 for(let i=0;i<n;i++){assert.equal(d.getFloat32(8+i*8,true),Math.fround(rows[i][0]+Math.fround(rows[i][2]*dt)));
 assert.equal(d.getFloat32(12+i*8,true),Math.fround(rows[i][1]+Math.fround(rows[i][3]*dt)));}
 assert.equal(f.inspect().lastClosed,true);
}
console.log('private single-call particle copy bridge passed');
