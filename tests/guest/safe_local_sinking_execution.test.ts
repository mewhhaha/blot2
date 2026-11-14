import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("safe scalar work after its consuming branch keeps its value", async () => {
  await compileAndRun(`
entry const heavy = func (input: U32) => return do:
  let work = @u32.add (@u32.mul (@u32.add (@u32.mul input 1664525) 1013904223) 22695477) 1
  if @u32.eq input 0:
    return 0
  return work
`, (guest) => {
    assert.equal(guest.call("heavy", 0), 0);
    const work = (input: number) =>
      (Math.imul((Math.imul(input, 1664525) + 1013904223) >>> 0, 22695477) + 1) >>> 0;
    for (const input of [1, 2, 0xffff_ffff]) {
      assert.equal(guest.call("heavy", input), work(input));
    }
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
`, (guest) => {
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

Deno.test("an immediately consumed opaque call or trap keeps eager order", async () => {
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
`, (guest) => {
    assert.equal(guest.call("direct", 1), 7);
    assert.throws(() => guest.call("direct", 0), WebAssembly.RuntimeError);
    assert.equal(guest.call("choice", 0), 5);
    assert.equal(guest.call("choice", 1), 6);
  });
});

Deno.test("safe sinks and eager traps preserve behavior in both codegen tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-safe-sink-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ?? new URL("../../compiler/zig-out/bin/blotc", import.meta.url);
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
    {
      const compiler = await createZigProjectCompiler({ executable, entry, prelude: null, cacheDirectory: false });
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
