import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
const normal=readFileSync('frame-arena.wasm'),trap=readFileSync('frame-trap.wasm');
assert(WebAssembly.validate(normal));assert(WebAssembly.validate(trap));
function instance(bytes,cap=768){const e=new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports,d=new DataView(e.memory.buffer);assert.equal(e.frame_config(cap),0);return {e,d};}
function setup(e,d,n=2,capacity=8){
 assert.equal(e.reserve(192),1);assert.equal(e.input_alloc(1,1,n),0);
 let p=d.getUint32(264,true);for(let i=0;i<n*4;i++)d.setFloat32(p+4*i,i+1,true);
 assert.equal(e.input_freeze(1,1),n);assert.equal(e.builder_alloc(1,1,capacity),0);
}
function close(e){assert.equal(e.output_end(1,1),0);assert.equal(e.input_end(1,1),0);assert.equal(e.close(1,1),0);}
function image(e){return Buffer.from(new Uint8Array(e.memory.buffer));}
// Admission before owner reservation and any copies. Failed entry preserves
// entire guest memory and no owner can have been reserved by this caller.
for(const cap of [0,1,767]) {const {e}=instance(normal,cap),before=image(e);assert.equal(e.frame_enter(),-5);assert.deepEqual(image(e),before);assert.equal(e.frame_top(),0);}
for(const cap of [768,769,4096]) {
 const {e,d}=instance(normal,cap);d.setUint8(49152,0xff);assert.equal(e.frame_enter(),0);assert.equal(e.frame_top(),768);
 assert.equal(d.getUint8(49152),0);const entered=image(e);assert.equal(e.frame_enter(),-4);assert.deepEqual(image(e),entered);
 setup(e,d);assert.equal(e.project(1,1,1,1,.5),2);assert.equal(e.frame_top(),768);
 const p=d.getUint32(328,true);assert.deepEqual([0,1,2,3].map(i=>d.getFloat32(p+4*i,true)),[2.5,4,8.5,10]);
 close(e);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);assert.equal(e.frame_leave(),-4);
}
{
 const {e,d}=instance(normal,1280);d.setUint32(404,512,true);d.setUint8(49152+512,0xff);
 assert.equal(e.frame_enter(),0);assert.equal(e.frame_top(),1280);assert.equal(d.getUint8(49152+512),0);
 setup(e,d);assert.equal(e.project(1,1,1,1,.5),2);close(e);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),512);
 assert.equal(e.frame_config(768),-4);
}
for(const [limit,top] of [[4097,0],[0xffffffff,0],[768,769],[0,1]]) {
 const {e,d}=instance(normal);d.setUint32(400,limit,true);d.setUint32(404,top,true);const before=image(e);
 assert.equal(e.frame_enter(),-5);assert.deepEqual(image(e),before);
}
// Reservation failure after a successful frame enter restores the frontier.
{
 const {e}=instance(normal);assert.equal(e.frame_enter(),0);assert(e.reserve(0xffffffff)<0);
 assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);
}
// Frame exit refuses every live owner or descriptor, with no mutation.
{
 const {e,d}=instance(normal);assert.equal(e.frame_enter(),0);setup(e,d);
 let before=image(e);assert.equal(e.frame_leave(),-4);assert.deepEqual(image(e),before);
 assert.equal(e.input_end(1,1),0);before=image(e);assert.equal(e.frame_leave(),-4);assert.deepEqual(image(e),before);
 assert.equal(e.close(1,1),-4);assert.deepEqual(image(e),before);
 assert.equal(e.output_end(1,1),0);before=image(e);assert.equal(e.frame_leave(),-4);assert.deepEqual(image(e),before);
 assert.equal(e.close(1,1),0);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);
}
// Existing owners are rejected at entry by this private one-owner fixture.
{
 const {e}=instance(normal);assert.equal(e.reserve(1),1);const before=image(e);assert.equal(e.frame_enter(),-4);assert.deepEqual(image(e),before);
 assert.equal(e.close(1,1),0);
}
// Empty reservations have live slots even though the bitmap remains zero.
{
 const {e}=instance(normal);assert.equal(e.reserve(0),1);let before=image(e);assert.equal(e.frame_enter(),-4);assert.deepEqual(image(e),before);assert.equal(e.close(1,1),0);
 assert.equal(e.frame_enter(),0);assert.equal(e.reserve(0),1);before=image(e);assert.equal(e.frame_leave(),-4);assert.deepEqual(image(e),before);
 assert.equal(e.close(1,2),0);assert.equal(e.frame_leave(),0);
}
// All four owner slots are checked, even when the bitmap is empty.
for(let slot=0;slot<4;slot++)for(const state of [1,2,4,255]) {
 const {e,d}=instance(normal);d.setUint32(36+slot*32,state,true);const before=image(e);
 assert.equal(e.frame_enter(),-4);assert.deepEqual(image(e),before);
}
{
 const {e,d}=instance(normal);d.setUint32(36,3,true);assert.equal(e.frame_enter(),0);assert.equal(e.frame_leave(),0);
}
// Corrupt active token/frontier: source call and leave reject before writes.
for(const [offset,value] of [[400,4097],[404,0],[408,1],[412,2]]) {
 const {e,d}=instance(normal);assert.equal(e.frame_enter(),0);setup(e,d);d.setUint32(offset,value,true);const before=image(e);
 assert.equal(e.project(1,1,1,1,.5),-5);assert.deepEqual(image(e),before);
 assert.equal(e.frame_leave(),-4);assert.deepEqual(image(e),before);
}
// No frame -> no source call. Preflight survives normal worker rejections;
// the host cleans descriptors/owner and explicitly restores its frontier.
{
 const {e}=instance(normal);const before=image(e);assert.equal(e.project(1,1,1,1,.5),-5);assert.deepEqual(image(e),before);
}
{
 const {e,d}=instance(normal);assert.equal(e.frame_enter(),0);setup(e,d);assert.equal(e.project(1,1,2,1,.5),-4);assert.equal(e.frame_top(),768);close(e);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);
}
{
 const {e,d}=instance(normal);assert.equal(e.frame_enter(),0);setup(e,d,2,1);assert.equal(e.project(1,1,1,1,.5),-3);
 assert.equal(e.frame_top(),768);close(e);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);
}
{
 const {e,d}=instance(trap);assert.equal(e.frame_enter(),0);setup(e,d);assert.throws(()=>e.project(1,1,1,1,.5),WebAssembly.RuntimeError);
 assert.equal(e.frame_top(),768); // abandon instance; no reusable cleanup claim
}
console.log('private pre-setup Wasm frame entry, restore, failure and poison witness passed');
