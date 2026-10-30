import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;
const program = `import * as iter from "std/iter"
type Log is data = #Log {calls: U32, trace: U32}
const sum = iter.fold_left add 0
const biased = iter.fold_left (func total => return func value => return total + value + 3) 10
const add_float = func (total: F32) => return func (value: F32) => return @f32.add total value
const sum_float = iter.fold_left add_float 1.25
const append = func values => return func value => return [...values, value]
const collect = iter.fold_left append [100]
const collect_float = iter.fold_left append [1.25]
const collect_refs = iter.fold_left (func values => return func value => return [...values, #[value, value + 1]]) [#[100, 101]]
const traced_add = func total => return func value => return do:
  use log <- @state.get #Log
  use @state.set (#Log {calls: log.calls + 1, trace: log.trace * 31 + value + 1})
  return total + value
const traced_sum = iter.fold_left traced_add 0
entry const pure = func count => return sum (iter.range 0 count)
entry const alias = func count => return do:
  let reduce = sum
  return reduce (iter.range 0 count)
entry const capture = func count => return biased (iter.range 0 count)
entry const floating = func count => return sum_float (iter.map (func value => return @u32.to_f32 value) (iter.range 0 count))
entry const references = func count => return Array.from_list (collect (iter.range 0 count))
entry const pointer_values = func count => return Array.from_list (collect (iter.map (func value => return value + 65536) (iter.range 0 count)))
entry const reference_floats = func count => return Array.from_list (collect_float (iter.map (func value => return @u32.to_f32 value) (iter.range 0 count)))
entry const reference_rows = func count => return do:
  let values = collect_refs (iter.range 0 count)
  let pressure = @array.fill 2048 99
  let total = 0
  for value in values:
    total := self + value[0] + value[1]
  return total + pressure[2047] - 99
entry const effects = func count => return do:
  let (log, answer) = @state.run (#Log {calls: 0, trace: 0}) (func () => return traced_sum (iter.range 0 count))
  return #[log.calls, log.trace, answer]
const event = func value => return do:
  use log <- @state.get #Log
  use @state.set (#Log {calls: log.calls + 1, trace: log.trace * 31 + value})
  return value
const apply = func callback => return func first => return func second => return callback first second
const selected = apply add
entry const argument_order = func seed => return do:
  let (log, answer) = @state.run (#Log {calls: 0, trace: 0}) (func () => return do:
    use first <- event seed
    use second <- event (seed + 1)
    return selected first second)
  return #[log.calls, log.trace, answer]
`;

Deno.test("evaluated named calls preserve captured values scalar signatures effects and argument order in both tiers", async () => {
  await compileAndRun(program, (guest) => {
    const call = (name: string, count: number) => {
      try {
        return guest.call(name, count);
      } catch (cause) {
        throw new Error(`${name}(${count}) trapped`, { cause });
      }
    };
    for (const count of [0, 1, 2, 3, 80, 81, 82, 245, 4096]) {
      const expected = (count * (count - 1) / 2) >>> 0;
      assert.equal(call("pure", count), expected);
      assert.equal(call("alias", count), expected);
      assert.equal(call("capture", count), expected + 3 * count + 10);
      assert.deepEqual(
        call("references", count),
        Uint32Array.from([100, ...Array.from({ length: count }, (_, i) => i)]),
      );
      assert.deepEqual(
        call("pointer_values", count),
        Uint32Array.from([
          100,
          ...Array.from({ length: count }, (_, i) => i + 65536),
        ]),
      );
      assert.deepEqual(
        call("reference_floats", count),
        Float32Array.from([
          1.25,
          ...Array.from({ length: count }, (_, i) => i),
        ]),
      );
      assert.equal(call("reference_rows", count), 201 + count * count);
      let trace = 0, floating = Math.fround(1.25);
      for (let value = 0; value < count; value++) {
        trace = (Math.imul(trace, 31) + value + 1) >>> 0;
        floating = Math.fround(floating + value);
      }
      assert.equal(call("floating", count), floating);
      assert.deepEqual(
        call("effects", count),
        Uint32Array.from([count, trace, expected]),
      );
    }
    for (const seed of [0, 1, 37, 4096]) {
      assert.deepEqual(
        call("argument_order", seed),
        Uint32Array.from([2, seed * 31 + seed + 1, seed * 2 + 1]),
      );
    }
    const warm = guest.memoryBytes();
    for (let repeat = 0; repeat < 12; repeat++) {
      assert.equal(guest.call("pure", 4096), 4096 * 4095 / 2);
    }
    assert.equal(guest.memoryBytes(), warm);
  }, { stdRoot });
});

Deno.test("optimized evaluated folds remove per-step adapter allocations", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-evaluated-budget-",
  });
  const entry = `${directory}/main.blot`;
  try {
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0] ??
        new URL("../zig-out/bin/blotc", import.meta.url).pathname,
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      codegenTier: "optimized",
      codegenWorkers: 1,
      cacheDirectory: false,
    });
    try {
      const built = await compiler.build({
        sources: {
          [entry]: `import * as iter from "std/iter"
const sum = iter.fold_left add 0
entry const range = func count => return sum (iter.range 0 count)
entry const mapped = func count => return sum (iter.map (func value => return value + 1) (iter.range 0 count))
entry const filtered = func count => return sum (iter.filter (func value => return value % 2 == 0) (iter.range 0 count))
entry const taken = func count => return sum (iter.take (count / 2) (iter.range 0 count))
entry const probe = func (seed: U32) => return #[seed]
`,
        },
      });
      assert(built.success, JSON.stringify(built));
      for (const count of [0, 4096]) {
        const half = Math.floor(count / 2);
        for (
          const [name, expected] of [
            ["range", count * (count - 1) / 2],
            ["mapped", count * (count + 1) / 2],
            ["filtered", half * (half - 1)],
            ["taken", half * (half - 1) / 2],
          ] as const
        ) {
          const traffic = observeGuestAllocations(built.bytes, [[
            name,
            count,
            expected >>> 0,
          ]]);
          assert.equal(
            traffic.rounded_allocation_bytes,
            0,
            `${name}(${count})`,
          );
        }
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("retained evaluated captures preserve static sharing after edits and keep scalar call reuse", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-static-sharing-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/dep.blot`;
  // Keep independent producer queries while their selected callback bodies
  // remain small enough to inline with their evaluator-owned captures.
  const aliases = Array.from(
    { length: 33 },
    (_, index) =>
      `  let copy_${index} = ${index ? `copy_${index - 1}` : "value"}`,
  ).join("\n");
  const library = (values: readonly number[]) =>
    `const factory = func values => return func (index: U32) => return values[@u32.rem index 2]
const stored = factory #[${values.join(", ")}]
const add = func amount => return func value => return @u32.add amount value
const biased = add 8
const read = func (value: U32) => return do:
${aliases}
  return stored copy_32
const scalar = func (value: U32) => return do:
${aliases}
  return biased copy_32
`;
  const source = (offset: number) =>
    `import {read, stored, scalar} from "./dep"
entry const left = func (value: U32) => return read value
entry const right = func (value: U32) => return stored (@u32.add value ${offset})
entry const stable = func (value: U32) => return scalar value
`;
  try {
    await Deno.writeTextFile(entry, source(1));
    await Deno.writeTextFile(producer, library([41, 7]));
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0] ??
          new URL("../zig-out/bin/blotc", import.meta.url).pathname,
        entry,
        prelude: null,
        codegenTier,
        codegenWorkers: 1,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [revision, [offset, values]] of ([
            [1, [41, 7]],
            [2, [41, 7]],
            [2, [43, 11]],
            [1, [41, 7]],
          ] as const).entries()
        ) {
          const sources = {
            [entry]: source(offset),
            [producer]: library(values),
          };
          const built = await retained.build({ sources });
          assert(built.success, JSON.stringify(built));
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(expected.success, JSON.stringify(expected));
            assert.deepEqual(
              built.bytes,
              expected.bytes,
              `${codegenTier}/${revision}`,
            );
          } finally {
            await fresh.dispose();
          }
          if (revision === 1) {
            const backend = built.stats.backend;
            assert(
              backend && typeof backend === "object" && !Array.isArray(backend),
            );
            assert(
              typeof backend.reused_named === "number" &&
                backend.reused_named > 0,
              JSON.stringify(backend),
            );
          }
          const guest = await instantiateGuest(built.bytes);
          try {
            for (const value of [0, 1, 2, 3, 99]) {
              assert.equal(guest.call("left", value), values[value % 2]);
              assert.equal(
                guest.call("right", value),
                values[(value + offset) % 2],
              );
              assert.equal(guest.call("stable", value), value + 8);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
