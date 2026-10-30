import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer =
  `type Render a is contract = { type Output, const get: a -> (Render.Output a), const show: a -> (Render.Output a) -> U32 }
impl Number : Render U32 = { type Output = U32, const get = func value => return value, const show = func owner => return func value => return value }
impl Flag : Render Bool = { type Output = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
type Item = exists [a] where { Render a } => a
const make: Bool -> Item = func flag => return if flag then pack [U32] 42 as Item else pack [Bool] true as Item
const reseal = func (item: Item) => return unpack item as [a] value in pack [a] value as Item
const seal: forall [a] where { Render a } => a -> Item = func value => return pack [a] value as Item
const read = func (item: Item) => return unpack item as [a] value in Render.show value (Render.get value)
const both = func (left: Item) => return func (right: Item) => return unpack left as [a] x in unpack right as [b] y in @u32.add (Render.show x (Render.get x)) (Render.show y (Render.get y))
`;
const consumer = `import {make, read, both, reseal, seal} from "./identity"
entry const answer = func (flag: Bool) => return read (reseal (reseal (make flag)))
entry const combined = func (flag: Bool) => return both (reseal (make flag)) (seal true)
entry const collection = func (flag: Bool) => return do:
  let items = #[reseal (make flag), seal true]
  break @u32.add (read (@array.get items 0)) (read (@array.get items 1))
`;
async function run(bytes: Uint8Array<ArrayBuffer>, number = 42) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(new WebAssembly.Module(bytes), {
      asynchronous,
    });
    try {
      const call = async (name: string, value: boolean) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      for (let repetition = 0; repetition < 96; repetition++) {
        const flag = repetition % 2 === 0;
        let expected = 7;
        if (flag) expected = number;
        assert.equal(await call("answer", flag), expected);
        assert.equal(await call("combined", flag), expected + 7);
        assert.equal(await call("collection", flag), expected + 7);
      }
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
Deno.test("associated dictionary results retain exact carriers across archives restart and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-dictionary-resealing-",
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
            consumer.replace("read (reseal (reseal (make flag)))", "read 42"),
            consumer.replace(
              "read (reseal (reseal (make flag)))",
              "both (make flag) true",
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
        const edited = await source.build({
          sources: {
            [entry]: consumer,
            [identity]: producer.replace("42 as Item", "43 as Item"),
          },
        });
        assert(edited.success, JSON.stringify(edited));
        await run(edited.bytes, 43);
        const reverted = await source.build({
          sources: { [entry]: consumer, [identity]: producer },
        });
        assert(reverted.success, JSON.stringify(reverted));
        assert.deepEqual(reverted.bytes, expected);
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
