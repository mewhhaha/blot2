import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("scalar List constructors snapshots and edits skip cycle scans", async () => {
  await compileAndRun(
    `
entry const run = func (count: U32) => return do:
  let values = @list.fill count 42
  let original = values
  values := [1, 2, 3, ...self]
  let joined_array = @array.from_list values
  let original_array = @array.from_list original
  break joined_array[3] + original_array[0]
entry const memory = func () : Array U32 => return #[]
`,
    (_, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      assert.equal((raw.run as CallableFunction)(8192), 84);
      assert.equal((raw["blot:cycle_passes"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:cycle_edges"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
      (raw["blot:ownership_leave"] as CallableFunction)(2);
    },
  );
});

Deno.test("zero-child admitted source keeps cycle work absent and validates counter metadata", async () => {
  await compileAndRun(
    `
entry const run = func (count: U32) => return do:
  let values = @array.fill count 42
  let original = values
  values[0] := 7
  break original[0] + values[0]
`,
    async (_, bytes) => {
      const module = new WebAssembly.Module(bytes);
      assert.deepEqual([
        ...new Uint8Array(
          WebAssembly.Module.customSections(module, "blot:ownership")[0],
        ),
      ], [2, 2, 0]);
      const raw = new WebAssembly.Instance(module).exports;
      for (let i = 0; i < 100; i++) {
        assert.equal(
          (raw.run as CallableFunction)(8192),
          49,
        );
      }
      assert.equal((raw["blot:cycle_passes"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:cycle_edges"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_roots"] as WebAssembly.Global).value, 0);
      assert.equal((raw["blot:rc_leases"] as WebAssembly.Global).value, 0);
      (raw["blot:ownership_leave"] as CallableFunction)(2);
      const name = new TextEncoder().encode("blot:cycles");
      const invalid = bytes.slice();
      const position = invalid.findIndex((_, i) =>
        name.every((byte, j) => invalid[i + j] === byte)
      );
      assert(position >= 0);
      invalid[position + name.length] = 2;
      await assert.rejects(
        () => instantiateGuest(invalid),
        /Invalid cycle section/,
      );
      const duplicate = new Uint8Array(bytes.length + name.length + 5);
      duplicate.set(bytes);
      duplicate.set(
        [0, name.length + 3, name.length, ...name, 1, 1],
        bytes.length,
      );
      await assert.rejects(
        () => instantiateGuest(duplicate),
        /Duplicate cycle section/,
      );
    },
  );
});
