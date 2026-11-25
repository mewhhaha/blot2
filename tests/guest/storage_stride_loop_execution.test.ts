import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const marking =
  `const mark = func (rows: own Array U32) -> (first: U32) -> (last: U32) -> (stride: U32): (Array U32, U32) => return do:
  let cursor = first
  for ever:
    if @u32.lt last cursor:
      break
    rows[cursor] := 305419896
    cursor := @u32.add self stride
  return (rows, cursor)
`;
const literal = marking.replace("const mark =", "const mark_odd =")
  .replace("@u32.add self stride", "@u32.add self 2");
const source = marking + literal + `
const mark_logged = func (rows: own Array U32) -> (log: Array U32 -> U32 ! {Foreign}) -> (first: U32) -> (last: U32) -> (stride: U32): U32 ! {Foreign} => return do:
  let cursor = first
  for ever:
    if @u32.lt last cursor:
      break
    rows[cursor] := 305419896
    use _ <- log #[cursor]
    cursor := @u32.add self stride
  return cursor
const mark_odd_logged = func (rows: own Array U32) -> (log: Array U32 -> U32 ! {Foreign}) -> (first: U32) -> (last: U32): U32 ! {Foreign} => return do:
  let cursor = first
  for ever:
    if @u32.lt last cursor:
      break
    rows[cursor] := 305419896
    use _ <- log #[cursor]
    cursor := @u32.add self 2
  return cursor
#entry const run = func (log: Array U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  use first <- log #[0, 0]
  use last <- log #[0, 1]
  use stride <- log #[0, 2]
  use out <- mark_logged (@array.fill 96 9) log first last stride
  return out
#entry const odd = func (log: Array U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  use first <- log #[0, 0]
  use last <- log #[0, 1]
  use out <- mark_odd_logged (@array.fill 96 9) log first last
  return out
#entry const same_start_and_stride = func (log: Array U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  use first <- log #[0, 0]
  use out <- mark_logged (@array.fill 96 9) log first 95 first
  return out
#entry const local_run = func (bounds: Array U32) => return do:
  let (target, _) = mark (@array.fill 96 9) bounds[0] bounds[1] bounds[2]
  return target
#entry const local_cursor = func (bounds: Array U32): U32 => return do:
  let (_, cursor) = mark (@array.fill 96 9) bounds[0] bounds[1] bounds[2]
  return cursor
#entry const local_odd = func (bounds: Array U32) => return do:
  let (target, _) = mark_odd (@array.fill 96 9) bounds[0] bounds[1] 2
  return target
#entry const local_odd_cursor = func (bounds: Array U32): U32 => return do:
  let (_, cursor) = mark_odd (@array.fill 96 9) bounds[0] bounds[1] 2
  return cursor
#entry const local_same_start_and_stride = func (first: U32) => return do:
  let (target, _) = mark (@array.fill 96 9) first 95 first
  return target
#entry const local_same_cursor = func (first: U32): U32 => return do:
  let (_, cursor) = mark (@array.fill 96 9) first 95 first
  return cursor
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

Deno.test(`strided fills preserve cursor wrapping lazy exits and trap prefixes`, async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-stride-loops-" });
  const entry = `${directory}/main.blot`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.blot`,
  });
  try {
    const result = await compiler.build({ sources: { [entry]: source } });
    assert(result.success, JSON.stringify(result));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(result.bytes, { asynchronous });
      const call = async (name: string, input: unknown = null) => {
        if (asynchronous) return await guest.callAsync(name, input);
        return guest.call(name, input);
      };
      try {
        let params: number[] = [];
        let written: number[] = [];
        const logCap = guest.capability({
          parameter: "Array U32",
          result: "U32",
          call: (msg: Uint32Array) => {
            if (msg.length === 2) return params[msg[1]];
            written.push(msg[0]);
            return 0;
          },
        });
        const replay = () => {
          const out = new Uint32Array(96).fill(9);
          for (const idx of written) out[idx] = 0x12345678;
          return out;
        };
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
          params = [first, last, stride];
          written = [];
          const scalar = expected(first, last, stride);
          const run = () => call("run", logCap);
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
          assert.deepEqual(replay(), scalar.rows);
        }
        for (const [first, last] of [[3, 95], [5, 94], [96, 95]]) {
          params = [first, last];
          written = [];
          const scalar = expected(first, last, 2);
          assert.equal(
            await call("odd", logCap),
            scalar.cursor,
          );
          assert.deepEqual(replay(), scalar.rows);
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
          params = [first];
          written = [];
          const scalar = expected(first, 95, first);
          assert.equal(
            await call("same_start_and_stride", logCap),
            scalar.cursor,
          );
          assert.deepEqual(replay(), scalar.rows);
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
