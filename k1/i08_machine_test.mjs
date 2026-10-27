import {strict as assert} from 'node:assert';import {readFileSync} from 'node:fs';
import {decode,reachable} from './i08_machine_decode.mjs';import {inspect} from './i08_machine_inspect.mjs';
const bytes=readFileSync(process.argv[2]||'private-invoke.wasm');
const evidence=inspect(bytes);assert.equal(evidence.ok,true);assert.equal(evidence.machineDepth,6);assert.equal(evidence.slotSkeletonVerified,true);
assert.equal(evidence.dynamicAccessesQualified,false);assert.equal(evidence.m11Qualified,false);
const graph=decode(bytes);assert.equal(graph.ok,true);assert.deepEqual(graph.bodies[22].calls,[16,18,0,19,5,6,8,21,13,12,11,19]);
for(let i=0;i<bytes.length;i++){const b=Uint8Array.from(bytes);b[i]^=1;assert.equal(inspect(b).ok,false);}
for(let i=0;i<bytes.length;i++)assert.equal(inspect(bytes.subarray(0,i)).ok,false);
const extra=new Uint8Array(bytes.length+1);extra.set(bytes);assert.equal(inspect(extra).ok,false);
function encodeS32(n){n=BigInt(n);const out=[];for(;;){let b=Number(n&127n);n>>=7n;const done=(n===0n&&!(b&64))||(n===-1n&&(b&64));out.push(done?b:b|128);if(done)return out;}}
// Each edit remains a structurally valid Wasm module. Exact source-bound
// target association must nevertheless reject the altered code or call.
{
 const op=graph.bodies[22].ops.find(x=>x.op===0x10&&x.imm===21);const b=Uint8Array.from(bytes);b[op.at+1]=20;
 assert(WebAssembly.validate(b));assert.equal(decode(b).ok,true);assert.notDeepEqual(decode(b).bodies[22].calls,graph.bodies[22].calls);assert.equal(inspect(b).ok,false);
}
{
 const op=graph.bodies[22].ops.find(x=>x.op===0x41&&x.imm===49280);const b=Uint8Array.from(bytes),replacement=encodeS32(49284);
 b.set(replacement,op.at+1);assert(WebAssembly.validate(b));assert.equal(decode(b).ok,true);assert.equal(inspect(b).ok,false);
}
{
 const op=graph.bodies[10].ops.find(x=>x.op===0x94);const b=Uint8Array.from(bytes);b[op.at]=0x92;
 assert(WebAssembly.validate(b));assert.equal(decode(b).ok,true);assert.equal(inspect(b).ok,false);
}
const cyclic={ok:true,bodies:[{calls:[1]},{calls:[0]}]};assert.throws(()=>reachable(cyclic,0),/cycle/);
assert.equal(decode(new Uint8Array(65537)).ok,false);assert.equal(decode(new Uint8Array(0)).ok,false);
let traps=0;class Hostile extends Uint8Array {get length(){traps++;throw Error('length');}[Symbol.iterator](){traps++;throw Error('iterator');}}
const h=new Hostile(bytes.length);Uint8Array.prototype.set.call(h,bytes);assert.equal(inspect(h).ok,true);assert.equal(traps,0);
const detached=new Uint8Array(8);structuredClone(detached,{transfer:[detached.buffer]});assert.equal(decode(detached).ok,false);
assert.equal(decode(new Proxy(h,{})).ok,false);
console.log('private independent fixed Wasm call graph and partial slot skeleton passed');
