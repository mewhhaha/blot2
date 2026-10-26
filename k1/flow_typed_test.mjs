import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

function uleb(bytes, p) {
  let v = 0, shift = 0;
  for (;;) {
    assert.ok(p < bytes.length && shift <= 28);
    const b = bytes[p++]; v += (b & 127) * 2 ** shift;
    if (!(b & 128)) return [v, p];
    shift += 7;
  }
}
function inspect(bytes) {
  let p = 8, traps = 0, branches = 0, code = false;
  while (p < bytes.length) {
    const section = bytes[p++]; let length; [length, p] = uleb(bytes, p);
    const end = p + length; assert.ok(end <= bytes.length);
    if (section !== 10) { p = end; continue; }
    assert.equal(code, false); code = true;
    let count, size; [count, p] = uleb(bytes, p); assert.equal(count, 1);
    [size, p] = uleb(bytes, p); assert.equal(p + size, end);
    let locals; [locals, p] = uleb(bytes, p); assert.equal(locals, 0);
    while (p < end) {
      const op = bytes[p++];
      if (op === 0x20) { let local; [local, p] = uleb(bytes, p); assert.equal(local, 1); }
      else if (op === 0x41) {
        let b, count = 0; do { assert.ok(p < end && count++ < 5); b = bytes[p++]; } while (b & 128);
      } else if (op === 0x04) { branches++; assert.ok(bytes[p] === 0x40 || bytes[p] === 0x7f); p++; }
      else if (op === 0x00) traps++;
      else assert.ok(op === 0x05 || op === 0x0b || op === 0x0f, `unexpected opcode ${op}`);
    }
    assert.equal(p, end);
  }
  assert.equal(code, true);
  return { traps, branches };
}
const expected = [[42, 42], [7, 0xffffffff], [2, 1], [5, 4], [7, 6], [9, 9]];
for (let i = 0; i < expected.length; i++) {
  const bytes = await readFile(`flow_typed_${i}.wasm`);
  assert.equal(WebAssembly.validate(bytes), true);
  const shape = inspect(bytes); assert.equal(shape.traps, 1);
  if (i > 0) assert.ok(shape.branches > 0);
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  assert.deepEqual(WebAssembly.Module.exports(module), [{ name: "f", kind: "function" }]);
  const f = new WebAssembly.Instance(module).exports.f;
  for (const x of [0, 1]) assert.equal(f(0, x) >>> 0, expected[i][x]);
}
for (const [kind, skip, evaluate, expected] of [["and", 0, 1, 2], ["or", 1, 0, 1]]) {
  const bytes = await readFile(`flow_typed_${kind}_probe.wasm`);
  assert.equal(WebAssembly.validate(bytes), true);
  assert.equal(inspect(bytes).traps, 2);
  const f = (await WebAssembly.instantiate(bytes)).instance.exports.f;
  assert.equal(f(0, skip) >>> 0, expected);
  assert.throws(() => f(0, evaluate), WebAssembly.RuntimeError);
}
console.log("private typed flow Wasm execution and short-circuit tests passed");
