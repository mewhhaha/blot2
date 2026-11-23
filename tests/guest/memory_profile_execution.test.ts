import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `import * as array from "std/array"
entry const boxed = func (count: U32) : Array U32 => return #[count, count + 1]
entry const copied = func (count: U32) => return do:
  let values = array.generate count (func index => return index + 1)
  let old = values.copy
  values[0] := 99
  break old[0] + values[0] + old.length
entry const trapped = func (index: U32) => return do:
  let values = array.generate 8 (func i => return i + 1)
  break values[index]
`;

const closures = `import * as array from "std/array"
entry const closures = func (steps: U32) => return do:
  let saved = array.generate 8 (func index => return func offset => return index + offset)
  let total = 0
  for step in 0..steps:
    let copied = array.generate saved.length (func i => return saved[i])
    total := self + copied[step % copied.length] step
  break total
`;

const options = (entry: string) => ({
  executable: resolve(Deno.args[0] ?? "compiler-goose/build/blotc-goose"),
  entry,
  prelude: new URL("../../std/prelude.blot", import.meta.url),
  stdRoot: new URL("../../std", import.meta.url),
});

Deno.test(`copies, traps and retained source edits keep their results`, async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-memory-profile-",
  });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    ...options(entry),
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(built.success, JSON.stringify(built));
    const guest = await instantiateGuest(built.bytes);
    try {
      for (let pass = 0; pass < 5; pass++) {
        assert.deepEqual(
          guest.call("boxed", pass),
          Uint32Array.of(pass, pass + 1),
        );
        assert.equal(guest.call("copied", 32), 132);
        assert.throws(
          () => guest.call("trapped", 8),
          WebAssembly.RuntimeError,
        );
        assert.equal(guest.call("trapped", 0), 1);
      }
    } finally {
      guest.dispose();
    }
    const repeated = await compiler.build({ sources: { [entry]: source } });
    assert(repeated.success);
    assert.deepEqual(repeated.bytes, built.bytes);
    const shiftedSource = "// updated source locations\n" + source;
    const shifted = await compiler.build({
      sources: { [entry]: shiftedSource },
    });
    assert(shifted.success);
    const fresh = await createZigProjectCompiler({
      ...options(entry),
    });
    try {
      const rebuilt = await fresh.build({
        sources: { [entry]: shiftedSource },
      });
      assert(rebuilt.success);
      assert.deepEqual(shifted.bytes, rebuilt.bytes);
    } finally {
      await fresh.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

// Direct backend gap: a closure parameter typed only by a later call is an unresolved type variable (tasks/DELETE_SCOPED.md).
Deno.test.ignore("copied arrays of curried closures keep their results", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-memory-closures-" });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler(options(entry));
  try {
    const built = await compiler.build({ sources: { [entry]: closures } });
    assert(built.success, JSON.stringify(built));
    const guest = await instantiateGuest(built.bytes);
    try {
      assert.equal(guest.call("closures", 16), 176);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
