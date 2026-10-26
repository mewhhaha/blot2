import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createBridgeFixture} from './bridge_host_fixture.mjs';
const host = createBridgeFixture(readFileSync('bridge-fixture.wasm'));
assert.deepEqual(Object.keys(host), ['call']);
const first = host.call([1, 2, 0xffffffff], 0x80000001, 20);
assert.equal(first.status, 'Ok');
assert.deepEqual([...first.values], [0x80000000, 0x80000003, 0x7ffffffe]);
const original = [...first.values];
assert.deepEqual(host.call([10, 11], 7, 15), {status: 'OutputTooSmall', required: 16, count: 2});
const second = host.call([3], 1, 12);
assert.deepEqual([...second.values], [2]);
assert.deepEqual([...first.values], original); // no reused Wasm-backed view
first.values[0] = 42;
assert.deepEqual([...host.call([1], 0, 12).values], [1]);
assert.throws(() => host.call([1,2,3,4,5], 0, 96), TypeError);
assert.throws(() => host.call([1.5], 0, 96), TypeError);
assert.throws(() => host.call(Array(1), 0, 12), TypeError);
const accessor = [];
Object.defineProperty(accessor, '0', {get() { throw new Error('getter ran'); }, enumerable: true});
assert.throws(() => host.call(accessor, 0, 12), TypeError);
let nested;
const proxied = new Proxy([7], {getOwnPropertyDescriptor(target, key) {
  if (key === '0') nested = host.call([99], 0, 12);
  return Reflect.getOwnPropertyDescriptor(target, key);
}});
assert.deepEqual([...host.call(proxied, 1, 12).values], [6]);
assert.deepEqual(nested, {status: 'Busy'});
assert.deepEqual([...host.call([1], 0, 12).values], [1]);
assert.throws(() => host.call([1], -1, 96), TypeError);
assert.throws(() => host.call([1], 0, 97), TypeError);
// An actual Wasm engine trap poisons the host and all later calls are refused.
// This small synthetic module exports an unreachable invoke and fixed memory.
const trap = new Uint8Array([
  0,97,115,109,1,0,0,0,
  1,8,1,96,3,127,127,127,1,127,
  3,2,1,0,
  5,4,1,1,1,1,
  7,19,2,6,105,110,118,111,107,101,0,0,6,109,101,109,111,114,121,2,0,
  10,5,1,3,0,0,11,
]);
const poisoned = createBridgeFixture(trap);
assert.deepEqual(poisoned.call([], 0, 8), {status: 'Poisoned'});
assert.deepEqual(poisoned.call([1], 0, 12), {status: 'Poisoned'});
console.log('private copied host wrapper and trap poisoning passed');
