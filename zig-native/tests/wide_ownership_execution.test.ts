import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const fields = Array.from({ length: 40 }, (_, word) => {
  if (word === 33) return `f033: #[value + 33]`;
  if (word === 34) return `f034: -0.0`;
  return `f${String(word).padStart(3, "0")}: value + ${word}`;
}).join(", ");
const model = `const make = fn (value: U32) => {${fields}}
const run = fn (value: U32) => do:
  let object = make value
  let before = object
  let read = fn () => before.f033[0] + before.f032
  object.f033 := #[self[0] + 1]
  object.f032 := self + 2
  for index in 0..32:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      return #[0]
  return #[before.f033[0], object.f033[0], before.f032, object.f032, read ()]
const floating = fn (value: U32) => (make value).f034
`;
Deno.test("wide ownership preserves snapshots float bits and static shape relocation through retained edits in both tiers", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`,
    producer = `${directory}/model.blot`,
    prefix = `${directory}/prefix.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (const count of [3, 65, 3]) {
          const sources = {
            [producer]: model,
            [prefix]: `const values = #[${
              Array.from({ length: count }, (_, i) => i).join(", ")
            }]`,
            [entry]: `import {run, floating} from "./model"
import {values} from "./prefix"
entry const main = fn value => run (value + values.length)
entry const bits = fn value => floating value
`,
          };
          const result = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            const module = new WebAssembly.Module(result.bytes);
            assert.deepEqual([
              ...new Uint8Array(
                WebAssembly.Module.customSections(module, "blot:ownership")[0],
              ),
            ], [2, 2, 0]);
            const guest = await instantiateGuest(result.bytes);
            try {
              const value = count + 1;
              const wanted = [
                value + 33,
                value + 34,
                value + 32,
                value + 34,
                2 * value + 65,
              ];
              assert.deepEqual(
                Array.from(guest.call("main", 1) as Uint32Array),
                wanted,
              );
              const warmed = guest.memoryBytes();
              for (let round = 0; round < 20; round++) {
                assert.deepEqual(
                  Array.from(guest.call("main", 1) as Uint32Array),
                  wanted,
                );
              }
              assert(guest.memoryBytes() <= warmed + 65536);
              assert(Object.is(guest.call("bits", 1), -0));
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("wide ownership selects exact bitmap and size for differently shaped constructor updates", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const types = Array.from({ length: 40 }, (_, word) => {
    if (word === 33) return "child: Array U32";
    return `f${String(word).padStart(3, "0")}: U32`;
  }).join(", ");
  const values = Array.from({ length: 40 }, (_, word) => {
    if (word === 33) return "child: #[40]";
    return `f${String(word).padStart(3, "0")}: ${word}`;
  }).join(", ");
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build({
          sources: {
            [entry]: `
type Shape is data = #Small {child: Array U32, value: U32} | #Large {${types}}
const replace = fn (shape: Shape) => do:
  shape.child := #[self[0] + 1]
  return shape
entry const run = fn (mode: U32) => do:
  let before = if mode == 0 then #Small {child: #[40], value: 7} else #Large {${values}}
  let captured = fn () => before.child[0]
  let changed = replace before
  for index in 0..32:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      return #[0]
  return #[before.child[0], changed.child[0], captured ()]
`,
          },
        });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const guest = await instantiateGuest(result.bytes);
        try {
          for (const mode of [0, 1, 0, 1]) {
            assert.deepEqual(
              Array.from(guest.call("run", mode) as Uint32Array),
              [40, 41, 40],
            );
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
