import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

for (const op of [0, 1, 2]) {
  const bytes = await readFile(`thin_${op}.wasm`);
  assert.equal(WebAssembly.validate(bytes), true);
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  assert.deepEqual(WebAssembly.Module.exports(module), [{ name: "f", kind: "function" }]);
  const f = new WebAssembly.Instance(module).exports.f;
  assert.equal(f.length, 1);
  // A test-only copy redirects the export to the canonical adapter. The
  // emitted fixture itself exposes only the thin worker.
  const adapterBytes = Uint8Array.from(bytes);
  const leb = (at) => {
    let value = 0, shift = 0;
    for (;;) {
      assert.ok(at < adapterBytes.length && shift <= 28);
      const b = adapterBytes[at++];
      value += (b & 127) * 2 ** shift;
      if ((b & 128) === 0) return [value, at];
      shift += 7;
    }
  };
  let at = 8, redirected = false;
  while (at < adapterBytes.length) {
    const section = adapterBytes[at++];
    let size; [size, at] = leb(at);
    const end = at + size;
    assert.ok(end <= adapterBytes.length);
    if (section === 7) {
      let count, length; [count, at] = leb(at); assert.equal(count, 1);
      [length, at] = leb(at); at += length;
      assert.equal(adapterBytes[at++], 0); // function export
      assert.equal(adapterBytes[at], 0); // one-byte worker index
      adapterBytes[at++] = 1; // one-byte canonical-adapter index
      assert.equal(at, end);
      redirected = true;
      break;
    }
    at = end;
  }
  assert.equal(redirected, true);
  const adapter = (await WebAssembly.instantiate(adapterBytes)).instance.exports.f;
  assert.equal(adapter.length, 2);
  for (const x of [0, 1, 254, 255, 256, 0x7fffffff, 0x80000000, 0xffffffff]) {
    const actual = f(x) >>> 0;
    const expected = op === 0 ? x : op === 1 ? (x & 255) >>> 0 : Number(x < 255);
    assert.equal(actual, expected, `op ${op} input ${x}`);
    assert.equal(adapter(0, x) >>> 0, expected, `adapter op ${op} input ${x}`);
  }
}
console.log("scalar thin-entry fixture passed");
