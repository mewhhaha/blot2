import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const source = `
type Box f is data = #Box f
type Factory a is data = #Factory a
const Factory.boxed = fn (factory: Factory a) => #Box (fn value => {item: value, factory: factory})
entry const integer = fn (seed: U32) => do:
  let factory = #Factory seed
  let stored = factory.boxed
  let #Box mapper = stored
  break @u32.add (mapper seed).item 1
entry const floating = fn (seed: F32) => do:
  let factory = #Factory seed
  let stored = factory.boxed
  let #Box mapper = stored
  break @f32.add (mapper seed).item 0.5
entry const reference = fn (seed: Array U32) => do:
  let factory = #Factory seed
  let stored = factory.boxed
  let #Box mapper = stored
  let kept = (mapper seed).item
  let pressure = @array.fill 8192 42
  break if @u32.eq pressure[0] 42 then kept else @panic "pressure changed"
entry const zero_width = fn (seed: U32) => do:
  let factory = #Factory seed
  let stored = factory.boxed
  let #Box mapper = stored
  break (mapper ()).item
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`single-use selected member storage retains checked scalar and reference fields (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const fresh = await compiler.build({ sources: { [entry]: source } });
      assert(fresh.success, JSON.stringify(fresh));
      const retained = await compiler.build({ sources: { [entry]: source } });
      assert(retained.success, JSON.stringify(retained));
      assert.deepEqual(retained.bytes, fresh.bytes);
      const module = new WebAssembly.Module(fresh.bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const guest = await instantiateGuest(module);
      try {
        assert.equal(guest.call("integer", 40), 41);
        assert.equal(guest.call("floating", 1.25), 1.75);
        assert.equal(guest.call("zero_width", 9), null);
        const values = Uint32Array.of(41, 8192);
        assert.deepEqual(guest.call("reference", values), values);
        const warm = guest.memoryBytes();
        for (let repeat = 0; repeat < 12; repeat++) {
          assert.deepEqual(guest.call("reference", values), values);
        }
        assert.equal(guest.memoryBytes(), warm);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
