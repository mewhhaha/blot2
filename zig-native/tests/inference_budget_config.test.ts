import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("runtime inference configuration binds identity and preserves the production default", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-budget-config-" });
  const entry = `${directory}/main.blot`;
  const cacheDirectory = `${directory}/cache`;
  const options = { executable, entry, prelude: null, cacheDirectory };
  const sources = { [entry]: "entry const answer = fn () => 42\n" };
  const production = await createZigProjectCompiler(options);
  const explicit = await createZigProjectCompiler({
    ...options,
    inferenceBudget: 1_000_000,
  });
  const bounded = await createZigProjectCompiler({
    ...options,
    inferenceBudget: 1,
  });
  try {
    assert.equal(production.compilerIdentity, explicit.compilerIdentity);
    assert.notEqual(bounded.compilerIdentity, production.compilerIdentity);
    const accepted = await production.build({ sources });
    assert(accepted.success, JSON.stringify(accepted));
    const reference = await explicit.build({ sources });
    assert(reference.success, JSON.stringify(reference));
    assert.deepEqual(reference.bytes, accepted.bytes);
    const rejected = await bounded.build({ sources });
    assert(!rejected.success, JSON.stringify(rejected));
    assert.equal(rejected.diagnostics.length, 1);
    assert.equal(rejected.diagnostics[0].code, "inference_budget");
    assert.match(rejected.diagnostics[0].message, /budget of 1 steps/);
  } finally {
    await Promise.all([
      production.dispose(),
      explicit.dispose(),
      bounded.dispose(),
    ]);
    await Deno.remove(directory, { recursive: true });
  }
});
