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

const fx=(x,y,vx,vy,dt)=>f(x+f(vx*dt));
const fy=(x,y,vx,vy,dt)=>f(y+f(vy*dt));
numerical('transition.wasm',[],0.25,fx,fy);
numerical('transition.wasm',[[1,2,3,4],[-2,7,0.5,-1],[1e30,-1e30,2,-2]],0.25,fx,fy);
console.log('source-linked worker fixture matches zero-trip and populated references');
