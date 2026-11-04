import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const marking =
  `const mark = func (rows: Array U32) -> (first: U32) -> (last: U32) -> (stride: U32): U32 => return do:
  let cursor = first
  for ever:
    if @u32.lt last cursor:
      break
    rows[cursor] := 305419896
    cursor := @u32.add self stride
  return cursor
`;
const literal = marking.replace("const mark =", "const mark_odd =")
  .replace("@u32.add self stride", "@u32.add self 2");
const source = marking + literal + `
const rows: Array U32 = @array.fill 96 9
entry const reset = func (): Unit => return do:
  let target = rows
  for index in 0 .. 96:
    target[index] := 9
  return ()
entry const run = func (bounds: Array U32): U32 => return mark rows bounds[0] bounds[1] bounds[2]
entry const read = func (): Array U32 => return @storage.copy rows
entry const odd = func (bounds: Array U32): U32 => return mark_odd rows bounds[0] bounds[1] 2
entry const same_start_and_stride = func (first: U32): U32 => return mark rows first 95 first
entry const local_run = func (bounds: Array U32) => return do:
  let target: Array U32 = @array.fill 96 9
  let alias = target
  let cursor = mark alias bounds[0] bounds[1] bounds[2]
  return target
entry const local_cursor = func (bounds: Array U32): U32 => return do:
  let target: Array U32 = @array.fill 96 9
  return mark target bounds[0] bounds[1] bounds[2]
entry const local_odd = func (bounds: Array U32) => return do:
  let target: Array U32 = @array.fill 96 9
  let cursor = mark_odd target bounds[0] bounds[1] 2
  return target
entry const local_odd_cursor = func (bounds: Array U32): U32 => return do:
  let target: Array U32 = @array.fill 96 9
  return mark_odd target bounds[0] bounds[1] 2
entry const local_same_start_and_stride = func (first: U32) => return do:
  let target: Array U32 = @array.fill 96 9
  let cursor = mark target first 95 first
  return target
entry const local_same_cursor = func (first: U32): U32 => return do:
  let target: Array U32 = @array.fill 96 9
  return mark target first 95 first
`;

function expected(first: number, last: number, stride: number) {
  const rows = new Uint32Array(96).fill(9);
  let cursor = first;
  let trapped = false;
  let iterations = 0;
  while (cursor <= last) {
    if (cursor >= rows.length) {
      trapped = true;
      break;
    }
    rows[cursor] = 0x12345678;
    cursor = (cursor + stride) >>> 0;
    assert(++iterations <= 100, "test fixture must terminate");
  }
  return { cursor, rows, trapped };
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`strided fills preserve cursor wrapping lazy exits and trap prefixes (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-stride-loops-" });
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
      assert.equal(counters.scoped_stride_reductions, 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = async (name: string, input: unknown = null) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          for (
            const [first, last, stride] of [
              [0, 95, 1],
              [4, 95, 3],
              [5, 93, 2],
              [95, 95, 1],
              [0, 0, 0xffffffff],
              [1, 1, 0xfffffffe],
              [96, 95, 0],
              [0xffffffff, 95, 1],
              [96, 0, 0xffffffff],
              [2, 20, 0xffffffff],
              [4, 95, 0xfffffffd],
              [95, 95, 0xffffffff],
              [1, 1, 0xffffffff],
              [0, 100, 3],
              [92, 0xffffffff, 7],
              [96, 100, 0],
              [0xffffffff, 0xffffffff, 1],
            ]
          ) {
            await call("reset");
            const scalar = expected(first, last, stride);
            const run = () =>
              call("run", new Uint32Array([first, last, stride]));
            const local = () =>
              call("local_run", new Uint32Array([first, last, stride]));
            if (scalar.trapped) {
              await assert.rejects(run, WebAssembly.RuntimeError);
              await assert.rejects(local, WebAssembly.RuntimeError);
            } else {
              assert.equal(await run(), scalar.cursor);
              assert.deepEqual(await local(), scalar.rows);
              assert.equal(
                await call(
                  "local_cursor",
                  new Uint32Array([first, last, stride]),
                ),
                scalar.cursor,
              );
            }
            assert.deepEqual(await call("read"), scalar.rows);
          }
          for (const [first, last] of [[3, 95], [5, 94], [96, 95]]) {
            await call("reset");
            const scalar = expected(first, last, 2);
            assert.equal(
              await call("odd", new Uint32Array([first, last])),
              scalar.cursor,
            );
            assert.deepEqual(await call("read"), scalar.rows);
            assert.deepEqual(
              await call("local_odd", new Uint32Array([first, last])),
              scalar.rows,
            );
            assert.equal(
              await call("local_odd_cursor", new Uint32Array([first, last])),
              scalar.cursor,
            );
          }
          for (const first of [1, 3, 7, 95]) {
            await call("reset");
            const scalar = expected(first, 95, first);
            assert.equal(
              await call("same_start_and_stride", first),
              scalar.cursor,
            );
            assert.deepEqual(await call("read"), scalar.rows);
            assert.deepEqual(
              await call("local_same_start_and_stride", first),
              scalar.rows,
            );
            assert.equal(await call("local_same_cursor", first), scalar.cursor);
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
