import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
let spine = "seed";
for (let index = 0; index < 16; index++) spine = `@u32.add (${spine}) 0`;
const source = (seed: string, prefix = "", increment = 1) =>
  `${prefix}const seed = ${seed}
const sum = func (limit: U32) : U32 => return do:
  use initial <- ${spine}
  use initial
  let total = initial
  for index in 0..limit:
    for 0..2:
      total := @u32.add self index
      if @u32.lt 3 total:
        break
  for value in #[1, 2]:
    total := @u32.add self value
  for ever:
    total := @u32.add self ${increment}
    let total = 42
    break
  break total
const keep = func (values: Array U32) : Array U32 => return do:
  let chosen = values
  for index in 0..4:
    chosen := values
    if @u32.eq index 2:
      break
  break chosen
entry const run = func (limit: U32) : U32 => return sum limit
entry const copied = func (limit: U32) : Array U32 => return keep #[limit, seed]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`body loop receipts preserve lexical exits owning arrays and failed revisions (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    const retained = await createZigProjectCompiler(options);
    try {
      const inserted =
        "const earlier = func (value: F32) : F32 => return @f32.add value 1.0\n";
      const revisions: readonly (readonly [string, number | null])[] = [
        [source("2"), 2],
        [source("2", inserted), 2],
        [source("3", inserted), 3],
        [source("missing_name"), null],
        [source("3", inserted, 2), 3],
        [source("2"), 2],
      ];
      for (const [text, seed] of revisions) {
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = { [entry]: text };
          const expected = await fresh.build({ sources });
          const actual = await retained.build({ sources });
          assert.equal(actual.success, expected.success);
          if (!actual.success || !expected.success) {
            assert.ok(!actual.success && !expected.success);
            assert.equal(seed, null);
            assert.deepEqual(actual.diagnostics, expected.diagnostics);
            continue;
          }
          assert.notEqual(seed, null);
          assert.deepEqual(actual.bytes, expected.bytes);
          const guest = await instantiateGuest(actual.bytes);
          try {
            for (let call = 0; call < 64; call++) {
              assert.equal(guest.call("run", call % 8), 42);
              assert.deepEqual(
                guest.call("copied", call),
                Uint32Array.of(call, seed!),
              );
            }
          } finally {
            guest.dispose();
          }
          if (text === source("2", inserted)) {
            const work = actual.stats.frontend.body_elaborations;
            const ordinary = expected.stats.frontend.body_elaborations;
            assert.ok(work !== null && ordinary !== null && work < ordinary);
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
