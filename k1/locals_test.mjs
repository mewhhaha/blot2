import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

function uleb(bytes, p) {
  let n = 0, shift = 0;
  for (;;) {
    assert.ok(p < bytes.length && shift <= 28);
    const b = bytes[p++]; n += (b & 127) * 2 ** shift;
    if (!(b & 128)) return [n, p]; shift += 7;
  }
}
function inspect(bytes) {
  let p = 8, code = false, traps = 0;
  while (p < bytes.length) {
    const section = bytes[p++]; let size; [size, p] = uleb(bytes, p);
    const end = p + size; assert.ok(end <= bytes.length);
    if (section !== 10) { p = end; continue; }
    assert.equal(code, false); code = true;
    let funcs, body; [funcs, p] = uleb(bytes, p); assert.equal(funcs, 1);
    [body, p] = uleb(bytes, p); assert.equal(p + body, end);
    let groups; [groups, p] = uleb(bytes, p); assert.ok(groups === 0 || groups === 1);
    if (groups) { let count; [count, p] = uleb(bytes, p); assert.ok(count <= 128); assert.equal(bytes[p++], 0x7f); }
    while (p < end) {
      const op = bytes[p++];
      if (op === 0x20 || op === 0x21) { let index; [index, p] = uleb(bytes, p); assert.ok(index >= 1 && index <= 129); }
      else if (op === 0x41) { let b, count = 0; do { assert.ok(p < end && count++ < 5); b = bytes[p++]; } while (b & 128); }
      else if (op === 0x04) { assert.equal(bytes[p++], 0x40); }
      else if (op === 0x00) traps++;
      else assert.ok([0x05,0x0b,0x0f,0x49,0x6a,0x6b,0x6c,0x71].includes(op), `unexpected opcode ${op}`);
    }
    assert.equal(p, end);
  }
  assert.equal(code, true); assert.equal(traps, 1);
}
const expected = [
  x => x, x => (x + 1) >>> 0, x => (x - 1) >>> 0,
  x => (-x) >>> 0, x => Math.imul(x, 3) >>> 0, () => 0xffffffff,
  x => { const y = x & 255; return y < 10 ? y + 1 : y; },
  x => x < 5 ? x : 0, x => x & 15, x => x, x => x,
];
for (let i = 0; i < expected.length; i++) {
  const bytes = await readFile(`locals_${i}.wasm`);
  assert.equal(WebAssembly.validate(bytes), true); inspect(bytes);
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  assert.deepEqual(WebAssembly.Module.exports(module), [{ name: "f", kind: "function" }]);
  const f = new WebAssembly.Instance(module).exports.f;
  for (const x of [0,1,2,9,10,255,256,2147483648,4294967295]) {
    assert.equal(f(0, x) >>> 0, expected[i](x) >>> 0, `case ${i}, input ${x}`);
  }
}
console.log("private U32 local and checked/wrapping Wasm execution passed");
