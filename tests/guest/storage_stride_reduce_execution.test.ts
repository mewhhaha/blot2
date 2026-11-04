import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const scan =
  `const scan = func (rows: Array U32) -> (bounds: Array U32): Array U32 => return do:
  let cursor = bounds[0]
  let limit = bounds[1]
  let last = bounds[2]
  let count = bounds[3]
  for ever:
    if @u32.lt limit cursor:
      break
    if @u32.eq rows[cursor] 1:
      last := cursor
      count := @u32.add self 1
    cursor := @u32.add self 2
  return #[cursor, last, count]
`;
const wrap = scan.replace("const scan =", "const scan_wrap =")
  .replace("@u32.add self 2", "@u32.add self 4294967295");
const zero = scan.replace("const scan =", "const scan_zero =")
  .replace("@u32.add self 2", "@u32.add self 0");
const source = scan + wrap + zero + `
const persisted: Array U32 = @array.generate 96 (func index => return @u32.rem index 2)
entry const local = func (bounds: Array U32): Array U32 => return do:
  let rows: Array U32 = @array.generate 96 (func index => return do:
    if @u32.eq bounds[4] 0:
      return 0
    if @u32.eq bounds[4] 1:
      return 1
    if @u32.eq (@u32.rem index 5) 0:
      return 1
    return 0)
  let alias = rows
  return scan alias bounds
entry const globals = func (bounds: Array U32): Array U32 => return scan persisted bounds
entry const public = func (input: Array U32): Array U32 => return scan input input
entry const wrapped = func (bounds: Array U32): Array U32 => return do:
  let rows: Array U32 = @array.fill 96 1
  return scan_wrap rows bounds
entry const zeroed = func (bounds: Array U32): Array U32 => return do:
  let rows: Array U32 = @array.fill 96 1
  return scan_zero rows bounds
entry const read = func (): Array U32 => return @storage.copy persisted
`;

function expected(rows: Uint32Array, bounds: number[], stride = 2) {
  let [cursor, limit, last, count] = bounds;
  let iterations = 0;
  while (cursor <= limit) {
    if (cursor >= rows.length) return null;
    if (rows[cursor] === 1) {
      last = cursor;
      count = (count + 1) >>> 0;
    }
    cursor = (cursor + stride) >>> 0;
    assert(++iterations <= 100, "test fixture must terminate");
  }
  return new Uint32Array([cursor, last, count]);
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`strided reductions preserve matches wrapping counters exits and checked fallbacks (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-stride-reduce-" });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(counters.scoped_stride_reductions > 0, JSON.stringify(counters));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = async (name: string, input: unknown = null) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          for (const kind of [0, 1, 2]) {
            const rows = Uint32Array.from({ length: 96 }, (_, index) => {
              if (kind === 0) return 0;
              if (kind === 1 || index % 5 === 0) return 1;
              return 0;
            });
            for (
              const bounds of [
                [0, 95, 7, 0],
                [3, 95, 0xffffffff, 0xfffffffe],
                [3, 17, 7, 4],
                [3, 15, 7, 4],
                [95, 95, 7, 4],
                [96, 95, 7, 4],
                [0xffffffff, 1, 7, 4],
                [0, 100, 7, 4],
                [94, 0xffffffff, 7, 4],
                [0xffffffff, 0xffffffff, 7, 4],
              ]
            ) {
              const scalar = expected(rows, bounds);
              const run = () =>
                call("local", new Uint32Array([...bounds, kind]));
              if (scalar === null) {
                await assert.rejects(run, WebAssembly.RuntimeError);
              } else assert.deepEqual(await run(), scalar);
            }
          }
          const persisted = Uint32Array.from({ length: 96 }, (_, i) => i % 2);
          for (
            const bounds of [[1, 95, 2, 1], [0, 100, 2, 1], [96, 95, 2, 1]]
          ) {
            const scalar = expected(persisted, bounds);
            const run = () => call("globals", new Uint32Array(bounds));
            if (scalar === null) {
              await assert.rejects(run, WebAssembly.RuntimeError);
            } else assert.deepEqual(await run(), scalar);
            assert.deepEqual(await call("read"), persisted);
          }
          const input = new Uint32Array([
            4,
            31,
            7,
            0xffffffff,
            ...Array(28).fill(1),
          ]);
          assert.deepEqual(
            await call("public", input),
            expected(input, [...input]),
          );
          for (const bounds of [[2, 20, 7, 0xfffffffe], [96, 95, 7, 1]]) {
            assert.deepEqual(
              await call("wrapped", new Uint32Array(bounds)),
              expected(new Uint32Array(96).fill(1), bounds, 0xffffffff),
            );
          }
          assert.deepEqual(
            await call("zeroed", new Uint32Array([96, 95, 7, 1])),
            new Uint32Array([96, 7, 1]),
          );
          await assert.rejects(
            () => call("zeroed", new Uint32Array([96, 100, 7, 1])),
            WebAssembly.RuntimeError,
          );
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
