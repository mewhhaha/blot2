import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const method = (increment = 0) =>
  `const Array.count = fn values => @u32.add (@array.length values) ${increment}\n`;
const program = (seed: string) =>
  `const seed = ${seed}
const bundle = do:
  let first = #[].count
  let second = #[].count
  let cost = 1
  for index in 0..256:
    cost := @u32.add self 1
  break {first, second, cost}
entry const run = fn () => @u32.add bundle.first (@u32.add bundle.second bundle.cost)
entry const unrelated = seed
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`constant inference barriers retain compound data and current observations (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const prelude = `${directory}/prelude.blot`;
    await Deno.writeTextFile(entry, program("2"));
    await Deno.writeTextFile(prelude, method());
    const options = {
      executable,
      entry,
      prelude,
      cacheDirectory: false as const,
      codegenTier,
    };
    const retained = await createZigProjectCompiler(options);
    try {
      const revisions = [["2", 0], ["3", 0], ["3", 1], ["2", 0]] as const;
      for (const [index, [seed, increment]] of revisions.entries()) {
        const sources = {
          [entry]: program(seed),
          [prelude]: method(increment),
        };
        const actual = await retained.build({ sources });
        assert(actual.success, JSON.stringify(actual));
        const fresh = await createZigProjectCompiler(options);
        try {
          const expected = await fresh.build({ sources });
          assert(expected.success, JSON.stringify(expected));
          assert.deepEqual(actual.bytes, expected.bytes);
          assert.equal(
            actual.stats.nativeWorkSteps,
            expected.stats.nativeWorkSteps,
          );
        } finally {
          await fresh.dispose();
        }
        if (index === 1) {
          const receipts = actual.stats.constantReceipts as {
            reused: number;
            queries_replayed: number;
          };
          assert(receipts.reused > 0);
          assert(receipts.queries_replayed >= 2);
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(actual.bytes, { asynchronous });
          try {
            let result;
            if (asynchronous) result = await guest.callAsync("run", null);
            else result = guest.call("run", null);
            assert.equal(result, 257 + 2 * increment);
            assert.equal(guest.read("unrelated"), Number(seed));
          } finally {
            guest.dispose();
          }
        }
        const checkpoint = await retained.exportCheckpoint();
        const failed = await retained.build({
          sources: {
            [entry]: program("missing_name"),
            [prelude]: method(increment),
          },
        });
        assert(!failed.success);
        assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
        const recovered = await retained.build({ sources });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, actual.bytes);
      }
    } finally {
      await retained.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
