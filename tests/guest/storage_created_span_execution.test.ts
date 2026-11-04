import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

function source(createdFirst: boolean) {
  const calls = (other: string) => {
    const pair = [`wrapped local ${other} 4`, `wrapped ${other} local 4`];
    if (!createdFirst) pair.reverse();
    return pair.map((call) => `  ${call}`).join("\n");
  };
  return `const walk = func (left: Array U32) -> (right: Array U32) -> (remaining: U32): Unit => return do:
  if @u32.eq remaining 0:
    return ()
  let index = @u32.sub remaining 1
  left[index] := @u32.add left[index] right[index]
  walk left right index
  right[index] := @u32.add self 1
  return ()
const wrapped = func (left: Array U32) -> (right: Array U32) -> (count: U32): Unit => return walk left right count
const bump = func (rows: Array U32) -> (index: U32): Unit => return do:
  rows[index] := @u32.add self 1
  return ()
const forwarded = func (rows: Array U32) -> (index: U32): Unit => return bump rows index
const read_if = func (rows: Array U32) -> (index: U32) -> (flag: U32): U32 => return do:
  if @u32.eq flag 0:
    return 0
  return rows[index]
const global: Array U32 = #[10, 20, 30, 40]
entry const reset = func (): Unit => return do:
  let rows = global
  for index in 0 .. 4:
    rows[index] := @u32.mul (@u32.add index 1) 10
  return ()
entry const mixed = func (input: Array U32): Array U32 => return do:
  let local: Array U32 = #[1, 2, 3, 4]
${calls("input")}
  return #[local[0], local[1], local[2], local[3], input[0], input[1], input[2], input[3]]
entry const globals = func (): Array U32 => return do:
  let local: Array U32 = #[1, 2, 3, 4]
${calls("global")}
  return #[local[0], local[1], local[2], local[3], global[0], global[1], global[2], global[3]]
entry const aliased = func (): Array U32 => return do:
  let local: Array U32 = #[1, 2, 3, 4]
  let alias = local
  wrapped local alias 4
  return local
entry const skipped = func (input: Array U32): U32 => return do:
  let empty: Array U32 = #[]
  wrapped empty input 0
  return @u32.add (read_if empty 4294967295 0) (read_if input 4294967295 0)
entry const varying = func (iterations: U32): U32 => return do:
  let total = 0
  for iteration in 0 .. iterations:
    let capacity = @u32.rem iteration 5
    let rows: Array U32 = @array.fill capacity 7
    if @u32.lt 0 capacity:
      let last = @u32.sub capacity 1
      forwarded rows last
      total := @u32.add self rows[last]
  return total
entry const varying_oob = func (): Unit => return do:
  for iteration in 0 .. 3:
    let rows: Array U32 = @array.fill (@u32.sub 4 iteration) 7
    forwarded rows 3
  return ()
entry const created_oob = func (index: U32): Unit => return do:
  let rows: Array U32 = @array.fill 4 7
  forwarded rows index
  return ()
entry const public_oob = func (input: Array U32): Unit => return forwarded input input.length
entry const prefix_trap = func (end: U32): Unit => return do:
  for index in 0 .. end:
    forwarded global index
  return ()
entry const read_global = func (): Array U32 => return @storage.copy global
const copy_float = func (dst: Array F32) -> (src: Array F32) -> (index: U32): Unit => return do:
  dst[index] := src[index]
  return ()
entry const floats = func (input: Array F32): Array F32 => return do:
  let rows: Array F32 = @array.fill 2 0.0
  copy_float rows input 0
  copy_float rows input 1
  copy_float input rows 0
  return rows
`;
}

function mixedExpected(createdFirst: boolean) {
  const local = [1, 2, 3, 4];
  const input = [10, 20, 30, 40];
  const pairs = [[local, input], [input, local]];
  if (!createdFirst) pairs.reverse();
  for (const [left, right] of pairs) {
    for (let index = 3; index >= 0; index--) {
      left[index] += right[index];
      right[index]++;
    }
  }
  return Uint32Array.from([...local, ...input]);
}

for (const codegenTier of ["development", "optimized"] as const) {
  for (const createdFirst of [true, false]) {
    Deno.test(`created scalar spans retain authority and bounds (${codegenTier}, created first ${createdFirst})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-created-span-",
      });
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
          sources: { [entry]: source(createdFirst) },
        });
        assert(result.success, JSON.stringify(result));
        const counters = result.stats.workCounters as Record<string, number>;
        assert(
          counters.scoped_created_span_validations_avoided > 0,
          JSON.stringify(counters),
        );
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          const call = async (name: string, input: unknown = null) => {
            if (asynchronous) return await guest.callAsync(name, input);
            return guest.call(name, input);
          };
          try {
            assert.deepEqual(
              await call("mixed", new Uint32Array([10, 20, 30, 40])),
              mixedExpected(createdFirst),
            );
            await call("reset");
            assert.deepEqual(
              await call("globals"),
              mixedExpected(createdFirst),
            );
            assert.deepEqual(
              await call("aliased"),
              new Uint32Array([3, 5, 7, 9]),
            );
            assert.equal(await call("skipped", new Uint32Array()), 0);
            for (const count of [0, 1, 4, 6, 12, 21]) {
              assert.equal(
                await call("varying", count),
                (count - Math.ceil(count / 5)) * 8,
              );
            }
            for (const name of ["varying_oob", "created_oob", "public_oob"]) {
              let input: unknown = null;
              if (name === "created_oob") input = 4;
              if (name === "public_oob") input = new Uint32Array([1, 2, 3]);
              await assert.rejects(
                () => call(name, input),
                WebAssembly.RuntimeError,
              );
            }
            await call("reset");
            await assert.rejects(
              () => call("prefix_trap", 6),
              WebAssembly.RuntimeError,
            );
            assert.deepEqual(
              await call("read_global"),
              new Uint32Array([11, 21, 31, 41]),
            );
            const bits = new Uint32Array([0x80000000, 0x7fc01234]);
            const floats = await call(
              "floats",
              new Float32Array(bits.buffer),
            ) as Float32Array;
            assert.deepEqual(
              new Uint32Array(floats.buffer, floats.byteOffset, floats.length),
              bits,
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
}
