import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
function uleb(bytes, offset) {
  let value = 0, shift = 0;
  for (;;) {
    assert.ok(offset < bytes.length && shift <= 28);
    const byte = bytes[offset++];
    value += (byte & 127) * 2 ** shift;
    if (!(byte & 128)) return [value, offset];
    shift += 7;
  }
}
function assertFixedMemory(bytes) {
  let p = 8;
  while (p < bytes.length) {
    const id = bytes[p++];
    let len; [len, p] = uleb(bytes, p);
    assert.ok(p + len <= bytes.length);
    if (id === 5) {
      let q = p, count, flags, min, max;
      [count, q] = uleb(bytes, q); [flags, q] = uleb(bytes, q);
      [min, q] = uleb(bytes, q); [max, q] = uleb(bytes, q);
      assert.deepEqual([count, flags, min, max, q], [1, 1, 275, 275, p + len]);
      return;
    }
    p += len;
  }
  assert.fail("missing fixed memory");
}
const numbers = [0, 1, 0x7fffffff, 0x80000000, 0xffffffff];
const inputs = [0, 1, 0x7fffffff, 0x80000000, 0xffffffff];
// Fixed-seed differential cases include unsigned values on both sides of the
// sign boundary and are reproducible across engines.
let random = 0x92d68ca2;
for (let i = 0; i < 1000; i++) {
  random ^= random << 13;
  random ^= random >>> 17;
  random ^= random << 5;
  inputs.push(random >>> 0);
}
const apply = (op, a, b) => op === 1 ? (a & b) >>> 0 : Number(a < b);
for (const [i, n] of numbers.entries()) {
  for (const op of [1, 2]) {
    for (const side of ["left", "right", "pair"]) {
      const bytes = await readFile(`v2_${side}_${op}_${i}.wasm`);
      assert.equal(WebAssembly.validate(bytes), true);
      assertFixedMemory(bytes);
      const module = await WebAssembly.compile(bytes);
      assert.deepEqual(WebAssembly.Module.imports(module), []);
      const fn = new WebAssembly.Instance(module).exports.f;
      for (const x of inputs) {
        const a = side === "right" ? x : n;
        const b = side === "left" ? x : side === "right" ? n : 1;
        const got = fn(0, x) >>> 0;
        assert.equal(got, apply(op, a, b), `${side} ${op} ${n} ${x}`);
        if (op === 2) assert.ok(got === 0 || got === 1);
      }
    }
  }
}
console.log("typed scalar Wasm laws passed");
