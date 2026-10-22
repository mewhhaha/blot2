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
    break 999
  let total = 0
  for index in 0..count:
    let discarded = @array.generate 4096 (fn value => value + index)
    total := self + first rest.next
  break first saved + first alias.next + total
entry const references = fn count => do:
  let values = #[#[7, 8], #[9], #[10, 11, 12]]
  let total = 0
  for value in iter.take count (iter.map identity values):
    let garbage = @array.generate 8192 identity
    total := self + value.length + value[0]
  break total
type Choice is data = #Present (Array U32, U32) | #Absent
entry const old_alias = fn seed => do:
  let saved = #Present (#[seed], seed + 1)
  let result = do:
    if seed == 0:
      break #Absent
    break saved
  let #Present (values, _) = saved else:
    break 999
  let garbage = @array.generate 8192 identity
  break case result of
    #Present (_, value) => values[0] + value
    #Absent => values[0] + 100
entry const empty = fn count => do:
  let source = iter.range 0 count
  let stored = #[source.next, (iter.range 0 0).next]
  break first stored[0] + first stored[1]
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
  break total
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

Deno.test("private child state keeps chained forks saved values and window snapshots across pressure", async () => {
  await compileAndRun(
    `
import * as iter from "std/iter"
const head = fn values => @cursor.value (@list.cursor values)
const third = fn values => @cursor.value (@cursor.advance (@cursor.advance (@list.cursor values)))
entry const chained = fn count => do:
  let cursor = iter.enumerate (iter.take (count / 2) (iter.map (fn value => value + 7) (iter.filter (fn value => value % 2 == 0) (iter.range 0 count))))
  let saved = cursor.next
  let #Some ((index, first), rest) = saved else:
    break 999
  let total = 0
  for (_, value) in rest:
    let garbage = @array.generate 8192 identity
    total := self + value
  let #Some ((_, again), _) = cursor.next else:
    break 999
  break index + first + again + total
entry const references = fn (seed: U32) => do:
  let values = @array.generate 4 (fn index => #[seed + index, index])
  let cursor = iter.take 3 (iter.filter (fn (value: Array U32) => value.length == 2) (iter.map identity values))
  let saved = cursor.next
  let #Some (first, rest) = saved else:
    break 999
  let total = 0
  for value in rest:
    let garbage = @array.generate 8192 identity
    total := self + value[0] + value.length
  let #Some (again, _) = cursor.next else:
    break 999
  break total + first[0] + first.length + again[0] + again.length
entry const windows = fn count => do:
  let cursor = iter.windows 3 (iter.range 0 count)
  let saved = cursor.next
  let #Some (first, rest) = saved else:
    break 999
  let total = 0
  for window in rest:
    let garbage = @array.generate 8192 identity
    total := self + head window
  let #Some (second, _) = rest.next else:
    break head first + total + third first + 100
  break third first + head second + total
`,
    (guest) => {
      for (const count of [0, 1, 2, 3, 4, 17, 65]) {
        const length = Math.floor(count / 2);
        let chained = 999;
        if (length !== 0) chained = length * (length + 6) + 7;
        assert.equal(guest.call("chained", count), chained);
        let windows = 999;
        if (count === 3) windows = 102;
        if (count > 3) windows = 3 + (count - 3) * (count - 2) / 2;
        assert.equal(guest.call("windows", count), windows);
      }
      for (const seed of [1, 7, 41]) {
        assert.equal(guest.call("references", seed), 4 * seed + 11);
      }
    },
    { stdRoot },
  );
});

Deno.test("private scalar callbacks retain conditional values reference pairs and independent replay under pressure", async () => {
  await compileAndRun(
    `
import * as iter from "std/iter"
const sum_pair = fn total => fn pair => do:
  let (index, value) = pair
  if index % 2 == 0:
    break total + value * 3 + index
  break total + value
entry const conditional = fn count => iter.fold_left sum_pair 0 (iter.enumerate (iter.range 0 count))
entry const replay = fn count => do:
  let cursor = iter.enumerate (iter.range 0 count)
  let saved = cursor.next
  let total = 0
  for repeat in 0..3:
    total := self + iter.fold_left sum_pair 0 cursor
    let garbage = @array.generate 8192 identity
  let #Some ((index, value), rest) = saved else:
    break total + 999
  let #Some ((again, second), _) = rest.next else:
    break total + index + value + 100
  break total + index + value + again + second
entry const references = fn (seed: U32) => do:
  let values = @array.generate 4 (fn index => #[seed + index, index])
  let cursor = iter.zip values (iter.range 0 4)
  let saved = cursor.next
  let total = 0
  for repeat in 0..3:
    total := self + iter.fold_left (fn accumulator => fn pair => do:
      let (values, index) = pair
      break accumulator + values.length + values[0] + index) 0 cursor
    let garbage = @array.generate 8192 identity
  let #Some ((first, index), _) = saved else:
    break 999
  break total + first.length + first[0] + index
entry const floats = fn seed => iter.fold_left (fn total => fn pair => do:
  let (index, value) = pair
  if index % 2 == 0:
    break total + value
  break total - value) seed (iter.enumerate #[1.5, 2.5, 3.5, 4.5])
`,
    (guest) => {
      for (const count of [0, 1, 2, 3, 17, 65]) {
        let expected = 0;
        for (let index = 0; index < count; index++) {
          if (index % 2 === 0) expected += index * 4;
          else expected += index;
        }
        assert.equal(guest.call("conditional", count), expected);
        let replay = expected * 3 + 2;
        if (count === 0) replay = 999;
        if (count === 1) replay = 100;
        assert.equal(guest.call("replay", count), replay);
      }
      for (const seed of [1, 7, 41]) {
        assert.equal(guest.call("references", seed), 13 * seed + 62);
      }
      assert.equal(guest.call("floats", 0), -2);
      assert.equal(guest.call("floats", 7), 5);
    },
    { stdRoot },
  );
});

Deno.test("private scalar callback edits and restored checkpoints match fresh bodies in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-private-consumer-",
  });
  const entry = `${directory}/main.blot`;
  const helper = `${directory}/consumer.blot`;
  const program = `import * as iter from "std/iter"
import * as consumer from "./consumer"
entry const run = fn count => iter.fold_left consumer.sum 0 (iter.enumerate (iter.range 0 count))
`;
  const sources = (factor: number) => ({
    [entry]: program,
    [helper]: `const sum = fn total => fn pair => do:
  let (index, value) = pair
  if index % 2 == 0:
    break total + value * ${factor} + index
  break total + value * ${factor}
`,
  });
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
      try {
        for (const factor of [3, 5, 3]) {
          const built = await retained.build({ sources: sources(factor) });
          const fresh = await createZigProjectCompiler(options);
          try {
            const ordinary = await fresh.build({ sources: sources(factor) });
            assert(
              built.success && ordinary.success,
              JSON.stringify({ built, ordinary }),
            );
            assert.deepEqual(built.bytes, ordinary.bytes);
            const guest = await instantiateGuest(built.bytes);
            try {
              for (const count of [0, 1, 2, 17, 65]) {
                let expected = factor * count * (count - 1) / 2;
                for (let index = 0; index < count; index += 2) {
                  expected += index;
                }
                assert.equal(guest.call("run", count), expected >>> 0);
              }
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
          if (checkpoint === undefined) {
            checkpoint = await retained.exportCheckpoint();
          }
        }
      } finally {
        await retained.dispose();
      }
      const resumed = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      const fresh = await createZigProjectCompiler(options);
      try {
        const built = await resumed.build({ sources: sources(5) });
        const ordinary = await fresh.build({ sources: sources(5) });
        assert(
          built.success && ordinary.success,
          JSON.stringify({ built, ordinary }),
        );
        assert.deepEqual(built.bytes, ordinary.bytes);
      } finally {
        await resumed.dispose();
        await fresh.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
