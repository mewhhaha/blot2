import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `type Sample a is data = $Sample {value: a}
const read = func (access: {rows: GrowArray a, stamp: U32}) => return {sample: $Sample {value: access.rows[0]}, stamp: access.stamp}
const twice = func access => return do:
  let first = read access
  let second = read access
  return {stamp: first.stamp, sample: second.sample}
const outer = func access => return do:
  let first = twice access
  let second = twice access
  return {sample: first.sample, stamp: second.stamp}
entry const integers = func (input: U32) => return do:
  let left: GrowArray U32 = #[input]
  let right: GrowArray U32 = #[@u32.add input 11]
  let first = outer {rows: left, stamp: 3}
  let second = outer {stamp: 7, rows: right}
  left[0] := @u32.add left[0] 19
  let third = outer {stamp: 13, rows: left}
  return #[first.sample.value, first.stamp, second.sample.value, second.stamp, third.sample.value, third.stamp, right[0]]
entry const floats = func (input: F32) => return do:
  let left: GrowArray F32 = #[input]
  let right: GrowArray F32 = #[@f32.add input 2.5]
  let first = outer {stamp: 17, rows: left}
  let second = outer {rows: right, stamp: 23}
  left[0] := @f32.add left[0] 7.25
  let third = outer {rows: left, stamp: 29}
  return #[first.sample.value, @u32.to_f32 first.stamp, second.sample.value, @u32.to_f32 second.stamp, third.sample.value, @u32.to_f32 third.stamp, right[0]]
type Vec3 is data = $Vec3 {x: F32, y: F32, z: F32}
const position = func (rows: GrowArray {position: Vec3}) => return rows[0].position
const position_twice = func rows => return do:
  let first = position rows
  let second = position rows
  return second
const tuple = func (rows: GrowArray {left: F32, right: F32}) => return (rows[0].left, rows[0].right)
const tuple_twice = func rows => return do:
  let (left, ignored) = tuple rows
  let (unused, right) = tuple rows
  return (left, right)
entry const projections = func (input: F32) => return do:
  let poses: GrowArray {position: Vec3} = #[{position: $Vec3 {z: 3.5, x: input, y: -0.0}}]
  let pairs: GrowArray {left: F32, right: F32} = #[{right: -0.0, left: input}]
  let point = position_twice poses
  let (left, right) = tuple_twice pairs
  return #[point.x, point.y, point.z, left, right]
const read_branch = func (rows: GrowArray U32) -> (early: Bool) => return do:
  let first = rows[0]
  if early:
    return {value: first, stamp: rows[1]}
  return {stamp: first, value: rows[1]}
const read_branch_twice = func (rows: GrowArray U32) => return do:
  let first = read_branch rows true
  let second = read_branch rows false
  return {value: first.value, stamp: second.stamp}
entry const early_returns = func (input: U32) => return do:
  let left: GrowArray U32 = #[input, 7]
  let right: GrowArray U32 = #[@u32.add input 11, 13]
  let first = read_branch_twice left
  let second = read_branch_twice right
  left[0] := @u32.add input 19
  let third = read_branch_twice left
  return #[first.value, second.stamp, third.value, right[1]]
type Choice is data = $Count U32 | $Empty
const choice_read = func (rows: GrowArray Choice): Choice => return rows[0]
const choice_twice = func rows => return do:
  let first = choice_read rows
  let second = choice_read rows
  return second
const choice_value = func (choice: Choice): U32 => return case choice of
  $Count value => value
  $Empty => 31
entry const variants = func (input: U32) => return do:
  let left: GrowArray Choice = #[$Count input]
  let right: GrowArray Choice = #[$Empty]
  let first = choice_twice left
  let second = choice_twice right
  left[0] := $Empty
  right[0] := $Count (@u32.add input 9)
  let third = choice_twice left
  let fourth = choice_twice right
  return #[choice_value first, choice_value second, choice_value third, choice_value fourth]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`shared aggregate readers preserve schemas and independent owners (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-aggregate-readers-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        stdRoot,
        prelude: `${stdRoot}/prelude.blot`,
        cacheDirectory: false,
        codegenTier,
        startupTimeoutMs: 5_000,
      });
      const result = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(result.success, JSON.stringify(result));
      const work = result.stats.workCounters as Record<string, number>;
      assert(work.scoped_reader_cache_hits >= 4, JSON.stringify(work));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          const call = async (name: string, input: number) => {
            if (asynchronous) return await guest.callAsync(name, input);
            return guest.call(name, input);
          };
          for (const input of [0, 1, 41, 0xfffffffd, 3, 0]) {
            assert.deepEqual(
              await call("early_returns", input),
              new Uint32Array([input, input + 11, input + 19, 13]),
            );
            assert.deepEqual(
              await call("variants", input),
              new Uint32Array([input, 31, 31, input + 9]),
            );
            assert.deepEqual(
              await call("integers", input),
              new Uint32Array([
                input,
                3,
                input + 11,
                7,
                input + 19,
                13,
                input + 11,
              ]),
            );
          }
          for (const input of [-0, 1.25, -10.5, 3, -0]) {
            assert.deepEqual(
              await call("floats", input),
              new Float32Array([
                input,
                17,
                input + 2.5,
                23,
                input + 7.25,
                29,
                input + 2.5,
              ]),
            );
            assert.deepEqual(
              await call("projections", input),
              new Float32Array([
                input,
                -0,
                3.5,
                input,
                -0,
              ]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
