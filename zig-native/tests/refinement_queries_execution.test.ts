import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("owned refinement queries preserve dependency edits catalog relocation failure recovery and restart", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-refinement-queries-",
  });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/dep.blot`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const clients: Awaited<ReturnType<typeof createZigProjectCompiler>>[] = [];
  const sources = (changed: number, fixed: number, reordered: boolean) => ({
    [entry]: `import {Box, fixed, read} from "./dep"
const factory = fn value => fn extra => value
const scalar = factory fixed
const nominal = factory (#Box fixed)
entry const run = fn (value: U32) => @u32.add (read value) ${changed}
entry const captured = fn (value: U32) => scalar value
entry const boxed = fn () => do:
  let #Box value = nominal 0
  return value
`,
    [dependency]: `${
      reordered ? "const unrelated = fn value => value\n" : ""
    }data Box a = #Box a
const fixed = ${fixed}
const read = fn (value: U32) => @u32.add value fixed
${reordered ? "" : "const unrelated = fn value => value\n"}`,
  });
  try {
    clients.push(await createZigProjectCompiler(options));
    clients.push(
      await createZigProjectCompiler({ ...options, semanticWorkers: 4 }),
    );
    let original: Uint8Array<ArrayBuffer> | undefined;
    for (
      const [changed, fixed, reordered] of [
        [8, 41, false],
        [9, 41, false],
        [9, 42, false],
        [9, 42, true],
        [8, 41, false],
        [8, 41, false],
      ] as const
    ) {
      const input = sources(changed, fixed, reordered);
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources: input });
        assert(expected.success, JSON.stringify(expected));
        original ??= expected.bytes;
        for (const client of clients) {
          const result = await client.build({ sources: input });
          assert(result.success, JSON.stringify(result));
          assert.deepEqual(result.bytes, expected.bytes);
          const guest = await instantiateGuest(result.bytes);
          try {
            for (const value of [0, 7, 0xffff_ffff]) {
              assert.equal(
                guest.call("run", value),
                (value + fixed + changed) >>> 0,
              );
              assert.equal(guest.call("captured", value), fixed);
            }
            assert.equal(guest.call("boxed", null), fixed);
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await fresh.dispose();
      }
    }
    const current = sources(8, 41, false);
    const diagnostics = [];
    for (const client of clients) {
      const failed = await client.build({
        sources: {
          ...current,
          [entry]: current[entry] + "const unused: U32 = false\n",
        },
      });
      assert(!failed.success);
      diagnostics.push(failed.diagnostics);
      const corrected = await client.build({ sources: current });
      assert(corrected.success);
      assert.deepEqual(corrected.bytes, original);
      const checkpoint = await client.exportCheckpoint();
      const restarted = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      try {
        const result = await restarted.build({ sources: current });
        assert(result.success);
        assert.deepEqual(result.bytes, original);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("run", 7), 56);
          assert.equal(guest.call("captured", 0), 41);
          assert.equal(guest.call("boxed", null), 41);
        } finally {
          guest.dispose();
        }
      } finally {
        await restarted.dispose();
      }
    }
    assert.deepEqual(diagnostics[0], diagnostics[1]);
  } finally {
    await Promise.all(clients.map((client) => client.dispose()));
    await Deno.remove(directory, { recursive: true });
  }
});
