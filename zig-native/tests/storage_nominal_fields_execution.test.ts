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
    });
    try {
      await Deno.writeTextFile(`${directory}/shapes.blot`, shapes);
      const result = await compiler.build({ sources: { [entry]: source } });
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
