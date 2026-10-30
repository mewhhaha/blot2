import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = func value => return value }
impl Flag : Render Bool = { const show = func value => return if value then 7 else @panic "dictionary trap" }
const render: forall [a] where { Render a } => a -> U32 = func value => return Render.show value
const forward: forall [a] where { Render a } => a -> U32 = func value => return render value
const sum: forall [a] where { Render a } => a -> a -> U32 = func left => return func right => return @u32.add (Render.show left) (Render.show right)
`;
const consumer = `import {Render, render, forward, sum} from "./render"
const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
const choose: Bool -> (forall [a] where { Render a } => a -> U32) = func flag => return if flag then render else forward
const invoke: (forall [a] where { Render a } => a -> U32) -> Bool -> U32 = func callback => return func flag => return callback flag
const partial: (forall [a] where { Render a } => a -> a -> U32) -> U32 = func callback => return callback 20 22
entry const answer = func (flag: Bool) => return both (choose flag)
entry const curried: Unit -> U32 = func () => return partial sum
entry const trapped = func (flag: Bool) => return invoke forward flag
entry const captured = func (offset: U32) => return both (func value => return @u32.add offset (Render.show value))
entry const snapshot = func (value: U32) => return #[value]
`;
async function execute(bytes: Uint8Array<ArrayBuffer>) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      const call = async (
        name: string,
        value: Parameters<typeof guest.call>[1],
      ) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      for (let i = 0; i < 48; i++) {
        assert.equal(await call("answer", i % 2 === 0), 49);
        assert.equal(await call("curried", null), 42);
        assert.equal(await call("captured", 10), 69);
        assert.equal(await call("trapped", true), 7);
      }
      await assert.rejects(call("trapped", false));
      assert.equal(await call("trapped", true), 7);
      const warmed = guest.memoryBytes();
      for (let i = 0; i < 48; i++) {
        assert.equal(await call("answer", i % 2 === 0), 49);
      }
      assert.equal(guest.memoryBytes(), warmed);
    } finally {
      guest.dispose();
    }
    const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    const invoke = raw.answer as CallableFunction;
    const counter = (name: string) =>
      Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
    for (let i = 0; i < 48; i++) {
      enter();
      assert.equal(invoke(i % 2), 49);
      leave(0);
      assert.equal(counter("roots"), 0);
      assert.equal(counter("leases"), 0);
    }
  }
}
Deno.test("universal dictionaries preserve exact evidence across dependency archives checkpoints failure recovery and warmed ownership", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-universal-dictionary-",
  });
  const entry = `${directory}/main.blot`,
    library = `${directory}/render.blot`,
    dependencies = `${directory}/render.blotdep`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(library, producer);
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
      const source = await createZigProjectCompiler(options),
        archive = await createZigProjectCompiler({ ...options, dependencies });
      let checkpoint: Uint8Array<ArrayBuffer>,
        expected: Uint8Array<ArrayBuffer>;
      try {
        const live = await source.build(), frozen = await archive.build();
        assert(live.success, JSON.stringify(live));
        assert(frozen.success, JSON.stringify(frozen));
        assert(frozen.stats.cachedModules > 0);
        assert.deepEqual(frozen.bytes, live.bytes);
        await execute(live.bytes);
        await execute(frozen.bytes);
        expected = live.bytes;
        checkpoint = await archive.exportCheckpoint();
        const failed = consumer.replace("partial sum", "partial render");
        const liveFailure = await source.build({
            sources: { [entry]: failed },
          }),
          frozenFailure = await archive.build({ sources: { [entry]: failed } });
        assert(!liveFailure.success && !frozenFailure.success);
        assert.deepEqual(frozenFailure.diagnostics, liveFailure.diagnostics);
        assert.deepEqual(await archive.exportCheckpoint(), checkpoint);
        const recovered = await archive.build({
          sources: { [entry]: consumer },
        });
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, expected);
      } finally {
        await source.dispose();
        await archive.dispose();
      }
      const restored = await createZigProjectCompiler({
        ...options,
        dependencies,
        checkpoint: checkpoint!,
      });
      try {
        const replayed = await restored.build();
        assert(replayed.success, JSON.stringify(replayed));
        assert.deepEqual(replayed.bytes, expected!);
        await execute(replayed.bytes);
      } finally {
        await restored.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
