import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
const target=readFileSync('one-module.wasm'),module=new WebAssembly.Module(target);
assert.deepEqual(WebAssembly.Module.imports(module),[]);
let state=0x41cd1207;const rnd=()=>state=(Math.imul(state,1664525)+1013904223)>>>0;
function setup(n) {
 const e=new WebAssembly.Instance(module).exports,m=new Uint8Array(e.memory.buffer),d=new DataView(m.buffer);
 assert.equal(e.frame_config(768),0);assert.equal(e.frame_enter(),0);assert.equal(e.reserve(192),1);assert.equal(e.input_alloc(1,1,n),0);
 const inp=d.getUint32(264,true),rows=Array.from({length:n},()=>Array.from({length:4},()=>((rnd()%20001)-10000)/32));
 rows.forEach((r,i)=>r.forEach((x,j)=>d.setFloat32(inp+i*16+j*4,x,true)));const saved=Uint8Array.from(m.subarray(inp,inp+n*16));
 assert.equal(e.input_freeze(1,1),n);assert.equal(e.builder_alloc(1,1,8),0);const op=d.getUint32(328,true),rec=49280,res=49312;
 d.setUint32(rec,n?inp:0,true);d.setUint32(rec+4,n,true);d.setFloat32(rec+8,.03125,true);d.setUint32(rec+12,op,true);d.setUint32(rec+16,8,true);m.fill(0xa5,res,res+16);
 return {e,m,d,inp,op,rec,res,rows,saved};
}
for(let test=0;test<225;test++) {
 const n=test%9,{e,m,d,inp,op,rec,res,rows,saved}=setup(n);e.adapter(0,res,rec);
 assert.deepEqual([0,4,8,12].map(i=>d.getUint32(res+i,true)),[0,n,n?op:0,n]);
 assert.deepEqual(m.subarray(inp,inp+n*16),saved);
 for(let i=0;i<n;i++){assert.equal(d.getFloat32(op+i*8,true),Math.fround(rows[i][0]+Math.fround(rows[i][2]*.03125)));
 assert.equal(d.getFloat32(op+i*8+4,true),Math.fround(rows[i][1]+Math.fround(rows[i][3]*.03125)));}
 assert.equal(e.output_end(1,1),0);assert.equal(e.input_end(1,1),0);assert.equal(e.close(1,1),0);assert.equal(e.frame_leave(),0);
}
for(const [field,value] of [[0,0],[4,1],[4,9],[12,0],[16,0],[16,7],[16,9]]) {
 const {e,m,d,rec,res}=setup(8);d.setUint32(rec+field,value,true);const before=Uint8Array.from(m.subarray(res,res+16));
 assert.throws(()=>e.adapter(0,res,rec),WebAssembly.RuntimeError);assert.deepEqual(m.subarray(res,res+16),before);
}
console.log('independent one-module finite F32, input preservation and forged-record oracle passed');
