import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
const source = `const pool: Array U32 = #[17,23]
const supplied = func (unused: U32): Array U32 => return #[1,2,3]
const through_pool = func (input: U32): Array U32 => return #[pool[0],input]
entry const fresh = func (input: U32): Array U32 => return do:
  let rows: ResizeArray U32 = #[4294967295,2147483648,7]
  let before = rows[0]
  rows[0] := input
  return #[before,rows[0],rows[1],rows[2]]
entry const floating = func (input: F32): Array F32 => return do:
  let rows: ResizeArray F32 = #[0.0,1.5,3.25]
  rows[0] := input
  return @storage.freeze rows
entry const flags = func (input: Bool): Array U32 => return do:
  let rows: ResizeArray Bool = #[true,false,true]
  rows[0] := input
  return #[if rows[0] then 1 else 0,if rows[1] then 1 else 0,if rows[2] then 1 else 0]
entry const units = func (): U32 => return do:
  let rows: ResizeArray Unit = #[(),(),()]
  return @storage.length rows
entry const empty = func (): U32 => return do:
  let rows: ResizeArray U32 = #[]
  return @storage.length rows
entry const grow = func (input: U32): Array U32 => return do:
  let rows: GrowArray U32 = #[11,13]
  @storage.push rows input
  return @storage.freeze rows
entry const destinations = func (input: U32): Array U32 => return do:
  let first = supplied input
  let second = through_pool input
  return #[first[0],second[0],second[1],pool[0]]
entry const raw = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[29,31]
  let before = rows[0]
  rows[0] := input
  return before
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped literal copies retain scalar bits independent mutation supplied destinations and reset (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-literal-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0] ??
        new URL("../../compiler/zig-out/bin/blotc", import.meta.url),
      entry,
      prelude: null,
      cacheDirectory: false,
      profileBackend: true,
      codegenTier,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      assert(
        ((result.stats.workCounters as Record<string, number>)
          .scoped_literal_data_bytes ?? 0) >= 60,
      );
      const guest = await instantiateGuest(result.bytes);
      try {
        assert.equal(guest.abi.version, 8);
        for (const input of [0, 7, 0xffffffff]) {
          assert.deepEqual(
            guest.call("fresh", input),
            new Uint32Array([0xffffffff, input, 0x80000000, 7]),
          );
          assert.deepEqual(
            guest.call("grow", input),
            new Uint32Array([11, 13, input]),
          );
          assert.deepEqual(
            guest.call("destinations", input),
            new Uint32Array([1, 17, input, 17]),
          );
        }
        for (const input of [0, -0, -7.5, NaN]) {
          assert.deepEqual(
            guest.call("floating", input),
            new Float32Array([input, 1.5, 3.25]),
          );
        }
        assert.deepEqual(guest.call("flags", true), new Uint32Array([1, 0, 1]));
        assert.deepEqual(
          guest.call("flags", false),
          new Uint32Array([0, 0, 1]),
        );
        assert.equal(guest.call("units", null), 3);
        assert.equal(guest.call("empty", null), 0);
      } finally {
        guest.dispose();
      }
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(result.bytes)).exports;
      for (const input of [7, 99, 0xffffffff]) {
        (raw["blot:reset"] as CallableFunction)(0);
        assert.equal((raw.raw as CallableFunction)(input), 29);
      }
      assert.throws(
        () => (raw["blot:memory"] as WebAssembly.Memory).grow(1),
        RangeError,
      );
      // The same retained client changes both literal bits and the named pool
      // extent, moving the final literal base after all owner regions.
      const edited = source.replace(
        "#[17,23]",
        "#[101,103,107,109,113,127,131]",
      )
        .replace("#[4294967295,2147483648,7]", "#[37,41,43,47,53]");
      const next = await compiler.build({ sources: { [entry]: edited } });
      assert(next.success, JSON.stringify(next));
      const changed = await instantiateGuest(next.bytes);
      try {
        assert.deepEqual(
          changed.call("fresh", 99),
          new Uint32Array([37, 99, 41, 43]),
        );
        assert.deepEqual(
          changed.call("destinations", 77),
          new Uint32Array([1, 101, 77, 101]),
        );
        assert.deepEqual(
          changed.call("fresh", 7),
          new Uint32Array([37, 7, 41, 43]),
        );
      } finally {
        changed.dispose();
      }
      const nextRaw =
        new WebAssembly.Instance(new WebAssembly.Module(next.bytes)).exports;
      (nextRaw["blot:reset"] as CallableFunction)(0);
      assert.equal((nextRaw.raw as CallableFunction)(123), 29);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
