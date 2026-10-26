import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
const bytes=readFileSync('variant.wasm');assert(WebAssembly.validate(bytes));const mod=new WebAssembly.Module(bytes);assert.equal(WebAssembly.Module.imports(mod).length,0);
function prepare(n){const e=new WebAssembly.Instance(mod).exports,m=new Uint8Array(e.memory.buffer),d=new DataView(m.buffer);assert.equal(e.frame_config(768),0);assert.equal(e.frame_enter(),0);assert.equal(e.reserve(192),1);assert.equal(e.input_alloc(1,1,n),0);const inp=d.getUint32(264,true);for(let i=0;i<n;i++)for(let j=0;j<4;j++)d.setFloat32(inp+i*16+j*4,i+j+1,true);assert.equal(e.input_freeze(1,1),n);assert.equal(e.builder_alloc(1,1,8),0);const outp=d.getUint32(328,true),record=49280,result=49312;d.setUint32(record,n?inp:0,true);d.setUint32(record+4,n,true);d.setFloat32(record+8,.5,true);d.setUint32(record+12,outp,true);d.setUint32(record+16,8,true);m.fill(0xa5,result,result+16);return {e,m,d,inp,outp,record,result};}
for(let n=0;n<=8;n++){
 const {e,m,d,outp,record,result}=prepare(n);assert.equal(e.adapter(0,result,record),undefined);assert.deepEqual([0,4,8,12].map(j=>d.getUint32(result+j,true)),[0,n,n?outp:0,n]);for(let i=0;i<n;i++){assert.equal(d.getFloat32(outp+i*8,true),i+3);assert.equal(d.getFloat32(outp+i*8+4,true),i+1);}assert.equal(e.output_end(1,1),0);assert.equal(e.input_end(1,1),0);assert.equal(e.close(1,1),0);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);
}
for(const offset of [16,20,24,28,32,36,144,256,260,264,268,320,324,328,332,384,404,408,412]){
 const {e,m,d,record,result}=prepare(2);d.setUint32(offset,d.getUint32(offset,true)^1,true);assert.throws(()=>e.adapter(0,result,record),WebAssembly.RuntimeError,`offset ${offset}`);assert.deepEqual(Array.from(m.subarray(result,result+16)),Array(16).fill(0xa5));
}
for(const limit of [0,767,4097,0xffffffff]){const {e,m,d,record,result}=prepare(2);d.setUint32(400,limit,true);assert.throws(()=>e.adapter(0,result,record),WebAssembly.RuntimeError);assert.deepEqual(Array.from(m.subarray(result,result+16)),Array(16).fill(0xa5));}
for(const [arg,result] of [[-4,49312],[49281,49312],[49280,49313],[49152,49312],[49280,49184],[49280,49284],[49904,49312],[49280,49908]]) {const {e,m}=prepare(2);const before=Uint8Array.from(m);assert.throws(()=>e.adapter(0,result,arg),WebAssembly.RuntimeError);assert.deepEqual(m,before);}
console.log('one-module canonical adapter/checked frame/worker execution and corrupt-state controls passed');
