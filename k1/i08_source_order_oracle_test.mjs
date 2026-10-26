import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {create} from './i08_source_order_window.mjs';
const target=readFileSync('live-worker.wasm'),bridge=create(target);
let seed=0x21b4a9d3;function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;}
function valid(b) {
 if(b.length<44||b.length>256)return false;
 const w=p=>b[p]+256*b[p+1]+65536*b[p+2]+16777216*b[p+3];
 if(w(0)!==0x4b310001||w(4)!==91||w(8)!==0||w(12)!==b.length-32||w(16)||w(20)||w(24)||w(28))return false;
 const count=w(32),offset=w(36),payload=b.length-32;
 if(count>8||offset%4||offset<12||offset>payload||count*16>payload-offset)return false;
 for(let i=44;i<b.length;i++){const x=i-32;if((x<offset||x>=offset+count*16)&&b[i]!==0)return false;}
 return true;
}
function pack(n) {const b=new Uint8Array(44+16*n),d=new DataView(b.buffer);d.setUint32(0,0x4b310001,true);d.setUint32(4,91,true);
 d.setUint32(12,b.length-32,true);d.setUint32(32,n,true);d.setUint32(36,12,true);return b;}
let accepted=0,rejected=0;
for(let i=0;i<10000;i++) {
 let b=pack(rnd()%9);
 switch(rnd()%8) {
  case 0:break;
  case 1:b[rnd()%32]^=1<<(rnd()%8);break;
  case 2:b[32+rnd()%8]^=1<<(rnd()%8);break;
  case 3:b=Uint8Array.from(b.subarray(0,rnd()%(b.length+1)));break;
  case 4:{const a=new Uint8Array(b.length+4);a.set(b);new DataView(a.buffer).setUint32(12,a.length-32,true);b=a;break;}
  case 5:{const a=new Uint8Array(b.length+4);a.set(b);a[a.length-1]=1;new DataView(a.buffer).setUint32(12,a.length-32,true);b=a;break;}
  case 6:{let a=new Uint8Array(b.length+4);a.set(b.subarray(0,44));a.set(b.subarray(44),48);let d=new DataView(a.buffer);d.setUint32(12,a.length-32,true);d.setUint32(36,16,true);b=a;break;}
  case 7:{const j=rnd()%b.length;b[j]^=1<<(rnd()%8);break;}
 }
 const ok=valid(b),before=bridge.inspect().calls,r=bridge.invoke(b,0);
 assert.equal(r.status,ok?2:1);assert.equal(bridge.inspect().calls,before+(ok?1:0));
 assert.equal(bridge.inspect().running,false);assert.equal(bridge.inspect().frameTop,0);ok?accepted++:rejected++;
}
console.log(`private fixed-window independent oracle passed ${accepted} valid ${rejected} invalid`);
