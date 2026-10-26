import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

for (const [index, name, expected] of [
  [0, "f", [7, 0xffffffff]],
  [1, "choose", [17, 42]],
  [2, "value", [9, 9]],
]) {
  const bytes = await readFile(`flow_decl_${index}.wasm`);
  assert.equal(WebAssembly.validate(bytes), true);
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  assert.deepEqual(WebAssembly.Module.exports(module), [{ name, kind: "function" }]);
  const f = new WebAssembly.Instance(module).exports[name];
  for (const x of [0, 1]) assert.equal(f(0, x) >>> 0, expected[x]);
}
console.log("private whole-source flow Wasm execution passed");
