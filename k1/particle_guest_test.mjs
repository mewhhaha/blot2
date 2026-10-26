// Private hand-emitted particle fixture: not source lowering, ownership
// validation, a host bridge, an M13 certificate or a legacy performance test.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';

const bytes = readFileSync('particle-guest.wasm');
assert(WebAssembly.validate(bytes));
const mod = new WebAssembly.Module(bytes);
assert.deepEqual(WebAssembly.Module.imports(mod), []);
assert.deepEqual(WebAssembly.Module.exports(mod).map(x => [x.name, x.kind]), [
  ['reserve', 'function'], ['close', 'function'], ['input_alloc', 'function'],
  ['input_freeze', 'function'], ['project', 'function'], ['memory', 'memory'],
]);
// Decode each code instruction, rather than searching bytes: 0x40 can occur
// in a signed LEB or block type. Inspect the complete unoptimized particle
// body: calls preflight only, and the loop has exactly scalar field operations.
function leb(buf, pos) {
  let n = 0, shift = 0, q;
  do { assert(pos.i < buf.length); q = buf[pos.i++]; n += (q & 127) * 2 ** shift; shift += 7; assert(shift <= 35); } while (q & 128);
  return n;
}
const plain = new Set([0x05, 0x0b, 0x0f, 0x45, 0x46, 0x47, 0x49, 0x4b, 0x4f,
  0x6a, 0x6b, 0x6c, 0x71, 0x72, 0x73, 0x74, 0x76, 0x92, 0x94]);
let bodies = 0, loopLoads = 0, loopStores = 0, loopAdds = 0, loopMuls = 0, projectCalls = 0;
const loopStoreOrder = [];
for (const p = { i: 8 }; p.i < bytes.length;) {
  const id = bytes[p.i++], size = leb(bytes, p), end = p.i + size; assert(end <= bytes.length);
  if (id === 10) {
    assert.equal(leb(bytes, p), 8);
    for (let fn = 0; fn < 8; fn++) {
      const len = leb(bytes, p), bodyEnd = p.i + len; assert(bodyEnd <= end);
      const groups = leb(bytes, p);
      for (let j = 0; j < groups; j++) { leb(bytes, p); assert([0x7f, 0x7d].includes(bytes[p.i++])); }
      let depth = 0, inLoop = false, loopDepth = 0;
      while (p.i < bodyEnd) {
        const op = bytes[p.i++]; assert.notEqual(op, 0x40, 'memory.grow is forbidden');
        if (op === 0x0b) {
          if (inLoop && depth === loopDepth) inLoop = false;
          if (depth > 0) depth--;
          continue;
        }
        if (op === 0x02 || op === 0x03 || op === 0x04) {
          assert([0x40, 0x7f].includes(bytes[p.i++])); depth++;
          if (fn === 7 && op === 0x03) { assert(!inLoop); inLoop = true; loopDepth = depth; }
          continue;
        }
        if (op === 0x10) {
          const target = leb(bytes, p);
          if (fn === 7) { assert.equal(target, 4); assert(!inLoop); projectCalls++; }
          continue;
        }
        if (op === 0x28 || op === 0x36 || op === 0x2a || op === 0x38) {
          const alignment = leb(bytes, p), offset = leb(bytes, p); assert.equal(alignment, 2);
          if (fn === 7 && inLoop) {
            if (op === 0x2a) loopLoads++;
            else if (op === 0x38) { loopStores++; loopStoreOrder.push(['f32', offset]); }
            else if (op === 0x36) loopStoreOrder.push(['length', offset]);
            else assert.fail('unexpected integer memory operation in particle loop');
          }
          continue;
        }
        if (plain.has(op)) {
          if (fn === 7 && inLoop && op === 0x92) loopAdds++;
          if (fn === 7 && inLoop && op === 0x94) loopMuls++;
          continue;
        }
        if ([0x0c, 0x0d, 0x20, 0x21, 0x41].includes(op)) { leb(bytes, p); continue; }
        assert.fail(`unexpected opcode ${op.toString(16)}`);
      }
      assert.equal(p.i, bodyEnd); bodies++;
    }
  } else p.i = end;
  assert.equal(p.i, end);
}
assert.equal(bodies, 8);
assert.deepEqual([projectCalls, loopLoads, loopStores, loopAdds, loopMuls], [2, 4, 2, 2, 2]);
assert.deepEqual(loopStoreOrder, [['f32', 0], ['f32', 4], ['length', 12]]);

function guest(selected = mod) {
  const e = new WebAssembly.Instance(selected).exports;
  assert.equal(e.memory.buffer.byteLength, 65536);
  assert.throws(() => e.memory.grow(1), RangeError);
  return e;
}
function image(e) { return Buffer.from(new Uint8Array(e.memory.buffer)); }
function words(e) { return new Uint32Array(e.memory.buffer); }
function slot(e, id) { return Array.from(words(e).slice(4 + (id - 1) * 8, 12 + (id - 1) * 8)); }
function inputDesc(e, id) { return Array.from(words(e).slice(64 + (id - 1) * 4, 68 + (id - 1) * 4)); }
function outputDesc(e, id) { return Array.from(words(e).slice(80 + (id - 1) * 4, 84 + (id - 1) * 4)); }
function unchanged(e, fn, expected) { const before = image(e); assert.equal(fn(), expected); assert.deepEqual(image(e), before); }
function allocate(e, inputBytes, outputBytes) {
  assert.equal(e.reserve(inputBytes), 1); assert.equal(e.reserve(outputBytes), 2);
}
function initRows(e, rows) {
  assert.equal(e.input_alloc(1, 1, rows.length), 0);
  const base = inputDesc(e, 1)[2], data = new DataView(e.memory.buffer);
  rows.forEach((r, i) => r.forEach((v, j) => data.setFloat32(base + i * 16 + j * 4, v, true)));
  assert.equal(e.input_freeze(1, 1), rows.length);
}
function f32bits(n) { const v = new DataView(new ArrayBuffer(4)); v.setFloat32(0, n, true); return v.getUint32(0, true); }
function expectFloatBits(actual, expected) {
  if (Number.isNaN(expected)) assert.equal(actual & 0x7fffffff, 0x7fc00000, 'canonical arithmetic NaN');
  else assert.equal(actual >>> 0, f32bits(expected) >>> 0);
}
function checkOutput(e, rows, dt, cap, originalInput) {
  const desc = outputDesc(e, 2), expectedPointer = rows.length ? slot(e, 2)[0] : 0;
  assert.deepEqual(desc, [2, 1, expectedPointer, rows.length]);
  assert.equal(slot(e, 2)[3], cap * 8);
  const data = new DataView(e.memory.buffer), out = desc[2];
  rows.forEach((r, i) => {
    const rounded = r.map(Math.fround), step = Math.fround(dt);
    const x = Math.fround(rounded[0] + Math.fround(rounded[2] * step));
    const y = Math.fround(rounded[1] + Math.fround(rounded[3] * step));
    expectFloatBits(data.getUint32(out + 8 * i, true), x);
    expectFloatBits(data.getUint32(out + 8 * i + 4, true), y);
  });
  const start = inputDesc(e, 1)[2];
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer, start, rows.length * 16)), originalInput);
}
// Empty input and zero-byte reservations still use distinct owner slots.
{
  const e = guest(); allocate(e, 0, 0); initRows(e, []);
  assert.deepEqual(inputDesc(e, 1), [2, 1, 0, 0]);
  assert.equal(e.project(1, 1, 2, 1, 0, 0.5), 0);
  checkOutput(e, [], 0.5, 0, Buffer.alloc(0));
  assert.equal(e.close(1, 1), 0); assert.equal(e.close(2, 1), 0);
}
{
  const e = guest(); allocate(e, 0, 32); initRows(e, []);
  assert.equal(e.project(1, 1, 2, 1, 4, 1), 0);
  checkOutput(e, [], 1, 4, Buffer.alloc(0));
  assert.equal(e.close(1, 1), 0); assert.equal(e.close(2, 1), 0);
}
// Failure checks are prior to output placement, writes, and publication.
{
  const e = guest(); allocate(e, 32, 16);
  unchanged(e, () => e.input_alloc(1, 1, 0xffffffff), -1);
  unchanged(e, () => e.input_alloc(1, 1, 3), -2);
  assert.equal(e.input_alloc(1, 1, 2), 0);
  unchanged(e, () => e.project(1, 1, 2, 1, 2, 1), -4); // not frozen
  const data = new DataView(e.memory.buffer), base = inputDesc(e, 1)[2];
  for (let i = 0; i < 8; i++) data.setFloat32(base + 4 * i, i + 1, true);
  assert.equal(e.input_freeze(1, 1), 2);
  unchanged(e, () => e.project(1, 1, 1, 1, 2, 1), -4); // same owner
  unchanged(e, () => e.project(1, 2, 2, 1, 2, 1), -4); // stale input
  unchanged(e, () => e.project(1, 1, 2, 2, 2, 1), -4); // stale output
  unchanged(e, () => e.project(1, 1, 2, 1, 0xffffffff, 1), -1);
  unchanged(e, () => e.project(1, 1, 2, 1, 3, 1), -2); // requested extent, not rounded
  unchanged(e, () => e.project(1, 1, 2, 1, 1, 1), -3); // capacity below input length
  const input = Buffer.from(new Uint8Array(e.memory.buffer, base, 32));
  assert.equal(e.project(1, 1, 2, 1, 2, 0.5), 2);
  checkOutput(e, [[1, 2, 3, 4], [5, 6, 7, 8]], 0.5, 2, input);
  unchanged(e, () => e.project(1, 1, 2, 1, 2, 1), -4); // published output cannot be reused
  assert.equal(e.close(1, 1), 0); assert.equal(e.close(2, 1), 0);
}
// Include signed zero, infinity and invalid arithmetic; expected non-NaN bits
// use two separately rounded f32 operations, not fused multiply-add.
{
  const rows = [
    [1, -2, 3.5, -4.25], [-0, +0, -0, +0], [Infinity, -Infinity, 0, -0],
    [1, 2, Infinity, -Infinity], [1.0000001192092896, -1, -1.0000001192092896, 1.0000001192092896],
  ];
  const e = guest(); allocate(e, rows.length * 16, 64); initRows(e, rows);
  const input = Buffer.from(new Uint8Array(e.memory.buffer, inputDesc(e, 1)[2], rows.length * 16));
  const outBase = slot(e, 2)[0], beforeUnused = Buffer.from(new Uint8Array(e.memory.buffer, outBase + rows.length * 8, 64 - rows.length * 8));
  assert.equal(e.project(1, 1, 2, 1, 8, 0), rows.length);
  checkOutput(e, rows, 0, 8, input);
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer, outBase + rows.length * 8, 64 - rows.length * 8)), beforeUnused);
  assert.equal(e.close(1, 1), 0); assert.equal(e.close(2, 1), 0);
}
// Separate test-only binaries inject an engine trap at each prefix of a
// four-row result. The internal builder remains live with exactly the complete
// rows, and no immutable view is published. This is not a recoverable source
// error or a claim that a trapped public bridge may safely resume: each
// fixture instance is discarded after inspection.
for (let prefix = 0; prefix <= 4; prefix++) {
  const faultBytes = readFileSync(`particle-fault-${prefix}.wasm`);
  assert(WebAssembly.validate(faultBytes));
  const e = guest(new WebAssembly.Module(faultBytes));
  const rows = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]];
  allocate(e, rows.length * 16, rows.length * 8); initRows(e, rows);
  const data = new DataView(e.memory.buffer), out = slot(e, 2)[0];
  new Uint8Array(e.memory.buffer, out, 32).fill(0xa5);
  const inputBase = inputDesc(e, 1)[2], input = Buffer.from(new Uint8Array(e.memory.buffer, inputBase, 64));
  assert.throws(() => e.project(1, 1, 2, 1, 4, 0.5), WebAssembly.RuntimeError);
  assert.deepEqual(outputDesc(e, 2), [1, 1, out, prefix]);
  for (let i = 0; i < prefix; i++) {
    expectFloatBits(data.getUint32(out + i * 8, true), Math.fround(rows[i][0] + Math.fround(rows[i][2] * 0.5)));
    expectFloatBits(data.getUint32(out + i * 8 + 4, true), Math.fround(rows[i][1] + Math.fround(rows[i][3] * 0.5)));
  }
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer, out + prefix * 8, (4 - prefix) * 8)), Buffer.alloc((4 - prefix) * 8, 0xa5));
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer, inputBase, 64)), input);
}
// Maximum contiguous use of all six granules, 1024 inputs and exactly full
// output. Values are deterministic; expected results are calculated separately.
{
  const rows = []; let seed = 0x6a09e667;
  const next = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
  for (let i = 0; i < 1024; i++) rows.push(Array.from({length: 4}, () => ((next() % 200001) - 100000) / 128));
  const dt = Math.fround(0.03125), e = guest(); allocate(e, rows.length * 16, rows.length * 8);
  assert.equal(words(e)[36], 63); initRows(e, rows);
  const input = Buffer.from(new Uint8Array(e.memory.buffer, inputDesc(e, 1)[2], rows.length * 16));
  assert.equal(e.project(1, 1, 2, 1, rows.length, dt), rows.length);
  checkOutput(e, rows, dt, rows.length, input);
  assert.equal(e.close(1, 1), 0); assert.equal(e.close(2, 1), 0); assert.equal(words(e)[36], 0);
}
console.log('private unoptimized particle Wasm fixture passed');
