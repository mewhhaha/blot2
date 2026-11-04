import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source =
  `const merge = func (dst: Array U32) -> (src: Array U32) -> (left: U32) -> (mid: U32) -> (right: U32): Unit => return do:
  let i = left
  let j = @u32.add mid 1
  let k = left
  for ever:
    if @u32.lt mid i:
      break
    if @u32.lt right j:
      break
    if @u32.lt src[j] src[i]:
      dst[k] := src[j]
      j := @u32.add self 1
    else:
      dst[k] := src[i]
      i := @u32.add self 1
    k := @u32.add self 1
  return ()
const src: Array U32 = #[1, 3, 5, 7, 9, 13, 2, 4, 6, 8, 10, 12]
const dst: Array U32 = @array.fill 12 99
const tiny: Array U32 = @array.fill 3 99
entry const reset = func () => return do:
  let target = dst
  let small = tiny
  for index in 0 .. 12:
    target[index] := 99
  for index in 0 .. 3:
    small[index] := 99
  return ()
entry const run = func (bounds: Array U32): Array U32 => return do:
  merge dst src bounds[0] bounds[1] bounds[2]
  return @storage.copy dst
entry const short_target = func (): Unit => return merge tiny src 0 5 11
entry const read = func (): Array U32 => return @storage.copy dst
entry const read_tiny = func (): Array U32 => return @storage.copy tiny
entry const alias = func (): Array U32 => return do:
  let rows: Array U32 = #[1, 3, 5, 2, 4, 6]
  merge rows rows 0 2 5
  return rows
entry const ties = func (): Array U32 => return do:
  let rows: Array U32 = #[2, 2, 2, 2, 2, 2]
  let result: Array U32 = @array.fill 6 99
  merge result rows 0 2 5
  return result
`;

const mergeBody = source.slice(0, source.indexOf("\nconst src:"));
const offsetMerge = mergeBody.replace("const merge =", "const merge_offset =")
  .replace("(right: U32): Unit", "(right: U32) -> (offset: U32): Unit")
  .replace("let k = left", "let k = offset");
const separateMerge = mergeBody.replace(
  "const merge =",
  "const merge_separate =",
)
  .replace("(src: Array U32)", "(one: Array U32) -> (two: Array U32)")
  .replaceAll("src[j]", "one[j]").replaceAll("src[i]", "two[i]");
const cursorMerge = offsetMerge.replace(
  "const merge_offset =",
  "const merge_positions =",
)
  .replace("): Unit", "): U32")
  .replace(
    "return ()",
    "return @u32.add (@u32.mul i 65536) (@u32.add (@u32.mul j 256) k)",
  );
const ranges = offsetMerge + "\n" + separateMerge + "\n" + cursorMerge + `
const wide_src: Array U32 = @array.generate 48 (func index => return do:
  if @u32.lt index 24:
    return @u32.mul index 2
  return @u32.add (@u32.mul (@u32.sub index 24) 2) 1)
const wide_dst: Array U32 = @array.fill 48 99
const late_src: Array U32 = @array.generate 48 (func index => return do:
  if @u32.lt index 24:
    return @u32.add index 100
  return @u32.sub index 24)
const left_rows: Array U32 = @array.generate 32 (func index => return @u32.mul index 2)
const right_rows: Array U32 = @array.generate 64 (func index => return do:
  if @u32.lt index 32:
    return 0
  return @u32.add (@u32.mul (@u32.sub index 32) 2) 1)
const separate_dst: Array U32 = @array.fill 64 99
entry const wide_reset = func () => return do:
  let target = wide_dst
  let other = separate_dst
  for index in 0 .. 48:
    target[index] := 99
  for index in 0 .. 64:
    other[index] := 99
  return ()
entry const wide = func (bounds: Array U32): Array U32 => return do:
  let target: Array U32 = @array.fill bounds[3] 99
  merge_offset target wide_src bounds[0] bounds[1] bounds[2] bounds[4]
  return target
entry const wide_store_trap = func (offset: U32): Unit => return merge_offset wide_dst wide_src 0 23 47 offset
entry const wide_source_trap = func (): Unit => return merge wide_dst late_src 0 23 63
entry const wide_read = func (): Array U32 => return @storage.copy wide_dst
entry const wide_alias = func (): Array U32 => return do:
  let rows = @storage.copy wide_src
  merge rows rows 0 23 47
  return rows
entry const wide_ties = func (right: U32): Array U32 => return do:
  let rows: Array U32 = @array.fill 48 7
  let target: Array U32 = @array.fill 24 99
  merge target rows 0 23 right
  return target
entry const separate = func (): Array U32 => return do:
  let target: Array U32 = @array.fill 63 99
  merge_separate target right_rows left_rows 0 31 63
  return target
entry const separate_trap = func (): Unit => return merge_separate separate_dst right_rows left_rows 0 39 63
entry const separate_read = func (): Array U32 => return @storage.copy separate_dst
entry const positions = func (bounds: Array U32): U32 => return do:
  let target: Array U32 = @array.fill 64 99
  if @u32.eq bounds[5] 1:
    return merge_positions target late_src bounds[0] bounds[1] bounds[2] bounds[4]
  if @u32.eq bounds[5] 2:
    let equal: Array U32 = @array.fill 48 7
    return merge_positions target equal bounds[0] bounds[1] bounds[2] bounds[4]
  if @u32.eq bounds[5] 3:
    let rows = @storage.copy wide_src
    return merge_positions rows rows bounds[0] bounds[1] bounds[2] bounds[4]
  return merge_positions target wide_src bounds[0] bounds[1] bounds[2] bounds[4]
`;

function expected(
  input: number[],
  dst: number[],
  left: number,
  mid: number,
  right: number,
) {
  return expectedSeparate(input, input, dst, left, mid, right, left);
}
function expectedSeparate(
  one: number[],
  two: number[],
  dst: number[],
  left: number,
  mid: number,
  right: number,
  offset: number,
  positions: number[] = [],
) {
  let i = left;
  let j = (mid + 1) >>> 0;
  let k = offset;
  while (i <= mid && j <= right) {
    if (j >= one.length || i >= two.length || k >= dst.length) break;
    const first = one[j];
    const second = two[i];
    if (first < second) {
      dst[k] = first;
      j = (j + 1) >>> 0;
    } else {
      dst[k] = second;
      i = (i + 1) >>> 0;
    }
    k = (k + 1) >>> 0;
  }
  positions.push(i, j, k);
  return Uint32Array.from(dst);
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`checked merge loops preserve aliases ties skipped accesses and trap prefixes (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-merge-loops-" });
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
      const result = await compiler.build({
        sources: { [entry]: source + ranges },
      });
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(counters.scoped_merge_loops > 0, JSON.stringify(counters));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = async (name: string, input: unknown = null) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          const values = [1, 3, 5, 7, 9, 13, 2, 4, 6, 8, 10, 12];
          for (
            const [left, mid, right] of [
              [0, 5, 11],
              [2, 5, 11],
              [12, 5, 0xffffffff],
              [0, 5, 5],
              [0xffffffff, 5, 11],
            ]
          ) {
            await call("reset");
            assert.deepEqual(
              await call("run", new Uint32Array([left, mid, right])),
              expected(values, Array(12).fill(99), left, mid, right),
            );
          }
          const alias = [1, 3, 5, 2, 4, 6];
          assert.deepEqual(
            await call("alias"),
            expected(alias, alias, 0, 2, 5),
          );
          assert.deepEqual(
            await call("ties"),
            new Uint32Array([2, 2, 2, 99, 99, 99]),
          );
          await call("reset");
          await assert.rejects(
            () => call("short_target"),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(await call("read_tiny"), new Uint32Array([1, 2, 3]));
          await call("reset");
          await assert.rejects(
            () => call("run", new Uint32Array([0, 5, 12])),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(
            await call("read"),
            expected(values, Array(12).fill(99), 0, 5, 12),
          );
          await call("reset");
          assert.deepEqual(
            await call("run", new Uint32Array([0, 0xffffffff, 0])),
            expected(values, Array(12).fill(99), 0, 0xffffffff, 0),
          );
          const wide = Array.from({ length: 48 }, (_, i) => {
            if (i < 24) return i * 2;
            return (i - 24) * 2 + 1;
          });
          for (
            const [left, mid, right, capacity, offset] of [
              [0, 23, 47, 47, 0],
              [0, 23, 47, 48, 0],
              [0, 23, 47, 48, 1],
              [2, 23, 47, 48, 2],
              [0, 7, 15, 15, 0],
              [0, 6, 14, 15, 0],
              [48, 23, 0xffffffff, 1, 0],
              [0, 23, 23, 1, 0],
            ]
          ) {
            assert.deepEqual(
              await call(
                "wide",
                new Uint32Array([left, mid, right, capacity, offset]),
              ),
              expectedSeparate(
                wide,
                wide,
                Array(capacity).fill(99),
                left,
                mid,
                right,
                offset,
              ),
            );
          }
          const aliases = wide.slice();
          assert.deepEqual(
            await call("wide_alias"),
            expected(aliases, aliases, 0, 23, 47),
          );
          assert.deepEqual(
            await call("wide_ties", 47),
            new Uint32Array(24).fill(7),
          );
          assert.deepEqual(
            await call("wide_ties", 0xffffffff),
            new Uint32Array(24).fill(7),
          );
          for (const offset of [2, 0xfffffffe, 0xffffffff]) {
            await call("wide_reset");
            await assert.rejects(
              () => call("wide_store_trap", offset),
              WebAssembly.RuntimeError,
            );
            assert.deepEqual(
              await call("wide_read"),
              expectedSeparate(
                wide,
                wide,
                Array(48).fill(99),
                0,
                23,
                47,
                offset,
              ),
            );
          }
          await call("wide_reset");
          await assert.rejects(
            () => call("wide_source_trap"),
            WebAssembly.RuntimeError,
          );
          const late = Array.from({ length: 48 }, (_, i) => {
            if (i < 24) return i + 100;
            return i - 24;
          });
          assert.deepEqual(
            await call("wide_read"),
            expected(late, Array(48).fill(99), 0, 23, 63),
          );
          const left = Array.from({ length: 32 }, (_, i) => i * 2);
          const right = Array.from({ length: 64 }, (_, i) => {
            if (i < 32) return 0;
            return (i - 32) * 2 + 1;
          });
          assert.deepEqual(
            await call("separate"),
            expectedSeparate(right, left, Array(63).fill(99), 0, 31, 63, 0),
          );
          await call("wide_reset");
          await assert.rejects(
            () => call("separate_trap"),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(
            await call("separate_read"),
            expectedSeparate(right, left, Array(64).fill(99), 0, 39, 63, 0),
          );
          for (
            const [start, mid, end, offset, kind] of [
              [0, 23, 47, 0, 0],
              [0, 23, 47, 0, 1],
              [0, 23, 47, 0, 2],
              [2, 23, 47, 5, 0],
              [0, 23, 47, 0, 3],
              [0, 23, 47, 1, 3],
            ]
          ) {
            let input = wide.slice();
            if (kind === 1) input = late.slice();
            if (kind === 2) input = Array(48).fill(7);
            let target = Array(64).fill(99);
            if (kind === 3) target = input;
            const cursors: number[] = [];
            expectedSeparate(
              input,
              input,
              target,
              start,
              mid,
              end,
              offset,
              cursors,
            );
            assert.equal(
              await call(
                "positions",
                new Uint32Array([start, mid, end, 64, offset, kind]),
              ),
              (cursors[0] * 65536 + cursors[1] * 256 + cursors[2]) >>> 0,
            );
          }
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
