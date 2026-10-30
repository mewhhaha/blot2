import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
let cost = "1";
for (let index = 0; index < 80; index++) cost = `@u32.add 1 (${cost})`;
const program = (seed: number) =>
  `const seed = ${seed}
const callback = do:
  let cost = ${cost}
  break func (value: U32) => return @u32.add value cost
const cursor = do:
  let cost = ${cost}
  break @array.cursor #[cost, 2]
entry const run = func (value: U32) => return @u32.add (callback value) (@cursor.value cursor)
entry const unrelated = seed
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`standalone constant callable and cursor replay owns fuel data and recovery (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-constant-callable-",
    });
    const entry = `${directory}/main.blot`;
    await Deno.writeTextFile(entry, program(2));
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
      codegenTier,
    };
    const retained = await createZigProjectCompiler(options);
    try {
      for (const [index, seed] of [2, 3, 2].entries()) {
        const sources = { [entry]: program(seed) };
        const result = await retained.build({ sources });
        assert(result.success, JSON.stringify(result));
        if (index !== 0) {
          const receipts = result.stats.constantReceipts as {
            reused: number;
            retries: number;
            source_steps_replayed: number;
          };
          assert.equal(receipts.reused, 2);
          assert.equal(receipts.retries, 0);
          assert(receipts.source_steps_replayed > 0);
        }
        const fresh = await createZigProjectCompiler(options);
        try {
          const expected = await fresh.build({ sources });
          assert(expected.success, JSON.stringify(expected));
          assert.deepEqual(result.bytes, expected.bytes);
          assert.equal(
            result.stats.nativeWorkSteps,
            expected.stats.nativeWorkSteps,
          );
        } finally {
          await fresh.close();
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            assert.equal(guest.read("unrelated"), seed);
            let answer;
            if (asynchronous) answer = await guest.callAsync("run", 40);
            else answer = guest.call("run", 40);
            assert.equal(answer, 202);
          } finally {
            guest.dispose();
          }
        }
        const checkpoint = await retained.exportCheckpoint();
        const failed = await retained.build({
          sources: {
            [entry]: program(seed).replace(
              "let cost =",
              "let cost = @u32.div 1 0 //",
            ),
          },
        });
        assert(!failed.success);
        assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
        const recovered = await retained.build({ sources });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, result.bytes);
      }
    } finally {
      await retained.close();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
