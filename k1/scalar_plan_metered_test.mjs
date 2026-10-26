import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const bytes = await readFile('metered_scalar.wasm');
const module = await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const f = new WebAssembly.Instance(module).exports.f;
for (const x of [0, 1, 6, 7, 8, 0x7fffffff, 0x80000000, 0xffffffff]) {
  assert.equal(f(0, x), Number(x < 7));
}
console.log('metered scalar Wasm execution passed');
