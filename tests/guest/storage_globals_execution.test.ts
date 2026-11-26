import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("plain global payload copies preserve variant fields and exact scalar bits", async () => {
  await compileAndRun(
    `
type Sample is data = $Empty | $Reading {word: U32, value: F32}
const samples: Array Sample = #[$Reading {word: 0xffffffff, value: -0.0}, $Empty, $Reading {word: 0x80000000, value: 1.5}]
const saved: Array Sample = @storage.copy samples
const value_of = func (sample: Sample): F32 => return case sample of
  $Reading {word, value} => value
  $Empty => 9.0
const word_of = func (sample: Sample): U32 => return case sample of
  $Reading {word, value} => word
  $Empty => 7
io const values = func () => return #[value_of saved[0], value_of saved[2]]
io const words = func () => return #[word_of saved[0], word_of saved[1], word_of saved[2]]
io const change_copy = func () => return do:
  let local = @storage.copy samples
  @storage.truncate local 0
  @storage.push local $Empty
  return word_of local[0]
`,
    (guest) => {
      assert.deepEqual(guest.call("values", null), new Float32Array([-0, 1.5]));
      assert.deepEqual(
        guest.call("words", null),
        new Uint32Array([0xffffffff, 7, 0x80000000]),
      );
      assert.equal(guest.call("change_copy", null), 7);
      assert.deepEqual(guest.call("values", null), new Float32Array([-0, 1.5]));
      assert.deepEqual(
        guest.call("words", null),
        new Uint32Array([0xffffffff, 7, 0x80000000]),
      );
    },
  );
});

Deno.test("computed instance pools initialize in dependency order and retain independent copies", async () => {
  await compileAndRun(
    `
const seed: Array U32 = #[41]
const build = func (items: Array U32): Array U32 => return do:
  let result: Array U32 = #[items[0] + 1]
  return result
const rows: Array U32 = build seed
const saved: Array U32 = @storage.copy seed
io const read = func () => return rows[@u32.sub (@storage.length rows) 1] + saved[0]
io const change_copy = func (value: U32) => return do:
  let local_seed = @storage.copy seed
  let local_rows = @storage.copy rows
  @storage.push local_seed value
  @storage.push local_rows (value + 1)
  return local_rows[1] + local_seed[1] + saved[0]
`,
    (guest) => {
      assert.equal(guest.call("read", null), 83);
      assert.equal(guest.call("change_copy", 7), 56);
      assert.equal(guest.call("read", null), 83);
    },
  );
});

// Constants are computed at instantiation (tasks/DELETE_SCOPED.md), so a
// failing initializer traps there.
Deno.test("failed computed initialization traps at instantiation", async () => {
  await assert.rejects(compileAndRun(
    `
const build = func (): Array U32 => return @panic "initialization fails"
const rows: Array U32 = build ()
io const answer = func () => return rows[0]
`,
    () => {},
  ), WebAssembly.RuntimeError);
});
