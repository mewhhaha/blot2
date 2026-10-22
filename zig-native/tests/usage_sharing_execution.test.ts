import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = `
const share: unique (Array U32) -> shared (Array U32) = fn owner => @usage.share owner
const size: shared (Array U32) -> U32 = fn values => @u32.add (@usage.length values) (@usage.length values)
const integer = fn (owner: unique U32) => do:
  let shared = @usage.share owner
  break @u32.add (@usage.read shared) (@usage.read shared)
const float = fn (owner: unique F32) => do:
  let shared = @usage.share owner
  break @f32.add (@usage.read shared) (@usage.read shared)
const list = fn (owner: unique (List U32)) => do:
  let shared = @usage.share owner
  break @u32.add (@usage.length shared) (@usage.length shared)
`;
const consumer = `
import {share, size, integer, float, list} from "./share"
entry const length = fn (value: U32) => size (share #[value, @u32.add value 1])
entry const scalar = fn (value: U32) => integer 21
entry const floating = fn (value: F32) => float 1.5
entry const listed = fn (value: U32) => list [value, @u32.add value 1, @u32.add value 2]
entry const surviving = fn (value: U32) => do:
  let values = share #[value, @u32.add value 1]
  break #[value, @u32.add value (@u32.sub (@usage.length values) 1)]
entry const captured = fn (value: U32) => do:
  let owner: unique (Array U32) = #[value, @u32.add value 1]
  let transfer: once (Unit -> shared (Array U32)) = fn () => @usage.share owner
  let shared = transfer ()
  break size shared
`;

async function execute(bytes: Uint8Array<ArrayBuffer>) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      const invoke = async (name: string, value: number) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      assert.equal(await invoke("scalar", 21), 42);
      assert.equal(await invoke("floating", 1.5), 3);
      assert.equal(await invoke("listed", 41), 6);
      assert.equal(await invoke("captured", 41), 4);
      const saved = await invoke("surviving", 41);
      assert(saved instanceof Uint32Array);
      assert.deepEqual([...saved], [41, 42]);
      for (let index = 0; index < 16; index++) await invoke("length", index);
      const warmed = guest.memoryBytes();
      for (let index = 0; index < 128; index++) {
        assert.equal(await invoke("length", index), 4);
        assert.equal(await invoke("captured", index), 4);
        assert.deepEqual(
          await invoke("surviving", index),
          new Uint32Array([index, index + 1]),
        );
        assert.deepEqual([...saved], [41, 42]);
        assert.equal(guest.memoryBytes(), warmed);
      }
    } finally {
      guest.dispose();
    }
  }
  const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
  for (let index = 0; index < 128; index++) {
    (raw["blot:ownership_enter"] as CallableFunction)();
    assert.equal((raw.captured as CallableFunction)(index), 4);
    (raw["blot:ownership_leave"] as CallableFunction)(0);
    (raw["blot:reset"] as CallableFunction)(0);
    for (const name of ["roots", "leases"]) {
      assert.equal(
        Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value),
        0,
      );
    }
  }
}

Deno.test("explicit sharing preserves ownership across imports archive retained restart and once captures", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-usage-share-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/share.blot`;
  const dependencies = `${directory}/share.blotdep`;
  try {
    await Deno.writeTextFile(entry, consumer);
    await Deno.writeTextFile(dependency, producer);
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
      const compiler = await createZigProjectCompiler(options);
      const archive = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      try {
        const first = await compiler.build();
        const imported = await archive.build();
        assert(first.success, JSON.stringify(first));
        assert(imported.success, JSON.stringify(imported));
        assert(imported.stats.cachedModules > 0);
        assert.deepEqual(imported.bytes, first.bytes);
        await execute(first.bytes);
        await execute(imported.bytes);
        const checkpoint = await compiler.exportCheckpoint();
        const bad = await compiler.build({
          sources: {
            [entry]: consumer,
            [dependency]: producer.replace(
              "fn owner => @usage.share owner",
              "fn owner => (@usage.share owner, owner)",
            ),
          },
        });
        assert(!bad.success);
        assert(
          bad.diagnostics.some((diagnostic) =>
            diagnostic.code === "use_after_move" ||
            diagnostic.code === "type_mismatch"
          ),
          JSON.stringify(bad),
        );
        const recovered = await compiler.build();
        assert(recovered.success, JSON.stringify(recovered));
        assert.deepEqual(recovered.bytes, first.bytes);
        const restarted = await createZigProjectCompiler({
          ...options,
          checkpoint,
        });
        try {
          const resumed = await restarted.build();
          assert(resumed.success, JSON.stringify(resumed));
          assert.deepEqual(resumed.bytes, first.bytes);
          await execute(resumed.bytes);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await compiler.dispose();
        await archive.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
