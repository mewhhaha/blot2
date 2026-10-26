import fs from 'node:fs';
import assert from 'node:assert/strict';
for (const [file,expected] of [['before.wasm',255],['after.wasm',7],['deep.wasm',9]]) {
 const {instance}=await WebAssembly.instantiate(fs.readFileSync(file));
 assert.equal(instance.exports.first(0,511),expected);
 assert.equal(instance.exports.second(0,511),expected);
}
