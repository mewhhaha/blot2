import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {create} from './leaf_runtime_host.mjs';
const original=Uint8Array.from(readFileSync('leaf-runtime-0.wasm'));
function stripCustom(bytes){let p=8;while(p<bytes.length){let begin=p,id=bytes[p++],n=0,k=0,c;do{c=bytes[p++];n+=(c&127)*2**k;k+=7;}while(c&128);if(id===0)return bytes.slice(0,begin);p+=n;}throw Error('no custom');}
const prefix=stripCustom(original);assert(WebAssembly.validate(prefix));
const obj=Object.getOwnPropertyDescriptor(Object.prototype,'then'),tprop=Object.getPrototypeOf(Uint8Array.prototype),tag=Object.getOwnPropertyDescriptor(tprop,Symbol.toStringTag),len=Object.getOwnPropertyDescriptor(tprop,'length'),then=Promise.prototype.then,mod=WebAssembly.Module,inst=WebAssembly.Instance,ta=globalThis.Uint8Array,number=globalThis.Number;
let touches=0,prefixRejected=false,result,host;
try {
 Object.defineProperty(Object.prototype,'then',{configurable:true,get(){touches++;throw Error('then getter invoked');}});
 Promise.prototype.then=function(){throw Error('tampered then');};
 Object.defineProperty(tprop,Symbol.toStringTag,{configurable:true,get(){return 'Uint8Array';}});
 Object.defineProperty(tprop,'length',{configurable:true,get(){return original.length;}});
 WebAssembly.Module=function(){throw Error('tampered module');};WebAssembly.Instance=function(){throw Error('tampered instance');};
 globalThis.Uint8Array=function(){throw Error('tampered array');};globalThis.Number=function(){return 42;};
 try {await create(0,prefix);}catch {prefixRejected=true;}
 host=await create(0,original);result=host.invoke(7);
}finally{
 if(obj)Object.defineProperty(Object.prototype,'then',obj);else delete Object.prototype.then;
 Promise.prototype.then=then;Object.defineProperty(tprop,Symbol.toStringTag,tag);Object.defineProperty(tprop,'length',len);
 WebAssembly.Module=mod;WebAssembly.Instance=inst;globalThis.Uint8Array=ta;globalThis.Number=number;
}
assert(prefixRejected);assert.equal(touches,0);assert.equal(Object.getPrototypeOf(host),null);assert.deepEqual(result,{status:'Ok',value:7});
console.log('independent post-import then-getter / promise / constructors / typed-intrinsics audit passed');
