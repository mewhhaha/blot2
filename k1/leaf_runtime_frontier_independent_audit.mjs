// Scratch independent oracle: source-0 is identity with depth=3/frame=12.
// Test-only exported memory observes reservations; not an accepted target.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source = readFileSync(process.argv[2]);
const module = new WebAssembly.Module(source);
assert.deepEqual(WebAssembly.Module.imports(module), []);
assert.deepEqual(WebAssembly.Module.exports(module).map(x=>x.name), ['invoke']);
function uleb(n) {const b=[];do{let x=n&127;n=Math.floor(n/128);b.push(n?x|128:x);}while(n);return b;}
function instrument(raw) {
 let bytes=Uint8Array.from(raw), p=8;
 function get() {let n=0,s=0;while (true) {let b=bytes[p++];n+=(b&127)*2**s;if((b&128)===0)return n;s+=7;}}
 while(p<bytes.length) {const start=p,id=bytes[p++],len=get(),payload=p,end=p+len;
  if(id===7) {assert.equal(bytes[payload],1);const payload2=Uint8Array.from([2,...bytes.slice(payload+1,end),6,...Buffer.from('memory'),2,0]);return Uint8Array.from([...bytes.slice(0,start),7,...uleb(payload2.length),...payload2,...bytes.slice(end)]);}
  p=end;
 }
 throw Error('export missing');
}
const inst=new WebAssembly.Instance(new WebAssembly.Module(instrument(source))).exports;
const memory=new Uint8Array(inst.memory.buffer), v=new DataView(inst.memory.buffer);
function check(d,f,x) {
 v.setUint32(0,d,true);v.setUint32(4,f,true);
 const before=memory.slice(0,16);
 const result=inst.invoke(x);
 const expected=d>124 ? 2n<<32n : f>1048576-12 ? 3n<<32n : BigInt(x>>>0);
 assert.equal(result,expected,`d=${d} f=${f} x=${x}`);
 assert.deepEqual(memory.slice(0,16),before);
}
for(const d of [0,123,124,125,127,128,129,0xffffffff]) for(const f of [0,1048563,1048564,1048565,1048576,1048577,0xffffffff]) check(d,f,0xffffffff);
let seed=0x6d2b79f5;
for(let i=0;i<200;i++) {seed=(Math.imul(seed,1664525)+1013904223)>>>0;const d=seed%140;seed=(Math.imul(seed,1664525)+1013904223)>>>0;const f=1048520+(seed%120);seed=(Math.imul(seed,1664525)+1013904223)>>>0;check(d,f,seed);}
console.log('independent depth/frame preflight oracle passed');
