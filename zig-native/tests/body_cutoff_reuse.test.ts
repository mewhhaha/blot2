import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;
const stdRoot = `${repo}std`;

// Body edits with unchanged types still change values, demand control flow
// and effect traces. Semantic receipts may survive; executable callers must
// follow the current bodies exactly like fresh builds.
Deno.test("body edits with unchanged interfaces update executable callers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-cutoff-" });
  const entry = `${directory}/main.blot`;
  const options = { executable, entry, prelude, stdRoot };
  const variants = {
    helper: "x + 1",
    pick: "if flag then @demand value else 7",
    bump: "use State.set U32 (old + 1)",
  };
  const source = (edit: Partial<typeof variants>) => {
    const v = { ...variants, ...edit };
    return `type State a is effect = { get: Unit -> a, set: a -> Unit }
const state = @effect.state (State.get U32) (State.set U32) 0
const helper = fn (x: U32) -> U32 => ${v.helper}
const pick = fn (flag: Bool) => fn ~(value: U32) => ${v.pick}
const bump = fn () => do:
  use old <- State.get U32 ()
  ${v.bump}
  return old
entry const via_helper = fn (x: U32) -> U32 => helper (helper x)
entry const lazy = fn (n: U32) -> U32 => pick (n == 0) (40 + 2)
entry const effects = fn () -> U32 => do:
  let (final, first) = do state:
    use a <- bump ()
    use b <- bump ()
    return a + b
  return final + first
entry const unrelated = fn (x: U32) -> U32 => do:
  let add = fn (y: U32) => y + x
  return add 3
`;
  };
  const twice = "use State.set U32 (old + 1)\n  use State.set U32 (old + 2)";
  const revisions: [
    Partial<typeof variants>,
    number,
    [number, number],
    number,
  ][] = [
    [{}, 1, [42, 7], 3],
    [{ helper: "x + 2" }, 2, [42, 7], 3],
    [{ helper: "2 + x" }, 2, [42, 7], 3],
    [{ pick: "if flag then 7 else @demand value" }, 1, [7, 42], 3],
    [{ bump: twice }, 1, [42, 7], 6],
    [{ helper: "x +" }, 0, [0, 0], 0],
    [{}, 1, [42, 7], 3],
  ];
  const retained = await createZigProjectCompiler(options);
  let hits = 0;
  try {
    for (const [edit, step, [lazy0, lazy1], effects] of revisions) {
      const sources = { [entry]: source(edit) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert.equal(result.success, expected.success, JSON.stringify(edit));
        if (!result.success && !expected.success) {
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes, JSON.stringify(edit));
        assert.equal(
          result.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        hits += (result.stats.refinements as Record<string, number>).hits;
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("via_helper", 10), 10 + 2 * step);
          assert.equal(guest.call("lazy", 0), lazy0);
          assert.equal(guest.call("lazy", 1), lazy1);
          assert.equal(guest.call("effects", null), effects);
          assert.equal(guest.call("unrelated", 4), 7);
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
    assert(hits > 0, "no refinement receipt replayed in the edited module");
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

// Body edits in public examples, including ones that change a module's size,
// keep retained output byte-identical to fresh builds through edit, revert,
// failure and re-edit.
const edits: [string, string, string][] = [
  ["ecs", "total := self + x + y", "total := self + y + x"],
  ["ecs", "x: x + vx * seconds", "x: x + vx * seconds + 0.0"],
  ["lists", "[1, 2, 3]", "[1, 2, 3, 4]"],
  [
    "syntax",
    "if left then @demand right else #False",
    "if left then (@demand right) && left else #False",
  ],
  ["monads", "#Some 40", "#Some (40 + 0)"],
];
Deno.test("body edits in public examples match fresh builds", async () => {
  const hits: Record<string, number> = {};
  for (const [name, search, replace] of edits) {
    const entry = `${repo}examples/${name}.blot`;
    const original = await Deno.readTextFile(entry);
    const edited = original.replaceAll(search, replace);
    assert.notEqual(edited, original, name);
    const broken = `${original}\nconst broken_body_probe: U32 = #Wrong\n`;
    const options = { executable, entry, prelude, stdRoot };
    const retained = await createZigProjectCompiler(options);
    try {
      for (const text of [original, edited, original, broken, edited]) {
        const sources = { [entry]: text };
        const result = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const expected = await fresh.build({ sources });
          assert.equal(result.success, expected.success, name);
          if (!result.success && !expected.success) {
            assert.deepEqual(result.diagnostics, expected.diagnostics, name);
            continue;
          }
          assert(result.success && expected.success, name);
          assert.deepEqual(result.bytes, expected.bytes, name);
          assert.equal(
            result.stats.nativeWorkSteps,
            expected.stats.nativeWorkSteps,
            name,
          );
          const key = `${name}:${replace}`;
          hits[key] = (hits[key] ?? 0) +
            (result.stats.refinements as Record<string, number>).hits;
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  }
  assert(hits["ecs:total := self + y + x"] > 0, JSON.stringify(hits));
});
