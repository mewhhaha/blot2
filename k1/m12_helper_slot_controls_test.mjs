// Independent all-owner-slot and freeze-precondition controls, to be run only
// after the source-linked helper_source_test has produced the current target.
import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {inspect} from './i08_machine_inspect.mjs';
const bytes=readFileSync('private-invoke.wasm');assert(inspect(bytes).ok);
const mod=new WebAssembly.Module(bytes);
for(let targetSlot=1;targetSlot<=4;targetSlot++)for(let n=0;n<=8;n++){
 const e=new WebAssembly.Instance(mod).exports,m=new Uint8Array(e.memory.buffer),d=new DataView(m.buffer);
 const get=p=>d.getUint32(p,true);assert.equal(e.frame_config(1024),0);assert.equal(e.frame_enter(),0);
 const prior=[];
 for(let k=1;k<targetSlot;k++){const slot=e.reserve(0);assert.equal(slot,k);prior.push([slot,get(16+32*(slot-1)+16)]);}
 const slot=e.reserve(192);assert.equal(slot,targetSlot);const gen=get(16+32*(slot-1)+16),di=256+16*(slot-1),db=320+16*(slot-1);
 assert.equal(e.input_alloc(slot,gen,n),0);const inp=get(di+8);if(n)m.fill(0x51,inp,inp+16*n);
 assert.equal(e.input_freeze(slot,gen),n);assert.equal(e.builder_alloc(slot,gen,8),0);const out=get(db+8);
 assert.equal(out,get(16+32*(slot-1))+16*n);assert.equal(e.project(slot,gen,slot,gen,.25),n);
 if(n)assert(m.subarray(inp,inp+16*n).every(x=>x===0x51));
 assert.equal(get(db+8),n?out:0);assert.equal(get(db+12),n);
 assert.equal(e.output_end(slot,gen),0);assert.equal(e.input_end(slot,gen),0);assert.equal(e.close(slot,gen),0);
 for(const [s,g] of prior)assert.equal(e.close(s,g),0);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);assert.equal(get(144),0);
}
// The freeze helper does not track individual writes. A raw allocated input can
// be frozen without any write, so source/caller initialization remains required.
{
 const e=new WebAssembly.Instance(mod).exports,d=new DataView(e.memory.buffer);assert.equal(e.reserve(16),1);const gen=d.getUint32(32,true);
 assert.equal(e.input_alloc(1,gen,1),0);assert.equal(e.input_freeze(1,gen),1);
 assert.equal(e.input_end(1,gen),0);assert.equal(e.close(1,gen),0);
}
console.log('all four owner slots, 0–8 rows, and freeze initialization premise passed');
