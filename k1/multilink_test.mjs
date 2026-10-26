import fs from 'node:fs';
import assert from 'node:assert/strict';
for (const [file,expected] of [['before.wasm',123],['after.wasm',7]]) {
 const {instance}=await WebAssembly.instantiate(fs.readFileSync(file));
 assert.equal(instance.exports.first(0,123),expected);
 assert.equal(instance.exports.second(0,123),42);
 assert.equal(instance.exports.third(0,511),255);
}
