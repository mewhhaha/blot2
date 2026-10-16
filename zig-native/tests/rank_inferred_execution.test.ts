import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = `const identity = fn value => value
const apply = fn callback => fn value => callback value
const forget = fn value => do:
  return fn (unit: Unit) => @u32.add 40 2
const annotated: forall [a] => a -> a = identity
const through: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = fn pair => apply (@product.get pair 0) (@product.get pair 1)
type Item = exists [a] => (a, a -> U32)
const make = fn (value: U32) => pack [U32] (value, identity) as Item
const read = fn (item: Item) => unpack item as [a] value in (@product.get value 1) (identity (@product.get value 0))
const discard = fn (item: Item) => unpack item as [a] value in forget (@product.get value 0)
`;
const consumer =
  `import {identity, apply, annotated, through, make, read, discard} from "./identity"
entry const forgotten = fn (value: U32) => (discard (make value)) ()
entry const whole = fn (value: U32) => annotated (apply identity value)
entry const fraction = fn (value: U32) => read (make value)
entry const host = fn (callback: U32 -> U32 ! {Foreign}) => through (callback, 42)
`;
async function run(bytes: Uint8Array<ArrayBuffer>) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(new WebAssembly.Module(bytes), {
      asynchronous,
    });
    try {
      let invoked = 0;
      let host: ReturnType<typeof guest.capability>;
      if (asynchronous) {
        host = guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: async (value) => {
            invoked++;
            await Promise.resolve();
            return value + 5;
          },
        });
      } else {
        host = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            invoked++;
            return value + 5;
          },
        });
      }
      const call = async (
        name: string,
        value: Parameters<typeof guest.call>[1],
      ) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      for (let value = 0; value < 96; value++) {
        assert.equal(await call("forgotten", value), 42);
        assert.equal(
          await call("whole", value),
          value,
        );
        assert.equal(
          await call("fraction", value),
          value,
        );
        assert.equal(
          await call("host", host),
          47,
        );
      }
      assert.equal(invoked, 96);
      const warmed = guest.memoryBytes();
      for (let value = 0; value < 96; value++) {
        assert.equal(
          await call("host", host),
          47,
        );
      }
      assert.equal(guest.memoryBytes(), warmed);
      assert.equal(invoked, 192);
    } finally {
      guest.dispose();
    }
  }
}
Deno.test("inferred helpers preserve exact scheme variables and opening captures beside universal row contracts across archives", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-rank-structural-" });
  const entry = `${directory}/main.blot`;
  const identity = `${directory}/identity.blot`;
  const dependencies = `${directory}/identity.blotdep`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(identity, producer);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const source = await createZigProjectCompiler(options);
      const archive = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      let checkpoint: Uint8Array<ArrayBuffer>;
      let expected: Uint8Array<ArrayBuffer>;
      try {
        const actual = await source.build();
        const frozen = await archive.build();
        assert(actual.success, JSON.stringify(actual));
        assert(frozen.success, JSON.stringify(frozen));
        assert(frozen.stats.cachedModules > 0);
        assert.deepEqual(frozen.bytes, actual.bytes);
        await run(actual.bytes);
        await run(frozen.bytes);
        expected = actual.bytes;
        checkpoint = await archive.exportCheckpoint();
        for (
          const failed of [
            consumer.replace("read (make value)", "read value"),
            consumer.replace(
              "through (callback, 42)",
              "through (42, callback)",
            ),
          ]
        ) {
          const live = await source.build({ sources: { [entry]: failed } });
          const frozenFailure = await archive.build({
            sources: { [entry]: failed },
          });
          assert(!live.success && !frozenFailure.success);
          assert.deepEqual(frozenFailure.diagnostics, live.diagnostics);
          assert.deepEqual(await archive.exportCheckpoint(), checkpoint);
        }
        const recovered = await archive.build({
          sources: { [entry]: consumer },
        });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, expected);
      } finally {
        await source.dispose();
        await archive.dispose();
      }
      await run(expected!);
      const restored = await createZigProjectCompiler({
        ...options,
        dependencies,
        checkpoint: checkpoint!,
      });
      try {
        const replayed = await restored.build();
        assert(replayed.success, JSON.stringify(replayed));
        assert.deepEqual(replayed.bytes, expected!);
        assert(
          (replayed.stats.runtimeOptimization as Record<string, number>)
            .reused >
            0,
          JSON.stringify(replayed.stats.runtimeOptimization),
        );
        await run(replayed.bytes);
      } finally {
        await restored.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
