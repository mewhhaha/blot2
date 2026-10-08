import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("closure keys distinguish equal-shaped static captures and reuse complete graphs", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-static-keys-" });
  const entry = `${directory}/main.blot`, library = `${directory}/library.blot`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.blot`,
  };
  const declarations =
    `type Pack [unused, selected] is data = #Pack { unused: unused, selected: selected }
const identity = fn value => value
const first = #Pack { unused: identity, selected: fn (value: U32) => value + 1 }
const second = #Pack { unused: identity, selected: fn (value: U32) => value + 10 }
const invoke = fn callback => callback 2
const capture = fn packed => fn (value: U32) => invoke (fn extra => do:
  let #Pack { selected } = packed
  return selected (value + extra))
`;
  const main = `import { first, second, capture } from "./library"
entry const answer = fn (value: U32) => capture first value * 1000 + capture second value + 0
`;
  const compiler = await createZigProjectCompiler(options);
  try {
    for (
      const [source, app, expected, reuse] of [
        [declarations, main, 8017, false],
        [declarations, main.replace("+ 0", "+ 1"), 8018, true],
        [
          declarations.replace("value + 1 }", "value + 3 }"),
          main,
          10017,
          false,
        ],
        [declarations.replace("value + extra", "absent"), main, null, false],
        [declarations, main, 8017, false],
      ] as const
    ) {
      const sources = { [entry]: app, [library]: source };
      const result = await compiler.build({ sources });
      if (expected === null) {
        assert(!result.success);
        continue;
      }
      assert(result.success, JSON.stringify(result));
      if (reuse) {
        const backend = result.stats.backend as Record<string, number>;
        assert(backend.reused_closures >= 2, JSON.stringify(result.stats));
      }
      const guest = await instantiateGuest(result.bytes);
      try {
        assert.equal(guest.call("answer", 5), expected);
      } finally {
        guest.dispose();
      }
      const fresh = await createZigProjectCompiler(options);
      try {
        const rebuilt = await fresh.build({ sources });
        assert(rebuilt.success);
        assert.deepEqual(result.bytes, rebuilt.bytes);
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
