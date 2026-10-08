import { deepStrictEqual, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("collection proofs follow imported body edits, failed revisions and fresh output", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-collection-proof-",
  });
  const entry = `${directory}/main.blot`,
    dependency = `${directory}/helpers.blot`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.blot`,
  };
  const before = `const pair = fn value => [value, value + 1]
const consume = fn (values: List U32) => do:
  let total = 0
  for value in values:
    total := self + value
  return total
const build = fn (values: Array U32) => #[x + y | x <- values, y <- values]
`;
  const main = `import { pair, consume, build } from "./helpers"
entry const answer = fn seed => consume (pair seed)
entry const product = fn values => build values
`;
  const retained = await createZigProjectCompiler(options);
  let successes = 0;
  try {
    for (
      const source of [
        before,
        before.replace("value + 1", "value + 2"),
        "const invalid = absent\n",
        before.replace("return total", "return total + values.length"),
        before,
      ]
    ) {
      const sources = { [entry]: main, [dependency]: source };
      const built = await retained.build({ sources });
      if (source.includes("absent")) {
        ok(!built.success);
        continue;
      }
      ok(built.success, JSON.stringify(built));
      const optimizer = built.stats.runtimeOptimization as {
        functions: number;
        reused: number;
        optimized: number;
      };
      ok(optimizer.functions > 0);
      if (successes++ === 1) {
        ok(optimizer.reused > 0, JSON.stringify(optimizer));
      }
      deepStrictEqual(
        optimizer.functions,
        optimizer.reused + optimizer.optimized,
      );
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        ok(expected.success);
        deepStrictEqual(built.bytes, expected.bytes);
        const guest = await instantiateGuest(built.bytes);
        try {
          deepStrictEqual(
            guest.call("answer", 20),
            source.includes("values.length")
              ? 43
              : source.includes("value + 2")
              ? 42
              : 41,
          );
          deepStrictEqual(
            guest.call("product", Uint32Array.of(1, 2)),
            Uint32Array.of(2, 3, 3, 4),
          );
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
