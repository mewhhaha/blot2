import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {invoke} from './i08_live_authority.mjs';
const target=readFileSync('live-worker.wasm');
for(let n=0;n<=8;n++) {
 const input=new Uint8Array(n*16),d=new DataView(input.buffer);
 for(let i=0;i<n;i++)for(let j=0;j<4;j++)d.setFloat32(16*i+4*j,i+j+1,true);
 const out=invoke(target,input,n,.5);assert.equal(out.status,'Ok');assert.equal(out.calls,1);assert.equal(out.closed,true);
 const od=new DataView(out.output.buffer);for(let i=0;i<n;i++) {
  assert.equal(od.getFloat32(i*8,true),i+1+(i+3)*.5);
  assert.equal(od.getFloat32(i*8+4,true),i+2+(i+4)*.5);
 }
 for(let forged=0;forged<14;forged++)assert.deepEqual(invoke(target,input,n,.5,forged),{status:'InvalidLiveState',calls:0,disposed:true});
 assert.deepEqual(invoke(target,input,n,.5,14),{status:'Poisoned',calls:0,disposed:true});
 assert.deepEqual(invoke(target,input,n,.5,15),{status:'Poisoned',calls:1,disposed:true});
}
let bad=Uint8Array.from(target);bad[bad.length-1]^=1;assert.throws(()=>invoke(bad,new Uint8Array(),0,.5),TypeError);
console.log('private live Wasm authority/descriptor/trap witness passed');
