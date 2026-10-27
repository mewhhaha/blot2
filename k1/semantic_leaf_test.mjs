import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const identity=(await WebAssembly.instantiate(readFileSync('semantic-leaf-0.wasm'))).instance.exports.f;
for(const x of [0,1,0xffffffff]) assert.equal(identity(0,x)>>>0,x);
const loop=(await WebAssembly.instantiate(readFileSync('semantic-leaf-1.wasm'))).instance.exports.f;
assert.equal(loop(0,0),0); assert.equal(loop(0,1),3);
console.log('semantic Core target execution passed');
