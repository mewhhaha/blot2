import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
const b=readFileSync('private-invoke.wasm'),mod=new WebAssembly.Module(b);assert.equal(WebAssembly.Module.imports(mod).length,0);
const e=new WebAssembly.Instance(mod).exports,mem=new Uint8Array(e.memory.buffer),d=new DataView(mem.buffer);let seed=0x21b4a9d3;
function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;}
function valid(b) {
 if(b.length<44||b.length>256)return false;
 const w=p=>b[p]+256*b[p+1]+65536*b[p+2]+16777216*b[p+3];
 if(w(0)!==0x4b310001||w(4)!==91||w(8)!==0||w(12)!==b.length-32||w(16)||w(20)||w(24)||w(28))return false;
 const count=w(32),offset=w(36),payload=b.length-32;
 if(count>8||offset%4||offset<12||offset>payload||count*16>payload-offset)return false;
 for(let i=44;i<b.length;i++){const x=i-32;if((x<offset||x>=offset+count*16)&&b[i]!==0)return false;}return true;
}
function pack(n) {const a=new Uint8Array(44+16*n),v=new DataView(a.buffer);v.setUint32(0,0x4b310001,true);v.setUint32(4,91,true);v.setUint32(12,a.length-32,true);v.setUint32(32,n,true);v.setUint32(36,12,true);return a;}
let accepted=0,rejected=0;
for(let i=0;i<10000;i++) {
 let x=pack(rnd()%9);switch(rnd()%8) {
  case 0:break;case 1:x[rnd()%32]^=1<<(rnd()%8);break;case 2:x[32+rnd()%8]^=1<<(rnd()%8);break;
  case 3:x=Uint8Array.from(x.subarray(0,rnd()%(x.length+1)));break;
  case 4:{let a=new Uint8Array(x.length+4);a.set(x);new DataView(a.buffer).setUint32(12,a.length-32,true);x=a;break;}
  case 5:{let a=new Uint8Array(x.length+4);a.set(x);a[a.length-1]=1;new DataView(a.buffer).setUint32(12,a.length-32,true);x=a;break;}
  case 6:{let a=new Uint8Array(x.length+4);a.set(x.subarray(0,44));a.set(x.subarray(44),48);let v=new DataView(a.buffer);v.setUint32(12,a.length-32,true);v.setUint32(36,16,true);x=a;break;}
  case 7:x[rnd()%x.length]^=1<<(rnd()%8);break;
 }
 mem.fill(0,32768,33024);mem.set(x,32768);mem.fill(0xa5,36896,37120);const inbefore=Uint8Array.from(mem.subarray(32768,33024));
 const ok=valid(x),status=e.invoke(91,x.length,0);assert.equal(status,ok?2:1);assert.deepEqual(mem.subarray(32768,33024),inbefore);
 const vals=Array.from({length:8},(_,j)=>d.getUint32(36864+j*4,true));const n=ok?new DataView(x.buffer).getUint32(32,true):0;
 assert.deepEqual(vals,[0x4b310001,91,ok?2:1,0,ok?8+n*8:0,n,0,0]);
 assert(mem.subarray(36896,37120).every(v=>v===0xa5));assert.equal(d.getUint32(416,true),0);assert.equal(d.getUint32(144,true),0);assert.equal(e.frame_top(),0);
 for(let slot=0;slot<4;slot++)assert([0,3].includes(d.getUint32(36+32*slot,true)));
 ok?accepted++:rejected++;
}
console.log(`independent actual Wasm wire/reuse/cleanup oracle passed ${accepted} accepted ${rejected} rejected`);
for(let test=0;test<500;test++) {
 const n=test%9,x=pack(n),v=new DataView(x.buffer);v.setFloat32(40,.25,true);
 for(let row=0;row<n;row++)for(let col=0;col<4;col++)v.setFloat32(44+row*16+col*4,((rnd()%10001)-5000)/32,true);
 const need=8+n*8,cap=[0,need-1,need,224][test%4];mem.fill(0,32768,33024);mem.set(x,32768);mem.fill(0xa5,36896,37120);
 const before=Uint8Array.from(mem.subarray(32768,33024)),status=e.invoke(91,x.length,cap),ok=cap>=need;
 assert.equal(status,ok?0:2);assert.deepEqual(mem.subarray(32768,33024),before);
 assert.deepEqual(Array.from({length:8},(_,j)=>d.getUint32(36864+j*4,true)),[0x4b310001,91,ok?0:2,ok?need:0,need,n,0,0]);
 if(ok){assert.equal(d.getUint32(36896,true),n);assert.equal(d.getUint32(36900,true),8);
  for(let row=0;row<n;row++){const i=44+16*row,xv=v.getFloat32(i,true),yv=v.getFloat32(i+4,true),vx=v.getFloat32(i+8,true),vy=v.getFloat32(i+12,true);
   assert.equal(d.getFloat32(36904+row*8,true),Math.fround(xv+Math.fround(vx*.25)));
   assert.equal(d.getFloat32(36908+row*8,true),Math.fround(yv+Math.fround(vy*.25)));}}
 else assert(mem.subarray(36896,37120).every(x=>x===0xa5));
 assert.equal(d.getUint32(416,true),0);assert.equal(d.getUint32(144,true),0);assert.equal(e.frame_top(),0);
}
d.setUint32(416,1,true);const held=Uint8Array.from(mem);assert.equal(e.invoke(91,44,0),4);assert.deepEqual(mem,held);d.setUint32(416,0,true);
console.log('independent Wasm success/capacity/F32 and Busy controls passed');
