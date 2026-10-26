import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const module = await WebAssembly.compile(await readFile('scalar_scheduled.wasm'));
assert.deepEqual(WebAssembly.Module.imports(module), []);
const less = new WebAssembly.Instance(module).exports.less;
for (const x of [0, 1, 6, 7, 8, 0x7fffffff, 0x80000000, 0xffffffff]) {
  assert.equal(less(0, x), Number(x < 7));
}
console.log('private scheduled scalar pipeline Wasm execution passed');
