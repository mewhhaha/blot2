import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const repo = new URL("../../", import.meta.url).pathname;
const prelude = `${repo}std/prelude.blot`;
const stdRoot = `${repo}std`;

// Literal edits in public examples, including effectful modules with
// operation witnesses, keep retained output byte-identical to fresh builds
// through edit, revert and a failing edit; unaffected bodies stay reusable.
const edits: [string, string, string][] = [
  ["scalar", "break 20", "break 21"],
  ["scalar", "@u32.add 20 21", "@u32.add 20 22"],
  ["ecs", "x: 10.0", "x: 11.0"],
  ["tags", "entry const answer: U32 = 20", "entry const answer: U32 = 21"],
  ["monads", "$Some 40", "$Some 41"],
  ["lists", "[1, 2, 3]", "[1, 2, 4]"],
  ["requests", "if value == 0", "if value == 1"],
  ["generic_effects", "reader 40", "reader 41"],
  ["host_io", "tick 41", "tick 42"],
  ["host_capabilities", "render_frame render 42", "render_frame render 43"],
];
Deno.test("literal edits in public examples match fresh builds and keep unaffected bodies", async () => {
  const reused: Record<string, number> = {};
  for (const [name, search, replace] of edits) {
    const entry = `${repo}examples/${name}.blot`;
    const original = await Deno.readTextFile(entry);
    const edited = original.replaceAll(search, replace);
    assert.notEqual(edited, original, name);
    const broken = `${original}\nconst broken_literal_probe: U32 = $Wrong\n`;
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
          const backend = result.stats.backend as Record<string, number>;
          reused[name] = (reused[name] ?? 0) + backend.reused_named +
            backend.reused_closures;
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  }
  // The effectful ecs module keeps unaffected bodies across its literal edit.
  assert(reused.ecs > 0, JSON.stringify(reused));
  assert(reused.scalar > 0, JSON.stringify(reused));
});

// A state provider's initial value, a reader witness and an unrelated literal
// change in one effectful module; executed results follow each revision.
Deno.test("state-provider and witness literal edits execute like fresh builds", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-literal-" });
  const entry = `${directory}/main.blot`;
  const options = { executable, entry, prelude: null };
  const source = (initial: number, read: number, other: number) =>
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
type Reader a is effect = { ask: Unit -> a }
const state = @effect.state (State.get U32) (State.set U32) ${initial}
const reader = func value => return @effect.provider (Reader.ask U32) (func () => return value)
const forty = reader ${read}
const other = ${other}
entry const stateful = func (step: U32) => return do:
  let (next, old) = do state:
    use old <- State.get U32 ()
    use State.set U32 (@u32.add old step)
    break old
  break @u32.add next old
entry const ask = func () => return do forty:
  use value <- Reader.ask U32 ()
  break @u32.add value 1
entry const plain = func (x: U32) => return @u32.add x 2
entry const unrelated = func () => return other
`;
  const revisions: [number, number, number][] = [
    [1, 40, 0],
    [1, 40, 1],
    [2, 40, 1],
    [2, 41, 1],
    [1, 40, 0],
  ];
  const retained = await createZigProjectCompiler(options);
  let reused = 0;
  try {
    for (const [initial, read, other] of revisions) {
      const sources = { [entry]: source(initial, read, other) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        assert.equal(
          result.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        const backend = result.stats.backend as Record<string, number>;
        reused += backend.reused_named + backend.reused_closures;
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("stateful", 5), 2 * initial + 5);
          assert.equal(guest.call("ask", null), read + 1);
          assert.equal(guest.call("plain", 3), 5);
          assert.equal(guest.call("unrelated", null), other);
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
