import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;

Deno.test("runtime inference configuration binds identity and preserves the production default", async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-budget-config-" });
  const entry = `${directory}/main.sq`;
  const options = { executable, entry, prelude: null };
  const sources = { [entry]: "io const answer = func () => return 42\n" };
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
