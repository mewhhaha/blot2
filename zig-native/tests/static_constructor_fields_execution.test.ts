import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("private tagged steps preserve forks saved results reference fields and collection pressure", async () => {
  await compileAndRun(
    `
import * as iter from "std/iter"
const first = fn step => case step of
  #Some (value, _) => value
  #Nothing => 999
entry const forks = fn count => do:
  let cursor = iter.range 0 count
  let saved = cursor.next
  let alias = cursor
  let #Some (_, rest) = saved else:
    return 999
  let total = 0
  for index in 0..count:
    let discarded = @array.generate 4096 (fn value => value + index)
    total := self + first rest.next
  return first saved + first alias.next + total
entry const references = fn count => do:
  let values = #[#[7, 8], #[9], #[10, 11, 12]]
  let total = 0
  for value in iter.take count (iter.map identity values):
    let garbage = @array.generate 8192 identity
    total := self + value.length + value[0]
  return total
type Choice is data = #Present (Array U32, U32) | #Absent
entry const old_alias = fn seed => do:
  let saved = #Present (#[seed], seed + 1)
  let result = do:
    if seed == 0:
      return #Absent
    return saved
  let #Present (values, _) = saved else:
    return 999
  let garbage = @array.generate 8192 identity
  return case result of
    #Present (_, value) => values[0] + value
    #Absent => values[0] + 100
entry const empty = fn count => do:
  let source = iter.range 0 count
  let stored = #[source.next, (iter.range 0 0).next]
  return first stored[0] + first stored[1]
`,
    (guest) => {
      assert.equal(guest.call("forks", 0), 999);
      assert.equal(guest.call("forks", 20), 20);
      assert.equal(guest.call("references", 0), 0);
      assert.equal(guest.call("references", 3), 32);
      assert.equal(guest.call("old_alias", 0), 100);
      assert.equal(guest.call("old_alias", 7), 15);
      assert.equal(guest.call("empty", 0), 1998);
      assert.equal(guest.call("empty", 1), 999);
    },
    { stdRoot },
  );
});

Deno.test("static constructor facts survive retained edits and portable replay in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-static-constructor-",
  });
  const entry = `${directory}/main.blot`;
  const helper = `${directory}/cursor.blot`;
  const program = `import * as cursor from "./cursor"
entry const run = fn count => do:
  let total = 0
  for value in cursor.make count:
    total := self + value
  return total
`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0],
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        stdRoot,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      let checkpoint;
      const sources = (emptyFirst: boolean) => {
        let declarations =
          "type Sequence is data = #Running (U32, U32) | #Finished\n";
        if (emptyFirst) {
          declarations =
            "type Sequence is data = #Finished | #Running (U32, U32)\n";
        }
        return {
          [entry]: program,
          [helper]: declarations + `
const make = fn end => #Running (0, end)
const Sequence.iter = fn (cursor: Sequence) => cursor
const Sequence.next = fn (cursor: Sequence) => case cursor of
  #Finished => #Nothing
  #Running (value, end) => if value >= end then #Nothing
    else #Some (value, #Running (value + 1, end))
`,
        };
      };
      try {
        for (const emptyFirst of [false, false, true, false]) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const built = await retained.build({
              sources: sources(emptyFirst),
            });
            const ordinary = await fresh.build({
              sources: sources(emptyFirst),
            });
            assert(
              built.success && ordinary.success,
              JSON.stringify({ built, ordinary }),
            );
            assert.deepEqual(built.bytes, ordinary.bytes);
            const guest = await instantiateGuest(built.bytes);
            try {
              assert.equal(guest.call("run", 0), 0);
              assert.equal(guest.call("run", 63), 1953);
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
        checkpoint = await retained.exportCheckpoint();
      } finally {
        await retained.dispose();
      }
      const resumed = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      const fresh = await createZigProjectCompiler(options);
      try {
        const built = await resumed.build({ sources: sources(true) });
        const ordinary = await fresh.build({ sources: sources(true) });
        assert(
          built.success && ordinary.success,
          JSON.stringify({ built, ordinary }),
        );
        assert.deepEqual(built.bytes, ordinary.bytes);
        if (codegenTier === "optimized") {
          const optimization = built.stats.runtimeOptimization as Record<
            string,
            number
          >;
          assert(optimization.reused > 0, JSON.stringify(optimization));
        }
      } finally {
        await resumed.dispose();
        await fresh.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
