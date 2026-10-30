import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

// Retained callers of array, nominal, aliased and imported aggregate constants
// keep their code only when the current value graph matches; data is always
// re-serialized in the current owner, so output equals a fresh build.
Deno.test("retained callers relocate aggregate constants through movement, traps and recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-aggregate-" });
  const entry = `${directory}/main.blot`;
  await Deno.writeTextFile(
    `${directory}/dep.blot`,
    "const shared: Array U32 = #[1, 2, 3]\n",
  );
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const source = (prefix: string, tail: string, other: string) =>
    `import * as dep from "./dep"
${prefix}const table: Array U32 = #[10, 20, ${tail}]
type Pair is data = #Pair { left: U32, right: U32 }
const pair = #Pair { left: 20, right: 22 }
const aliased = (table, table)
const other = ${other}
entry const pick = func (i: U32) => return table[i]
entry const first = func () => return do:
  let #Pair { left, right } = pair
  break @u32.add left right
entry const sum_alias = func (i: U32) => return do:
  let (left, right) = aliased
  break @u32.add left[i] right[i]
entry const from_dep = func (i: U32) => return dep.shared[i]
entry const unrelated = func () => return other
`;
  // Moved functions and data, an element edit, a trapping constant, recovery.
  const revisions: [string, string, string][] = [
    ["", "30", "0"],
    ["", "30", "1"],
    ["const moved: Array U32 = #[7, 8]\nentry const early = func (i: U32) => return moved[i]\n", "30", "1"],
    ["", "31", "2"],
    ["", "31", "@u32.div 1 0"],
    ["", "31", "3"],
  ];
  const retained = await createZigProjectCompiler(options);
  let reused = 0;
  try {
    for (const [prefix, tail, other] of revisions) {
      const sources = { [entry]: source(prefix, tail, other) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success && !expected.success) {
          assert(other.includes("div"));
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        assert.equal(result.stats.nativeWorkSteps, expected.stats.nativeWorkSteps);
        reused += (result.stats.backend as Record<string, number>)
          .reused_aggregate_constants;
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("pick", 2), Number(tail));
          assert.equal(guest.call("first", null), 42);
          assert.equal(guest.call("sum_alias", 1), 40);
          assert.equal(guest.call("from_dep", 2), 3);
          assert.equal(guest.call("unrelated", null), Number(other));
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
    assert(reused > 0);
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
