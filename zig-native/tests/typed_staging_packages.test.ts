import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out-dev/bin/blotc", import.meta.url).pathname;
const library = (value: number) =>
  `type Item = exists [a] => (a, a -> U32)
const read: Item -> U32 = fn item => unpack item as [a] value in (@product.get value 1) (@product.get value 0)
const generated = @code.quote (fn (flag: Bool) -> Item ! {} => if flag then pack [U32] (${value}, fn number => number) as Item else pack [Bool] (flag, fn truth => if truth then 9 else 7) as Item)
const sealed = @code.quote (pack [U32] (${value}, fn number => number) as Item)
const shape = (@code.describe sealed).result
`;
const consumer = `import {generated, read, shape} from "./producer"
const same = @descriptor.same shape shape
entry const answer = fn (flag: Bool) => read ((@code.emit generated) flag)
`;
async function observe(bytes: Uint8Array<ArrayBuffer>, expected: number) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      const invoke = async (flag: boolean) => {
        if (asynchronous) return await guest.callAsync("answer", flag);
        return guest.call("answer", flag);
      };
      assert.equal(await invoke(true), expected);
      assert.equal(await invoke(false), 7);
      for (let index = 0; index < 16; index++) await invoke(index % 2 === 0);
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 128; index++) {
        let value = 7;
        if (index % 2 === 0) value = expected;
        assert.equal(await invoke(index % 2 === 0), value);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}
Deno.test("quoted heterogeneous sealed packages preserve descriptor shape stored operations hygiene and restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-staged-packages-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  const archive = `${directory}/producer.blotdep`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const value of [42, 43, 42]) {
          const sources = { [entry]: consumer, [producer]: library(value) };
          await Deno.writeTextFile(entry, consumer);
          await Deno.writeTextFile(producer, library(value));
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(expected.success, JSON.stringify(expected));
            const actual = await retained.build({ sources });
            assert(actual.success, JSON.stringify(actual));
            assert.deepEqual(actual.bytes, expected.bytes);
            await observe(actual.bytes, value);
            const failed = await retained.build({
              sources: {
                ...sources,
                [entry]: consumer +
                  "const forbidden = @descriptor.fields shape\n",
              },
            });
            assert(!failed.success, JSON.stringify(failed));
            await observe(actual.bytes, value);
            const recovered = await retained.build({ sources });
            assert(recovered.success, JSON.stringify(recovered));
            assert.deepEqual(recovered.bytes, expected.bytes);
            assert.equal(recovered.stats.nativeWorkSteps, 0);
            const checkpoint = await retained.exportCheckpoint();
            const packed = await new Deno.Command(executable, {
              args: ["dependencies", entry, archive, "--prelude", "none"],
              stdout: "piped",
              stderr: "piped",
            }).output();
            assert(
              packed.success,
              new TextDecoder().decode(packed.stdout) +
                new TextDecoder().decode(packed.stderr),
            );
            for (
              const replay of [{ ...options, checkpoint }, {
                ...options,
                dependencies: archive,
              }]
            ) {
              const restarted = await createZigProjectCompiler(replay);
              try {
                const resumed = await restarted.build({ sources });
                assert(resumed.success, JSON.stringify(resumed));
                if ("dependencies" in replay) {
                  assert(
                    resumed.stats.cachedModules > 0,
                    JSON.stringify(resumed.stats),
                  );
                }
                assert.deepEqual(resumed.bytes, expected.bytes);
                await observe(resumed.bytes, value);
              } finally {
                await restarted.dispose();
              }
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
