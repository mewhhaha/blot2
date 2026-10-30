import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
let spine = "seed";
for (let step = 0; step < 16; step++) spine = `@u32.add (${spine}) 0`;
const source = (
  seed: string,
  prefix = "",
  point = "{ x: U32, y: Array U32 }",
) =>
  `${prefix}type Point is data = #Point ${point}
type Bucket is data = #Bucket { points: Array Point }
const seed = ${seed}
const update = func (index: U32) : Array U32 => return do:
  let bucket = #Bucket { points: #[#Point { y: #[10], x: ${spine} }, #Point { y: #[20], x: ${spine} }] }
  let before = bucket
  bucket.points[index].y[0] := @u32.add self seed
  break #[before.points[index].y[0], bucket.points[index].y[0]]
const replace = func values => return func index => return func value => return do:
  values[index] := value
  break values
entry const run = func (index: U32) : Array U32 => return update index
entry const replaced = func (value: U32) : Array U32 => return replace #[seed, 41] 1 value
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`body path update receipts preserve selector order old leaf and snapshots (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      const prefix = "const earlier = func (value: F32) => return @f32.add value 1.0\n";
      const revisions: readonly (readonly [string, number | null])[] = [
        [source("2"), 2],
        [source("2", prefix), 2],
        [source("3", prefix), 3],
        [source("missing_name"), null],
        [source("3", prefix, "{ y: Array U32, x: U32 }"), 3],
        [source("2"), 2],
      ];
      for (const [text, seed] of revisions) {
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = { [entry]: text };
          const ordinary = await fresh.build({ sources });
          const result = await compiler.build({ sources });
          assert.equal(result.success, ordinary.success);
          if (!result.success || !ordinary.success) {
            assert.ok(!result.success && !ordinary.success);
            if (seed !== null) console.error(result.diagnostics);
            assert.equal(seed, null);
            assert.deepEqual(result.diagnostics, ordinary.diagnostics);
            continue;
          }
          assert.ok(seed !== null);
          assert.deepEqual(result.bytes, ordinary.bytes);
          const guest = await instantiateGuest(result.bytes);
          try {
            for (let round = 0; round < 2; round++) {
              for (let call = 0; call < 64; call++) {
                const index = call % 2;
                const before = (index + 1) * 10;
                assert.deepEqual(
                  guest.call("run", index),
                  Uint32Array.of(before, before + seed),
                );
                assert.deepEqual(
                  guest.call("replaced", call),
                  Uint32Array.of(seed, call),
                );
              }
            }
            assert.throws(() => guest.call("run", 2));
            assert.deepEqual(
              guest.call("run", 1),
              Uint32Array.of(20, 20 + seed),
            );
          } finally {
            guest.dispose();
          }
          if (text === source("2", prefix)) {
            const work = result.stats.frontend.body_elaborations;
            const expected = ordinary.stats.frontend.body_elaborations;
            assert.ok(work !== null && expected !== null && work < expected);
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
