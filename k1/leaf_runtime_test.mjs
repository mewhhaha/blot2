import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
function ule(n){let b=[];do{let x=n&127;n=Math.floor(n/128);b.push(n?x|128:x);}while(n);return b;}
// Test-only export of already-private memory; real verified module exposes only invoke.
function withMemory(input){let b=Uint8Array.from(input),p=8;function read(){let n=0,k=0;for(;;){let x=b[p++];n+=(x&127)*2**k;if(!(x&128))return n;k+=7;}}
 while(p<b.length){let start=p,id=b[p++],n=read(),payload=p,end=p+n;if(id===7){assert.equal(b[payload],1);let old=b.slice(payload+1,end),data=Uint8Array.from([2,...old,6,...Buffer.from('memory'),2,0]);return Uint8Array.from([...b.slice(0,start),7,...ule(data.length),...data,...b.slice(end)]);}p=end;}throw Error('export');}
let source=readFileSync('leaf-runtime-0.wasm');assert(WebAssembly.validate(source));let normal=new WebAssembly.Module(source);assert.deepEqual(WebAssembly.Module.imports(normal),[]);assert.deepEqual(WebAssembly.Module.exports(normal).map(x=>x.name),['invoke']);
async function create(index){let raw=readFileSync(`leaf-runtime-${index}.wasm`);let instrumented=withMemory(raw);assert(WebAssembly.validate(instrumented));return (await WebAssembly.instantiate(instrumented)).instance.exports;}
let e=await create(0),d=new DataView(e.memory.buffer),mem=new Uint8Array(e.memory.buffer);
function state(depth,frame){d.setUint32(0,depth,true);d.setUint32(4,frame,true);}
function run(depth,frame,arg,expected){state(depth,frame);let before=Uint8Array.from(mem);assert.equal(e.invoke(arg),expected);assert.deepEqual(mem,before);}
for(let arg of [0,1,0xffffffff])run(0,0,arg,BigInt(arg));
run(124,1048576-12,17,17n);run(125,0,17,2n<<32n);run(129,0,17,2n<<32n);run(0xffffffff,0xffffffff,17,2n<<32n);run(0,1048576-11,17,3n<<32n);run(0,0xffffffff,17,3n<<32n);
let loop=await create(1),lv=new DataView(loop.memory.buffer);for(let n of [0,1,4,5,6,0xffffffff]){assert.equal(loop.invoke(n),BigInt(Math.min(n,5)));assert.equal(lv.getUint32(0,true),0);assert.equal(lv.getUint32(4,true),0);}
let frame=await create(2);assert.equal(frame.invoke(7),3n<<32n);let dep=await create(3);assert.equal(dep.invoke(7),2n<<32n);
// Test-only source trap. The real source target checker rejects these bytes;
// on trap the counters are not restored and the private instance is discarded.
let b=Uint8Array.from(withMemory(source)),p=8;function read(){let n=0,k=0;for(;;){let x=b[p++];n+=(x&127)*2**k;if(!(x&128))return n;k+=7;}}let found=false;while(p<b.length){let id=b[p++],n=read(),end=p+n;if(id===10){assert.equal(read(),2);read();assert.equal(b[p],0);assert.equal(b[p+1],0x20);b[p+1]=0;found=true;break;}p=end;}assert(found&&WebAssembly.validate(b));let trapped=(await WebAssembly.instantiate(b)).instance.exports;let td=new DataView(trapped.memory.buffer);
td.setUint32(0,125,true);td.setUint32(4,0,true);assert.equal(trapped.invoke(7),2n<<32n);assert.equal(td.getUint32(0,true),125);assert.equal(td.getUint32(4,true),0);
td.setUint32(0,0,true);td.setUint32(4,1048576-11,true);assert.equal(trapped.invoke(7),3n<<32n);assert.equal(td.getUint32(0,true),0);assert.equal(td.getUint32(4,true),1048576-11);
td.setUint32(4,0,true);assert.throws(()=>trapped.invoke(7),WebAssembly.RuntimeError);assert.equal(td.getUint32(0,true),4);assert.equal(td.getUint32(4,true),12);
console.log('private Wasm depth/frame reservation, exact restore, failure atomicity and trap-discard controls passed');
