import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const { instance } = await WebAssembly.instantiate(await readFile("add_scoped.wasm"));
for (const n of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) {
  assert.equal(instance.exports.f(0, n) >>> 0, n >>> 0);
}
console.log("scoped checked-add Wasm execution passed");
