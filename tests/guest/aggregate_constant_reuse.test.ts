import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

// Retained builds of array, nominal, aliased and imported aggregate constants
// equal a fresh build through moved code, element edits, a trapping constant
// and recovery. A trapping constant compiles and traps when it is first read.
Deno.test("retained builds of aggregate constants match fresh builds through movement, traps and recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-aggregate-" });
  const entry = `${directory}/main.blot`;
  await Deno.writeTextFile(
    `${directory}/dep.blot`,
    "const shared: Array U32 = #[1, 2, 3]\n",
  );
  const options = {
    executable: Deno.args[0] ??
      new URL("../../compiler-goose/build/blotc-goose", import.meta.url),
    entry,
    prelude: null,
  };
  const source = (prefix: string, tail: string, other: string) =>
    `import * as dep from "./dep"
${prefix}const table: Array U32 = #[10, 20, ${tail}]
type Pair is data = $Pair { left: U32, right: U32 }
const pair = $Pair { left: 20, right: 22 }
const aliased = (table, table)
const other = ${other}
io const pick = func (i: U32) => return table[i]
io const first = func () => return do:
  let $Pair { left, right } = pair
  break @u32.add left right
io const sum_alias = func (i: U32) => return do:
  let (left, right) = aliased
  break @u32.add left[i] right[i]
io const from_dep = func (i: U32) => return dep.shared[i]
io const unrelated = func () => return other
`;
  // Moved functions and data, an element edit, a trapping constant, recovery.
  const revisions: [string, string, string][] = [
    ["", "30", "0"],
    ["", "30", "1"],
    ["const moved: Array U32 = #[7, 8]\nio const early = func (i: U32) => return moved[i]\n", "30", "1"],
    ["", "31", "2"],
    ["", "31", "@u32.div 1 0"],
    ["", "31", "3"],
  ];
  const retained = await createZigProjectCompiler(options);
  try {
    for (const [prefix, tail, other] of revisions) {
      const sources = { [entry]: source(prefix, tail, other) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("pick", 2), Number(tail));
          assert.equal(guest.call("first", null), 42);
          assert.equal(guest.call("sum_alias", 1), 40);
          assert.equal(guest.call("from_dep", 2), 3);
          if (other.includes("div")) {
            assert.throws(() => guest.call("unrelated", null), WebAssembly.RuntimeError);
          } else {
            assert.equal(guest.call("unrelated", null), Number(other));
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
