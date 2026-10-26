import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {create} from './i08_source_order_window.mjs';
const target=readFileSync('live-worker.wasm');
function pack(n,dt=.5,pad=0) {
 const off=12+pad,len=32+off+16*n,b=new Uint8Array(len),d=new DataView(b.buffer);
 d.setUint32(0,0x4b310001,true);d.setUint32(4,91,true);d.setUint32(12,len-32,true);
 d.setUint32(32,n,true);d.setUint32(36,off,true);d.setFloat32(40,dt,true);
 for(let i=0;i<n;i++)for(let k=0;k<4;k++)d.setFloat32(32+off+i*16+k*4,i+k+1,true);
 return b;
}
function header(result,status,payload,required,count,detail=0) {
 assert.equal(result.status,status);assert.equal(result.frame.length,32+payload);
 const d=new DataView(result.frame.buffer);assert.deepEqual(Array.from({length:8},(_,i)=>d.getUint32(i*4,true)),[0x4b310001,91,status,payload,required,count,detail,0]);
}
for(let i=0;i<target.length;i++){const bad=Uint8Array.from(target);bad[i]^=1;assert.throws(()=>create(bad),TypeError);}
const b=create(target);
for(let n=0;n<=8;n++)for(const pad of [0,4,8]) {
 const input=pack(n,.5,pad),snapshot=input.slice(),before=b.inspect().calls,need=8+n*8;
 const inView=new DataView(input.buffer);assert.equal(inView.getUint32(32,true),n);assert.equal(inView.getUint32(36,true),12+pad);assert.equal(inView.getFloat32(40,true),.5);
 const ok=b.invoke(input,need);header(ok,0,need,need,n);assert.equal(b.inspect().calls,before+1);
 assert.equal(b.inspect().running,false);assert.equal(b.inspect().frameTop,0);assert.deepEqual(input,snapshot);
 const d=new DataView(ok.frame.buffer);assert.equal(d.getUint32(32,true),n);assert.equal(d.getUint32(36,true),8);
 for(let i=0;i<n;i++){assert.equal(d.getFloat32(40+i*8,true),i+1+(i+3)*.5);assert.equal(d.getFloat32(44+i*8,true),i+2+(i+4)*.5);}
 const old=ok.frame.slice(),count=b.inspect().calls;const small=b.invoke(input,need-1);header(small,2,0,need,n);
 assert.equal(b.inspect().calls,count+1);assert.deepEqual(ok.frame,old);
}
let baseline=b.inspect().calls;const input=pack(2,.5,4);
// An earlier fixture encoded dt before the descriptor. It is not the
// checked adapter's `{source, dt, output}` order and must be rejected here.
const oldOrder=input.slice(),oldView=new DataView(oldOrder.buffer);
oldView.setFloat32(32,.5,true);oldView.setUint32(36,2,true);oldView.setUint32(40,16,true);
header(b.invoke(oldOrder,224),1,0,0,0);assert.equal(b.inspect().calls,baseline);
header(b.invoke(input,225),1,0,0,0);assert.equal(b.inspect().calls,baseline);assert.equal(b.inspect().frameTop,0);
for(let kind=0;kind<13;kind++) {
 const bad=input.slice(),d=new DataView(bad.buffer);
 if(kind===0)d.setUint32(0,0,true);if(kind===1)d.setUint32(4,92,true);if(kind===2)d.setUint32(8,1,true);
 if(kind===3)d.setUint32(12,0,true);if(kind===4)d.setUint32(16,1,true);if(kind===5)d.setUint32(20,1,true);
 if(kind===6)d.setUint32(24,1,true);if(kind===7)d.setUint32(28,1,true);if(kind===8)d.setUint32(32,9,true);
 if(kind===9)d.setUint32(36,13,true);if(kind===10)d.setUint32(36,4,true);if(kind===11)bad[44]=1;if(kind===12)d.setUint32(36,200,true);
 header(b.invoke(bad,224),1,0,0,0);assert.equal(b.inspect().calls,baseline);assert.equal(b.inspect().frameTop,0);
}
for(const size of [0,1,31,32,43,257]){header(b.invoke(new Uint8Array(size),0),1,0,0,0);assert.equal(b.inspect().calls,baseline);}
const frame=create(target,767);header(frame.invoke(input,224),5,0,0,0);assert.deepEqual(frame.inspect(),{running:false,poisoned:false,frameTop:0,calls:0});
const reserved=create(target,1024,1);header(reserved.invoke(input,224),3,0,0,0,1);assert.equal(reserved.inspect().calls,0);assert.equal(reserved.inspect().frameTop,0);
for(const [fault,expected] of [[2,0],[3,1]]) {const failure=create(target,1024,fault);assert.equal(failure.invoke(input,224).status,'Poisoned');
 assert.deepEqual(failure.inspect(),{running:false,poisoned:true,frameTop:0,calls:expected});assert.equal(failure.invoke(input,224).status,'Poisoned');}
let traps=0;class Hostile extends Uint8Array {get length(){traps++;throw Error('length');}get buffer(){traps++;throw Error('buffer');}
 get byteOffset(){traps++;throw Error('byteOffset');}get byteLength(){traps++;throw Error('byteLength');}
 subarray(){traps++;throw Error('subarray');}[Symbol.iterator](){traps++;throw Error('iter');}}
const h=new Hostile(input.length);Uint8Array.prototype.set.call(h,input);const success=b.invoke(h,224);header(success,0,24,24,2);assert.equal(traps,0);
const detached=new Uint8Array(44);structuredClone(detached,{transfer:[detached.buffer]});header(b.invoke(detached,0),1,0,0,0);
assert.throws(()=>b.invoke(new Proxy(h,{}),224),TypeError);assert.equal(b.inspect().running,false);assert.equal(b.inspect().frameTop,0);
console.log('private fixed-window source-bound wrapper passed');
