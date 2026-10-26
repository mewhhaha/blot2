// Private integration fixture. Raw memory is exported only for tests, and its
// arbitrary corruption is outside the trusted owner/bitmap invariant.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const bytes = readFileSync('bridge-fixture.wasm');
assert(WebAssembly.validate(bytes));
const mod = new WebAssembly.Module(bytes);
assert.deepEqual(WebAssembly.Module.imports(mod), []);
assert.deepEqual(WebAssembly.Module.exports(mod).map(x => [x.name, x.kind]), [['invoke', 'function'], ['memory', 'memory']]);
// Decode the generated code section instruction by instruction. A literal
// immediate may contain 0x40; only the opcode denotes memory.grow.
function leb(buf, pos) {
  let n = 0, shift = 0, b;
  do { assert(pos.i < buf.length); b = buf[pos.i++]; n += (b & 127) * 2 ** shift; shift += 7; assert(shift <= 35); } while (b & 128);
  return n;
}
const plain = new Set([0x00, 0x05, 0x0b, 0x0f, 0x45, 0x46, 0x47, 0x49, 0x4b, 0x4c, 0x4f,
  0x6a, 0x6b, 0x6c, 0x71, 0x72, 0x73, 0x74, 0x76]);
let bodies = 0;
for (const p = {i: 8}; p.i < bytes.length;) {
  const id = bytes[p.i++], size = leb(bytes, p), end = p.i + size;
  assert(end <= bytes.length);
  if (id === 10) {
    assert.equal(leb(bytes, p), 12);
    for (let fn = 0; fn < 12; fn++) {
      const len = leb(bytes, p), bodyEnd = p.i + len; assert(bodyEnd <= end);
      const groups = leb(bytes, p);
      for (let j = 0; j < groups; j++) { leb(bytes, p); assert.equal(bytes[p.i++], 0x7f); }
      while (p.i < bodyEnd) {
        const op = bytes[p.i++];
        assert.notEqual(op, 0x40, 'memory.grow is forbidden');
        if (plain.has(op)) continue;
        if ([0x02, 0x03, 0x04].includes(op)) { assert([0x40, 0x7f].includes(bytes[p.i++])); continue; }
        if ([0x0c, 0x0d, 0x10, 0x20, 0x21, 0x41].includes(op)) { leb(bytes, p); continue; }
        if ([0x28, 0x2d, 0x36].includes(op)) { leb(bytes, p); leb(bytes, p); continue; }
        assert.fail(`unexpected opcode ${op.toString(16)}`);
      }
      assert.equal(p.i, bodyEnd); bodies++;
    }
  } else p.i = end;
  assert.equal(p.i, end);
}
assert.equal(bodies, 12);
function make() {
  const e = new WebAssembly.Instance(mod).exports;
  assert.equal(e.memory.buffer.byteLength, 65536);
  assert.throws(() => e.memory.grow(1), RangeError);
  return e;
}
function dv(e) { return new DataView(e.memory.buffer); }
function u8(e) { return new Uint8Array(e.memory.buffer); }
function put(e, addr, value) { dv(e).setUint32(addr, value >>> 0, true); }
function get(e, addr) { return dv(e).getUint32(addr, true); }
function header(e) { return Array.from({length: 8}, (_, i) => get(e, 33024 + i * 4)); }
function initialize(e, values, mask, gap = 0, tail = 0) {
  const off = 12 + gap, payload = off + values.length * 4 + tail;
  u8(e).fill(0, 32768, 32896); u8(e).fill(0xa5, 33024, 33152);
  put(e, 32768, 0x4b310001); put(e, 32772, 17); put(e, 32780, payload);
  put(e, 32800, mask); put(e, 32804, values.length); put(e, 32808, off);
  values.forEach((x, i) => put(e, 32800 + off + i * 4, x));
  return payload + 32;
}
function clean(e) {
  assert.equal(get(e, 256), 0); assert.equal(get(e, 144) & 63, 0);
  for (let i = 0; i < 4; i++) assert.notEqual(get(e, 16 + i * 32 + 20), 1);
}
function sameInput(e, input) { assert.deepEqual(Buffer.from(u8(e).slice(32768, 32896)), input); }
function untouchedPayload(e) { assert(u8(e).slice(33056, 33152).every(x => x === 0xa5)); }
let seed = 0x71a1e43d;
const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
const e = make();
for (let n = 0; n <= 4; n++) for (let capacity = 0; capacity <= 28; capacity++) for (let gap of [0, 4, 12]) {
  const values = Array.from({length: n}, random), mask = random(), tail = random() % 4;
  const inputBytes = initialize(e, values, mask, gap, tail), old = Buffer.from(u8(e).slice(32768, 32896));
  const oldCalls = get(e, 260), required = 8 + n * 4;
  const status = e.invoke(17, inputBytes, capacity);
  assert.equal(status, capacity < required ? 2 : 0);
  sameInput(e, old); clean(e); assert.equal(get(e, 260), oldCalls + 1);
  if (status === 2) {
    assert.deepEqual(header(e), [0x4b310001, 17, 2, 0, required, n, 0, 0]); untouchedPayload(e);
  } else {
    assert.deepEqual(header(e), [0x4b310001, 17, 0, required, required, n, 0, 0]);
    assert.equal(get(e, 33056), n); assert.equal(get(e, 33060), 8);
    values.forEach((v, i) => assert.equal(get(e, 33064 + i * 4), (v ^ mask) >>> 0));
    assert(u8(e).slice(33056 + required, 33152).every(x => x === 0xa5));
  }
}
// A copied host result survives future reuse of private output memory.
let length = initialize(e, [7, 11], 5);
assert.equal(e.invoke(17, length, 16), 0);
const host = Buffer.from(u8(e).slice(33056, 33072));
length = initialize(e, [17], 31);
assert.equal(e.invoke(17, length, 12), 0);
assert.equal(host.readUInt32LE(0), 2); assert.equal(host.readUInt32LE(8), 7 ^ 5); assert.equal(host.readUInt32LE(12), 11 ^ 5);
// Busy must be decided before any memory/state mutation, even for bad inputs.
put(e, 256, 1);
let before = Buffer.from(u8(e)); assert.equal(e.invoke(0, 0, 0xffffffff), 4); assert.deepEqual(Buffer.from(u8(e)), before);
put(e, 256, 0);
// Every input word is independently checked before invocation or publication.
for (const mutate of [
  () => put(e, 32768, 0), () => put(e, 32772, 18), () => put(e, 32776, 1),
  () => put(e, 32780, 15), () => put(e, 32784, 1), () => put(e, 32788, 1),
  () => put(e, 32792, 1), () => put(e, 32796, 1), () => put(e, 32804, 5),
  () => put(e, 32808, 13), () => put(e, 32808, 8), () => put(e, 32808, 0xfffffffc),
]) {
  length = initialize(e, [7], 5); mutate(); const old = Buffer.from(u8(e).slice(32768, 32896)); const calls = get(e, 260);
  assert.equal(e.invoke(17, length, 12), 1); sameInput(e, old); clean(e); assert.equal(get(e, 260), calls);
  assert.deepEqual(header(e), [0x4b310001, 17, 1, 0, 0, 0, 0, 0]); untouchedPayload(e);
}
// Unreferenced gap and tail bytes are padding and must be zero.
for (const position of [32812, 32813, 32820]) {
  length = initialize(e, [7], 5, 4, 1); u8(e)[position] = 1; const calls = get(e, 260);
  assert.equal(e.invoke(17, length, 12), 1); clean(e); assert.equal(get(e, 260), calls); untouchedPayload(e);
}
for (const [exportId, inputBytes, capacity] of [[18, 48, 12], [17, 31, 12], [17, 129, 12], [17, 48, 97], [17, -1, 12], [17, 48, -1]]) {
  initialize(e, [7], 5); const calls = get(e, 260);
  assert.equal(e.invoke(exportId, inputBytes, capacity), 1); clean(e); assert.equal(get(e, 260), calls); untouchedPayload(e);
}
// Controlled exhaustion of the bitmap exercises reservation-failure cleanup;
// this is a fault injection, not proof against arbitrary metadata forgery.
length = initialize(e, [7], 5); put(e, 144, 63); const calls = get(e, 260);
assert.equal(e.invoke(17, length, 12), 3); assert.equal(get(e, 256), 0); assert.equal(get(e, 144), 63); assert.equal(get(e, 260), calls);
assert.deepEqual(header(e), [0x4b310001, 17, 3, 0, 0, 0, 3, 0]); untouchedPayload(e);
put(e, 144, 0); clean(e);
// Independently parse and check randomized host inputs; no model helper or
// guest validation is reused by this oracle.
function expected(input, exportId, size, capacity) {
  exportId >>>= 0; size >>>= 0; capacity >>>= 0;
  if (exportId !== 17 || size < 44 || size > 128 || capacity > 96) return {status: 1};
  const v = new DataView(input.buffer, input.byteOffset, input.byteLength);
  const w = p => v.getUint32(p, true), payload = size - 32;
  if (w(0) !== 0x4b310001 || w(4) !== 17 || w(8) !== 0 || w(12) !== payload ||
      w(16) !== 0 || w(20) !== 0 || w(24) !== 0 || w(28) !== 0) return {status: 1};
  const count = w(36), off = w(40);
  if (count > 4 || off % 4 || off < 12 || off > payload || count * 4 > payload - off) return {status: 1};
  for (let i = 12; i < payload; i++) if ((i < off || i >= off + count * 4) && input[32 + i]) return {status: 1};
  const required = 8 + count * 4;
  if (capacity < required) return {status: 2, required, count};
  return {status: 0, required, count, values: Array.from({length: count}, (_, i) => (w(32 + off + 4*i) ^ w(32)) >>> 0)};
}
for (let iteration = 0; iteration < 2500; iteration++) {
  const n = random() % 5, values = Array.from({length: n}, random), mask = random();
  length = initialize(e, values, mask, (random() % 5) * 4, random() % 8);
  let id = 17, cap = random() % 31;
  if (random() % 2) { const pos = random() % length; u8(e)[32768 + pos] ^= 1 << (random() % 8); }
  if (random() % 16 === 0) length = random() % 140;
  if (random() % 16 === 0) id = random();
  if (random() % 16 === 0) cap = random();
  const input = Buffer.from(u8(e).slice(32768, 32896)), want = expected(input, id, length, cap);
  const calls = get(e, 260), got = e.invoke(id, length, cap);
  assert.equal(got, want.status); sameInput(e, input); clean(e);
  assert.equal(get(e, 260), calls + (want.status === 1 ? 0 : 1));
  if (want.status === 1) { assert.deepEqual(header(e), [0x4b310001,17,1,0,0,0,0,0]); untouchedPayload(e); }
  else if (want.status === 2) { assert.deepEqual(header(e), [0x4b310001,17,2,0,want.required,want.count,0,0]); untouchedPayload(e); }
  else {
    assert.deepEqual(header(e), [0x4b310001,17,0,want.required,want.required,want.count,0,0]);
    want.values.forEach((value, i) => assert.equal(get(e, 33064 + i * 4), value));
  }
}
console.log('private copy-only bridge Wasm fixture passed');
