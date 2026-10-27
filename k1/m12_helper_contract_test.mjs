// Independent executable controls for the *actual* source-checked fixed target.
// The caller-flow Goose test must emit private-invoke.wasm in this directory.
// This is not a proof of general ownership, runtime authority or all inputs.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { inspect } from './i08_machine_inspect.mjs';
import { decode } from './i08_machine_decode.mjs';
import { verifyHelperStructure } from './m12_helper_structure.mjs';
const canonical = readFileSync('private-invoke.wasm');
assert.equal(inspect(canonical).ok, true); // exact guarded canonical machine target
const bytes = process.argv[2] ? readFileSync(process.argv[2]) : canonical;
const graph=decode(bytes); assert(verifyHelperStructure(graph));
const canonGraph=decode(canonical);
// Alternate targets must be emitted and checked by the source-linked Goose
// test. Their helpers/caller are compared instruction-by-instruction to the
// pinned canonical target, independent of changed worker instruction offsets.
for(const i of [0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,18,19,20,21,22]) {
 const shape=b=>b.ops.map(({op,imm})=>({op,imm}));
 assert.deepEqual(shape(graph.bodies[i]),shape(canonGraph.bodies[i]));
}
// Change one operand in each key guard and require structural rejection even
// independently of the full-target pin. The graph is test-only, not evidence.
for(const [fn,op,value] of [[4,0,1],[5,3,2],[6,3,3],[8,3,2],[9,0,1],[11,3,3],[12,3,3],[13,3,3]]) {
 const copy=structuredClone(graph); copy.bodies[fn].ops[op].imm=value;
 assert.equal(verifyHelperStructure(copy),false);
}
const mod = new WebAssembly.Module(bytes);
assert.deepEqual(WebAssembly.Module.imports(mod), []);
let checks = 0;
function fresh() {
 const e = new WebAssembly.Instance(mod).exports;
 const m = new Uint8Array(e.memory.buffer), d = new DataView(m.buffer);
 return {e,m,d};
}
function val(d,p){return d.getUint32(p,true)}
function put(d,p,v){d.setUint32(p,v>>>0,true)}
function unchanged(s, fn, expected) {
 const before = Uint8Array.from(s.m);
 assert.equal(fn(), expected); assert.deepEqual(s.m,before); checks++;
}
function owner(s, bytes=192) {
 const slot=s.e.reserve(bytes); assert(slot>=1 && slot<=4);
 const ptr=16+32*(slot-1), gen=val(s.d,ptr+16);
 assert(gen!==0); assert.equal(val(s.d,ptr+20),1);
 assert.equal(val(s.d,ptr+4),bytes);return {slot,ptr,gen};
}
function setup(n,cap=8) {
 const s=fresh(); assert.equal(s.e.frame_config(1024),0); assert.equal(s.e.frame_enter(),0);
 const o=owner(s),i=256+16*(o.slot-1),b=320+16*(o.slot-1);
 assert.equal(s.e.input_alloc(o.slot,o.gen,n),0);
 const base=val(s.d,i+8); assert.equal(base,n?val(s.d,o.ptr):0);
 for(let k=0;k<n*16;k++)s.m[base+k]=(k*23+7)&255;
 assert.equal(s.e.input_freeze(o.slot,o.gen),n);
 assert.equal(s.e.builder_alloc(o.slot,o.gen,cap),0);
 return {...s,...o,i,b,base};
}
for (let n=0;n<=8;n++) {
 const s=setup(n),{e,d,m,slot,gen,ptr,i,b}=s;
 const output=val(d,b+8), top=val(d,ptr+12), ownerBase=val(d,ptr);
 assert.equal(top,16*n+64); assert.equal(output,ownerBase+16*n);
 assert.equal(val(d,i),2);assert.equal(val(d,b),1);assert.equal(val(d,b+12),0);
 assert.equal(val(d,384+4*(slot-1)),8);
 unchanged(s,()=>e.close(slot,gen),-4);
 unchanged(s,()=>e.input_end(slot,gen+1),-4);
 unchanged(s,()=>e.output_end(slot,gen+1),-4);
 unchanged(s,()=>e.project(slot,gen+1,slot,gen,0),-4);
 unchanged(s,()=>e.project(slot,gen,slot,gen+1,0),-4);
 const before=Uint8Array.from(m.subarray(ownerBase,ownerBase+16*n));
 assert.equal(e.project(slot,gen,slot,gen,.5),n);
 assert.deepEqual(m.subarray(ownerBase,ownerBase+16*n),before);
 assert.equal(val(d,b),2);assert.equal(val(d,b+12),n);assert.equal(val(d,b+8),n?output:0);
 unchanged(s,()=>e.project(slot,gen,slot,gen,.5),-4);
 unchanged(s,()=>e.close(slot,gen),-4);
 assert.equal(e.output_end(slot,gen),0);assert.equal(val(d,b),0);
 unchanged(s,()=>e.output_end(slot,gen),-4);
 unchanged(s,()=>e.close(slot,gen),-4);
 assert.equal(e.input_end(slot,gen),0);assert.equal(val(d,i),0);
 unchanged(s,()=>e.input_end(slot,gen),-4);
 assert.equal(e.close(slot,gen),0);assert.equal(val(d,144),0);
 unchanged(s,()=>e.close(slot,gen),-4);
 assert.equal(e.reserve(192),slot);assert.notEqual(val(d,ptr+16),gen);
 unchanged(s,()=>e.input_alloc(slot,gen,1),-4);
 unchanged(s,()=>e.close(slot,gen),-4);
 checks++;
}
// Allocation rejects invalid handles, multiplication overflow, capacity
// overflow and duplicate live descriptors before writing any byte.
{
 const s=fresh(),o=owner(s),{e}=s;
 for(const slot of [0,5,0xffffffff]) unchanged(s,()=>e.input_alloc(slot,o.gen,1),-4);
 unchanged(s,()=>e.input_alloc(o.slot,0,1),-4);
 unchanged(s,()=>e.input_alloc(o.slot,o.gen,268435456),-1);
 unchanged(s,()=>e.input_alloc(o.slot,o.gen,13),-2);
 unchanged(s,()=>e.builder_alloc(o.slot,o.gen,536870912),-1);
 unchanged(s,()=>e.builder_alloc(o.slot,o.gen,25),-2);
 assert.equal(e.input_alloc(o.slot,o.gen,1),0);
 unchanged(s,()=>e.input_alloc(o.slot,o.gen,1),-4);
 unchanged(s,()=>e.close(o.slot,o.gen),-4);
 assert.equal(e.input_discard(o.slot,o.gen),0);
 assert.equal(e.close(o.slot,o.gen),0);
}
// Each isolated descriptor or owner corruption must be rejected without writes
// before worker entry. Corruption is inserted by this test only; such memory
// is not an authorization model, nor assumed safe to expose to hostile hosts.
{
 const s=setup(2);const d=s.d,o=s.ptr,i=s.i,b=s.b;
 const cases=[
  [i,1], [i+4,s.gen+1], [i+8,val(d,o)+4], [i+12,0x10000000],
  [b,0], [b+4,s.gen+1], [b+12,1],
  [b+8,val(d,o)], [b+8,val(d,o)+33], [b+8,val(d,o)+196],
  [384+4*(s.slot-1),0x20000000],
  [o+12,193], [o+16,s.gen+1], [o+20,0], [144,0]
 ];
 for(const [p,value] of cases) {
  const old=val(d,p);put(d,p,value);
  unchanged(s,()=>s.e.project(s.slot,s.gen,s.slot,s.gen,.25),-4);
  put(d,p,old);
 }
}
// Distinct formal region labels never establish disjoint backing: project
// explicitly requires the same owner in this fixture and rejects a different
// live owner even if both records are valid.
{
 const s=setup(2),other=owner(s,64);
 unchanged(s,()=>s.e.project(s.slot,s.gen,other.slot,other.gen,.25),-4);
 assert.equal(s.e.close(other.slot,other.gen),0);
}
// An undersized but otherwise valid builder fails before data or descriptor
// changes. This negative control is deliberately not classified as a trap.
{
 const s=setup(2,1);
 unchanged(s,()=>s.e.project(s.slot,s.gen,s.slot,s.gen,.25),-3);
 assert.equal(s.e.output_end(s.slot,s.gen),0);
 assert.equal(s.e.input_end(s.slot,s.gen),0);
 assert.equal(s.e.close(s.slot,s.gen),0);
}
console.log(`fixed-target helper contract executable audit passed (${checks} controls)`);
