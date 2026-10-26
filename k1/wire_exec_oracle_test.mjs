import {strict as assert} from 'node:assert';
import {readFileSync} from 'node:fs';
import {createWireExecFixture} from './wire_exec_host.mjs';
let seed=0xaba467f1;const r=()=>seed=(Math.imul(seed,1664525)+1013904223)>>>0;
for(const [kind,name] of [[1,'u32'],[2,'bool'],[3,'f32'],[4,'unit']]) {
 const f=createWireExecFixture(readFileSync(`wire-exec-${name}.wasm`),kind);
 for(let i=0;i<3000;i++) {
  const a=Array.from({length:r()%5},r),b=Array.from({length:r()%5},()=>!!(r()&1)),c=Array.from({length:r()%5},r),units=r()%5;
  const args=[r(),a,b,c,units],length=kind===4?units:args[kind].length,need=8+(kind===4?0:4*length),capacity=r()%26;
  const got=f.call(...args,capacity);
  if(need>capacity)assert.deepEqual(got,{status:'OutputTooSmall',required:need,count:length});
  else {assert.equal(got.status,'Ok');if(kind===4)assert.equal(got.count,length);else assert.deepEqual(Array.from(got.values),args[kind]);}
 }
}
class ZeroLength extends Uint8Array {get length(){return 70;}}
class Liar extends Uint8Array {every(){return true;}}
const proxy=new Proxy(new Uint8Array(70),{get(t,k){if(k==='length')return 70;if(k==='every')return ()=>true;return Reflect.get(t,k,t);}});
for(const fake of [new ZeroLength(0),new Liar(70),proxy])assert.throws(()=>createWireExecFixture(fake,1),TypeError);
console.log('12,000 independent source-schema output/capacity and typed-array-spoof controls passed');
