import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const caller = `import * as values from "./values"
entry const answer = func (input: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[input]
  let left = values.four marker[0]
  let right = values.four (@u32.add input 10)
  let latest = values.one 99
  let mixed = values.mixed input
  let overwrite = values.four 123
  let (a, b, c, d) = @simd.f32x4.bits (mixed.zero, mixed.nan, mixed.zero, mixed.nan)
  return #[left.one.x, left.y, left.z, left.w, right.one.x, right.w, latest.x, mixed.word, a, b, c, d, overwrite.one.x]
entry const fallback = func (input: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[input]
  let row = values.five marker[0]
  let selected = values.choice input
  let word = case selected of
    $values.Left value => value
    $values.Right value => @u32.add value 1
  return #[row.a, row.e, word]
entry const guarded = func (input: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[input]
  let first = values.four marker[0]
  let row = values.guarded input
  return #[first.one.x, first.w, row.one.x, row.w]
entry const stopped = func (input: U32): U32 => return do:
  let marker: GrowArray U32 = #[input]
  return (values.stopped marker[0]).one.x
`;
function producer(offset: number): string {
  return `type One is data = $One {x: U32}
type Four is data = $Four {one: One, y: U32, z: U32, w: U32}
type Five is data = $Five {a: U32, b: U32, c: U32, d: U32, e: U32}
type Mixed is data = $Mixed {word: U32, zero: F32, nan: F32}
type Choice is data = $Left U32 | $Right U32
const one = func (x: U32): One => return $One {x: @u32.add x ${offset}}
const four = func (input: U32): Four => return $Four {one: one input, y: 2, z: 3, w: 4}
const five = func (input: U32): Five => return $Five {a: input, b: 2, c: 3, d: 4, e: 5}
const choice = func (input: U32): Choice => return if input == 0 then $Left input else $Right input
const mixed = func (input: U32): Mixed => return do:
  let (zero, nan, _, _) = @simd.u32x4.from_bits (0x80000000, 0x7FC01234, 0, 0)
  return $Mixed {word: input, zero, nan}
const stopped = func (input: U32): Four => return do:
  use @panic "stopped"
  return four input
const guarded = func (input: U32): Four => return do:
  if input == 0:
    return four 55
  if input == 1:
    let failed = @u32.div 19 0
    return four failed
  return four input
`;
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`inline return registers retain nested results bits traps and source edits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-inline-registers-",
    });
    const entry = `${directory}/main.blot`;
    const values = `${directory}/values.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const options = {
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false as const,
      codegenTier,
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      let latest: Uint8Array<ArrayBuffer> | undefined;
      let sources: Record<string, string> = {};
      for (const offset of [0, 7, 19]) {
        sources = { [entry]: caller, [values]: producer(offset) };
        const result = await compiler.build({ sources });
        assert(result.success, JSON.stringify(result));
        const counters = result.stats.workCounters as Record<string, number>;
        assert(counters.scoped_inline_register_calls > 0);
        assert.equal(
          counters.scoped_inline_result_owners_avoided,
          counters.scoped_inline_register_calls,
        );
        latest = result.bytes;
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            const call = async (name: string, input: number) => {
              if (asynchronous) return await guest.callAsync(name, input);
              return guest.call(name, input);
            };
            for (const input of [0, 9, 0xFFFFFFFF]) {
              assert.deepEqual(
                await call("answer", input),
                new Uint32Array([
                  input + offset,
                  2,
                  3,
                  4,
                  input + 10 + offset,
                  4,
                  99 + offset,
                  input,
                  0x80000000,
                  0x7FC01234,
                  0x80000000,
                  0x7FC01234,
                  123 + offset,
                ]),
              );
              let selected = 0;
              if (input !== 0) selected = input + 1;
              assert.deepEqual(
                await call("fallback", input),
                new Uint32Array([input, 5, selected]),
              );
            }
            assert.deepEqual(
              await call("guarded", 0),
              new Uint32Array([offset, 4, 55 + offset, 4]),
            );
            await assert.rejects(
              async () => await call("guarded", 1),
              WebAssembly.RuntimeError,
            );
            await assert.rejects(
              async () => await call("stopped", 1),
              WebAssembly.RuntimeError,
            );
            assert.deepEqual(
              await call("guarded", 8),
              new Uint32Array([8 + offset, 4, 8 + offset, 4]),
            );
          } finally {
            guest.dispose();
          }
        }
      }
      const fresh = await createZigProjectCompiler(options);
      try {
        const result = await fresh.build({ sources });
        assert(result.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, latest);
      } finally {
        await fresh.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

const plannedSource = `type Pair is data = $Pair {x: U32, y: U32}
const pair = func (input: U32): Pair => return $Pair {x: input, y: @u32.add input 1}
const calculate = func (counter: Array U32) -> (input: U32): U32 => return do:
  counter[0] := @u32.add counter[0] 1
  return input
const consume = func (destination: ResizeArray U32) -> (read: Unit -> U32 ! {|e}): Unit => return do:
  let total = read ()
${"  total := @u32.add total 1\n".repeat(1000)}  let first = pair total
${"  total := @u32.add total 1\n".repeat(1000)}  let second = pair total
  @storage.push destination first.x
  @storage.push destination first.y
  @storage.push destination second.x
  @storage.push destination second.y
  return ()
const exercise = func (value: U32) -> (destination: ResizeArray U32): Unit => return do:
  for index in 0 .. 3:
    consume destination (func () => return value)
  return ()
entry const answer = func (input: U32): Array U32 => return do:
  let counter: Array U32 = #[0]
  let destination: ResizeArray U32 = #[]
  let held = pair input
  exercise (calculate counter input) destination
  return #[held.x, held.y, counter[0], destination[0], destination[1], destination[2], destination[3], destination[8], destination[9], destination[10], destination[11]]
type Row is data = $Row {target: Ref U32}
const rollback_pair = func (input: U32): Pair => return $Pair {x: input, y: @u32.add input 1}
const bump = func (rows: ResizeArray Row): Unit => return do:
  for row in rows:
    @storage.write row.target (@u32.add (@storage.load row.target) 1)
const change = func (rows: ResizeArray Row): U32 => return do:
  let held = rollback_pair (@storage.length rows)
  bump rows
  @storage.truncate rows 1
  let later = rollback_pair 9
  return @u32.add held.y later.y
entry const rollback = func (input: U32): Array U32 => return do:
  let left: Array U32 = #[input]
  let right: Array U32 = #[@u32.add input 10]
  let rows: ResizeArray Row = #[$Row {target: @storage.at left 0}, $Row {target: @storage.at right 0}]
  let count = change rows
  return #[left[0], right[0], count]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`inline return registers survive reusable helpers and enclosing loops (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-inline-registers-helpers-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const result = await compiler.build({
        sources: { [entry]: plannedSource },
      });
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(counters.scoped_inline_register_calls > 0);
      assert(counters.scoped_function_plan_definitions > 0, JSON.stringify(counters));
      assert(counters.scoped_completed_plan_rollbacks > 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          for (const input of [0, 91, 0xFFFFFFFF]) {
            let actual: unknown;
            if (asynchronous) actual = await guest.callAsync("answer", input);
            else actual = guest.call("answer", input);
            let rolled: unknown;
            if (asynchronous) rolled = await guest.callAsync("rollback", input);
            else rolled = guest.call("rollback", input);
            assert.deepEqual(
              rolled,
              new Uint32Array([input + 1, input + 11, 13]),
            );
            assert.deepEqual(
              actual,
              new Uint32Array([
                input,
                input + 1,
                1,
                input + 1000,
                input + 1001,
                input + 2000,
                input + 2001,
                input + 1000,
                input + 1001,
                input + 2000,
                input + 2001,
              ]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
