import { strict as assert } from "node:assert";
import { createCompiler, instantiateGuest } from "../../mod.ts";

Deno.test("retained code validates static capture graphs and per-body inline dependencies", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`, library = `${directory}/lib.blot`;
  const options = {
    entry,
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
  };
  const compiler = await createCompiler(options);
  const declarations = `
type Pack [unused, selected] is data = #Pack { unused: unused, selected: selected }
const identity = fn value => value
const packed = #Pack { unused: identity, selected: fn (value: U32) => value + 1 }
const invoke = fn callback => callback 1
const capture = fn packed => fn (value: U32) => invoke (fn extra => do:
  let #Pack { selected } = packed
  return selected (value + extra))
const work = fn (value: U32) => do:
  let total = 0
  for i in 0..value:
    total := total + capture packed i
  return total
const unrelated = 10
`;
  const main = `import * as lib from "./lib"
const offset = 10
entry const answer = fn (value: U32) => lib.work value + offset
`;
  try {
    for (
      const [lib, app, expected, reused] of [
        [declarations, main, 75, false],
        [declarations, main.replace("offset = 10", "offset = 11"), 76, true],
        [
          declarations.replace("unrelated = 10", "unrelated = 11"),
          main,
          75,
          true,
        ],
        [declarations.replace("value + 1", "value + 2"), main, 85, false],
        [declarations.replace("callback 1", "callback 2"), main, 85, false],
        [declarations.replace("value + 1", "missing"), main, null, false],
        [declarations, main, 75, false],
        [
          declarations.replace("unrelated = 10", "unrelated = 12"),
          main,
          75,
          true,
        ],
      ] as const
    ) {
      const sources = { [entry]: app, [library]: lib };
      const result = await compiler.build({ sources });
      if (expected === null) {
        assert.equal(result.success, false);
        continue;
      }
      assert(result.success, JSON.stringify(result));
      if (reused) {
        const counters = result.stats.backend as Record<string, number>;
        assert(counters.reused_named > 0, JSON.stringify(result.stats));
        assert.equal(counters.fresh_closures, 0, "Static closure was rebuilt");
        assert.equal(result.stats.attemptStats.reused_output, false);
      }
      const guest = await instantiateGuest(result.bytes);
      try {
        assert.equal(guest.call("answer", 10), expected);
      } finally {
        guest.dispose();
      }
      const fresh = await createCompiler(options);
      try {
        const rebuilt = await fresh.build({ sources });
        assert(rebuilt.success, JSON.stringify(rebuilt));
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

Deno.test("editing an unrelated function preserves callers of an inlined body", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`, library = `${directory}/lib.blot`;
  const options = {
    entry,
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
  };
  const compiler = await createCompiler(options);
  const lib =
    `const select = fn (a: Bool) => fn ~(b: U32) => if a then @demand b else 0
const work = fn (count: U32) => do:
  let total = 0
  for i in 0..count:
    total := total + select #True i
  return total
const unrelated = fn (x: U32) => x + 1
`;
  const main =
    'import * as lib from "./lib"\nentry const answer = fn (count: U32) => lib.work count\n';
  try {
    for (
      const [text, answer, reuse] of [
        [lib, 45, false],
        [lib.replace("x + 1", "x + 2"), 45, true],
        [
          lib.replace("then @demand b else 0", "then 0 else @demand b"),
          0,
          false,
        ],
        [lib, 45, false],
      ] as const
    ) {
      const sources = { [entry]: main, [library]: text };
      const result = await compiler.build({ sources });
      assert(result.success, JSON.stringify(result));
      if (reuse) {
        assert(
          (result.stats.backend as Record<string, number>).reused_named > 0,
          JSON.stringify(result.stats),
        );
      }
      const guest = await instantiateGuest(result.bytes);
      try {
        assert.equal(guest.call("answer", 10), answer);
      } finally {
        guest.dispose();
      }
      const fresh = await createCompiler(options);
      try {
        const rebuilt = await fresh.build({ sources });
        assert(rebuilt.success, JSON.stringify(rebuilt));
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
