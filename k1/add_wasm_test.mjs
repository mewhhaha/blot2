// Execute and inspect proof-gated private checked-add fixture bytes.
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
function leb(bytes, offset) {
  let value = 0, shift = 0;
  for (;;) {
    assert.ok(offset < bytes.length && shift <= 28);
    const byte = bytes[offset++]; value += (byte & 127) * 2 ** shift;
    if (!(byte & 128)) return [value, offset];
    shift += 7;
  }
}
for (let i = 0; i < 3; i++) {
  const bytes = await readFile(`add_v4_${i}.wasm`);
  assert.ok(WebAssembly.validate(bytes));
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  const instance = new WebAssembly.Instance(module);
  for (const x of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) {
    assert.equal(instance.exports.f(0, x) >>> 0, x);
  }
  let p = 8, found = false;
  while (p < bytes.length) {
    const id = bytes[p++]; let length; [length, p] = leb(bytes, p);
    assert.ok(p + length <= bytes.length);
    if (id === 10) {
      const code = bytes.subarray(p, p + length);
      // One function, size seven, zero locals, local.get argument, i32.const
      // zero, i32.add, end. No unvalidated transform replaces the add.
      assert.deepEqual([...code], [1, 7, 0, 0x20, 1, 0x41, 0, 0x6a, 0x0b]);
      found = true;
    }
    p += length;
  }
  assert.ok(found, "missing code section");
}
console.log("checked-add Wasm execution and opcode passed");
