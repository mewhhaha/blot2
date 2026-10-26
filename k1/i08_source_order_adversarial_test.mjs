import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {create} from './i08_source_order_window.mjs';
const target=readFileSync('live-worker.wasm'), f=Math.fround;
const dts=[0,0x80000000,0x3f000000,0x7f800000,0xff800000,0x7fc12345];
function make(n,offset,bits,old=false){let b=new Uint8Array(32+offset+n*16),v=new DataView(b.buffer);v.setUint32(0,0x4b310001,true);v.setUint32(4,91,true);v.setUint32(12,b.length-32,true);
 if(old){v.setUint32(32,bits,true);v.setUint32(36,n,true);v.setUint32(40,offset,true);}else{v.setUint32(32,n,true);v.setUint32(36,offset,true);v.setUint32(40,bits,true);}
 for(let i=0;i<n;i++)for(let j=0;j<4;j++)v.setFloat32(32+offset+i*16+j*4,i+j+1,true);return b;}
let good=0,bad=0;const bridge=create(target);
for(let n=0;n<=8;n++)for(let offset=12;offset<=64;offset+=4)for(let bits of dts){if(offset+n*16>224)continue;
 const b=make(n,offset,bits),snapshot=b.slice(),before=bridge.inspect().calls,ret=bridge.invoke(b,224);assert.equal(ret.status,0);assert.equal(bridge.inspect().calls,before+1);assert.deepEqual(b,snapshot);
 const v=new DataView(ret.frame.buffer),dt=new DataView(Uint32Array.of(bits).buffer).getFloat32(0,true);assert.equal(v.getUint32(32,true),n);
 for(let i=0;i<n;i++)for(let k=0;k<2;k++){const actual=v.getFloat32(40+i*8+4*k,true),expect=f((i+k+1)+f((i+k+3)*dt));if(Number.isNaN(expect))assert(Number.isNaN(actual));else assert(Object.is(actual,expect));}
 const prior=bridge.inspect().calls,old=make(n,offset,bits,true);assert.equal(bridge.invoke(old,224).status,1);assert.equal(bridge.inspect().calls,prior);
 if(offset>12){let changed=b.slice();changed[44]=1;assert.equal(bridge.invoke(changed,224).status,1);assert.equal(bridge.inspect().calls,prior);}
 let cap=bridge.invoke(b,7+n*8);assert.equal(cap.status,2);assert.equal(cap.frame.length,32);assert.equal(bridge.inspect().calls,prior+1);good++;bad++;
}
console.log(`source-order independent offsets/float/old-order cases passed: ${good} valid, ${bad} old-order rejected`);
