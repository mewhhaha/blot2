import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const f=(await WebAssembly.instantiate(readFileSync('semantic-owner-offset.wasm'))).instance.exports.f;
for(const x of [0,1,4294967290,4294967291,4294967295]) assert.equal(f(0,x)>>>0,x<=4294967290?x+5:x);
console.log('guarded offset semantic owner target passed');
