import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
const mod=new WebAssembly.Module(readFileSync('one-module.wasm'));assert.equal(WebAssembly.Module.imports(mod).length,0);
let state=0x8bfa3921;function rand(){state^=state<<13;state^=state>>>17;state^=state<<5;return state>>>0;}
const scratch=new DataView(new ArrayBuffer(4));function from(bits){scratch.setUint32(0,bits,true);return scratch.getFloat32(0,true);}function bits(x){scratch.setFloat32(0,x,true);return scratch.getUint32(0,true);}
const special=[0,0x80000000,1,0x80000001,0x7f7fffff,0xff7fffff,0x3f800000,0xbf800000,0x7f800000,0xff800000,0x7fc00000,0x7fc12345];function scalar(){return from((rand()&1)?special[rand()%special.length]:rand());}
const f=Math.fround;let count=0;
for(let k=0;k<100;k++){const n=k%9,rows=Array.from({length:n},()=>[scalar(),scalar(),scalar(),scalar()]),dt=scalar(),e=new WebAssembly.Instance(mod).exports,d=new DataView(e.memory.buffer),m=new Uint8Array(e.memory.buffer);
 assert.equal(e.frame_config(768),0);assert.equal(e.frame_enter(),0);assert.equal(e.reserve(192),1);assert.equal(e.input_alloc(1,1,n),0);const inp=d.getUint32(264,true);
 for(let i=0;i<n;i++)for(let j=0;j<4;j++)d.setFloat32(inp+i*16+j*4,rows[i][j],true);
 assert.equal(e.input_freeze(1,1),n);assert.equal(e.builder_alloc(1,1,8),0);const outp=d.getUint32(328,true),record=49280,result=49312;
 d.setUint32(record,n?inp:0,true);d.setUint32(record+4,n,true);d.setFloat32(record+8,dt,true);d.setUint32(record+12,outp,true);d.setUint32(record+16,8,true);m.fill(0xa5,result,result+16);e.adapter(0,result,record);
 assert.deepEqual([0,4,8,12].map(x=>d.getUint32(result+x,true)),[0,n,n?outp:0,n]);
 for(let i=0;i<n;i++){const [x,y,vx,vy]=rows[i].map(f),delta=f(dt),w=[f(x+f(vx*delta)),f(y+f(vy*delta))];for(let j=0;j<2;j++){const a=d.getUint32(outp+i*8+j*4,true);if(Number.isNaN(w[j]))assert(Number.isNaN(from(a)));else assert.equal(a,bits(w[j]),`case ${k} row ${i} field ${j}`);}count++;}
 assert.equal(e.output_end(1,1),0);assert.equal(e.input_end(1,1),0);assert.equal(e.close(1,1),0);assert.equal(e.frame_leave(),0);assert.equal(e.frame_top(),0);
}
console.log(`independent one-module F32/cleanup oracle passed ${count} rows`);
