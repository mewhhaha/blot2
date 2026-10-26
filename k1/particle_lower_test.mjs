// Independent numerical/state oracle for structured private particle workers.
// It is not a public K1 ABI, ownership proof, general compiler or M13 cert.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
const f=Math.fround;
function make(name) {
  const bytes=readFileSync(name);assert(WebAssembly.validate(bytes));const mod=new WebAssembly.Module(bytes);
  assert.deepEqual(WebAssembly.Module.imports(mod),[]);
  assert.deepEqual(WebAssembly.Module.exports(mod).map(x=>[x.name,x.kind]),[
    ['reserve','function'],['close','function'],['input_alloc','function'],['input_freeze','function'],
    ['advance','function'],['builder_alloc','function'],['project','function'],['memory','memory'],
  ]);
  const e=new WebAssembly.Instance(mod).exports;assert.throws(()=>e.memory.grow(1),RangeError);return e;
}
function words(e){return new Uint32Array(e.memory.buffer);}
function slot(e,id){return Array.from(words(e).slice(4+(id-1)*8,12+(id-1)*8));}
function desc(e,id,base){return Array.from(words(e).slice(base+(id-1)*4,base+id*4));}
function image(e){return Buffer.from(new Uint8Array(e.memory.buffer));}
function expectedBits(value){const d=new DataView(new ArrayBuffer(4));d.setFloat32(0,value,true);return d.getUint32(0,true);}
function same(got,want){if(Number.isNaN(want))assert(Number.isNaN(new DataView(Uint32Array.of(got).buffer).getFloat32(0,true)));else assert.equal(got>>>0,expectedBits(want)>>>0);}
function setup(e,rows,capacity,pad=0,raw=false) {
  assert.equal(e.reserve(rows.length*16),1);assert.equal(e.reserve(pad+capacity*8),2);
  assert.equal(e.input_alloc(1,1,rows.length),0);const inBase=desc(e,1,64)[2],view=new DataView(e.memory.buffer);
  rows.forEach((r,i)=>r.forEach((v,j)=>raw?view.setUint32(inBase+i*16+j*4,v,true):view.setFloat32(inBase+i*16+j*4,v,true)));
  assert.equal(e.input_freeze(1,1),rows.length);assert.equal(e.advance(2,1,pad),0);
  if(pad)new Uint8Array(e.memory.buffer,slot(e,2)[0],pad).fill(0xa5);
  assert.equal(e.builder_alloc(2,1,capacity),0);return {input:inBase,output:desc(e,2,80)[2],top:slot(e,2)[3]};
}
function numerical(name,rows,dt,fx,fy,pad=0) {
  const e=make(name),prepared=setup(e,rows,rows.length,pad),beforeInput=Buffer.from(new Uint8Array(e.memory.buffer,prepared.input,rows.length*16));
  const beforePad=Buffer.from(new Uint8Array(e.memory.buffer,slot(e,2)[0],pad));
  assert.equal(e.project(1,1,2,1,dt),rows.length);assert.equal(slot(e,2)[3],prepared.top);
  assert.deepEqual(desc(e,2,80),[2,1,rows.length?prepared.output:0,rows.length]);
  const v=new DataView(e.memory.buffer),step=f(dt);
  rows.forEach((row,i)=>{const [x,y,vx,vy]=row.map(f);same(v.getUint32(prepared.output+i*8,true),fx(x,y,vx,vy,step));same(v.getUint32(prepared.output+i*8+4,true),fy(x,y,vx,vy,step));});
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,prepared.input,rows.length*16)),beforeInput);
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,slot(e,2)[0],pad)),beforePad);
  assert.equal(e.close(1,1),0);assert.equal(e.close(2,1),0);
}
const formulas=[
  [(x,y,vx,vy,dt)=>f(x+f(vx*dt)),(x,y,vx,vy,dt)=>f(y+f(vy*dt))],
  [(x,y,vx,vy,dt)=>f(f(vx+x)*dt),(x,y,vx,vy,dt)=>f(f(y*dt)+vy)],
  [(x,y,vx)=>vx,(x)=>x],
  [(x,y,vx,vy,dt)=>f(dt+f(x*vy)),(x,y,vx,vy,dt)=>f(f(vx+y)*f(vy+dt))],
];
const names=['a','b','c','d'];
const edgeRows=[[1,-2,3.5,-4.25],[-0,0,-0,0],[Infinity,-Infinity,0,-0],[1,2,Infinity,-Infinity],
 [1.0000001192092896,-1,-1.0000001192092896,1.0000001192092896]];
for(let i=0;i<4;i++) {numerical(`particle-lower-${names[i]}.wasm`,[],0.5,...formulas[i]);numerical(`particle-lower-${names[i]}.wasm`,edgeRows,0,...formulas[i],12);}
let seed=0x51b2e319;const random=()=>seed=(Math.imul(seed,1664525)+1013904223)>>>0;
const rows=[];for(let i=0;i<1024;i++)rows.push(Array.from({length:4},()=>((random()%200001)-100000)/128));
for(let i=0;i<4;i++) numerical(`particle-lower-${names[i]}.wasm`,rows,0.03125,...formulas[i]);
// Pure field copies preserve all F32 bits, including noncanonical NaNs and
// signed zero; no arithmetic or JS float conversion is used for comparison.
{
 const raw=[[0x7fa12345,0,0xffc54321,0x80000000],[0x80000000,0,0x00000001,0]],e=make('particle-lower-c.wasm'),p=setup(e,raw,2,0,true);
 assert.equal(e.project(1,1,2,1,0),2);const view=new DataView(e.memory.buffer);
 for(let i=0;i<raw.length;i++){assert.equal(view.getUint32(p.output+8*i,true),raw[i][2]>>>0);assert.equal(view.getUint32(p.output+8*i+4,true),raw[i][0]>>>0);}
}
// Unsatisfied capacity and same-owner calls must leave the caller's existing
// builder and every other state byte unchanged.
{
 const e=make('particle-lower-b.wasm');setup(e,[[1,2,3,4],[5,6,7,8]],1,4);
 for(const [args,status] of [[[1,1,2,1,1],-3],[[1,1,1,1,1],-4]]) {const before=image(e);assert.equal(e.project(...args),status);assert.deepEqual(image(e),before);}
}
console.log('structured particle workers match independent F32/state oracle');
