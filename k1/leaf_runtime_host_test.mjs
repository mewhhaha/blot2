import assert from 'node:assert/strict';import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {pathToFileURL} from 'node:url';import {create} from './leaf_runtime_host.mjs';
const targets=Array.from({length:4},(_,i)=>Uint8Array.from(readFileSync(`leaf-runtime-${i}.wasm`)));
for(let i=0;i<4;i++){let h=await create(i,targets[i]);for(let n of [0,1,4,5,6,0xffffffff]){let want=i===2?{status:'FrameLimit'}:i===3?{status:'DepthLimit'}:{status:'Ok',value:i===1?Math.min(n,5):n};assert.deepEqual(h.invoke(n),want);}
 for(let j=0;j<4;j++)if(j!==i)await assert.rejects(create(i,targets[j]));
 for(let j=0;j<targets[i].length;j++){let changed=Uint8Array.from(targets[i]);changed[j]^=1;await assert.rejects(create(i,changed));await assert.rejects(create(i,targets[i].subarray(0,j)));}}
let mutable=Uint8Array.from(targets[0]),pending=create(0,mutable);mutable.fill(0);assert.deepEqual((await pending).invoke(1),{status:'Ok',value:1});
// Capture tested for all target, validation, and invocation operations.
const corrupt=Uint8Array.from(targets[0]);corrupt[corrupt.length-1]^=1;
function beforeCustom(b){let p=8;while(p<b.length){let start=p,id=b[p++],n=0,shift=0,v;do{v=b[p++];n+=(v&127)*2**shift;shift+=7;}while(v&128);if(id===0)return b.slice(0,start);p+=n;}throw Error('missing custom section');}
const prefix=beforeCustom(targets[0]);assert(WebAssembly.validate(prefix));
const typedPrototype=Object.getPrototypeOf(Uint8Array.prototype),oldLength=Object.getOwnPropertyDescriptor(typedPrototype,'length');
const oldEvery=Uint8Array.prototype.every,oldSet=Uint8Array.prototype.set,oldInteger=Number.isInteger,oldApply=Reflect.apply,oldFreeze=Object.freeze;
const oldInstantiate=WebAssembly.instantiate,oldImports=WebAssembly.Module.imports,oldExports=WebAssembly.Module.exports,oldInstanceExports=Object.getOwnPropertyDescriptor(WebAssembly.Instance.prototype,'exports');
let rejected=false,prefixRejected=false,floatResult,validResult;
try {
 Uint8Array.prototype.every=function(){return true;};Uint8Array.prototype.set=function(){};Number.isInteger=()=>true;Reflect.apply=()=>null;Object.freeze=x=>x;
 WebAssembly.instantiate=async()=>{throw Error('substituted instantiate');};WebAssembly.Module.imports=()=>[{}];WebAssembly.Module.exports=()=>[];
 Object.defineProperty(WebAssembly.Instance.prototype,'exports',{configurable:true,get(){return {invoke(){return 999n}}}});
 Object.defineProperty(typedPrototype,'length',{configurable:true,get(){return prefix.byteLength;}});
 try {await create(0,corrupt);}catch {rejected=true;}
 try {await create(0,prefix);}catch {prefixRejected=true;}
 let safe=await create(0,targets[0]);floatResult=safe.invoke(0.5);validResult=safe.invoke(7);
} finally {
 Uint8Array.prototype.every=oldEvery;Uint8Array.prototype.set=oldSet;Number.isInteger=oldInteger;Reflect.apply=oldApply;Object.freeze=oldFreeze;
 Object.defineProperty(typedPrototype,'length',oldLength);
 WebAssembly.instantiate=oldInstantiate;WebAssembly.Module.imports=oldImports;WebAssembly.Module.exports=oldExports;Object.defineProperty(WebAssembly.Instance.prototype,'exports',oldInstanceExports);
}
assert(rejected);assert(prefixRejected);assert.deepEqual(floatResult,{status:'InvalidInput'});assert.deepEqual(validResult,{status:'Ok',value:7});
// Promise resolution must never assimilate a post-import Object.prototype.then.
// The function returns a null-prototype host and uses captured synchronous Wasm constructors.
const oldModule=WebAssembly.Module,oldInstance=WebAssembly.Instance,oldThen=Object.getOwnPropertyDescriptor(Object.prototype,'then');
let thenCalls=0,safeThenHost;
try {
 Object.defineProperty(Object.prototype,'then',{configurable:true,value(resolve){thenCalls++;resolve(null);}});
 WebAssembly.Module=function(){throw Error('substituted Module');};WebAssembly.Instance=function(){throw Error('substituted Instance');};
 safeThenHost=await create(0,targets[0]);
} finally {
 WebAssembly.Module=oldModule;WebAssembly.Instance=oldInstance;
 if(oldThen)Object.defineProperty(Object.prototype,'then',oldThen);else delete Object.prototype.then;
}
assert.equal(thenCalls,0);assert.equal(Object.getPrototypeOf(safeThenHost),null);assert.deepEqual(safeThenHost.invoke(7),{status:'Ok',value:7});

let targetTouches=0;let hostileTarget=new Proxy({}, {get(){targetTouches++;throw Error('target getter')},getPrototypeOf(){targetTouches++;throw Error('target prototype')}});await assert.rejects(create(0,hostileTarget));assert.equal(targetTouches,0);
let valueTouches=0;let hostile=new Proxy({}, {get(){valueTouches++;throw Error('no coercion')}}),h=await create(0,targets[0]);for(let x of [undefined,null,true,false,1n,Symbol('x'),hostile,new Number(1),NaN,Infinity,-1,0.5,4294967296])assert.deepEqual(h.invoke(x),{status:'InvalidInput'});assert.equal(valueTouches,0);assert.deepEqual(h.invoke(-0),{status:'Ok',value:0});
let a=h.invoke(7);a.value=123;assert.deepEqual(h.invoke(7),{status:'Ok',value:7});
class Spoof extends Uint8Array{get length(){return 0}get byteLength(){return 0}every(){return true}}
let fake=new Spoof(targets[0].length);fake.set(targets[0]);assert.deepEqual((await create(0,fake)).invoke(1),{status:'Ok',value:1});fake[0]^=1;await assert.rejects(create(0,fake));await assert.rejects(create(0,new Proxy(targets[0],{})));let detached=Uint8Array.from(targets[0]);structuredClone(detached.buffer,{transfer:[detached.buffer]});await assert.rejects(create(0,detached));
// Mutate the source leaf into a type-valid trap. The production pin rejects it;
// a temporary test-only copy of the host pins it to exercise poison/discard.
function sourceTrap(input){let b=Uint8Array.from(input),p=8;function leb(){let n=0,k=0;for(;;){let v=b[p++];n+=(v&127)*2**k;if(!(v&128))return n;k+=7;}}while(p<b.length){let id=b[p++],n=leb(),end=p+n;if(id===10){assert.equal(leb(),2);leb();assert.equal(b[p],0);assert.equal(b[p+1],0x20);b[p+1]=0;assert(WebAssembly.validate(b));return b;}p=end;}throw Error('no code');}
async function temporaryHost(mutated){let original=Buffer.from(targets[0]).toString('hex'),changed=Buffer.from(mutated).toString('hex'),source=readFileSync(new URL('./leaf_runtime_host.mjs',import.meta.url),'utf8');assert(source.includes(original));let dir=mkdtempSync(join(tmpdir(),'leaf-host-test-')),path=join(dir,'host.mjs');writeFileSync(path,source.replace(original,changed));return import(pathToFileURL(path));}
let trap=sourceTrap(targets[0]);await assert.rejects(create(0,trap));let test=await temporaryHost(trap),failed=await test.create(0,trap);assert.deepEqual(failed.invoke(1),{status:'Poisoned'});assert.deepEqual(failed.invoke(2),{status:'Poisoned'});assert.deepEqual(failed.invoke({}),{status:'Poisoned'});
// Test-only valid module emits an impossible status by signed widening.
let impossible=Uint8Array.from(targets[0]);let aidx=-1;for(let i=0;i<impossible.length;i++)if(impossible[i]===0xad){assert.equal(aidx,-1);aidx=i;}assert(aidx>=0);impossible[aidx]=0xac;assert(WebAssembly.validate(impossible));await assert.rejects(create(0,impossible));let test2=await temporaryHost(impossible),bad=await test2.create(0,impossible);assert.deepEqual(bad.invoke(0xffffffff),{status:'Poisoned'});assert.deepEqual(bad.invoke(0),{status:'Poisoned'});
console.log('four source-pinned private leaf hosts, hostile inputs and sticky trap/impossible-status poison passed');
