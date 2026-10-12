import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

const definitions = `
type Box f is data = #Box f
const box = fn value => #Box value
const get = fn (#Box mapper) => mapper
`;

Deno.test("single-use local creators preserve selected scalar and reference fields", async () => {
  for (
    const [type, read] of [
      ["U32", "@u32.add (mapper seed).item 1"],
      ["F32", "@f32.add (mapper seed).item 1.0"],
      ["Array U32", "@array.length (mapper seed).item"],
    ]
  ) {
    await compileAndRun(
      definitions + `
entry const run = fn (seed: ${type}) => do:
  let stored = box (fn value => {item: value})
  let #Box mapper = stored
  return ${read}
`,
      (guest, bytes) => {
        const module = new WebAssembly.Module(bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        let argument: number | Uint32Array = 8192;
        let expected = 8193;
        if (type === "F32") {
          argument = 41.5;
          expected = 42.5;
        }
        if (type === "Array U32") {
          argument = Uint32Array.of(41, 8192);
          expected = 2;
        }
        assert.equal(guest.call("run", argument), expected);
      },
    );
  }
});

Deno.test("multiple generic local instances retain independent checked views", async () => {
  await compileAndRun(
    definitions + `
entry const run = fn (seed: U32) => do:
  let stored = box (fn value => {item: value})
  let scalar = (get stored seed).item
  let reference = (get stored #[seed, 8192]).item
  return @u32.add scalar reference[0]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const mode = new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      );
      assert.equal(
        mode[0],
        1,
        "multiple physical instances must decline this proof",
      );
      assert.equal(guest.call("run", 65536), 131072);
    },
  );
});

Deno.test("captured generic local storage keeps its conservative representation", async () => {
  await compileAndRun(
    definitions + `
entry const run = fn (seed: U32) => do:
  let stored = box (fn value => {item: value})
  let read = fn (value: U32) => (get stored value).item
  return read seed
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const mode = new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      );
      assert.equal(mode[0], 1, "a captured producer must decline this proof");
      assert.equal(guest.call("run", 8192), 8192);
    },
  );
});
