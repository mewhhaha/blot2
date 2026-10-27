import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {bind} from './i08_caller_window_binding.mjs';
let b=readFileSync(process.argv[2] || 'private-invoke.wasm');let r=bind(b);assert(r.ok,r.error);assert(!r.m11Qualified&&!r.publicEligible);
class Spoof extends Uint8Array {get length(){return 0} get byteLength(){return 0} every(){return true}}
let spoof=new Spoof(b.length);spoof.set(b);assert(bind(spoof).ok);spoof[0]^=1;assert(!bind(spoof).ok);
assert(!bind(new Proxy(b,{})).ok);let detached=Uint8Array.from(b);structuredClone(detached.buffer,{transfer:[detached.buffer]});assert(!bind(detached).ok);
for(let i=0;i<b.length;i++){let x=Uint8Array.from(b);x[i]^=1;assert(!bind(x).ok,'byte '+i);assert(!bind(b.subarray(0,i)).ok,'truncation '+i)}
console.log('guard/loop site binding accepted exact target and rejected all byte mutations/truncations');
