import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;
// Resolver continuations bind checker-local payloads in frozen Core.
const library = `const try = monad Maybe
const add_present = fn left => fn right => do try:
  use first <- left
  use second <- right
  return first + second
`;
const entrySource = (offset: string) =>
  `import * as lib from "./lib"
const factory = fn number => fn extra => @u32.add number extra
const callback = factory ${offset}
entry const answer = fn (extra: U32) -> U32 => callback extra
entry const present = fn () => Maybe.unwrap_or 0 (lib.add_present (#Some 1) (#Some 2))
`;

async function project() {
  const directory = await Deno.makeTempDir({ prefix: "blot-semantic-" });
  await Deno.writeTextFile(`${directory}/lib.blot`, library);
  await Deno.writeTextFile(`${directory}/main.blot`, entrySource("40"));
  const bundle = `${directory}/deps.blotdep`;
  const packed = await new Deno.Command(executable, {
    args: ["dependencies", `${directory}/main.blot`, bundle, "--prelude", prelude],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(
    packed.success,
    new TextDecoder().decode(packed.stdout) +
      new TextDecoder().decode(packed.stderr),
  );
  return { directory, entry: `${directory}/main.blot`, bundle };
}

async function run(bytes: Uint8Array<ArrayBuffer>) {
  const guest = await instantiateGuest(bytes);
  try {
    return [guest.call("answer", 2), guest.call("present", null)];
  } finally {
    guest.dispose();
  }
}

Deno.test("monadic libraries pack into dependency artifacts and execute", async () => {
  const { directory, entry, bundle } = await project();
  try {
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude,
      dependencies: bundle,
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      assert(built.stats.cachedModules > 0);
      assert.deepEqual(await run(built.bytes), [42, 3]);
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("dependency-loaded projects restart from persisted semantic owners and recover failed edits", async () => {
  const { directory, entry, bundle } = await project();
  const options = { executable, entry, prelude, dependencies: bundle };
  try {
    const producer = await createZigProjectCompiler(options);
    let expected: Uint8Array<ArrayBuffer>;
    let checkpoint: Uint8Array<ArrayBuffer>;
    try {
      const built = await producer.build();
      assert(built.success, JSON.stringify(built));
      expected = built.bytes;
      checkpoint = await producer.exportCheckpoint();
    } finally {
      await producer.dispose();
    }
    const restored = await createZigProjectCompiler({ ...options, checkpoint });
    try {
      const built = await restored.build();
      assert(built.success, JSON.stringify(built));
      assert.deepEqual(built.bytes, expected!);
      const selected = built.stats.selectedQueries as Record<string, number>;
      // The first revision has no in-process predecessor: the Gate was built
      // over the persisted owner and replayed at least one selected receipt.
      assert.equal(selected.gate_fresh, 1, JSON.stringify(selected));
      assert(selected.reused > 0, JSON.stringify(selected));
      assert.deepEqual(await run(built.bytes), [42, 3]);
      for (const text of [entrySource("41"), entrySource("#Wrong"), entrySource("40")]) {
        const sources = { [entry]: text };
        const result = await restored.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const rebuilt = await fresh.build({ sources });
          assert.equal(result.success, rebuilt.success);
          if (result.success && rebuilt.success) {
            assert.deepEqual(result.bytes, rebuilt.bytes);
          } else if (!result.success && !rebuilt.success) {
            assert.deepEqual(result.diagnostics, rebuilt.diagnostics);
          }
        } finally {
          await fresh.dispose();
        }
      }
      const recovered = await restored.build({ sources: { [entry]: entrySource("40") } });
      assert(recovered.success);
      assert.deepEqual(await run(recovered.bytes), [42, 3]);
    } finally {
      await restored.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
