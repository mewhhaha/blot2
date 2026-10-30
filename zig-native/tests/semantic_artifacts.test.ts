import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;
// Resolver continuations bind checker-local payloads in frozen Core.
const library = `const try = monad Maybe
const add_present = func left => return func right => return do try:
  use first <- left
  use second <- right
  break first + second
`;
// Keep this synthetic factory above the source-inlining budget so restart
// validation exercises a persisted, independently selected semantic receipt.
const entrySource = (offset: string) =>
  `import * as lib from "./lib"
const factory = func number => return func extra => return do:
  let query_copy_00 = extra
  let query_copy_01 = query_copy_00
  let query_copy_02 = query_copy_01
  let query_copy_03 = query_copy_02
  let query_copy_04 = query_copy_03
  let query_copy_05 = query_copy_04
  let query_copy_06 = query_copy_05
  let query_copy_07 = query_copy_06
  let query_copy_08 = query_copy_07
  let query_copy_09 = query_copy_08
  let query_copy_10 = query_copy_09
  let query_copy_11 = query_copy_10
  let query_copy_12 = query_copy_11
  let query_copy_13 = query_copy_12
  let query_copy_14 = query_copy_13
  let query_copy_15 = query_copy_14
  let query_copy_16 = query_copy_15
  let query_copy_17 = query_copy_16
  let query_copy_18 = query_copy_17
  let query_copy_19 = query_copy_18
  let query_copy_20 = query_copy_19
  let query_copy_21 = query_copy_20
  let query_copy_22 = query_copy_21
  let query_copy_23 = query_copy_22
  let query_copy_24 = query_copy_23
  let query_copy_25 = query_copy_24
  let query_copy_26 = query_copy_25
  let query_copy_27 = query_copy_26
  let query_copy_28 = query_copy_27
  let query_copy_29 = query_copy_28
  let query_copy_30 = query_copy_29
  let query_copy_31 = query_copy_30
  let query_copy_32 = query_copy_31
  return @u32.add number query_copy_32
const callback = factory ${offset}
entry const answer = func (extra: U32) : U32 => return callback extra
entry const present = func () => return Maybe.unwrap_or 0 (lib.add_present (#Some 1) (#Some 2))
`;

async function project() {
  const directory = await Deno.makeTempDir({ prefix: "blot-semantic-" });
  await Deno.writeTextFile(`${directory}/lib.blot`, library);
  await Deno.writeTextFile(`${directory}/main.blot`, entrySource("40"));
  const bundle = `${directory}/deps.blotdep`;
  const packed = await new Deno.Command(executable, {
    args: [
      "dependencies",
      `${directory}/main.blot`,
      bundle,
      "--prelude",
      prelude,
    ],
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
      for (
        const text of [
          entrySource("41"),
          entrySource("#Wrong"),
          entrySource("40"),
        ]
      ) {
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
      const recovered = await restored.build({
        sources: { [entry]: entrySource("40") },
      });
      assert(recovered.success);
      assert.deepEqual(await run(recovered.bytes), [42, 3]);
    } finally {
      await restored.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
