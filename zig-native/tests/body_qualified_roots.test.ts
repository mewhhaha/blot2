import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

function spine(value: string) {
  for (let step = 0; step < 12; step++) value = `(fn item => item) (${value})`;
  return value;
}

Deno.test("body checker reuse owns qualified generic dotted roots through rejection and recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-qualified-roots-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      for (const form of ["projected", "record", "declared"] as const) {
        const source = (
          inserted = false,
          reordered = false,
          missing = false,
        ) => {
          let root = "value.first", path = "root.count";
          if (form === "record") {
            root = "{item: value.first}";
            path = "root.item.count";
          }
          let producer = "";
          if (form === "declared") {
            producer =
              'const first: a -> b where {field "first" a b} = fn value => value.first\n';
            root = "first value";
          }
          const field = missing ? "absent" : "count";
          const scalar = reordered
            ? `{other:3.0,first:{tail:2,${field}:value}}`
            : `{first:{${field}:value,tail:2.0},other:3}`;
          const owning = reordered
            ? `{first:{${field}:#[value],tail:2.0},other:3}`
            : `{other:3.0,first:{tail:2,${field}:#[value]}}`;
          const prefix = inserted
            ? "const earlier_spelling = {first:3.0}\n"
            : "";
          return `${prefix}${producer}const extract = fn value => do:
  let root = ${root}
  return ${spine(path)}
entry const run = fn (value: U32) => extract ${scalar}
entry const packed = fn (value: U32) => extract ${owning}
`;
        };
        await Deno.writeTextFile(entry, source());
        const options = {
          executable,
          entry,
          prelude: null,
          codegenTier,
          cacheDirectory: false as const,
        };
        const retained = await createZigProjectCompiler(options);
        try {
          const revisions = [
            [false, false, false],
            [true, false, false],
            [true, true, false],
            [true, true, true],
            [true, true, false],
            [false, false, false],
          ] as const;
          for (
            const [revision, [inserted, reordered, missing]] of revisions
              .entries()
          ) {
            const fresh = await createZigProjectCompiler(options);
            try {
              const sources = { [entry]: source(inserted, reordered, missing) };
              const expected = await fresh.build({ sources });
              const actual = await retained.build({ sources });
              assert.equal(actual.success, expected.success);
              assert.equal(actual.success, !missing, JSON.stringify(actual));
              if (!actual.success || !expected.success) {
                assert.ok(!actual.success && !expected.success);
                assert.deepEqual(actual.diagnostics, expected.diagnostics);
                continue;
              }
              assert.deepEqual(actual.bytes, expected.bytes);
              if (revision === 1) {
                assert.ok(
                  Number(actual.stats.frontend.body_elaborations) <
                    Number(expected.stats.frontend.body_elaborations),
                  JSON.stringify({
                    form,
                    codegenTier,
                    actual: actual.stats,
                    expected: expected.stats,
                  }),
                );
              }
              const guest = await instantiateGuest(actual.bytes);
              try {
                assert.equal(guest.call("run", 40), 40);
                assert.deepEqual(
                  guest.call("packed", 40),
                  new Uint32Array([40]),
                );
              } finally {
                await guest.dispose();
              }
            } finally {
              await fresh.dispose();
            }
          }
        } finally {
          await retained.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
