import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const shapes = `type Vector is data = $Vector {x: F32}
type Pose is data = $Pose {position: Vector}
const vector = func (x: F32) => return $Vector {x}
const Vector.add = func (left: Vector) -> (right: Vector) => return vector (@f32.add left.x right.x)
const rows = func (pool: ResizeArray (Maybe a)): &[Maybe a] => return &pool[0..pool.length]
`;
const source = `import * as shapes from "./shapes"
const shifted = func access -> tag => return do:
  let poses = shapes.rows access.pool
  let $Some pose = poses.at 0 else:
    return (tag, shapes.vector 0.0)
  return (tag, pose.position + shapes.vector 1.0)
entry const answer = func (input: F32) => return do:
  let pool: ResizeArray (Maybe shapes.Pose) = #[$Some $shapes.Pose {position: shapes.vector input}]
  let (integer, first) = shifted {pool} 7
  pool[0] := $Some $shapes.Pose {position: shapes.vector (input + 10.0)}
  let (floating, second) = shifted {pool} input
  return #[U32.to_f32 integer, first.x, floating, second.x]
type Payload a is data = $Payload {left: a, right: a}
const swap = func (value: Payload a): Payload a => return $Payload {right: value.left, left: value.right}
const roundtrip = func value => return swap (swap value)
const sum = func (value: Payload a) => return value.left + value.right
const selected = func (value: Maybe (Payload a)) -> (fallback: Payload a): Payload a => return case value of
  $Some payload => roundtrip payload
  $Nothing => roundtrip fallback
type Token a is data = $Token Unit
const carry = func (token: Token a): Token a => return token
const carried = func token => return carry (carry token)
const integer_token = func (token: Token U32) -> (value: U32): U32 => return @u32.add value 1
const floating_token = func (token: Token F32) -> (value: U32): U32 => return @u32.add value 2
entry const integers = func (input: U32) => return do:
  let live: GrowArray U32 = #[input]
  let first = selected ($Some ($Payload {right: 3, left: live[0]})) ($Payload {left: 99, right: 99})
  let second = selected $Nothing ($Payload {right: live[0], left: 7})
  let third = selected ($Some ($Payload {left: @u32.add live[0] 11, right: 13})) first
  let integer: Token U32 = $Token ()
  let floating: Token F32 = $Token ()
  return #[first.left, first.right, second.left, second.right, sum first, sum second,
    sum third, integer_token (carried integer) live[0], floating_token (carried floating) live[0]]
entry const floats = func (input: F32) => return do:
  let live: GrowArray F32 = #[input]
  let first = selected ($Some ($Payload {left: live[0], right: 2.5})) ($Payload {right: 99.0, left: 99.0})
  let second = selected $Nothing ($Payload {right: live[0], left: 7.25})
  let third = selected ($Some ($Payload {right: 1.5, left: live[0]})) first
  return #[first.left, second.right, third.left, first.right, second.left, sum first, sum second, sum third]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`loaded nominal fields retain checked dispatch across generic contexts (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-nominal-fields-",
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
      startupTimeoutMs: 5_000,
    });
    try {
      await Deno.writeTextFile(`${directory}/shapes.blot`, shapes);
      const result = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(result.success, JSON.stringify(result));
      assert(
        (result.stats.workCounters as Record<string, number>)
          .scoped_emission_expressions > 0,
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          for (const input of [-0, 1.25, 100]) {
            const value = asynchronous
              ? await guest.callAsync("answer", input)
              : guest.call("answer", input);
            assert.deepEqual(
              value,
              new Float32Array([7, input + 1, input, input + 11]),
            );
          }
          for (const input of [0, 1, 41, 0xfffffffd, 3, 0]) {
            let value;
            if (asynchronous) value = await guest.callAsync("integers", input);
            else value = guest.call("integers", input);
            assert.deepEqual(
              value,
              new Uint32Array([
                input,
                3,
                7,
                input,
                input + 3,
                input + 7,
                input + 24,
                input + 1,
                input + 2,
              ]),
            );
          }
          for (const input of [0, -0, 1.25, -10.5, 3, -0]) {
            let value;
            if (asynchronous) value = await guest.callAsync("floats", input);
            else value = guest.call("floats", input);
            assert.deepEqual(
              value,
              new Float32Array([
                input,
                input,
                input,
                2.5,
                7.25,
                input + 2.5,
                input + 7.25,
                input + 1.5,
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
