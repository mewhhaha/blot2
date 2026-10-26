import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
function uleb(bytes, at) {
  let value = 0, shift = 0;
  for (;;) {
    assert.ok(at < bytes.length && shift <= 28);
    const byte = bytes[at++];
    value += (byte & 127) * 2 ** shift;
    if (!(byte & 128)) return [value, at];
    shift += 7;
  }
}
function assertNoTrapOrUnexpectedCode(bytes) {
  let p = 8, found = false;
  while (p < bytes.length) {
    const id = bytes[p++];
    let size; [size, p] = uleb(bytes, p);
    const end = p + size;
    assert.ok(end <= bytes.length);
    if (id !== 10) { p = end; continue; }
    let count, body; [count, p] = uleb(bytes, p); assert.equal(count, 1);
    [body, p] = uleb(bytes, p); assert.equal(p + body, end);
    let locals; [locals, p] = uleb(bytes, p); assert.equal(locals, 0);
    while (p < end) {
      const opcode = bytes[p++];
      if (opcode === 0x20) { let ignored; [ignored, p] = uleb(bytes, p); assert.equal(ignored, 1); }
      else if (opcode === 0x41) {
        let byte, length = 0;
        do { assert.ok(p < end && length++ < 5); byte = bytes[p++]; } while (byte & 128);
      } else if (opcode === 0x04) { assert.equal(bytes[p++], 0x7f); }
      else { assert.ok(opcode === 0x05 || opcode === 0x0b, `unexpected opcode ${opcode}`); }
    }
    assert.equal(p, end);
    found = true;
  }
  assert.equal(found, true);
}
const atoms = [x => x, () => true, () => false];
const conditions = [...atoms];
for (const a of atoms) for (const b of atoms) {
  conditions.push(x => a(x) && b(x), x => a(x) || b(x));
}
for (let i = 0; i < conditions.length; i++) {
  const bytes = await readFile(`control_${i}.wasm`);
  assert.equal(WebAssembly.validate(bytes), true);
  assertNoTrapOrUnexpectedCode(bytes);
  const module = await WebAssembly.compile(bytes);
  assert.deepEqual(WebAssembly.Module.imports(module), []);
  const f = new WebAssembly.Instance(module).exports.f;
  for (const x of [0, 1]) {
    assert.equal(f(0, x) >>> 0, conditions[i](x === 1) ? 0xffffffff : 7);
  }
}
for (const [name, skipped, taken, value] of [["and", 0, 1, 0], ["or", 1, 0, 1]]) {
  const bytes = await readFile(`control_${name}_probe.wasm`);
  const f = (await WebAssembly.instantiate(bytes)).instance.exports.probe;
  assert.equal(f(0, skipped), value);
  assert.throws(() => f(0, taken), WebAssembly.RuntimeError);
}
console.log("control Wasm execution and short-circuit laws passed");
