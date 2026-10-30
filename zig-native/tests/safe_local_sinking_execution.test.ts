import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

function firstFunctionBody(bytes: Uint8Array): Uint8Array {
  let offset = 8;
  function unsigned() {
    let value = 0;
    let shift = 0;
    while (true) {
      const byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) return value;
      shift += 7;
    }
  }
  while (offset < bytes.length) {
    const section = bytes[offset++];
    const length = unsigned();
    const end = offset + length;
    if (section === 10) {
      assert(unsigned() > 0);
      const bodyLength = unsigned();
      return bytes.subarray(offset, offset + bodyLength);
    }
    offset = end;
  }
  throw new Error("Missing Wasm code section");
}

Deno.test("safe scalar work is emitted after its consuming branch without a temporary or thunk", async () => {
  await compileAndRun(`
entry const heavy = func (input: U32) => return do:
  let work = @u32.add (@u32.mul (@u32.add (@u32.mul input 1664525) 1013904223) 22695477) 1
  if @u32.eq input 0:
    return 0
  return work
`, (guest, bytes, metrics) => {
    assert.equal((metrics.work_counters as { safe_local_sinks: number }).safe_local_sinks, 1);
    const body = firstFunctionBody(bytes);
    assert.equal(body[0], 0, "the internal function needs no temporary locals");
    const branch = body.findIndex((byte, index) => byte === 0x46 && body[index + 1] === 0x04 && body[index + 2] === 0x40);
    const multiply = body.indexOf(0x6c);
    assert(branch >= 0 && multiply > branch, "multiplication must follow the branch");
    assert.equal(guest.call("heavy", 0), 0);
    assert.equal(typeof guest.call("heavy", 2), "number");
  });
});

Deno.test("safe single-use locals can move into a branch without changing aliases or loops", async () => {
  await compileAndRun(`
entry const branch = func (input: U32) => return do:
  let computed = @u32.add input 40
  if @u32.eq input 0:
    return 0
  return computed
entry const alias = func (input: U32) => return do:
  let before = input
  let computed = @u32.add before 1
  before := @u32.add self 10
  return @u32.add computed before
entry const repeated = func (input: U32) => return do:
  let computed = @u32.add input 1
  let total = 0
  for 0..3:
    total := @u32.add self computed
  return total
`, (guest, _, metrics) => {
    const counters = metrics.work_counters as { safe_local_sinks: number };
    assert(counters.safe_local_sinks > 0);
    assert.equal(guest.call("branch", 0), 0);
    assert.equal(guest.call("branch", 2), 42);
    assert.equal(guest.call("alias", 1), 13);
    assert.equal(guest.call("repeated", 2), 9);
  });
});

Deno.test("trapping and effectful initializers remain eager", async () => {
  await compileAndRun(`
entry const trap = func (input: U32) => return do:
  let quotient = @u32.div 7 input
  if @u32.eq input 0:
    return 0
  return quotient
entry const effectful = func (callback: U32 -> U32 ! {Foreign}) => return do:
  use result <- callback 42
  if true:
    return 7
  return result
`, guest => {
    assert.equal(guest.call("trap", 1), 7);
    assert.throws(() => guest.call("trap", 0), WebAssembly.RuntimeError);
    let calls = 0;
    const callback = guest.capability({ parameter: "U32", result: "U32", call: (value: number) => { calls++; return value; } });
    assert.equal(guest.call("effectful", callback), 7);
    assert.equal(calls, 1);
  });
});

Deno.test("an immediately consumed opaque call or trap keeps eager order without a temporary", async () => {
  await compileAndRun(`
const divide = func (input: U32) => return @u32.div 7 input
const predicate = func (input: U32) => return @u32.eq input 0
entry const direct = func (input: U32) => return do:
  let value = divide input
  return value
entry const choice = func (input: U32) => return do:
  let condition = predicate input
  if condition:
    return 5
  return 6
`, (guest, _, metrics) => {
    assert((metrics.work_counters as { safe_local_sinks: number }).safe_local_sinks >= 2);
    assert.equal(guest.call("direct", 1), 7);
    assert.throws(() => guest.call("direct", 0), WebAssembly.RuntimeError);
    assert.equal(guest.call("choice", 0), 5);
    assert.equal(guest.call("choice", 1), 6);
  });
});

Deno.test("safe sinks and eager traps preserve behavior in both codegen tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-safe-sink-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url);
  const source = `
const helper = func (value: U32) => return @u32.div 7 value
entry const branch = func (input: U32) => return do:
  let work = @u32.mul (@u32.add input 2) 17
  if @u32.eq input 0:
    return 0
  return work
entry const snapshot = func (input: U32) => return do:
  let before = input
  let work = @u32.add before 1
  before := @u32.add self 10
  return @u32.add work before
entry const repeated = func (input: U32) => return do:
  let work = @u32.add input 1
  let total = 0
  for 0..3:
    total := @u32.add self work
  return total
entry const trap = func (input: U32) => return do:
  let quotient = @u32.div 7 input
  if @u32.eq input 0:
    return 0
  return quotient
entry const opaque = func (input: U32) => return do:
  let quotient = helper input
  if @u32.eq input 0:
    return 0
  return quotient
entry const direct = func (input: U32) => return do:
  let quotient = helper input
  return quotient
`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({ executable, entry, prelude: null, cacheDirectory: false, codegenTier });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("branch", 0), 0);
          assert.equal(guest.call("branch", 2), 68);
          assert.equal(guest.call("snapshot", 1), 13);
          assert.equal(guest.call("repeated", 2), 9);
          assert.equal(guest.call("trap", 1), 7);
          assert.throws(() => guest.call("trap", 0), WebAssembly.RuntimeError);
          assert.equal(guest.call("opaque", 1), 7);
          assert.throws(() => guest.call("opaque", 0), WebAssembly.RuntimeError);
          assert.equal(guest.call("direct", 1), 7);
          assert.throws(() => guest.call("direct", 0), WebAssembly.RuntimeError);
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
