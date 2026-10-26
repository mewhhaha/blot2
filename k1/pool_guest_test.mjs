// Executed Wasm tests for a private fixed-pool guest fixture. This is not a
// K1 compiler or runtime certificate; the deliberately exported memory permits
// selected malformed-state tests that checked K1 source must not be able to
// forge. It does not validate global owner disjointness: a forged owner can
// point at another owner's run. These tests do not establish robustness to
// arbitrary hostile memory corruption.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';

const bytes = readFileSync('pool-guest.wasm');
assert(WebAssembly.validate(bytes));
const module = new WebAssembly.Module(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
assert.deepEqual(WebAssembly.Module.exports(module).map(x => [x.name, x.kind]), [
  ['reserve', 'function'], ['close', 'function'], ['memory', 'memory'],
]);

// Decode every instruction in this deliberately small fixture rather than
// searching raw bytes (a LEB immediate may itself contain 0x40). The admitted
// grammar has no imported helpers, indirect calls, memory.grow or unknown op.
function uleb(buf, pos) {
  let n = 0, shift = 0, b;
  do { assert(pos.i < buf.length); b = buf[pos.i++]; n += (b & 127) * 2 ** shift; shift += 7; assert(shift <= 35); } while (b & 128);
  return n;
}
const noImmediate = new Set([0x05, 0x0b, 0x0f, 0x45, 0x46, 0x47, 0x49, 0x4b, 0x4f,
  0x6a, 0x6b, 0x6c, 0x71, 0x72, 0x73, 0x74, 0x76]);
let codeBodies = 0;
for (const p = { i: 8 }; p.i < bytes.length;) {
  const id = bytes[p.i++]; const len = uleb(bytes, p); const end = p.i + len;
  assert(end <= bytes.length);
  if (id === 10) {
    const count = uleb(bytes, p); assert.equal(count, 4);
    for (let fn = 0; fn < count; fn++) {
      const size = uleb(bytes, p), bodyEnd = p.i + size;
      assert(bodyEnd <= end);
      const groups = uleb(bytes, p);
      for (let i = 0; i < groups; i++) { uleb(bytes, p); assert.equal(bytes[p.i++], 0x7f); }
      while (p.i < bodyEnd) {
        const op = bytes[p.i++];
        assert.notEqual(op, 0x40, 'memory.grow must not occur');
        if (noImmediate.has(op)) continue;
        if (op === 0x02 || op === 0x03 || op === 0x04) {
          const blocktype = bytes[p.i++]; assert(blocktype === 0x40 || blocktype === 0x7f); continue;
        }
        if ([0x0c, 0x0d, 0x10, 0x20, 0x21, 0x41].includes(op)) { uleb(bytes, p); continue; }
        if (op === 0x28 || op === 0x36) { uleb(bytes, p); uleb(bytes, p); continue; }
        assert.fail(`unexpected opcode 0x${op.toString(16)}`);
      }
      assert.equal(p.i, bodyEnd); codeBodies++;
    }
  } else p.i = end;
  assert.equal(p.i, end);
}
assert.equal(codeBodies, 4);

function guest() {
  const e = new WebAssembly.Instance(module).exports;
  assert.equal(e.memory.buffer.byteLength, 65536);
  assert.throws(() => e.memory.grow(1), RangeError);
  return { ...e, words: new Uint32Array(e.memory.buffer) };
}
// Buffer.slice aliases its original backing store. Copy from a Uint8Array so
// the snapshot cannot silently change when guest memory is later mutated.
function image(e) { return Buffer.from(new Uint8Array(e.memory.buffer)); }
function slot(e, id) { return Array.from(e.words.slice(4 + (id - 1) * 8, 12 + (id - 1) * 8)); }

{
  const e = guest();
  const before = image(e);
  e.words[0] = 123;
  assert.equal(before.readUInt32LE(0), 0);
  assert.notDeepEqual(image(e), before);
  e.words[0] = 0;
  assert.deepEqual(image(e), before);
}

{
  const e = guest();
  assert.equal(e.reserve(4096), 1);
  assert.equal(e.reserve(8192), 2);
  assert.equal(e.reserve(4096), 3);
  assert.deepEqual(slot(e, 1), [4096, 4096, 4096, 0, 1, 1, 0, 0]);
  assert.deepEqual(slot(e, 2), [8192, 8192, 8192, 0, 1, 1, 0, 0]);
  assert.equal(e.words[36], 15);
  assert.equal(e.close(2, 1), 0);
  assert.equal(e.words[36], 9);
  let before = image(e);
  assert.equal(e.reserve(12288), -3); // fragmentation despite four free granules
  assert.deepEqual(image(e), before);
  assert.equal(e.reserve(4097), 2);
  assert.deepEqual(slot(e, 2), [8192, 4097, 8192, 0, 2, 1, 0, 0]);
  before = image(e);
  assert.equal(e.close(2, 1), -4); // stale generation
  assert.deepEqual(image(e), before);
  assert.equal(e.reserve(0), 4);
  assert.deepEqual(slot(e, 4), [0, 0, 0, 0, 1, 1, 0, 0]);
  before = image(e);
  assert.equal(e.reserve(0xffffffff), -1); // overflow before no slots
  assert.equal(e.reserve(0xfffff000), -2); // last roundable request; no slots
  assert.equal(e.reserve(0), -2);
  assert.deepEqual(image(e), before);
  assert.equal(e.close(4, 1), 0);
  assert.equal(e.words[36], 15);
}
{
  const e = guest();
  e.words[8] = 0xfffffffe; // simulate near-exhausted free generation
  assert.equal(e.reserve(1), 1);
  assert.equal(slot(e, 1)[4], 0xffffffff);
  assert.equal(e.close(1, 0xffffffff), 0);
  assert.equal(slot(e, 1)[5], 3);
  assert.equal(e.reserve(0), 2); // retired slot never reused
}
for (const tamper of [
  e => { e.words[4] += 1; },                 // unaligned base
  e => { e.words[4] = 0; },                  // base below pool
  e => { e.words[4] = 7 * 4096; },           // extent outside pool
  e => { e.words[5] = 4097; },               // bad rounded size
  e => { e.words[7] = 4097; },               // top exceeds request
  e => { e.words[36] = 0; },                 // bitmap no longer covers run
  e => { e.words[9] = 4; },                  // wrong owner state
]) {
  const e = guest(); assert.equal(e.reserve(4096), 1);
  tamper(e); const before = image(e);
  assert.equal(e.close(1, 1), -4);
  assert.deepEqual(image(e), before);
}
{
  const e = guest(); assert.equal(e.reserve(0), 1);
  e.words[4] = 4096; // zero-sized regions must have base zero
  const before = image(e); assert.equal(e.close(1, 1), -4); assert.deepEqual(image(e), before);
  assert.equal(e.close(0, 1), -4); assert.equal(e.close(5, 1), -4); assert.equal(e.close(1, 0), -4);
  assert.deepEqual(image(e), before);
}

// Differential state-machine run against an independent small JS model.
// It includes zero-byte owners, fragmentation, stale close and boundary sizes;
// it does not qualify the source checker, host ABI, or full K1 runtime.
{
  const e = guest();
  const slots = Array.from({ length: 4 }, () => [0, 0, 0, 0, 0, 0, 0, 0]);
  let bits = 0, seed = 0x71e3a28b;
  function random() { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; }
  function referenceReserve(bytes) {
    bytes >>>= 0;
    if (bytes > 0xfffff000) return -1;
    const rounded = Math.ceil(bytes / 4096) * 4096;
    const index = slots.findIndex(s => s[5] === 0);
    if (index < 0) return -2;
    const needed = rounded / 4096;
    let begin = -1;
    for (let i = 0; i <= 6 - needed; i++) {
      const mask = ((1 << needed) - 1) << i;
      if ((bits & mask) === 0) { begin = i; break; }
    }
    if (begin < 0) return -3;
    bits |= ((1 << needed) - 1) << begin;
    const gen = slots[index][4] + 1;
    slots[index] = [needed ? 4096 + begin * 4096 : 0, bytes, rounded, 0, gen, 1, 0, 0];
    return index + 1;
  }
  function referenceClose(id, gen) {
    if (id < 1 || id > 4 || !gen) return -4;
    const s = slots[id - 1];
    if (s[5] !== 1 || s[4] !== gen) return -4;
    if (s[2]) {
      const begin = (s[0] - 4096) / 4096, count = s[2] / 4096;
      bits &= ~(((1 << count) - 1) << begin);
    }
    s[5] = gen === 0xffffffff ? 3 : 0;
    return 0;
  }
  const sizes = [0, 1, 4095, 4096, 4097, 8192, 12288, 24576, 24577, 0xfffff000, 0xffffffff];
  let reserveSuccesses = 0, reserveFailures = 0, closeSuccesses = 0, closeFailures = 0;
  for (let step = 0; step < 2000; step++) {
    const draw = random();
    if (draw % 3 !== 0) {
      const size = sizes[random() % sizes.length];
      const expected = referenceReserve(size);
      assert.equal(e.reserve(size), expected, `reserve at step ${step}`);
      if (expected > 0) reserveSuccesses++; else reserveFailures++;
    } else {
      const id = random() % 6, expected = id >= 1 && id <= 4 ? slots[id - 1][4] : 0;
      const gen = (random() & 1) ? expected : (expected + 1) >>> 0;
      const result = referenceClose(id, gen);
      assert.equal(e.close(id, gen), result, `close at step ${step}`);
      if (result === 0) closeSuccesses++; else closeFailures++;
    }
    assert.equal(e.words[36], bits >>> 0, `bitmap at step ${step}`);
    for (let id = 1; id <= 4; id++) assert.deepEqual(slot(e, id), slots[id - 1], `owner ${id} at step ${step}`);
  }
  assert(reserveSuccesses > 0 && reserveFailures > 0 && closeSuccesses > 0 && closeFailures > 0);
}
console.log('private Wasm pool guest laws passed');
