import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `const merge = func (dst: Array U32) -> (src: Array U32) -> (left: U32) -> (mid: U32) -> (right: U32): Unit => return do:
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

function expected(input: number[], dst: number[], left: number, mid: number, right: number) {
  let i = left;
  let j = (mid + 1) >>> 0;
  let k = left;
  while (i <= mid && j <= right) {
    if (j >= input.length || i >= input.length || k >= dst.length) break;
    const one = input[j];
    const two = input[i];
    if (one < two) {
      dst[k] = one;
      j = (j + 1) >>> 0;
    } else {
      dst[k] = two;
      i = (i + 1) >>> 0;
    }
    k = (k + 1) >>> 0;
  }
  return Uint32Array.from(dst);
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`checked merge loops preserve aliases ties skipped accesses and trap prefixes (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-merge-loops-" });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0], entry, stdRoot,
      prelude: `${stdRoot}/prelude.blot`, cacheDirectory: false, codegenTier,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
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
          for (const [left, mid, right] of [[0, 5, 11], [2, 5, 11], [12, 5, 0xffffffff], [0, 5, 5], [0xffffffff, 5, 11]]) {
            await call("reset");
            assert.deepEqual(await call("run", new Uint32Array([left, mid, right])), expected(values, Array(12).fill(99), left, mid, right));
          }
          const alias = [1, 3, 5, 2, 4, 6];
          assert.deepEqual(await call("alias"), expected(alias, alias, 0, 2, 5));
          assert.deepEqual(await call("ties"), new Uint32Array([2, 2, 2, 99, 99, 99]));
          await call("reset");
          await assert.rejects(() => call("short_target"), WebAssembly.RuntimeError);
          assert.deepEqual(await call("read_tiny"), new Uint32Array([1, 2, 3]));
          await call("reset");
          await assert.rejects(() => call("run", new Uint32Array([0, 5, 12])), WebAssembly.RuntimeError);
          assert.deepEqual(await call("read"), expected(values, Array(12).fill(99), 0, 5, 12));
          await call("reset");
          assert.deepEqual(await call("run", new Uint32Array([0, 0xffffffff, 0])), expected(values, Array(12).fill(99), 0, 0xffffffff, 0));
        } finally { guest.dispose(); }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
