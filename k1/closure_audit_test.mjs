// Independent randomized execution checks for the fixed private closure guest.
// closure_test.goose emits this file before this script runs.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const bytes = readFileSync('closure_fixture.wasm');
assert(WebAssembly.validate(bytes));
const module = new WebAssembly.Module(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const run = new WebAssembly.Instance(module).exports.run;
let seed = 0xbabe12f0;
const next = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
for (let i = 0; i < 50000; i++) {
  const capture = next(), argument = next(), capacity = next() % 8;
  const expected = capacity < 4 ? -1n : BigInt((capture & argument) >>> 0);
  assert.equal(run(capture, argument, capacity), expected);
}
console.log('independent closure execution oracle passed');
