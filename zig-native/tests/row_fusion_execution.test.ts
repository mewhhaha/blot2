import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

function pipelineSources() {
  const helpers: string[] = [];
  const functions: string[] = [];
  const cases: { name: string; width: number }[] = [];
  for (const shape of ["record", "tuple"]) {
    let first = 1;
    if (shape === "tuple") first = 2;
    for (let width = first; width <= 16; width++) {
      const fields: string[] = [];
      const types: string[] = [];
      const reads: string[] = [];
      for (let field = 0; field < width; field++) {
        const value =
          `input[@u32.rem (@u32.add index ${field}) (@array.length input)]`;
        if (shape === "record") {
          fields.push(`f${field}: ${value}`);
          types.push(`f${field}: F32`);
          reads.push(`row.f${field}`);
        } else {
          fields.push(value);
          types.push("F32");
          reads.push(`@product.get row ${field}`);
        }
      }
      let row = `(${fields.join(", ")})`;
      let type = `(${types.join(", ")})`;
      if (shape === "record") {
        row = `{${fields.join(", ")}}`;
        type = `{${types.join(", ")}}`;
      }
      let reduction = reads[0];
      for (const read of reads.slice(1)) {
        reduction = `@f32.add (${reduction}) (${read})`;
      }
      const consumer = `consume_${shape}_${width}`;
      helpers.push(
        `const ${consumer} = fn (row: ${type}) -> F32 => ${reduction}\n`,
      );
      for (const collection of ["array", "list"]) {
        const name = `${collection}_${shape}_${width}`;
        let firstRow = "@array.get saved 0";
        if (collection === "list") {
          firstRow = "@cursor.value (@list.cursor saved)";
        }
        cases.push({ name, width });
        functions.push(`entry const ${name} = fn (input: Array F32) => do:
  let original = @${collection}.generate 600 (fn index => ${row})
  let saved = original
  let values = @${collection}.slice original 123 257
  let total = 0.0
  for row in values:
    total := @f32.add total (${consumer} row)
  let first = ${firstRow}
  break @f32.add total (${consumer} first)
`);
      }
    }
  }
  return { source: helpers.join("\n") + functions.join("\n"), cases };
}

Deno.test("row producer composition preserves snapshots, wrapping and early exits", async () => {
  await compileAndRun(
    `
const transform = fn row => {a: @u32.add row.a 1, b: @u32.mul row.b 2, c: row.c}
const consume = fn row => @u32.add (@u32.add row.a row.b) row.c
entry const run = fn (count: U32) => do:
  let arrays = @array.generate count (fn index => {a: index, b: @u32.add index 1, c: 4294967295})
  let lists = @list.from_array arrays
  let saved = arrays
  let total = 0
  for row in arrays:
    total := @u32.add total (consume (transform row))
  for row in lists:
    total := @u32.add total (consume (transform row))
  arrays[0].a := 99
  break #[total, saved[0].a, arrays[0].a]
entry const stopped = fn (count: U32) => do:
  let rows = @list.generate count (fn index => {a: index, b: 1, c: 2})
  let total = 0
  for row in rows:
    if @u32.eq row.a 83:
      break
    total := @u32.add total (consume row)
  break total
entry const returned = fn (count: U32) => do:
  let rows = @array.generate count (fn index => {a: index, b: 1, c: 2})
  for row in rows:
    if @u32.eq row.a 83:
      break consume (transform row)
  break 0
`,
    (guest) => {
      for (const count of [1, 82, 83, 84, 257, 600]) {
        assert.deepEqual(
          guest.call("run", count),
          Uint32Array.of((3 * count * (count - 1) + 4 * count) >>> 0, 0, 99),
        );
        const stopped = Math.min(count, 83);
        assert.equal(
          guest.call("stopped", count),
          stopped * (stopped - 1) / 2 + 3 * stopped,
        );
        let returned = 0;
        if (count > 83) returned = 88;
        assert.equal(guest.call("returned", count), returned);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("rows escaping through ordinary calls, closures and demands keep owned bases", async () => {
  await compileAndRun(
    `
const consume = fn row => @u32.add row.a row.b
const store = fn row => #[row]
const capture = fn row => fn () => consume row
const defer_row = fn ~row => fn () => consume (@force row)
entry const stored = fn (count: U32) => do:
  let rows = @list.generate count (fn index => {a: index, b: @u32.add index 1})
  let saved = #[]
  for row in rows:
    saved := #[...saved, (store row)[0]]
  let pressure = @array.fill 8192 99
  break #[consume row | row <- saved]
entry const captured = fn (count: U32) => do:
  let rows = @array.generate count (fn index => {a: index, b: @u32.add index 1})
  let saved = #[]
  for row in rows:
    saved := #[...saved, capture row]
  let pressure = @array.fill 8192 99
  break #[read () | read <- saved]
entry const deferred = fn (count: U32) => do:
  let rows = @list.generate count (fn index => {a: index, b: @u32.add index 1})
  let saved = #[]
  for row in rows:
    saved := #[...saved, defer_row row]
  let pressure = @array.fill 8192 99
  break #[read () | read <- saved]
`,
    (guest) => {
      for (const count of [0, 1, 83, 257]) {
        const expected = Uint32Array.from(
          { length: count },
          (_, index) => 2 * index + 1,
        );
        for (const entry of ["stored", "captured", "deferred"]) {
          assert.deepEqual(guest.call(entry, count), expected, entry);
        }
      }
    },
    { prelude: "none" },
  );
});

Deno.test("effectful row consumers preserve call and trap order", async () => {
  await compileAndRun(
    `
const consume = fn host => fn row => do:
  use first <- host row.a
  use second <- host row.b
  break @u32.add first second
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do:
  let rows = @list.generate 257 (fn index => {a: @u32.mul index 2, b: @u32.add (@u32.mul index 2) 1})
  let total = 0
  for row in rows:
    use value <- consume host row
    total := @u32.add total value
  break total
entry const trap = fn (host: U32 -> U32 ! {Foreign}) => do:
  let rows = @array.generate 257 (fn index => {a: index, b: @u32.rem index 83})
  let total = 0
  for row in rows:
    use value <- host row.a
    total := @u32.add total (@u32.div value row.b)
  break total
`,
    (guest) => {
      const seen: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          seen.push(value);
          return value;
        },
      });
      assert.equal(guest.call("run", host), 514 * 513 / 2);
      assert.deepEqual(seen, Array.from({ length: 514 }, (_, index) => index));
      seen.length = 0;
      assert.throws(() => guest.call("trap", host), WebAssembly.RuntimeError);
      assert.deepEqual(seen, [0]);
      seen.length = 0;
      assert.equal(guest.call("run", host), 514 * 513 / 2);
    },
    { prelude: "none" },
  );
});

Deno.test("fused row consumers revalidate source, compiled and checkpoint dependency edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-fused-revision-" });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/rows.blot`;
  const archive = `${directory}/rows.blotdep`;
  const main = `import { transform, consume } from "./rows"
entry const run = fn (count: U32) => do:
  let rows = @list.generate count (fn index => {a: index, b: @u32.add index 1})
  let total = 0
  for row in rows:
    total := @u32.add total (consume (transform row))
  break total
`;
  const original = `const transform = fn row => {a: @u32.add row.a 1, b: row.b}
const consume = fn row => @u32.add row.a row.b
`;
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(library, original);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    let initial: Uint8Array<ArrayBuffer> | undefined;
    for (const dependencies of [undefined, archive]) {
      const options = {
        executable,
        entry,
        prelude: null,
        dependencies,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [source, expected] of [
            [original, 257 * 258],
            [original.replace("row.a 1", "row.a 3"), 257 * 260],
            [
              original.replace("@u32.add row.a row.b", "@u32.mul row.a row.b"),
              257 * 258 * 515 / 6,
            ],
            [original.replace("row.b}", "absent}"), null],
            [original, 257 * 258],
          ] as const
        ) {
          const sources = { [library]: source };
          let before: Uint8Array<ArrayBuffer> | undefined;
          if (expected === null) before = await retained.exportCheckpoint();
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const rebuilt = await fresh.build({ sources });
            assert.equal(built.success, rebuilt.success);
            if (!built.success) {
              assert(!rebuilt.success);
              assert.equal(expected, null);
              assert.deepEqual(built.diagnostics, rebuilt.diagnostics);
              assert.deepEqual(await retained.exportCheckpoint(), before);
              continue;
            }
            assert(rebuilt.success);
            assert.deepEqual(built.bytes, rebuilt.bytes);
            if (source === original) {
              if (initial) assert.deepEqual(built.bytes, initial);
              initial = built.bytes;
            }
            const checkpoint = await retained.exportCheckpoint();
            const restored = await createZigProjectCompiler({
              ...options,
              checkpoint,
            });
            try {
              const restarted = await restored.build({ sources });
              assert(restarted.success, JSON.stringify(restarted));
              assert.deepEqual(restarted.bytes, built.bytes);
              for (const bytes of [built.bytes, restarted.bytes]) {
                const guest = await instantiateGuest(bytes);
                try {
                  assert.equal(guest.call("run", 257), expected);
                } finally {
                  guest.dispose();
                }
              }
            } finally {
              await restored.dispose();
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

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`named packed row consumers preserve widths slices saved rows and F32 order (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-row-fusion-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const { source, cases } = pipelineSources();
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        for (
          const input of [
            Float32Array.of(16777216, 0.125, -16777216, -0.25, 3.5, -0),
            Float32Array.of(Infinity, -Infinity, 1),
            Float32Array.of(1e-45, -1e-45, -0, 0),
          ]
        ) {
          for (const { name, width } of cases) {
            const row = (index: number) => {
              let result = input[index % input.length];
              for (let field = 1; field < width; field++) {
                result = Math.fround(
                  result + input[(index + field) % input.length],
                );
              }
              return result;
            };
            let expected = 0;
            for (let index = 123; index < 380; index++) {
              expected = Math.fround(expected + row(index));
            }
            expected = Math.fround(expected + row(0));
            assert.equal(guest.call(name, input), expected, name);
          }
        }
        assert.throws(
          () => guest.call("list_record_16", new Float32Array()),
          WebAssembly.RuntimeError,
        );
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
