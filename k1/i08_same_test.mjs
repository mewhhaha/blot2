// Same-owner byte-range model. Raw memory/state is hostile fixture data, not
// source-owned capability, lifetime or canonical M12 bridge authority.
import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
function make(name='i08-same.wasm'){const b=readFileSync(name);assert(WebAssembly.validate(b));return new WebAssembly.Instance(new WebAssembly.Module(b)).exports;}
function w(e){return new Uint32Array(e.memory.buffer);}function img(e){return Buffer.from(new Uint8Array(e.memory.buffer));}
function setup(rows,capacity,padding=0,extra=0,name){
 const e=make(name);assert.equal(e.reserve(rows.length*16+padding+capacity*8+extra),1);
 assert.equal(e.input_alloc(1,1,rows.length),0);const data=new DataView(e.memory.buffer),base=w(e)[66];
 rows.forEach((r,i)=>r.forEach((x,j)=>data.setFloat32(base+i*16+j*4,x,true)));
 assert.equal(e.input_freeze(1,1),rows.length);if(padding)assert.equal(e.advance(1,1,padding),0);
 assert.equal(e.builder_alloc(1,1,capacity),0);return {e,data,input:base,out:w(e)[82],top:w(e)[7]};
}
function unchanged(e,f,status){const before=img(e);assert.equal(f(),status);assert.deepEqual(img(e),before);}
function f(x){return Math.fround(x);}function check(g,rows,dt){const v=g.data;for(let i=0;i<rows.length;i++){const r=rows[i].map(f);assert.equal(v.getFloat32(g.out+i*8,true),f(r[0]+f(r[2]*f(dt))));assert.equal(v.getFloat32(g.out+i*8+4,true),f(r[1]+f(r[3]*f(dt))));}}
const rows=[[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]];
for(const n of [0,1,4])for(const padding of [0,4,12]){
 const selected=rows.slice(0,n),g=setup(selected,n,padding),{e}=g,before=Buffer.from(new Uint8Array(e.memory.buffer,g.input,n*16));
 assert.equal(e.project(1,1,1,1,0.5),n);assert.equal(w(e)[7],g.top);check(g,selected,0.5);
 assert.equal(w(e)[83],n);assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,g.input,n*16)),before);
 unchanged(e,()=>e.close(1,1),-4);
 assert.equal(e.output_end(1,1),0);unchanged(e,()=>e.output_end(1,1),-4);
 unchanged(e,()=>e.close(1,1),-4);assert.equal(e.input_end(1,1),0);unchanged(e,()=>e.input_end(1,1),-4);
 assert.equal(e.close(1,1),0);
}
{
 const g=setup(rows,3),{e}=g;unchanged(e,()=>e.project(1,1,1,1,1),-3);
 unchanged(e,()=>e.project(1,2,1,1,1),-4);unchanged(e,()=>e.project(1,1,1,2,1),-4);
}
for(const offset of [0,4,16,60]){
 const g=setup(rows,4,0,16),{e}=g;w(e)[82]=w(e)[4]+offset;unchanged(e,()=>e.project(1,1,1,1,1),-4);
}
{
 const g=setup(rows,4),{e}=g;w(e)[82]=w(e)[4]+g.top+4;unchanged(e,()=>e.project(1,1,1,1,1),-4);
}
for(let prefix=0;prefix<=4;prefix++){
 const g=setup(rows,4,0,0,`i08-same-fault-${prefix}.wasm`),{e}=g;
 new Uint8Array(e.memory.buffer,g.out,32).fill(0xa5);
 assert.throws(()=>e.project(1,1,1,1,0.5),WebAssembly.RuntimeError);assert.equal(w(e)[83],prefix);check(g,rows.slice(0,prefix),0.5);
 assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,g.out+prefix*8,(4-prefix)*8)),Buffer.alloc((4-prefix)*8,0xa5));
}
{
 const rows=[];for(let i=0;i<1024;i++)rows.push([i,-i,i/2,-i/4]);
 const g=setup(rows,rows.length);assert.equal(g.e.project(1,1,1,1,0.125),rows.length);check(g,rows,0.125);
}
console.log('same-owner disjoint range, failure, prefix and F32 witness passed');
// Independent arithmetic model for all aligned and unaligned candidate builder
// pointers in small owner allocations, including empty input/output.
let checked=0;
for(let n=0;n<=4;n++)for(let cap=0;cap<=5;cap++){
 const selected=rows.slice(0,n),top=n*16+cap*8;
 for(let off=0;off<=top+4;off++){
  const g=setup(selected,cap),{e}=g;w(e)[82]=w(e)[4]+off;
  const geometry=(off%4===0 && off<=top && cap*8<=top-off && (n===0||cap===0||off>=n*16));
  const status=geometry?(n<=cap?n:-3):-4;
  if(status<0)unchanged(e,()=>e.project(1,1,1,1,0.5),status);
  else {assert.equal(e.project(1,1,1,1,0.5),status);}
  checked++;
 }
}
console.log(`${checked} same-owner range/preflight cases passed`);
// Explicit fixture transitions: owner cannot close while either descriptor is
// live, ending a descriptor prevents further use, and end is single-use.
{
 const g=setup(rows,4),{e}=g;unchanged(e,()=>e.close(1,1),-4);
 assert.equal(e.input_end(1,1),0);unchanged(e,()=>e.project(1,1,1,1,1),-4);
 unchanged(e,()=>e.close(1,1),-4);assert.equal(e.output_end(1,1),0);assert.equal(e.close(1,1),0);
 unchanged(e,()=>e.input_end(1,1),-4);unchanged(e,()=>e.output_end(1,1),-4);
}
// Source-generated expression workers retain their source order and Wasm F32
// rounding under same-owner placement. Raw copy preserves noncanonical NaNs.
const forms=[[(x,y,vx,vy,dt)=>f(x+f(vx*dt)),(x,y,vx,vy,dt)=>f(y+f(vy*dt))],
 [(x,y,vx,vy,dt)=>f(f(vx+x)*dt),(x,y,vx,vy,dt)=>f(f(y*dt)+vy)],
 [(x,y,vx)=>vx,x=>x],[(x,y,vx,vy,dt)=>f(dt+f(x*vy)),(x,y,vx,vy,dt)=>f(f(vx+y)*f(vy+dt))]];
const bits=x=>{let d=new DataView(new ArrayBuffer(4));d.setFloat32(0,x,true);return d.getUint32(0,true);};
for(let k=0;k<4;k++){
 const input=[[1,-2,3.5,-4.25],[-0,0,-0,0],[1,2,Infinity,-Infinity]];
 const g=setup(input,input.length,4,0,`particle-lower-${'abcd'[k]}.wasm`),before=img(g.e);
 assert.equal(g.e.project(1,1,1,1,0.5),input.length);
 for(let i=0;i<input.length;i++)for(let j=0;j<2;j++){
  const v=forms[k][j](...input[i].map(f),f(0.5)),got=g.data.getUint32(g.out+i*8+j*4,true);
  if(Number.isNaN(v))assert(Number.isNaN(g.data.getFloat32(g.out+i*8+j*4,true)));else assert.equal(got,bits(v));
 }
 assert.deepEqual(Buffer.from(new Uint8Array(g.e.memory.buffer,g.input,input.length*16)),before.subarray(g.input,g.input+input.length*16));
}
console.log('same-owner source-generated F32 workers passed');
// Aborting a partially initialized mutable input must not claim it was
// frozen. Discard consumes its descriptor and permits closing the owner.
{
 const e=make();assert.equal(e.reserve(32),1);assert.equal(e.input_alloc(1,1,2),0);
 unchanged(e,()=>e.close(1,1),-4);unchanged(e,()=>e.input_end(1,1),-4);
 unchanged(e,()=>e.input_discard(1,2),-4);assert.equal(e.input_discard(1,1),0);
 unchanged(e,()=>e.input_discard(1,1),-4);assert.equal(e.close(1,1),0);
}
{
 const g=setup(rows,4),{e}=g;unchanged(e,()=>e.input_discard(1,1),-4);
}
