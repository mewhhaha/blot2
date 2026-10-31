import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const entry =
  new URL("../fixtures/scoped-loop-refinement.blot", import.meta.url)
    .pathname;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`loop carries forget entry-only inline variant refinements (${codegenTier})`, async () => {
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      stdRoot: new URL("../../std/", import.meta.url).pathname,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const result = await compiler.build();
      assert(result.success, JSON.stringify(result));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = (
          name: string,
          input: number | Float32Array<ArrayBuffer>,
        ) =>
          asynchronous ? guest.callAsync(name, input) : guest.call(name, input);
        try {
          for (const count of [0, 1, 2, 4, 16]) {
            assert.deepEqual(
              await call("trace", count),
              new Uint32Array(count),
            );
            assert.deepEqual(
              await call("nested", count),
              Uint32Array.from([
                ...new Uint32Array(count),
                Math.max(0, count - 1),
              ]),
            );
            const expected: number[] = [];
            for (let index = 0; index < count; index++) {
              expected.push(index % 3 === 1 ? index - 1 : 100 + index);
            }
            assert.deepEqual(
              await call("alternating", count),
              Uint32Array.from(expected),
            );
            assert.deepEqual(
              await call("mixed", count),
              Uint32Array.from(
                { length: count },
                (_, index) => index % 2 === 0 ? 10 : 20,
              ),
            );
            for (const name of ["borrowed", "borrowed_continue"]) {
              assert.deepEqual(
                await call(name, count),
                Uint32Array.from(
                  { length: count },
                  (_, index) => index % 2 === 0 ? 7 : 99,
                ),
              );
            }
          }
          for (
            const [values, expected] of [
              [[], 99],
              [[1], 0],
              [[1, 2, 3], 0],
              [[3, 2, 1], 2],
              [[1, 1, 1], 0],
              [[3, 1, 1, 2], 1],
            ] as const
          ) {
            assert.equal(
              await call("minimum", Float32Array.from(values)),
              expected,
            );
          }
        } finally {
          guest.dispose();
        }
      }
      const source = await Deno.readTextFile(entry);
      for (const exit of ["", "    continue\n"]) {
        const rejected = await compiler.build({
          sources: {
            [entry]: `${source}
type Restricted is data = $Inline U32 | $Reference (&[U32])
entry const invalid = func (count: U32): U32 => return do:
  let labels: Array U32 = #[7]
  let state: Restricted = $Inline 0
  for index in 0 .. count:
    state := $Reference (&labels[0..1])
${exit}  return case state of
    $Inline value => value
    $Reference reference => reference.at 0
`,
          },
        });
        assert(!rejected.success);
        assert.equal(rejected.diagnostics[0].code, "storage_escape");
        assert.equal(
          rejected.diagnostics[0].message,
          exit === ""
            ? "A loop must retain the same named owners and borrowed roots across iterations"
            : "A loop exit must retain the same named owners and borrowed roots",
        );
        assert.equal("bytes" in rejected, false);
      }
      const recovered = await compiler.build();
      assert(recovered.success, JSON.stringify(recovered));
      assert.deepEqual(recovered.bytes, result.bytes);
    } finally {
      await compiler.dispose();
    }
  });
}
