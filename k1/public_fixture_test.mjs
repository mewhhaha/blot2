import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const functions = [];
for (let i = 0; i < 4; i++) {
  const bytes = await readFile(`public_fixture_${i}.wasm`);
  assert.equal(WebAssembly.validate(bytes), true);
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  functions.push(new WebAssembly.Instance(module).exports.answer);
}
for (const value of [0, 1, 2, 255, 256, 0x7fffffff, 0x80000000, 0xffffffff]) {
  assert.equal(functions[0](0,value) >>> 0, value);
  assert.equal(functions[1](0,value) >>> 0, 0xffffffff);
  assert.equal(functions[2](0,value) >>> 0, (value & 255) >>> 0);
  assert.equal(functions[3](0,value) >>> 0, Number(value < 2));
}
console.log("public artifact fixture execution passed");
