import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
const original=readFileSync('one-module.wasm');
function read(buf,pos){let n=0,shift=0,b;do {assert(pos.i<buf.length);b=buf[pos.i++];n+=(b&127)*2**shift;shift+=7;assert(shift<=35);}while(b&128);return n;}
function leb(n){let a=[];do{let x=n&127;n=Math.floor(n/128);if(n)x|=128;a.push(x);}while(n);return a;}
let p={i:8},prefix=[...original.subarray(0,8)],changed=false;
while(p.i<original.length){let id=original[p.i++],len=read(original,p),start=p.i,end=start+len;assert(end<=original.length);if(id!==10){prefix.push(id,...leb(len),...original.subarray(start,end));p.i=end;continue;}
 const code=original.subarray(start,end),q={i:0},count=read(code,q),rewritten=[...leb(count)];assert.equal(count,22);
 for(let i=0;i<count;i++){const n=read(code,q),body=Buffer.from(code.subarray(q.i,q.i+n));q.i+=n;let out=body;
  if(i===10){const needle=Buffer.from([0x20,0x03,0x20,0x06,0x41,0x01,0x6a,0x36,0x02,0x0c]),where=body.indexOf(needle);assert(where>=0 && body.indexOf(needle,where+1)<0);const at=where+needle.length;out=Buffer.concat([body.subarray(0,at),Buffer.from([0x00]),body.subarray(at)]);changed=true;}
  rewritten.push(...leb(out.length),...out);
 }
 assert.equal(q.i,code.length);prefix.push(id,...leb(rewritten.length),...rewritten);p.i=end;
}
assert(changed);const fault=Uint8Array.from(prefix);assert(WebAssembly.validate(fault));const e=new WebAssembly.Instance(new WebAssembly.Module(fault)).exports,d=new DataView(e.memory.buffer),m=new Uint8Array(e.memory.buffer);
assert.equal(e.frame_config(768),0);assert.equal(e.frame_enter(),0);assert.equal(e.reserve(192),1);assert.equal(e.input_alloc(1,1,2),0);const inp=d.getUint32(264,true);
for(let i=0;i<2;i++)for(let j=0;j<4;j++)d.setFloat32(inp+16*i+4*j,i+j+1,true);
assert.equal(e.input_freeze(1,1),2);assert.equal(e.builder_alloc(1,1,8),0);const dest=d.getUint32(328,true),rec=49280,res=49312;
d.setUint32(rec,inp,true);d.setUint32(rec+4,2,true);d.setFloat32(rec+8,.5,true);d.setUint32(rec+12,dest,true);d.setUint32(rec+16,8,true);m.fill(0xa5,res,res+16);
assert.throws(()=>e.adapter(0,res,rec),WebAssembly.RuntimeError);assert.deepEqual(Array.from(m.subarray(res,res+16)),Array(16).fill(0xa5));assert.equal(d.getUint32(332,true),1);assert.equal(d.getFloat32(dest,true),2.5);assert.equal(d.getFloat32(dest+4,true),4);assert.equal(e.frame_top(),768);assert.equal(d.getUint32(36,true),1);
console.log('test-only worker fault after one published row leaves Result unpublished; instance must be discarded');
