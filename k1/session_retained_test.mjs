import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const bytes = await readFile("session_retained.wasm");
assert.equal(WebAssembly.validate(bytes), true);
const module = await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const identity = new WebAssembly.Instance(module).exports.identity;
for (const value of [0, 1, 42, 0x7fffffff, 0x80000000, 0xffffffff]) {
  assert.equal(identity(0, value) >>> 0, value);
}
console.log("private session retained Wasm execution passed");
