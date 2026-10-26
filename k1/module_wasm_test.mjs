// Inspect and execute synthetic v3 module fixtures. They are not source
// admission, a public export contract, or a K1 runtime certificate.
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
function uleb(bytes, offset) {
  let value = 0, shift = 0;
  for (;;) {
    assert.ok(offset < bytes.length && shift <= 28, "malformed LEB");
    const byte = bytes[offset++]; value += (byte & 127) * 2 ** shift;
    if (!(byte & 128)) return [value, offset];
    shift += 7;
  }
}
function sections(bytes) {
  let p = 8; const out = new Map();
  while (p < bytes.length) {
    const id = bytes[p++]; let len; [len, p] = uleb(bytes, p);
    assert.ok(p + len <= bytes.length);
    if (id) { assert.ok(!out.has(id)); out.set(id, bytes.subarray(p, p + len)); }
    p += len;
  }
  return out;
}
function bodies(code, expected) {
  let p = 0, n; [n, p] = uleb(code, p); assert.equal(n, expected);
  const result = [];
  for (let i = 0; i < n; i++) {
    let size; [size, p] = uleb(code, p); assert.ok(p + size <= code.length);
    result.push([...code.subarray(p, p + size)]); p += size;
  }
  assert.equal(p, code.length);
  return result;
}
async function load(path, count) {
  const bytes = await readFile(path); assert.ok(WebAssembly.validate(bytes));
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  const sec = sections(bytes); assert.deepEqual([...sec.keys()], [1, 3, 5, 7, 10]);
  let p = 0, n, flags, minimum, maximum; const mem = sec.get(5);
  [n, p] = uleb(mem, p); [flags, p] = uleb(mem, p);
  [minimum, p] = uleb(mem, p); [maximum, p] = uleb(mem, p);
  assert.deepEqual([n, flags, minimum, maximum, p], [1, 1, 275, 275, mem.length]);
  const metadata = WebAssembly.Module.customSections(module, "blot.k1.fixture.memory");
  assert.equal(metadata.length, 1);
  const map = JSON.parse(new TextDecoder().decode(metadata[0]));
  assert.equal(map.pages, 275); assert.deepEqual(map.pool, [1191936, 16777216]);
  const body = bodies(sec.get(10), count);
  return { instance: new WebAssembly.Instance(module), body };
}
const { instance, body } = await load("module_v3.wasm", 5);
assert.deepEqual(body[0], [0, 0x41, 0, 0x20, 1, 0x10, 2, 0x0b]);
assert.deepEqual(body[1], [0, 0x41, 0, 0x41, 0x7f, 0x10, 2, 0x0b]);
assert.deepEqual(body[3], [0, 0x41, 0, 0x20, 1, 0x10, 0, 0x0b]);
for (const x of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) {
  for (const name of ["forward", "backward", "leaf"]) assert.equal(instance.exports[name](0, x) >>> 0, x);
  assert.equal(instance.exports.literal(0, x) >>> 0, 0xffffffff);
  assert.equal(instance.exports.mask(0, x) >>> 0, (x & 0x80000000) >>> 0);
}
const chain = await load("module_chain.wasm", 128);
assert.equal(chain.instance.exports.f0(0, 0x80000000) >>> 0, 0x80000000);
const many = await load("module_many.wasm", 256);
assert.equal(Object.keys(many.instance.exports).length, 256);
assert.equal(many.instance.exports.f255(0, 0xffffffff) >>> 0, 0xffffffff);
console.log("multi-function Wasm execution passed");
