import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
import * as rolling from "std/rolling"
import * as summary from "std/summary"
import * as iter from "std/iter"
import * as algebra from "./algebra"
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
entry const run = fn (count: U32) => do:
  let values = iter.map algebra.measure (iter.range 0 count)
  let width = 3
  let ordered = iter.fold_left add 0 (rolling.fold add 0 width values)
  let monoid = iter.fold_left add 0 (rolling.monoid add 0 width values)
  let group = iter.fold_left add 0 (rolling.group add (fn value => @u32.sub 0 value) 0 width values)
  let tree = summary.build add 0 values
  break #[ordered, monoid, group, summary.query add 0 0 count tree]
`;
const dependency =
  "const measure = fn (value: U32) -> U32 => @u32.add value 1\n";

Deno.test("rolling and summary owners survive source dependency checkpoint failures and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-reduction-revisions-",
  });
  const entry = `${directory}/main.blot`;
  const helper = `${directory}/algebra.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        stdRoot: new URL("../../std", import.meta.url).pathname,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      let checkpoint;
      try {
        for (
          const [program, algebra] of [
            [source, dependency],
            [source.replace("let width = 3", "let width = 2"), dependency],
            [source, dependency.replace("value 1", "value 2")],
            [
              source,
              dependency.replace("@u32.add value 1", "@f32.add 1.0 2.0"),
            ],
            [source, dependency],
          ]
        ) {
          const sources = { [entry]: program, [helper]: algebra };
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const ordinary = await fresh.build({ sources });
            assert.equal(built.success, ordinary.success);
            if (!built.success && !ordinary.success) {
              assert.deepEqual(built.diagnostics, ordinary.diagnostics);
            }
            if (built.success && ordinary.success) {
              assert.deepEqual(built.bytes, ordinary.bytes);
              const guest = await instantiateGuest(built.bytes);
              try {
                let width = 3;
                if (program.includes("let width = 2")) width = 2;
                let offset = 1;
                if (algebra.includes("value 2")) offset = 2;
                let total = 0;
                for (let start = 0; start + width <= 20; start++) {
                  for (let i = 0; i < width; i++) total += start + i + offset;
                }
                assert.deepEqual(
                  guest.call("run", 20),
                  Uint32Array.of(total, total, total, 190 + 20 * offset),
                );
              } finally {
                guest.dispose();
              }
            }
          } finally {
            await fresh.dispose();
          }
        }
        checkpoint = await retained.exportCheckpoint();
      } finally {
        await retained.dispose();
      }
      const restarted = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = {
          [entry]: source,
          [helper]: dependency.replace("value 1", "value 2"),
        };
        const resumed = await restarted.build({ sources });
        const ordinary = await fresh.build({ sources });
        assert(resumed.success && ordinary.success);
        assert.deepEqual(resumed.bytes, ordinary.bytes);
        const guest = await instantiateGuest(resumed.bytes);
        try {
          assert.deepEqual(
            guest.call("run", 20),
            Uint32Array.of(621, 621, 621, 230),
          );
        } finally {
          guest.dispose();
        }
      } finally {
        await restarted.dispose();
        await fresh.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
