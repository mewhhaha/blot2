// Run in the directory where wasm_test.goose emitted its fixtures.
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

function uleb(bytes, offset) {
  let value = 0;
  let scale = 1;
  for (;;) {
    assert.ok(offset < bytes.length, "truncated LEB");
    const byte = bytes[offset++];
    value += (byte & 127) * scale;
    if ((byte & 128) === 0) return [value, offset];
    scale *= 128;
    assert.ok(scale <= 2 ** 35, "oversized LEB");
  }
}

function sections(bytes) {
  const found = new Map();
  let p = 8;
  while (p < bytes.length) {
    const id = bytes[p++];
    let length;
    [length, p] = uleb(bytes, p);
    assert.ok(p + length <= bytes.length, "section out of bounds");
    if (id !== 0) {
      assert.equal(found.has(id), false, "duplicate section");
      found.set(id, bytes.subarray(p, p + length));
    }
    p += length;
  }
  return found;
}

async function instance(path) {
  const bytes = await readFile(path);
  assert.equal(WebAssembly.validate(bytes), true, `${path}: invalid Wasm`);
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), [], "no helpers or imports");
  assert.equal(WebAssembly.Module.exports(module).some((x) => x.kind === "memory"), false);
  const section = sections(bytes);
  assert.deepEqual([...section.keys()], [1, 3, 5, 7, 10]);
  // One memory, min and max are both 275 pages. No memory import or export.
  const memory = section.get(5);
  let p = 0, n, flags, initial, maximum;
  [n, p] = uleb(memory, p);
  [flags, p] = uleb(memory, p);
  [initial, p] = uleb(memory, p);
  [maximum, p] = uleb(memory, p);
  assert.deepEqual([n, flags, initial, maximum, p], [1, 1, 275, 275, memory.length]);
  const metadata = WebAssembly.Module.customSections(module, "blot.k1.fixture.memory");
  assert.equal(metadata.length, 1);
  const map = JSON.parse(new TextDecoder().decode(metadata[0]));
  assert.deepEqual(map, {
    version: 1, page_bytes: 65536, pages: 275, granule_bytes: 4096,
    static_bytes: 0, dictionary_bytes: 0, control: [0, 16], owners: [16, 8192],
    owner_slots: 256, owner_stride: 32, bitmap: [8208, 512], frame: [8720, 1048576],
    ingress: [1057296, 65536], egress: [1122832, 65536],
    alignment_padding: [1188368, 3568], pool: [1191936, 16777216],
    page_padding: [17969152, 53248], memory_bytes: 18022400,
  });
  const regions = [map.control, map.owners, map.bitmap, map.frame, map.ingress,
    map.egress, map.alignment_padding, map.pool, map.page_padding];
  let end = 0;
  for (const [start, size] of regions) {
    assert.equal(start, end, "layout has overlap or unaccounted space");
    end = start + size;
    assert.ok(end <= 0x40000000, "memory exceeds K1 hard limit");
  }
  assert.equal(end, map.pages * map.page_bytes);
  assert.equal(map.pool[0] % map.granule_bytes, 0);
  assert.equal(map.pool[1] % map.granule_bytes, 0);
  assert.equal(map.bitmap[1], Math.ceil(map.pool[1] / map.granule_bytes / 8));
  assert.equal(map.owners[1], map.owner_slots * map.owner_stride);

  // Inspect the whole code body, not arbitrary data bytes: exactly one function,
  // no locals, one const or local.get instruction, then end. Thus this fixture
  // has no calls, helper dispatch, or memory.grow instruction.
  const code = section.get(10);
  p = 0;
  [n, p] = uleb(code, p);
  assert.equal(n, 1);
  let bodyLength;
  [bodyLength, p] = uleb(code, p);
  assert.equal(p + bodyLength, code.length);
  assert.equal(code[p++], 0, "unexpected locals");
  const opcode = code[p++];
  assert.ok(opcode === 0x20 || opcode === 0x41);
  while ((code[p++] & 0x80) !== 0) assert.ok(p < code.length);
  assert.equal(code[p++], 0x0b);
  assert.equal(p, code.length, "unexpected instructions");
  return new WebAssembly.Instance(module);
}

const identity = await instance("identity.wasm");
for (const value of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) {
  assert.equal(identity.exports.id(0, value) >>> 0, value);
}
const expected = [0, 63, 64, 127, 128, 0x7fffffff, 0x80000000, 0xffffffff];
for (const [index, value] of expected.entries()) {
  const module = await instance(`const${index}.wasm`);
  assert.equal(module.exports.value(0, 123) >>> 0, value);
}
const longName = "x".repeat(130);
assert.equal((await instance("long.wasm")).exports[longName](0, 7), 7);
console.log("scalar Wasm fixture and memory layout: passed");
