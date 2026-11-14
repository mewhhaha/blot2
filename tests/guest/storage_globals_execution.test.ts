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
entry const values = func () => return #[value_of saved[0], value_of saved[2]]
entry const words = func () => return #[word_of saved[0], word_of saved[1], word_of saved[2]]
entry const change = func () => return do:
  let changed = @storage.write (&samples[0]) $Empty
  return 0
`,
    (guest) => {
      assert.deepEqual(guest.call("values", null), new Float32Array([-0, 1.5]));
      assert.deepEqual(
        guest.call("words", null),
        new Uint32Array([0xffffffff, 7, 0x80000000]),
      );
      guest.call("change", null);
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
const build = func (items: Array U32): GrowArray U32 => return do:
  let result: GrowArray U32 = #[items[0] + 1]
  return result
const rows: GrowArray U32 = build seed
const saved: Array U32 = @storage.copy seed
entry const read = func () => return rows[0] + saved[0]
entry const change = func (value: U32) => return do:
  let changed_seed = @storage.write (&seed[0]) value
  let changed_rows = @storage.write (&rows[0]) (value + 1)
  return saved[0]
`,
    (guest) => {
      assert.equal(guest.call("read", null), 83);
      assert.equal(guest.call("change", 7), 41);
      assert.equal(guest.call("read", null), 49);
      assert.equal(guest.call("read", null), 49);
    },
  );
});

// Constants are computed at instantiation (tasks/DELETE_SCOPED.md), so a
// failing initializer traps at the first read that needs it.
Deno.test("failed computed initialization traps at its first read", async () => {
  await compileAndRun(
    `
const attempts: ResizeArray U32 = #[0]
const build = func (): Array U32 => return do:
  let counted = @storage.write (&attempts[0]) (attempts[0] + 1)
  if attempts[0] == 1:
    return @panic "first initialization fails"
  return #[40 + attempts[0]]
const rows: Array U32 = build ()
entry const answer = func () => return rows[0]
entry const count = func () => return attempts[0]
`,
    (guest) => {
      assert.throws(() => guest.call("answer", null), WebAssembly.RuntimeError);
      assert.equal(guest.call("count", null), 1);
    },
  );
});
