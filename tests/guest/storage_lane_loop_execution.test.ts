import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const kernel =
  `const recur = func (state: own Array U32) -> (input: Array U32) -> (first: U32) -> (end: U32): Array U32 => return do:
  for index in first .. end:
    let slot = index % 8
    let word = state[slot]
    word := (self << 5) + self + input[index]
    word := (self + (self << 10)) ^ (self >> 6)
    state[slot] := word
  return state
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
const recur_logged = func (state: own Array U32) -> (src: Array U32) -> (log: U32 -> U32 ! {Foreign}) -> (end: U32): Array U32 ! {Foreign} => return do:
  for index in 0 .. end:
    let slot = index % 8
    let word = state[slot]
    word := (self << 5) + self + src[index]
    word := (self + (self << 10)) ^ (self >> 6)
    state[slot] := word
    use _ <- log word
  return state
io const run = func (bounds: Array U32): Array U32 => return do:
  let state = @storage.copy saved
  let local_input: Array U32 = @array.generate 96 (func index => return @u32.add (@u32.mul index 123456789) 0xF0000000)
  return recur state local_input bounds[0] bounds[1]
io const alias = func (bounds: Array U32): Array U32 => return do:
  let state = @storage.copy input
  return recur state state.copy bounds[0] bounds[1]
io const trap_input = func (log: U32 -> U32 ! {Foreign}): Unit ! {Foreign} => return do:
  use _ <- recur_logged (@storage.copy saved) short_input log 40
  return ()
io const trap_state = func (log: U32 -> U32 ! {Foreign}): Unit ! {Foreign} => return do:
  use _ <- recur_logged (@storage.copy short_state) input log 40
  return ()
io const empty = func (bounds: Array U32): Array U32 => return do:
  let state: Array U32 = #[]
  let rows: Array U32 = #[]
  return recur state rows bounds[0] bounds[1]
`;

const dynamicSource = kernel.replace("const recur =", "const dynamic_recur =")
  .replace(
    "word := (self << 5) + self + input[index]",
    "word := (self << input[index]) ^ self",
  ).replace("    word := (self + (self << 10)) ^ (self >> 6)\n", "") + `
io const dynamic = func (end: U32): Array U32 => return do:
  let state = @storage.copy saved
  let local_input: Array U32 = @array.generate 96 (func index => return @u32.add (@u32.mul index 123456789) 0xF0000000)
  return dynamic_recur state local_input 0 end
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

Deno.test(`cyclic lanes retain exact words aliases tails and trap prefixes`, async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-lane-loops-" });
  const entry = `${directory}/main.sq`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    stdRoot,
    prelude: `${stdRoot}/prelude.sq`,
  });
  try {
    const result = await compiler.build({
      sources: { [entry]: source + dynamicSource },
    });
    assert(result.success, JSON.stringify(result));
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
        let logged: number[] = [];
        const logCap = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (word: number) => {
            logged.push(word);
            return 0;
          },
        });
        const replay = (base: number[]) => {
          const st = base.slice();
          logged.forEach((w, i) => {
            st[i % 8] = w;
          });
          return Uint32Array.from(st);
        };
        await assert.rejects(
          () => call("trap_input", logCap),
          WebAssembly.RuntimeError,
        );
        assert.deepEqual(
          replay(initial),
          expected(initial.slice(), rows.slice(0, 19), 0, 40),
        );
        logged = [];
        await assert.rejects(
          () => call("trap_state", logCap),
          WebAssembly.RuntimeError,
        );
        assert.deepEqual(
          replay(initial.slice(0, 4)),
          expected(initial.slice(0, 4), rows, 0, 40),
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

// Direct backend gap: a primitive operator ignores the prelude's member, so U32 `+` does not call a custom `U32.add` (tasks/DELETE_SCOPED.md).
Deno.test.ignore("cyclic lanes call the prelude's U32.add", async () => {
  const directory = await Deno.makeTempDir({ prefix: "squid-lane-loops-" });
  const entry = `${directory}/main.sq`;
  const stdRoot = new URL("../../std", import.meta.url).pathname;
  const rows = Array.from(
    { length: 96 },
    (_, index) => (Math.imul(index, 123456789) + 0xf0000000) >>> 0,
  );
  try {
    const customPrelude = `${directory}/prelude.sq`;
    const prelude = await Deno.readTextFile(`${stdRoot}/prelude.sq`);
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
    });
    try {
      const custom = await customCompiler.build({
        sources: { [entry]: source },
      });
      assert(custom.success, JSON.stringify(custom));
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
    await Deno.remove(directory, { recursive: true });
  }
});
