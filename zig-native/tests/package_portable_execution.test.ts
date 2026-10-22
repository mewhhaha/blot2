import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = `type Item = exists [a, b] => (a, a -> b, b -> U32)
const make: U32 -> Item = fn value => pack [U32, F32] (value, fn number => @u32.to_f32 number, fn number => @f32.to_u32 number) as Item
const choose: Bool -> Item = fn flag => if flag then pack [U32, F32] (42, fn number => @u32.to_f32 number, fn number => @f32.to_u32 number) as Item else pack [Bool, U32] (flag, fn boolean => if boolean then 9 else 7, fn number => number) as Item
const captured: U32 -> Item = fn value => pack [U32, F32] (value, fn number => @u32.to_f32 number, fn number => @u32.add (@f32.to_u32 number) value) as Item
const read: Item -> U32 = fn item => unpack item as [a, b] body in (@product.get body 2) ((@product.get body 1) (@product.get body 0))
`;
const consumer = `import {make, read, captured, choose} from "./identity"
entry const whole: U32 -> U32 = fn value => read (make value)
entry const selected: Bool -> U32 = fn flag => do:
  let items = (make 42, choose flag)
  break @u32.add (read (@product.get items 0)) (read (@product.get items 1))
entry const doubled: U32 -> U32 = fn value => read (captured value)
entry const fraction: U32 -> U32 = fn value => read (make (@u32.add value 1))
`;

async function run(bytes: Uint8Array<ArrayBuffer>) {
  const guest = await instantiateGuest(bytes);
  try {
    assert.equal(guest.call("selected", true), 84);
    assert.equal(guest.call("selected", false), 49);
    for (const value of [0, 13, 42, 1024]) {
      assert.equal(guest.call("whole", value), value);
      assert.equal(guest.call("doubled", value), value * 2);
      assert.equal(guest.call("fraction", value), value + 1);
    }
    for (let index = 0; index < 16; index++) guest.call("doubled", 42);
    const warmed = guest.memoryBytes();
    for (let index = 0; index < 128; index++) {
      assert.equal(guest.call("doubled", 21), 42);
      let expected = 49;
      if (index % 2 === 0) expected = 84;
      assert.equal(guest.call("selected", index % 2 === 0), expected);
    }
    assert.equal(guest.memoryBytes(), warmed);
    const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
    const enter = raw["blot:ownership_enter"] as CallableFunction;
    const leave = raw["blot:ownership_leave"] as CallableFunction;
    for (let index = 0; index < 16; index++) {
      enter();
      assert.equal((raw.doubled as CallableFunction)(21), 42);
      leave(0);
      assert.equal(
        Number((raw["blot:rc_roots"] as WebAssembly.Global).value),
        0,
      );
      assert.equal(
        Number((raw["blot:rc_leases"] as WebAssembly.Global).value),
        0,
      );
    }
  } finally {
    guest.dispose();
  }
}

Deno.test("portable two binder packages execute source archive checkpoint restart and failed edit recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-package-portable-",
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
            consumer.replace(
              "read (make value)",
              "unpack (make value) as [a, b] body in @product.get body 0",
            ),
            consumer.replace(
              "read (make value)",
              "unpack (make value) as [a] body in 42",
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
