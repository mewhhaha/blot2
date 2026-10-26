import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
const hex = readFileSync(process.argv[2], "utf8");
assert.match(hex, /^(?:[0-9a-f]{2})+\n$/);
const module = await WebAssembly.compile(Buffer.from(hex.trim(), "hex"));
assert.deepEqual(WebAssembly.Module.imports(module), []);
const instance = new WebAssembly.Instance(module);
assert.deepEqual(Object.keys(instance.exports), ["a", "c", "b", "d"]);
for (const value of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) {
  const want = (value & 0x80000000) >>> 0;
  for (const name of ["a", "b", "d"]) assert.equal(instance.exports[name](0, value) >>> 0, want);
  assert.equal(instance.exports.c(0, value) >>> 0, 0x80000000);
}
console.log("multi-function source/Core/Wasm fixture passed");
