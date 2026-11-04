import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const kernel =
  `const recur = func (state: Array U32) -> (input: Array U32) -> (first: U32) -> (end: U32): Unit => return do:
  for index in first .. end:
    let slot = index % 8
    let word = state[slot]
    word := (self << 5) + self + input[index]
    word := (self + (self << 10)) ^ (self >> 6)
    state[slot] := word
  return ()
`;
const initial = [
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
];
const source = kernel + `
const saved: Array U32 = #[0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
const short_state: Array U32 = #[0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A]
const input: Array U32 = @array.generate 96 (func index => return @u32.add (@u32.mul index 123456789) 0xF0000000)
const short_input: Array U32 = @array.generate 19 (func index => return @u32.add (@u32.mul index 123456789) 0xF0000000)
entry const run = func (bounds: Array U32): Array U32 => return do:
  let state = @storage.copy saved
  let local_input: Array U32 = @array.generate 96 (func index => return @u32.add (@u32.mul index 123456789) 0xF0000000)
  recur state local_input bounds[0] bounds[1]
  return state
entry const alias = func (bounds: Array U32): Array U32 => return do:
  let state = @storage.copy input
  recur state state bounds[0] bounds[1]
  return state
entry const trap_input = func (): Unit => return recur saved short_input 0 40
entry const trap_state = func (): Unit => return recur short_state input 0 40
entry const read = func (): Array U32 => return @storage.copy saved
entry const read_short = func (): Array U32 => return @storage.copy short_state
entry const empty = func (bounds: Array U32): Array U32 => return do:
  let state: Array U32 = #[]
  let rows: Array U32 = #[]
  recur state rows bounds[0] bounds[1]
  return state
`;

const dynamicSource = kernel.replace("const recur =", "const dynamic_recur =")
  .replace(
    "word := (self << 5) + self + input[index]",
    "word := (self << input[index]) ^ self",
  ).replace("    word := (self + (self << 10)) ^ (self >> 6)\n", "") + `
entry const dynamic = func (end: U32): Array U32 => return do:
  let state = @storage.copy saved
  let local_input: Array U32 = @array.generate 96 (func index => return @u32.add (@u32.mul index 123456789) 0xF0000000)
  dynamic_recur state local_input 0 end
  return state
`;

function expected(
  state: number[],
  input: number[],
  first: number,
  end: number,
) {
  for (let index = first; index < end; index++) {
    const slot = index % 8;
    if (slot >= state.length || index >= input.length) break;
    let word = (((state[slot] << 5) >>> 0) + state[slot] + input[index]) >>> 0;
    word = (((word + (word << 10)) >>> 0) ^ (word >>> 6)) >>> 0;
    state[slot] = word;
  }
  return Uint32Array.from(state);
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`cyclic lanes retain exact words aliases tails and trap prefixes (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-lane-loops-" });
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
        sources: { [entry]: source + dynamicSource },
      });
      assert(result.success, JSON.stringify(result));
      const counters = result.stats.workCounters as Record<string, number>;
      assert(counters.scoped_lane_simd_loops > 0, JSON.stringify(counters));
      assert(
        counters.scoped_lane_loops > counters.scoped_lane_simd_loops,
        JSON.stringify(counters),
      );
      const rows = Array.from(
        { length: 96 },
        (_, index) => (Math.imul(index, 123456789) + 0xf0000000) >>> 0,
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = async (name: string, input: unknown = null) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          for (const first of [0, 1, 7, 8, 16, 88]) {
            for (const count of [0, 1, 7, 8, 15, 16, 17, 23, 24, 31, 32]) {
              const end = Math.min(first + count, rows.length);
              assert.deepEqual(
                await call("run", new Uint32Array([first, end])),
                expected(initial.slice(), rows, first, end),
                `range ${first}..${end}`,
              );
            }
          }
          for (const end of [0, 1, 15, 16, 17, 31, 32, 47]) {
            const state = initial.slice();
            for (let index = 0; index < end; index++) {
              const slot = index % 8;
              state[slot] = ((state[slot] << rows[index]) ^ state[slot]) >>> 0;
            }
            assert.deepEqual(
              await call("dynamic", end),
              Uint32Array.from(state),
            );
          }
          for (const [first, end] of [[0, 96], [8, 96], [0, 16], [1, 32]]) {
            const aliases = rows.slice();
            assert.deepEqual(
              await call("alias", new Uint32Array([first, end])),
              expected(aliases, aliases, first, end),
            );
          }
          for (const [first, end] of [[0, 0], [8, 0], [0xffffffff, 1]]) {
            assert.deepEqual(
              await call("empty", new Uint32Array([first, end])),
              new Uint32Array(),
            );
          }
          await assert.rejects(
            () => call("trap_input"),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(
            await call("read"),
            expected(initial.slice(), rows.slice(0, 19), 0, 40),
          );
          await assert.rejects(
            () => call("trap_state"),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(
            await call("read_short"),
            expected(initial.slice(0, 4), rows, 0, 40),
          );
        } finally {
          guest.dispose();
        }
      }
      const customPrelude = `${directory}/prelude.blot`;
      const prelude = await Deno.readTextFile(`${stdRoot}/prelude.blot`);
      await Deno.writeTextFile(
        customPrelude,
        prelude.replace(
          "const U32.add = @u32.add",
          "const U32.add = func (left: U32) -> (right: U32): U32 => return @u32.bit_xor left right",
        ),
      );
      const customCompiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        stdRoot,
        prelude: customPrelude,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const custom = await customCompiler.build({
          sources: { [entry]: source },
        });
        assert(custom.success, JSON.stringify(custom));
        const customCounters = custom.stats.workCounters as Record<
          string,
          number
        >;
        assert.equal(customCounters.scoped_lane_loops, 0);
        const guest = await instantiateGuest(custom.bytes);
        try {
          const state = initial.slice();
          for (let index = 0; index < 40; index++) {
            const slot = index % 8;
            const word = ((state[slot] << 5) ^ state[slot] ^ rows[index]) >>> 0;
            state[slot] = (word ^ (word << 10) ^ (word >>> 6)) >>> 0;
          }
          assert.deepEqual(
            guest.call("run", new Uint32Array([0, 40])),
            Uint32Array.from(state),
          );
        } finally {
          guest.dispose();
        }
      } finally {
        await customCompiler.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
