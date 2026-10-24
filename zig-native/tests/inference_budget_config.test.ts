import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

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
    // Reopening this cache key joins any detached writer before teardown.
    const settled = await createZigProjectCompiler(options);
    await settled.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("explicit associated work limits span modules and rejection recovers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-associated-budget-",
  });
  const entry = `${directory}/main.blot`;
  const library =
    `type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
type Package = exists [a] where { Source a } => a
const read = fn (item: Package) => unpack item as [a] value in Source.show value (Source.get value)
const number: Package = pack [U32] 42 as Package
const answer = fn () => read number
`;
  const sources = {
    [`${directory}/first.blot`]: library,
    [`${directory}/second.blot`]: library,
    [entry]: `import * as first from "./first"
import * as second from "./second"
entry const answer = fn () => @u32.add (first.answer ()) (second.answer ())
`,
  };
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const bounded = await createZigProjectCompiler({
    ...options,
    inferenceBudget: 2048,
  });
  const sufficient = await createZigProjectCompiler({
    ...options,
    inferenceBudget: 4096,
  });
  try {
    // Each module fits 2048 steps alone. Their combined associated evidence
    // must consume the configured project budget, not a hidden million steps.
    const rejected = await bounded.build({ sources });
    assert(!rejected.success, JSON.stringify(rejected));
    assert.equal(rejected.diagnostics[0].code, "associated_limit");
    const accepted = await sufficient.build({ sources });
    assert(accepted.success, JSON.stringify(accepted));
    const guest = await instantiateGuest(accepted.bytes);
    try {
      assert.equal(guest.call("answer", null), 84);
    } finally {
      guest.dispose();
    }
    const recovered = await bounded.build({
      sources: {
        ...sources,
        [entry]:
          'import * as first from "./first"\nentry const answer = fn () => first.answer ()\n',
      },
    });
    assert(recovered.success, JSON.stringify(recovered));
    const next = await instantiateGuest(recovered.bytes);
    try {
      assert.equal(next.call("answer", null), 42);
    } finally {
      next.dispose();
    }
  } finally {
    await Promise.all([bounded.dispose(), sufficient.dispose()]);
    await Deno.remove(directory, { recursive: true });
  }
});
