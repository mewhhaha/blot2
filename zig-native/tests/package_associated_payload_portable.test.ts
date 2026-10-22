import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer =
  `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => @u32.add owner value }
impl Flag : Source Bool = { type Item = F32, const get = fn value => if value then 7.5 else 9.5, const show = fn owner => fn value => @u32.add (@f32.to_u32 value) (if owner then 0 else 2) }
type Item = exists [a] where { Source a } => (a, Source.Item a)
const make: Bool -> Item = fn flag => if flag then pack [U32] (20,22) as Item else pack [Bool] (#True,7.5) as Item
const reseal = fn (item: Item) => unpack item as [a] value in pack [a] value as Item
const read = fn (item: Item) => unpack item as [a] value in Source.show (@product.get value 0) (@product.get value 1)
const both = fn (left: Item) => fn (right: Item) => @u32.add (read left) (read right)
`;
const consumer = `import {make, read, both} from "./identity"
entry const cache_control = fn (value: U32) => @u32.add value 1
entry const answer = fn (flag: Bool) => read (make flag)
entry const combined = fn (flag: Bool) => both (make flag) (make #False)
entry const collection = fn (flag: Bool) => do:
  let items = #[make flag, make #False]
  break @u32.add (read (@array.get items 0)) (read (@array.get items 1))
`;
async function run(bytes: Uint8Array<ArrayBuffer>) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(new WebAssembly.Module(bytes), {
      asynchronous,
    });
    try {
      const call = async (name: string, value: boolean | number) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      for (let repetition = 0; repetition < 96; repetition++) {
        const flag = repetition % 2 === 0;
        let expected = 7;
        if (flag) expected = 42;
        assert.equal(await call("answer", flag), expected);
        assert.equal(await call("combined", flag), expected + 7);
        assert.equal(await call("collection", flag), expected + 7);
      }
      const control = await call("cache_control", 41);
      assert.equal(control, 42);
      const warmed = guest.memoryBytes();
      for (let repetition = 0; repetition < 96; repetition++) {
        assert.equal(await call("collection", false), 14);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
  }
}
Deno.test("associated package payloads retain exact equations across source archives restart and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-associated-payload-",
  });
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
            consumer.replace("read (make flag)", "read 42"),
            consumer.replace("read (make flag)", "both (make flag) #True"),
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
        // Associated package graphs currently rebuild their runtime artifacts.
        // This law proves portable bytes and execution, not artifact reuse.
        await run(replayed.bytes);
      } finally {
        await restored.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
