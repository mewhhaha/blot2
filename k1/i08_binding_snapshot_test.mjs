import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {check,diagnosticForTests} from './i08_binding_provenance.mjs';
const b=readFileSync(process.argv[2] || 'private-invoke.wasm');class Spoof extends Uint8Array {get length(){return 0} get byteLength(){return 0} every(){return true}}
let x=new Spoof(b.length);x.set(b);assert(check(x).ok);assert(diagnosticForTests(x).ok);x[0]^=1;assert(!check(x).ok);
assert(!check(new Proxy(b,{})).ok);let gone=Uint8Array.from(b);structuredClone(gone.buffer,{transfer:[gone.buffer]});assert(!check(gone).ok);console.log('both independently callable binding paths snapshot and reject spoof/detached inputs');
