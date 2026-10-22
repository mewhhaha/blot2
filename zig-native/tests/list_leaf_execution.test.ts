import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `entry const carried = fn (count: U32) => do:
  let values = @list.generate count (fn index => #[index])
  let kept = #[42]
  for row in values:
    values := []
    kept := row
    let pressure = @array.fill 8192 count
    if pressure[0] != count:
      @panic "pressure changed"
  break kept
entry const trace = fn (send: U32 -> U32 ! {Foreign}) => do:
  let values = [#[41], #[42]]
  let sum = 0
  for row in values:
    values := []
    use reply <- send row[0]
    sum := self + reply
  break sum
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`leaf List owners preserve carried children under pressure and suspension (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      codegenTier,
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      cacheDirectory: false,
    });
    try {
      const first = await compiler.build({ sources: { [entry]: source } });
      assert(first.success, JSON.stringify(first));
      const retained = await compiler.build({ sources: { [entry]: source } });
      assert(retained.success, JSON.stringify(retained));
      assert.deepEqual(retained.bytes, first.bytes);
      await Deno.writeTextFile(entry, source);
      const bundle = `${directory}/deps.blotdep`;
      const packed = await new Deno.Command(executable, {
        args: [
          "dependencies",
          entry,
          bundle,
          "--prelude",
          new URL("../../std/prelude.blot", import.meta.url).pathname,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      const compiled = await createZigProjectCompiler({
        executable,
        entry,
        codegenTier,
        dependencies: bundle,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
      });
      try {
        const fromArchive = await compiled.build();
        assert(fromArchive.success, JSON.stringify(fromArchive));
        assert(fromArchive.stats.cachedModules > 0);
        assert.deepEqual(fromArchive.bytes, first.bytes);
        const checkpoint = await compiled.exportCheckpoint();
        const restarted = await createZigProjectCompiler({
          executable,
          entry,
          codegenTier,
          dependencies: bundle,
          prelude: new URL("../../std/prelude.blot", import.meta.url),
          cacheDirectory: false,
          checkpoint,
        });
        try {
          const restored = await restarted.build();
          assert(restored.success, JSON.stringify(restored));
          assert.deepEqual(restored.bytes, first.bytes);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await compiled.dispose();
      }
      assert.deepEqual(
        [
          ...new Uint8Array(
            WebAssembly.Module.customSections(
              new WebAssembly.Module(first.bytes),
              "blot:ownership",
            )[0],
          ),
        ],
        [2, 2, 0],
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(first.bytes, { asynchronous });
        try {
          async function invoke(name: string, value: number) {
            if (asynchronous) return await guest.callAsync(name, value);
            return guest.call(name, value);
          }
          for (const count of [0, 1, 2, 64, 241, 242, 513]) {
            const result = await invoke("carried", count);
            let expected = 42;
            if (count > 0) expected = count - 1;
            assert.deepEqual(result, Uint32Array.of(expected));
          }
          const events: number[] = [];
          const definition = {
            parameter: "U32",
            result: "U32",
            call: (value: number) => {
              events.push(value);
              return value;
            },
          } as const;
          if (asynchronous) {
            const send = guest.capabilityAsync({
              ...definition,
              call: async (value) => definition.call(value),
            });
            assert.equal(await guest.callAsync("trace", send), 83);
          } else {
            const send = guest.capability(definition);
            assert.equal(guest.call("trace", send), 83);
          }
          assert.deepEqual(events, [41, 42]);
          let warmBytes = 0;
          for (let iteration = 0; iteration < 16; iteration++) {
            assert.deepEqual(await invoke("carried", 513), Uint32Array.of(512));
            if (iteration === 3) warmBytes = guest.memoryBytes();
            if (iteration > 3) assert.equal(guest.memoryBytes(), warmBytes);
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
