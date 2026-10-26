// Closed source/Core/target witness under trusted fixture owner/loan state.
// Raw setup exports and memory are test-only, not a public K1 ABI. The source
// worker receives an already-created Builder; setup placement is not source
// behavior. Trapped fixture instances are inspected and then discarded.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
const bytes=readFileSync('particle-source.wasm'); assert(WebAssembly.validate(bytes));
const mod=new WebAssembly.Module(bytes); assert.deepEqual(WebAssembly.Module.imports(mod),[]);
assert.deepEqual(WebAssembly.Module.exports(mod).map(x=>[x.name,x.kind]),[
  ['reserve','function'],['close','function'],['input_alloc','function'],['input_freeze','function'],
  ['advance','function'],['builder_alloc','function'],['project','function'],['memory','memory'],
]);
// Decode all code bodies and distinguish wrapper/preflight helpers from the
// actual source worker. The worker has no call or reservation instruction at
// all; its loop stores both F32 fields before publishing initialized length.
function leb(buf,p) {let n=0,s=0,b;do {assert(p.i<buf.length);b=buf[p.i++];n+=(b&127)*2**s;s+=7;assert(s<=35);} while(b&128);return n;}
const plain=new Set([0x00,0x05,0x0b,0x0f,0x45,0x46,0x47,0x49,0x4b,0x4f,0x6a,0x6b,0x6c,0x71,0x72,0x73,0x74,0x76,0x92,0x94]);
let bodies=0, wrapperCalls=[],workerCalls=[],loopStores=[],workerLoads=0,workerAdds=0,workerMuls=0;
for(const p={i:8};p.i<bytes.length;) {
  const id=bytes[p.i++],len=leb(bytes,p),end=p.i+len;assert(end<=bytes.length);
  if(id===10) {
    assert.equal(leb(bytes,p),11);
    for(let fn=0;fn<11;fn++) {
      const size=leb(bytes,p),finish=p.i+size;assert(finish<=end);const groups=leb(bytes,p);
      for(let j=0;j<groups;j++) {leb(bytes,p);assert([0x7f, 0x7d].includes(bytes[p.i++]));}
      let depth=0,inLoop=false,loopDepth=0;
      while(p.i<finish) {
        const op=bytes[p.i++];assert.notEqual(op,0x40,'memory.grow forbidden');
        if(op===0x0b) {if(inLoop&&depth===loopDepth) inLoop=false;if(depth>0)depth--;continue;}
        if([0x02,0x03,0x04].includes(op)) {assert([0x40,0x7f].includes(bytes[p.i++]));depth++;if(fn===10&&op===0x03){assert(!inLoop);inLoop=true;loopDepth=depth;}continue;}
        if(op===0x10) {const dest=leb(bytes,p);if(fn===9)wrapperCalls.push(dest);if(fn===10)workerCalls.push(dest);continue;}
        if([0x28,0x36,0x2a,0x38].includes(op)) {
          assert.equal(leb(bytes,p),2);const offset=leb(bytes,p);
          if(fn===9&&op===0x36)assert.fail('source wrapper must not place or write');
          if(fn===10&&inLoop) {
            if(op===0x2a)workerLoads++;
            else if(op===0x38)loopStores.push(['f32',offset]);
            else if(op===0x36)loopStores.push(['length',offset]);
            else assert.fail('unexpected worker loop memory op');
          }
          continue;
        }
        if(plain.has(op)) {if(fn===10&&inLoop&&op===0x92)workerAdds++;if(fn===10&&inLoop&&op===0x94)workerMuls++;continue;}
        if([0x0c,0x0d,0x20,0x21,0x41].includes(op)){leb(bytes,p);continue;}
        assert.fail(`unexpected opcode 0x${op.toString(16)}`);
      }
      assert.equal(p.i,finish);bodies++;
    }
  } else p.i=end;
  assert.equal(p.i,end);
}
assert.equal(bodies,11);assert.deepEqual(wrapperCalls,[4,4,10]);assert.deepEqual(workerCalls,[]);
assert.deepEqual([workerLoads,workerMuls,workerAdds],[4,2,2]);
assert.deepEqual(loopStores,[['f32',0],['f32',4],['length',12]]);
function guest(selected=mod) {const e=new WebAssembly.Instance(selected).exports;assert.equal(e.memory.buffer.byteLength,65536);assert.throws(()=>e.memory.grow(1),RangeError);return e;}
function w(e){return new Uint32Array(e.memory.buffer);}
function slot(e,id){return Array.from(w(e).slice(4+(id-1)*8,12+(id-1)*8));}
function inDesc(e,id){return Array.from(w(e).slice(64+(id-1)*4,68+(id-1)*4));}
function outDesc(e,id){return Array.from(w(e).slice(80+(id-1)*4,84+(id-1)*4));}
function cap(e,id){return w(e)[96+id-1];}
function image(e){return Buffer.from(new Uint8Array(e.memory.buffer));}
function unchanged(e,fn,expected){const before=image(e);assert.equal(fn(),expected);assert.deepEqual(image(e),before);}
function bits(v){const d=new DataView(new ArrayBuffer(4));d.setFloat32(0,v,true);return d.getUint32(0,true);}
function sameBits(got,want){if(Number.isNaN(want))assert.equal(got&0x7fffffff,0x7fc00000);else assert.equal(got>>>0,bits(want)>>>0);}
function setup(e,rows,capacity,padding=0) {
  assert.equal(e.reserve(rows.length*16),1);assert.equal(e.reserve(padding+capacity*8),2);
  assert.equal(e.input_alloc(1,1,rows.length),0);const inbase=inDesc(e,1)[2],view=new DataView(e.memory.buffer);
  rows.forEach((r,i)=>r.forEach((v,j)=>view.setFloat32(inbase+i*16+j*4,v,true)));
  assert.equal(e.input_freeze(1,1),rows.length);
  assert.equal(e.advance(2,1,padding),0);
  if(padding)new Uint8Array(e.memory.buffer,slot(e,2)[0],padding).fill(0xa5);
  assert.equal(e.builder_alloc(2,1,capacity),0);
  assert.deepEqual(outDesc(e,2),[1,1,slot(e,2)[0]+padding,0]);
  assert.equal(cap(e,2),capacity);return {inbase,outbase:outDesc(e,2)[2]};
}
function check(e,rows,capacity,dt,prep,padding=0) {
  const beforeTop=slot(e,2)[3],beforeInput=Buffer.from(new Uint8Array(e.memory.buffer,prep.inbase,rows.length*16));
  const beforePad=Buffer.from(new Uint8Array(e.memory.buffer,slot(e,2)[0],padding));
  assert.equal(e.project(1,1,2,1,dt),rows.length);
  assert.equal(slot(e,2)[3],beforeTop);assert.equal(cap(e,2),capacity);
  assert.deepEqual(outDesc(e,2),[2,1,rows.length?prep.outbase:0,rows.length]);
  const d=new DataView(e.memory.buffer),step=Math.fround(dt);
  rows.forEach((r,i)=>{const x=r.map(Math.fround);sameBits(d.getUint32(prep.outbase+i*8,true),Math.fround(x[0]+Math.fround(x[2]*step)));sameBits(d.getUint32(prep.outbase+i*8+4,true),Math.fround(x[1]+Math.fround(x[3]*step)));});
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,prep.inbase,rows.length*16)),beforeInput);
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,slot(e,2)[0],padding)),beforePad);
}
// The output owner already has a 12-byte allocation before builder creation.
// A source worker that demanded top==0, or that placed its own builder, would
// fail this witness. Its pre-existing allocation and final frontier survive.
{
  const rows=[[1,2,3,4],[5,-6,7,-8]],e=guest(),prep=setup(e,rows,3,12);
  assert.equal(slot(e,2)[3],36);assert.equal(prep.outbase,slot(e,2)[0]+12);
  check(e,rows,3,0.5,prep,12);
  unchanged(e,()=>e.project(1,1,2,1,0.5),-4); // consumed/frozen builder
  assert.equal(e.close(1,1),0);assert.equal(e.close(2,1),0);
}
// Explicit alias rejection, malformed descriptor and capacity failure preserve
// the existing builder and all memory; owner uniqueness remains a trusted pool
// invariant and is not inferred from arbitrary raw identifiers.
{
  const rows=[[1,2,3,4],[5,6,7,8]],e=guest(),prep=setup(e,rows,1,4);
  unchanged(e,()=>e.project(1,1,1,1,1),-4);
  unchanged(e,()=>e.project(1,1,2,1,1),-3); // n=2 exceeds builder capacity=1
  unchanged(e,()=>e.builder_alloc(2,1,0),-4); // existing builder remains live
  w(e)[86]=prep.inbase; // untrusted test corrupts output data pointer
  unchanged(e,()=>e.project(1,1,2,1,1),-4);
}
{
  const e=guest();assert.equal(e.reserve(0),1);assert.equal(e.reserve(16),2);
  assert.equal(e.input_alloc(1,1,0),0);assert.equal(e.input_freeze(1,1),0);
  unchanged(e,()=>e.builder_alloc(2,1,0xffffffff),-1);
  unchanged(e,()=>e.builder_alloc(2,1,3),-2);
  assert.equal(e.builder_alloc(2,1,2),0);
  const before=slot(e,2)[3];assert.equal(e.project(1,1,2,1,1),0);
  assert.deepEqual(outDesc(e,2),[2,1,0,0]);assert.equal(slot(e,2)[3],before);
}
{
  const rows=[[1,-2,3.5,-4.25],[-0,0,-0,0],[Infinity,-Infinity,0,-0],[1,2,Infinity,-Infinity]];
  const e=guest(),prep=setup(e,rows,rows.length);check(e,rows,rows.length,0,prep);
}
{
  const rows=[];let seed=0x7a19cd42;const rnd=()=>seed=(Math.imul(seed,1664525)+1013904223)>>>0;
  for(let i=0;i<1024;i++)rows.push(Array.from({length:4},()=>((rnd()%200001)-100000)/128));
  const e=guest(),prep=setup(e,rows,rows.length);assert.equal(w(e)[36],63);check(e,rows,rows.length,0.03125,prep);
  assert.equal(e.close(1,1),0);assert.equal(e.close(2,1),0);assert.equal(w(e)[36],0);
}
// Test-only trap hooks stop after each complete row publication. These raw
// instances are discarded; a public bridge would poison them after any trap.
for(let prefix=0;prefix<=4;prefix++) {
  const bytes=readFileSync(`particle-source-fault-${prefix}.wasm`);assert(WebAssembly.validate(bytes));
  const e=guest(new WebAssembly.Module(bytes)),rows=[[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]],prep=setup(e,rows,4,4);
  const top=slot(e,2)[3],beforeInput=Buffer.from(new Uint8Array(e.memory.buffer,prep.inbase,64));
  const unused=new Uint8Array(e.memory.buffer,prep.outbase,32);unused.fill(0xa5);
  assert.throws(()=>e.project(1,1,2,1,0.5),WebAssembly.RuntimeError);
  assert.deepEqual(outDesc(e,2),[1,1,prep.outbase,prefix]);assert.equal(slot(e,2)[3],top);
  const d=new DataView(e.memory.buffer);
  for(let i=0;i<prefix;i++){sameBits(d.getUint32(prep.outbase+i*8,true),Math.fround(rows[i][0]+Math.fround(rows[i][2]*0.5)));sameBits(d.getUint32(prep.outbase+i*8+4,true),Math.fround(rows[i][1]+Math.fround(rows[i][3]*0.5)));}
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,prep.outbase+prefix*8,(4-prefix)*8)),Buffer.alloc((4-prefix)*8,0xa5));
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,prep.inbase,64)),beforeInput);
}
console.log('private source-linked existing-builder particle witness passed');
