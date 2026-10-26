// Executed private pool/builder fixture. The test models local runtime state,
// not source-level affine authority, loans, a public ABI, or a certificate.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';

const bytes = readFileSync('pool-builder-guest.wasm');
assert(WebAssembly.validate(bytes));
const mod = new WebAssembly.Module(bytes);
assert.deepEqual(WebAssembly.Module.imports(mod), []);
assert.deepEqual(WebAssembly.Module.exports(mod).map(x => [x.name, x.kind]), [
  ['reserve', 'function'], ['close', 'function'], ['begin', 'function'],
  ['append', 'function'], ['freeze', 'function'], ['read', 'function'], ['memory', 'memory'],
]);
// Decode the bounded fixture's code rather than searching bytes: immediates
// can contain 0x40. Every instruction and immediate must be recognized.
function leb(buf, pos) {
  let n = 0, shift = 0, b;
  do { assert(pos.i < buf.length); b = buf[pos.i++]; n += (b & 127) * 2 ** shift; shift += 7; assert(shift <= 35); } while (b & 128);
  return n;
}
const plain = new Set([0x00, 0x05, 0x0b, 0x0f, 0x45, 0x46, 0x47, 0x49, 0x4b, 0x4f,
  0x6a, 0x6b, 0x6c, 0x71, 0x72, 0x73, 0x74, 0x76]);
let bodies = 0;
for (const p = { i: 8 }; p.i < bytes.length;) {
  const id = bytes[p.i++], size = leb(bytes, p), end = p.i + size;
  assert(end <= bytes.length);
  if (id === 10) {
    assert.equal(leb(bytes, p), 10);
    for (let fn = 0; fn < 10; fn++) {
      const len = leb(bytes, p), bodyEnd = p.i + len; assert(bodyEnd <= end);
      const groups = leb(bytes, p);
      for (let j = 0; j < groups; j++) { leb(bytes, p); assert.equal(bytes[p.i++], 0x7f); }
      while (p.i < bodyEnd) {
        const op = bytes[p.i++];
        assert.notEqual(op, 0x40, 'memory.grow is forbidden');
        if (plain.has(op)) continue;
        if (op === 0x02 || op === 0x03 || op === 0x04) {
          assert([0x40, 0x7f].includes(bytes[p.i++])); continue;
        }
        if ([0x0c, 0x0d, 0x10, 0x20, 0x21, 0x41].includes(op)) { leb(bytes, p); continue; }
        if (op === 0x28 || op === 0x36) { leb(bytes, p); leb(bytes, p); continue; }
        assert.fail(`unexpected opcode ${op.toString(16)}`);
      }
      assert.equal(p.i, bodyEnd); bodies++;
    }
  } else p.i = end;
  assert.equal(p.i, end);
}
assert.equal(bodies, 10);
function guest() {
  const e = new WebAssembly.Instance(mod).exports;
  assert.equal(e.memory.buffer.byteLength, 65536);
  assert.throws(() => e.memory.grow(1), RangeError);
  return e;
}
function image(e) { return Buffer.from(new Uint8Array(e.memory.buffer)); }
function words(e) { return new Uint32Array(e.memory.buffer); }
function slot(e, id) { return Array.from(words(e).slice(4 + (id - 1) * 8, 12 + (id - 1) * 8)); }
function desc(e, id) { return Array.from(words(e).slice(40 + (id - 1) * 6, 45 + (id - 1) * 6)); }
function noChange(e, f, expected) { const before = image(e); assert.equal(f(), expected); assert.deepEqual(image(e), before); }

// Requested bytes, not rounded backing, bound placement. Failures preserve all
// metadata and data; scalar is written before the initialized length changes.
{
  const e = guest(); assert.equal(e.reserve(13), 1);
  noChange(e, () => e.begin(1, 1, 0xffffffff), -1);
  noChange(e, () => e.begin(1, 1, 4), -2);
  noChange(e, () => e.begin(1, 2, 1), -4);
  assert.equal(e.begin(1, 1, 3), 0);
  assert.deepEqual(slot(e, 1), [4096, 13, 4096, 12, 1, 1, 0, 0]);
  assert.deepEqual(desc(e, 1), [1, 1, 4096, 3, 0]);
  noChange(e, () => e.begin(1, 1, 1), -4);
  assert.equal(e.append(1, 1, 0), 0);
  assert.equal(e.append(1, 1, 0xffffffff), 0);
  assert.equal(e.append(1, 1, 0x12345678), 0);
  assert.equal(words(e)[1024], 0);
  assert.equal(words(e)[1025], 0xffffffff);
  assert.equal(words(e)[1026], 0x12345678);
  noChange(e, () => e.append(1, 1, 9), -3);
  assert.equal(e.freeze(1, 1), 3);
  assert.deepEqual(desc(e, 1), [2, 1, 4096, 3, 3]);
  assert.equal(e.read(1, 1, 0) >>> 0, 0);
  assert.equal(e.read(1, 1, 1) >>> 0, 0xffffffff);
  assert.equal(e.read(1, 1, 2) >>> 0, 0x12345678);
  const before = image(e); assert.throws(() => e.read(1, 1, 3), WebAssembly.RuntimeError); assert.deepEqual(image(e), before);
  noChange(e, () => e.append(1, 1, 8), -4);
  noChange(e, () => e.freeze(1, 1), -4);
  // The test ends the view before closing; raw exports do not prove the loan.
  assert.equal(e.close(1, 1), 0);
  noChange(e, () => e.begin(1, 1, 1), -4);
  assert.equal(e.reserve(4), 1);
  assert.equal(e.begin(1, 2, 1), 0);
  noChange(e, () => e.append(1, 1, 7), -4);
  assert.equal(e.append(1, 2, 7), 0);
  assert.equal(e.freeze(1, 2), 1); assert.equal(e.read(1, 2, 0), 7);
}
// Zero-sized capacity is still an affine builder and yields an empty view;
// no index may read it even if a zero-byte region reserved an owner slot.
{
  const e = guest(); assert.equal(e.reserve(0), 1); assert.equal(e.begin(1, 1, 0), 0);
  noChange(e, () => e.append(1, 1, 55), -3); assert.equal(e.freeze(1, 1), 0);
  const before = image(e); assert.throws(() => e.read(1, 1, 0), WebAssembly.RuntimeError); assert.deepEqual(image(e), before);
  assert.equal(e.close(1, 1), 0);
}
{
  const e = guest(); assert.equal(e.reserve(16), 1); assert.equal(e.begin(1, 1, 4), 0);
  assert.equal(e.freeze(1, 1), 0); assert.deepEqual(desc(e, 1), [2, 1, 0, 4, 0]);
  const before = image(e); assert.throws(() => e.read(1, 1, 0), WebAssembly.RuntimeError); assert.deepEqual(image(e), before);
  assert.equal(e.close(1, 1), 0);
}
// Independently reserved owners have disjoint physical runs; closing and
// recycling one slot must not change the other's live builder or bytes.
{
  const e = guest(); assert.equal(e.reserve(16), 1); assert.equal(e.reserve(16), 2);
  assert.equal(e.begin(1, 1, 2), 0); assert.equal(e.begin(2, 1, 2), 0);
  assert.equal(e.append(1, 1, 11), 0); assert.equal(e.append(2, 1, 22), 0);
  assert.equal(e.freeze(1, 1), 1); assert.equal(e.read(1, 1, 0), 11);
  const otherSlot = slot(e, 2), otherDesc = desc(e, 2), otherWord = words(e)[2048];
  assert.equal(e.close(1, 1), 0); assert.equal(e.reserve(16), 1);
  assert.equal(e.begin(1, 2, 2), 0); assert.equal(e.append(1, 2, 33), 0);
  assert.deepEqual(slot(e, 2), otherSlot); assert.deepEqual(desc(e, 2), otherDesc);
  assert.equal(words(e)[2048], otherWord);
  assert.equal(e.freeze(2, 1), 1); assert.equal(e.read(2, 1, 0), 22);
  assert.equal(e.freeze(1, 2), 1); assert.equal(e.read(1, 2, 0), 33);
  assert.equal(e.close(1, 2), 0); assert.equal(e.close(2, 1), 0);
}
// Verify local malformed owner/descriptor extents cannot cause writes or
// out-of-range loads. Global ownership disjointness remains trusted.
for (const tamper of [
  e => { words(e)[4]++; }, e => { words(e)[4] = 0; },
  e => { words(e)[7] = 4097; }, e => { words(e)[36] = 0; },
  e => { words(e)[42] = 28672; }, e => { words(e)[43] = 0xffffffff; },
  e => { words(e)[44] = 3; }, e => { words(e)[41] = 2; },
]) {
  const e = guest(); assert.equal(e.reserve(8), 1); assert.equal(e.begin(1, 1, 2), 0);
  tamper(e); noChange(e, () => e.append(1, 1, 9), -4); noChange(e, () => e.freeze(1, 1), -4);
}
// Independent reference model for bounded successful builders, including
// exhaustion, stale generations and all observed data words. A fresh region
// is used each epoch after the preceding frozen view's loan is ended.
{
  const e = guest(); let seed = 0x91cafe14;
  const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
  for (let epoch = 1; epoch <= 250; epoch++) {
    const requested = random() % 65, cap = random() % 20;
    assert.equal(e.reserve(requested), 1);
    let expectedTop = 0;
    if (cap * 4 > requested) {
      noChange(e, () => e.begin(1, epoch, cap), -2);
      assert.equal(e.close(1, epoch), 0); continue;
    }
    assert.equal(e.begin(1, epoch, cap), 0); expectedTop = cap * 4;
    const values = [], attempts = random() % 27;
    for (let i = 0; i < attempts; i++) {
      const value = random();
      if (values.length === cap) noChange(e, () => e.append(1, epoch, value), -3);
      else { assert.equal(e.append(1, epoch, value), 0); values.push(value); }
      assert.equal(slot(e, 1)[3], expectedTop);
      assert.equal(desc(e, 1)[4], values.length);
    }
    assert.equal(e.freeze(1, epoch), values.length);
    for (let i = 0; i < values.length; i++) assert.equal(e.read(1, epoch, i) >>> 0, values[i]);
    const before = image(e); assert.throws(() => e.read(1, epoch, values.length), WebAssembly.RuntimeError); assert.deepEqual(image(e), before);
    assert.equal(e.close(1, epoch), 0);
  }
}
console.log('private pool/destination/builder Wasm integration passed');
