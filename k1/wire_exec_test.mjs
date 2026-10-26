import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {createWireExecFixture} from './wire_exec_host.mjs';
const args=[5,[0,0xffffffff,42],[false,true,false],[0x7fc00001,0x80000000,0x3f800000],3];
for(const [kind,name] of [[1,'u32'],[2,'bool'],[3,'f32'],[4,'unit']]) {
 const bytes=readFileSync(`wire-exec-${name}.wasm`), f=createWireExecFixture(bytes,kind);
 const ok=f.call(...args,224);assert.equal(ok.status,'Ok');
 if(kind===4) assert.equal(ok.count,3);
 else assert.deepEqual(Array.from(ok.values),args[kind]);
 const required=kind===4?8:20;
 assert.deepEqual(f.call(...args,required-1),{status:'OutputTooSmall',required,count:3});
 assert.equal(f.call(...args,required).status,'Ok');
 const copy=ok.values && Array.from(ok.values);
 args[1][0]=19;assert.equal(f.call(...args,224).status,'Ok');
 if(copy) assert.deepEqual(Array.from(ok.values),copy);
 args[1][0]=0;
 assert.throws(()=>f.call(5,[1,,3],args[2],args[3],3,224),TypeError);
 assert.throws(()=>f.call(5,args[1],[false,2],args[3],3,224),TypeError);
 const getter=[1];Object.defineProperty(getter,'0',{get(){throw Error('not called')}});
 assert.throws(()=>f.call(5,getter,args[2],args[3],3,224),TypeError);
 let reentry;const proxy=new Proxy([1],{getOwnPropertyDescriptor(target,key){
   reentry=f.call(...args,224);return Reflect.getOwnPropertyDescriptor(target,key);
 }});
 assert.equal(f.call(5,proxy,args[2],args[3],3,224).status,'Ok');assert.deepEqual(reentry,{status:'Busy'});
 assert.equal(f.call(...args,224).status,'Ok');
 const hostile=new Proxy([1],{getOwnPropertyDescriptor(){throw new WebAssembly.RuntimeError('input trap');}});
 assert.throws(()=>f.call(5,hostile,args[2],args[3],3,224),WebAssembly.RuntimeError);
 assert.equal(f.call(...args,224).status,'Ok');
 const bad=Uint8Array.from(bytes);bad[bad.length-1]^=1;
 assert.throws(()=>createWireExecFixture(bad,kind),TypeError);
 class Spoof extends Uint8Array { every() { return true; } }
 assert.throws(()=>createWireExecFixture(new Spoof(bytes.length),kind),TypeError);
 class Short extends Uint8Array { get length() { return bytes.length; } }
 const short=new Short(bytes.length-1);short.set(bytes.subarray(0,bytes.length-1));
 assert.throws(()=>createWireExecFixture(short,kind),TypeError);
}
console.log('private multi-schema source-bound scalar Wasm host adapter passed');
