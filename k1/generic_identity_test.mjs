import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const bytes = await readFile("generic_identity.wasm");
assert.equal(WebAssembly.validate(bytes), true);
const module = await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
assert.deepEqual(WebAssembly.Module.exports(module), [
  { name: "memory", kind: "memory" }, { name: "identity", kind: "function" }
]);
const instance = new WebAssembly.Instance(module);
const mem = new Uint8Array(instance.exports.memory.buffer);
const words = new DataView(instance.exports.memory.buffer);
const dict = 256, input = 1024, output = 2048;
const dictionaries = await readFile("generic_identity_dicts.bin");
assert.equal(dictionaries.length, 6 * 16);
// Exercise the same machine function and one fixed memory across admitted
// layout sizes. Logical move/loan authority is a compiler precondition; these
// JS witnesses establish only copied bytes and zero-size behavior.
for (let index = 0; index < 6; index++) {
  const record = dictionaries.subarray(index * 16, (index + 1) * 16);
  const size = record.readUInt32LE(0);
  assert.equal(size, [0, 4, 8, 64, 252, 256][index]);
  mem.fill(0xaa, output - 1, output + 258);
  for (let i = 0; i < size; i++) mem[input + i] = (i * 37 + 19) & 255;
  mem.set(record, dict);
  assert.equal(words.getUint32(dict, true), size);
  instance.exports.identity(0, size === 0 ? 0 : output, dict, size === 0 ? 0 : input);
  for (let i = 0; i < size; i++) assert.equal(mem[output + i], mem[input + i]);
  assert.equal(mem[output - 1], 0xaa);
  assert.equal(mem[output + size], 0xaa);
}
console.log("single generic Wasm worker execution passed");
