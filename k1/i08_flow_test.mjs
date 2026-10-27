import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {decode} from './i08_machine_decode.mjs';
import {verifyFlow,unsafeDiagnosticForTests} from './i08_flow_verify.mjs';
const original=readFileSync(process.argv[2]||'private-invoke.wasm'),g=decode(original);
assert(g.ok);const ok=verifyFlow(original);assert(ok.ok,ok.error);assert.equal(ok.m11Qualified,false);assert.equal(ok.eligible,false);assert.equal(ok.machineDepth,6);assert(ok.adapter.length>0&&ok.shim.length>0);
let count=0;
function reject(name,fn){let b=Uint8Array.from(original);fn(b);assert(WebAssembly.validate(b),name+' must be valid Wasm');let diagnostic=unsafeDiagnosticForTests(b);assert(!diagnostic.ok,name+': '+JSON.stringify(diagnostic));assert(!verifyFlow(b).ok,name+' pin');count++;}
const p=g.bodies[22].ops,a=g.bodies[21].ops,s=g.bodies[20].ops;
reject('zero-frontier failure must not fall through',b=>b[p[341].at]=0x1a);
reject('frontier field address',b=>b[p[309].at+2]=4);
reject('return-slot call argument',b=>b[p[543].at+1]+=4);
reject('input-slot call argument',b=>b[p[544].at+1]+=4);
reject('adapter reads result as argument',b=>b[a[92].at+1]=1);
reject('shim reads result as argument',b=>b[s[103].at+1]=1);
reject('adapter local unknown address',b=>b[a[92].at+1]=0);
reject('shim out of slot',b=>b[s[104].at+2]=24);
for(let i=0;i<original.length;i++){let b=Uint8Array.from(original);b[i]^=1;assert(!verifyFlow(b).ok,'pin mutation '+i);}
for(let i=0;i<original.length;i++){assert(!verifyFlow(original.subarray(0,i)).ok,'truncation '+i);}
console.log(JSON.stringify({mutations:count,pinMutations:original.length,truncations:original.length,adapterAccesses:ok.adapter.length,shimAccesses:ok.shim.length}));
