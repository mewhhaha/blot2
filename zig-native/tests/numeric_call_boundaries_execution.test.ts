import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const extra = `
entry const captured_choice = func (choice: U32) => return do:
  let offset = choice + 9
  let read = if choice % 2 == 0 then (func (row: Row) : U32 => return row.count + offset) else (func (row: Row) : U32 => return row.id * offset)
  let rows = array.generate 32 make_row
  let total = 0
  for row in rows:
    total := self + read row
  break total
entry const saved_choice = func (choice: U32) => return do:
  let take = if choice % 2 == 0 then (func (row: Row) : Row => return row) else (func (row: Row) : Row => return make_row (row.id + 100))
  let rows = array.generate 32 make_row
  let saved = make_row 0
  for row in rows:
    saved := take row
  rows[31].count := 999
  break saved.count
entry const unknown_choice = func (choice: U32) => return do:
  let readers = #[(func (row: Row) : U32 => return row.count + 3), (func (row: Row) : U32 => return row.id + 7)]
  let read = readers[choice % 2]
  let rows = array.generate 32 make_row
  let total = 0
  for row in rows:
    total := self + read row
  break total
type Vector is data = $Vector {x: F32, y: F32}
entry const selected_bits = func (seed: F32) => return do:
  let read = if seed == 0.0 then (func (value: Vector) : F32 => return value.x) else (func (value: Vector) : F32 => return value.y)
  let values = array.fill 2 ($Vector {x: seed, y: seed})
  let result = 0.0
  for value in values:
    result := read value
  break #[result]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`numeric call boundaries preserve selected captures escapes and imported construction (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-numeric-calls-" });
    const entry = `${directory}/main.blot`;
    const library = `${directory}/rows.blot`;
    const fixture = new URL(
      "../../benchmarks/runtime-boundaries/",
      import.meta.url,
    );
    const main = await Deno.readTextFile(new URL("main.blot", fixture)) + extra;
    const rows = await Deno.readTextFile(new URL("rows.blot", fixture));
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      stdRoot: new URL("../../std", import.meta.url),
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({
        sources: { [entry]: main, [library]: rows },
      });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        for (const choice of [0, 1, 2, 3, 16, 17]) {
          const offset = choice + 9;
          assert.equal(
            guest.call("captured_choice", choice),
            choice % 2 === 0 ? 528 + 32 * offset : 528 * offset,
          );
          assert.equal(
            guest.call("saved_choice", choice),
            choice % 2 === 0 ? 32 : 133,
          );
          assert.equal(
            guest.call("unknown_choice", choice),
            528 + 32 * (choice % 2 === 0 ? 3 : 7),
          );
        }
        for (const seed of [-0, 0, 1.5, -10, Infinity, -Infinity]) {
          const actual = guest.call("selected_bits", seed) as Float32Array;
          assert.deepEqual(
            new Uint32Array(actual.buffer, actual.byteOffset, actual.length),
            new Uint32Array(Float32Array.of(seed).buffer),
          );
        }
      } finally {
        guest.dispose();
      }
      const exports =
        new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports;
      const counter = (name: string) =>
        Number((exports[`blot:${name}`] as WebAssembly.Global).value) >>> 0;
      const invoke = (name: string, input: number, expected: number) => {
        (exports["blot:ownership_enter"] as CallableFunction)();
        let outcome = 1;
        try {
          assert.equal(
            (exports[name] as CallableFunction)(input) >>> 0,
            expected >>> 0,
          );
          outcome = 0;
        } finally {
          (exports["blot:ownership_leave"] as CallableFunction)(outcome);
        }
        assert.equal(counter("rc_roots"), 0);
        assert.equal(counter("rc_leases"), 0);
      };
      for (const size of [0, 1, 32, 33, 2000]) {
        const expected = size * (size + 1) / 2;
        for (
          const name of ["nominal_generate", "wide_generate", "scalar_generate"]
        ) {
          invoke(name, size, expected);
          const before = counter("rc_destroyed");
          invoke(name, size, expected);
          if (codegenTier === "optimized") {
            assert.equal(
              (counter("rc_destroyed") - before) >>> 0,
              1,
              `${name}/${size}`,
            );
          }
        }
      }
      for (const passes of [0, 2, 3]) {
        for (const name of ["direct", "indexed", "selected"]) {
          invoke(name, passes, passes * 2001000);
          const before = counter("rc_destroyed");
          invoke(name, passes, passes * 2001000);
          if (codegenTier === "optimized") {
            assert.equal(
              (counter("rc_destroyed") - before) >>> 0,
              1,
              `${name}/${passes}`,
            );
          }
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
