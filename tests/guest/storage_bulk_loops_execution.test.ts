import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source =
  `const copy = func (dst: own Array U32) -> (src: Array U32) -> (first: U32) -> (end: U32): Array U32 => return do:
  for index in first .. end:
    dst[index] := src[index]
  return dst
const fill = func (dst: own Array U32) -> (first: U32) -> (end: U32): Array U32 => return do:
  for index in first .. end:
    dst[index] := 305419896
  return dst
const zero = func (dst: own Array U32) -> (end: U32): Array U32 => return do:
  for index in 0 .. end:
    dst[index] := 0
  return dst
const fcopy = func (dst: own Array F32) -> (src: Array F32) -> (end: U32): Array F32 => return do:
  for index in 0 .. end:
    dst[index] := src[index]
  return dst
const ffill = func (dst: own Array F32) -> (end: U32): Array F32 => return do:
  for index in 0 .. end:
    dst[index] := 1.5
  return dst
io const copied = func (bounds: Array U32): Array U32 => return do:
  let dst: Array U32 = @array.fill 48 9
  let src: Array U32 = @array.generate 48 (func index => return @u32.add index 100)
  return copy dst src bounds[0] bounds[1]
io const filled = func (bounds: Array U32): Array U32 => return do:
  let dst: Array U32 = @array.fill 48 9
  return fill dst bounds[0] bounds[1]
io const zeroed = func (end: U32): Array U32 => return do:
  let dst: Array U32 = @array.fill 48 9
  return zero dst end
io const alias = func (end: U32): Array U32 => return do:
  let rows: Array U32 = @array.generate 48 (func index => return index)
  return copy rows rows.copy 0 end
io const floating = func (end: U32): Array F32 => return do:
  let dst: Array F32 = @array.fill 48 9.0
  let (negative_zero, nan, _, _) = @simd.u32x4.from_bits (0x80000000, 0x7fc01234, 0, 0)
  let src: Array F32 = @array.generate 48 (func index => return if @u32.eq index 0 then negative_zero else if @u32.eq index 1 then nan else 1.25)
  return fcopy dst src end
io const float_fill = func (end: U32): Array F32 => return do:
  let dst: Array F32 = @array.fill 48 9.0
  return ffill dst end
io const bool_fill = func (end: U32): Bool => return do:
  let dst: Array Bool = @array.fill 48 false
  for index in 0 .. end:
    dst[index] := true
  return dst[0] and dst[47]
io const shifted = func (end: U32): Array U32 => return do:
  let rows: Array U32 = @array.generate 48 (func index => return index)
  for index in 1 .. end:
    rows[index] := rows[@u32.sub index 1]
  return rows
const short: Array U32 = @array.fill 24 7
const long: Array U32 = @array.fill 48 7
const push_range = func (emit: U32 -> U32 ! {Foreign}) -> (src: Array U32) -> (end: U32): Unit ! {Foreign} => return do:
  for index in 0 .. end:
    use _ <- emit src[index]
  return ()
io const trap_source = func (emit: U32 -> U32 ! {Foreign}): Unit ! {Foreign} => return push_range emit short 48
io const trap_target = func (emit: U32 -> U32 ! {Foreign}): Unit ! {Foreign} => return push_range emit long 64
io const ordered_trap = func (emit: U32 -> U32 ! {Foreign}): Array U32 ! {Foreign} => return do:
  let dst: Array U32 = @array.fill 48 9
  for index in 0 .. 49:
    dst[index] := if @u32.eq index 48 then @u32.div 1 0 else index
    use _ <- emit 1
  return dst
const fill_then_read = func (rows: own Array U32) -> (first: U32) -> (end: U32) -> (read_index: U32): U32 => return do:
  for index in first .. end:
    rows[index] := 7
  let selected = rows[read_index]
  return @u32.add selected rows[0]
io const reads_after_fill = func (bounds: Array U32): U32 => return do:
  let rows: Array U32 = @array.fill 48 9
  return fill_then_read rows bounds[0] bounds[1] bounds[2]
const conditional_read = func (rows: Array U32) -> (flag: U32) -> (first: U32) -> (second: U32): U32 => return do:
  let selected = 0
  if @u32.lt 0 flag:
    selected := rows[first]
  return @u32.add selected rows[second]
io const conditional_reads = func (inputs: Array U32): U32 => return do:
  let rows: Array U32 = @array.generate 48 (func index => return @u32.add index 100)
  return conditional_read rows inputs[0] inputs[1] inputs[2]
const loop_read = func (rows: Array U32) -> (first: U32) -> (end: U32) -> (read_index: U32): U32 => return do:
  let selected = 0
  for index in first .. end:
    selected := @u32.add selected rows[index]
  return @u32.add selected rows[read_index]
io const reads_after_loop = func (bounds: Array U32): U32 => return do:
  let rows: Array U32 = @array.generate 48 (func index => return @u32.add index 100)
  return loop_read rows bounds[0] bounds[1] bounds[2]
`;

Deno.test(`bulk fixed scalar loops preserve ranges aliases bits and prefix traps`, async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-bulk-loops-" });
  const entry = `${directory}/main.sq`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.sq`,
  });
  try {
    const result = await compiler.build({ sources: { [entry]: source } });
    assert(result.success, JSON.stringify(result));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(result.bytes, { asynchronous });
      try {
        const call = async (name: string, input: unknown = null) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        for (
          const [first, end] of [
            [0, 0],
            [48, 0],
            [0xffffffff, 0],
            [0, 1],
            [2, 17],
            [2, 18],
            [0, 48],
            [7, 48],
          ]
        ) {
          const bounds = new Uint32Array([first, end]);
          assert.deepEqual(
            await call("copied", bounds),
            Uint32Array.from(
              { length: 48 },
              (_, i) => {
                if (i >= first && i < end) return i + 100;
                return 9;
              },
            ),
          );
          assert.deepEqual(
            await call("filled", bounds),
            Uint32Array.from(
              { length: 48 },
              (_, i) => {
                if (i >= first && i < end) return 0x12345678;
                return 9;
              },
            ),
          );
        }
        assert.deepEqual(await call("zeroed", 48), new Uint32Array(48));
        assert.deepEqual(
          await call("alias", 48),
          Uint32Array.from({ length: 48 }, (_, i) => i),
        );
        const floats = await call("floating", 48) as Float32Array;
        assert(Object.is(floats[0], -0));
        const bits = new Uint32Array(
          floats.buffer,
          floats.byteOffset,
          floats.length,
        );
        assert.equal(bits[1], 0x7fc01234);
        assert.deepEqual(floats.slice(2), new Float32Array(46).fill(1.25));
        assert.deepEqual(
          await call("float_fill", 48),
          new Float32Array(48).fill(1.5),
        );
        assert.equal(await call("bool_fill", 48), true);
        assert.deepEqual(await call("shifted", 48), new Uint32Array(48));
        let emitted: number[] = [];
        const emit = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value: number) => {
            emitted.push(value);
            return value;
          },
        });
        await assert.rejects(
          () => call("trap_source", emit),
          WebAssembly.RuntimeError,
        );
        assert.deepEqual(
          Uint32Array.from(emitted),
          new Uint32Array(24).fill(7),
        );
        emitted = [];
        await assert.rejects(
          () => call("trap_target", emit),
          WebAssembly.RuntimeError,
        );
        assert.deepEqual(
          Uint32Array.from(emitted),
          new Uint32Array(48).fill(7),
        );
        emitted = [];
        await assert.rejects(
          () => call("ordered_trap", emit),
          WebAssembly.RuntimeError,
        );
        assert.equal(emitted.length, 48);
        for (
          const [first, end, readIndex, expected] of [
            [0, 48, 47, 14],
            [0, 0, 47, 18],
            [2, 3, 2, 16],
            [48, 0, 47, 18],
          ]
        ) {
          assert.equal(
            await call(
              "reads_after_fill",
              new Uint32Array([first, end, readIndex]),
            ),
            expected,
          );
        }
        assert.equal(
          await call(
            "conditional_reads",
            new Uint32Array([0, 0xffffffff, 3]),
          ),
          103,
        );
        assert.equal(
          await call("conditional_reads", new Uint32Array([1, 2, 3])),
          205,
        );
        await assert.rejects(
          () =>
            call("conditional_reads", new Uint32Array([1, 0xffffffff, 3])),
          WebAssembly.RuntimeError,
        );
        for (
          const [first, end, expected] of [
            [49, 49, 103],
            [0xffffffff, 0xffffffff, 103],
            [0xffffffff, 0, 103],
            [0, 1, 203],
            [0, 48, 6031],
          ]
        ) {
          assert.equal(
            await call("reads_after_loop", new Uint32Array([first, end, 3])),
            expected,
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
