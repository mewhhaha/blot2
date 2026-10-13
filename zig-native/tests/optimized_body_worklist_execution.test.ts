import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("optimizer dependency edits and restored checkpoints keep executed callees fresh in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-optimizer-worklist-" });
  const entry = `${directory}/main.blot`;
  const helper = `${directory}/helper.blot`;
  const program = `import * as helper from "./helper"
entry const run = fn count => helper.left count + helper.right count
`;
  const sources = (bias: number) => ({
    [entry]: program,
    [helper]: `const leaf = fn value => value + ${bias}
const left = fn count => do:
  let total = 0
  for value in 0..count:
    total := self + leaf value
  return total
const right = fn count => do:
  let total = 0
  for value in 0..count:
    total := self + value * 7
  return total
`,
  });
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0], entry, codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        stdRoot: new URL("../../std", import.meta.url).pathname,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      let checkpoint;
      try {
        for (const bias of [3, 5, 3, 3]) {
          const built = await retained.build({ sources: sources(bias) });
          const fresh = await createZigProjectCompiler(options);
          try {
            const ordinary = await fresh.build({ sources: sources(bias) });
            assert(built.success && ordinary.success, JSON.stringify({ built, ordinary }));
            assert.deepEqual(built.bytes, ordinary.bytes);
            const guest = await instantiateGuest(built.bytes);
            try {
              for (const count of [0, 1, 2, 17, 65]) {
                assert.equal(guest.call("run", count), (4 * count * (count - 1) + bias * count) >>> 0);
              }
            } finally { guest.dispose(); }
          } finally { await fresh.dispose(); }
          if (checkpoint === undefined) checkpoint = await retained.exportCheckpoint();
        }
      } finally { await retained.dispose(); }
      const resumed = await createZigProjectCompiler({ ...options, checkpoint });
      const fresh = await createZigProjectCompiler(options);
      try {
        const built = await resumed.build({ sources: sources(5) });
        const ordinary = await fresh.build({ sources: sources(5) });
        assert(built.success && ordinary.success, JSON.stringify({ built, ordinary }));
        assert.deepEqual(built.bytes, ordinary.bytes);
        const guest = await instantiateGuest(built.bytes);
        try { assert.equal(guest.call("run", 17), 1173); } finally { guest.dispose(); }
      } finally { await resumed.dispose(); await fresh.dispose(); }
    }
  } finally { await Deno.remove(directory, { recursive: true }); }
});
