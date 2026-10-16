import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer =
  `const first: forall [a, b] => (a, b) -> a = fn value => @product.get value 0
const twice: forall [a] => a -> (a, a) = fn value => (value, value)
const twice_alias: forall [a] => a -> (a, a) = twice
const record: forall [a] => a -> {value: a} = fn value => {value: value}
const head: forall [a] => Array a -> a = fn values => @array.get values 0
const keep: forall [a] => a -> (forall [b] => b -> a) = fn first => fn second => first
const pass: (forall [a] => (Bool, a) -> U32) -> U32 = fn recurse => recurse (#False, 42)
const recursive: forall [a] => (Bool, a) -> U32 = fn pair => if @product.get pair 0 then pass recursive else 0
const apply_twice: (forall [a, b] => (a, b) -> a) -> U32 -> (U32, F32) = fn first => fn value => (first (value, #True), first (@u32.to_f32 value, value))
`;
const consumer =
  `import {first, twice_alias, record, head, keep, recursive, apply_twice} from "./identity"
entry const recursive_call = fn (value: U32) => recursive (#True, value)
entry const whole = fn (value: U32) => @product.get (apply_twice first value) 0
entry const fraction = fn (value: U32) => @product.get (apply_twice first value) 1
entry const duplicate = fn (value: F32) => @product.get (twice_alias value) 1
entry const stored = fn (value: U32) => (record value).value
entry const array_head = fn (value: U32) => head #[value, 42]
entry const held = fn (value: U32) => (keep value) #True
`;
async function run(bytes: Uint8Array<ArrayBuffer>) {
  const guest = await instantiateGuest(new WebAssembly.Module(bytes));
  try {
    for (let value = 0; value < 96; value++) {
      assert.equal(guest.call("whole", value), value);
      assert.equal(guest.call("recursive_call", value), 0);
      assert.equal(guest.call("fraction", value), value);
      assert.equal(guest.call("duplicate", value + 0.25), value + 0.25);
      assert.equal(guest.call("stored", value), value);
      assert.equal(guest.call("held", value), value);
      assert.equal(guest.call("array_head", value), value);
    }
    const warmed = guest.memoryBytes();
    for (let value = 0; value < 96; value++) {
      assert.equal(guest.call("held", value), value);
    }
    assert.equal(guest.memoryBytes(), warmed);
  } finally {
    guest.dispose();
  }
}
Deno.test("parametric rank templates execute structural results nested captures and independent dynamic instantiations", async () => {
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
            consumer.replace(
              "apply_twice first value",
              "apply_twice (fn item => 42) value",
            ),
            consumer.replace(
              "apply_twice first value",
              "apply_twice (fn item => @product.get item 1) value",
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
