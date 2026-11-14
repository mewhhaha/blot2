import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler/zig-out/bin/blotc", import.meta.url).pathname;
const entry =
  new URL("../../compiler/fixtures/scoped-loop-refinement.blot", import.meta.url)
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
    } finally {
      await compiler.dispose();
    }
  });
}
