import { strict as assert } from "node:assert";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("Item 1: array length mutations require sole ownership and preserve explicit copies", async () => {
  await compileExpectedFailure(
    `
io bad (): U32 =>
  let rows: #[U32] = #[1]
  let saved = rows
  @storage.push rows 2
  return @storage.length saved
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
io bad (): U32 =>
  let rows: #[U32] = #[1]
  let saved = rows
  @storage.truncate rows 0
  return @storage.length saved
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
io bad (): U32 =>
  let rows: #[U32] = #[1, 2]
  let saved = rows
  let _ = @storage.pop rows
  return @storage.length saved
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
io bad (): U32 =>
  let rows: #[U32] = #[1]
  let saved = rows
  rows := self.push 2
  return saved.length
`,
    "own_argument",
    undefined,
    { stdRoot },
  );
  await compileExpectedFailure(
    `
io bad (): U32 =>
  let rows: #[U32] = #[1]
  let saved = rows
  rows := self.truncate 0
  return saved.length
`,
    "own_argument",
    undefined,
    { stdRoot },
  );
  await compileExpectedFailure(
    `
func add_one (xs: #[U32]): Unit =>
  @storage.push xs 9
  return ()
io bad (): U32 =>
  let rows: #[U32] = #[1]
  let saved = rows
  add_one rows
  return @storage.length saved
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
func add_one_owned (xs: own #[U32]): #[U32] =>
  @storage.push xs 9
  return xs
io bad (): U32 =>
  let rows: #[U32] = #[1]
  let saved = rows
  rows := add_one_owned self
  return @storage.length saved + @storage.length rows
`,
    "own_argument",
  );
  await compileAndRun(
    `
func add_one_owned (xs: own #[U32]): #[U32] =>
  @storage.push xs 9
  return xs
func shrink_owned (xs: own #[U32]): #[U32] =>
  @storage.truncate xs 0
  return xs
io main (): #[U32] =>
  let rows: #[U32] = #[42]
  let saved = @storage.copy rows
  rows := add_one_owned self
  let grown_len = @storage.length rows
  let saved_after_grow = @storage.length saved
  rows := shrink_owned self
  return #[saved_after_grow, grown_len, @storage.length rows, @storage.length saved, saved[0]]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("main", null) as Uint32Array),
        [1, 2, 0, 1, 42],
      );
    },
  );
  await compileAndRun(
    `
type Pools = { draws: #[U32], sounds: #[U32] }
func fill (draws: own #[U32]) -> (sounds: own #[U32]): (#[U32], #[U32]) =>
  @storage.truncate draws 0
  @storage.truncate sounds 0
  @storage.push draws 7
  @storage.push sounds 9
  return (draws, sounds)
func run (pools: own Pools): Pools =>
  let (draws, sounds) = fill pools.draws pools.sounds
  return { draws, sounds }
io main (): #[U32] =>
  let draws: #[U32] = #[1, 2]
  let sounds: #[U32] = #[3]
  let pools: Pools = { draws, sounds }
  pools := run self
  return #[pools.draws[0], pools.sounds[0]]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("main", null) as Uint32Array),
        [7, 9],
      );
    },
  );
  await compileExpectedFailure(
    `
type Pools = { draws: #[U32], sounds: #[U32] }
func fill (a: own #[U32]) -> (b: own #[U32]): (#[U32], #[U32]) =>
  @storage.push a 7
  @storage.push b 9
  return (a, b)
func run (pools: own Pools): Pools =>
  let (a, b) = fill pools.draws pools.draws
  return { draws: a, sounds: b }
io main (): U32 =>
  let draws: #[U32] = #[1]
  let sounds: #[U32] = #[3]
  let pools: Pools = { draws, sounds }
  pools := run self
  return @storage.length pools.draws
`,
    "spent_value",
  );
  await compileExpectedFailure(
    `
type Holder = { rows: #[U32] }
func append (h: Holder) -> (v: U32): U32 =>
  @storage.push h.rows v
  return @storage.length h.rows
io main (): U32 =>
  let base: #[U32] = #[1]
  let fresh: Holder = { rows: @storage.copy base }
  return append fresh 9 + @storage.length base
`,
    "aliased_update",
  );
  await compileAndRun(
    `
type Holder = { rows: #[U32] }
func append (h: own Holder) -> (v: U32): Holder =>
  @storage.push h.rows v
  return h
io main (): U32 =>
  let base: #[U32] = #[1]
  let fresh: Holder = { rows: @storage.copy base }
  fresh := append self 9
  return @storage.length fresh.rows + @storage.length base
`,
    (guest) => {
      equal(guest.call("main", null), 3);
    },
  );
});

Deno.test("Item 3a: effectful contract_method preserves callback evaluation order", async () => {
  await compileAndRun(
    `
type Box is data = $Box U32
type Make a is trait = {
  make: a -> ((U32 -> U32 ! {Foreign}) -> (U32 -> U32 ! {Foreign}) ! {Foreign})
}
func make_box (b: Box) -> (log: U32 -> U32 ! {Foreign}): (U32 -> U32 ! {Foreign}) ! {Foreign} =>
  let $Box v = b
  use _ <- log 1
  return func (y: U32) => return do:
    use _ <- log 3
    return v + y
const Box.Make: Make Box = {
  make: func (b: Box) -> (log: U32 -> U32 ! {Foreign}) => return make_box b log,
}
const run: a -> (U32 -> U32 ! {Foreign}) -> (U32 -> U32 ! {Foreign}) where { Make a } = func x -> log -> y => return do:
  use f <- Make.make x log
  use _ <- log 2
  return f y
io main (log: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => run ($Box 100) log 23
`,
    (guest) => {
      const seen: number[] = [];
      const log = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          seen.push(value as number);
          return 0;
        },
      });
      const out = guest.call("main", log);
      equal(out, 123);
      assert.deepEqual(seen, [1, 2, 3]);
    },
    { stdRoot },
  );
  await compileAndRun(
    `
effect Tick: U32 -> U32
type Box is data = $Box U32
type MakeEffect a is trait = {
  make: a -> (U32 -> U32 ! {Tick}) ! {Tick}
}
func make_box_effect (b: Box): (U32 -> U32 ! {Tick}) ! {Tick} =>
  let $Box v = b
  use _ <- Tick 10
  return func (y: U32) => return do:
    use _ <- Tick 30
    return v + y
const Box.MakeEffect: MakeEffect Box = {
  make: func (b: Box) => return make_box_effect b,
}
const run: a -> (U32 -> U32 ! {Tick}) where { MakeEffect a } = func x -> y => return do:
  use f <- MakeEffect.make x
  use _ <- Tick 20
  return f y
io main (log: U32 -> U32 ! {Foreign}): U32 ! {Foreign} =>
  return do (@effect.provider Tick log):
    return run ($Box 50) 7
`,
    (guest) => {
      const seen: number[] = [];
      const log = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => {
          seen.push(value as number);
          return 0;
        },
      });
      const out = guest.call("main", log);
      equal(out, 57);
      assert.deepEqual(seen, [10, 20, 30]);
    },
    { stdRoot },
  );
});

Deno.test("Item 3b: structurally inferred wrapper around multiple restore_into calls preserves owning result types", async () => {
  await compileAndRun(
    `
type State is data = $State { epoch: U32 }
type Access is data = $Access { a: #[U32], b: #[U32], surface_epoch: State }

func reset_surface (s: State) -> (v: U32): State => $State { epoch: s.epoch + v }

func dec_a (vals: #[U32]) -> (own access) =>
  access.a[0] := vals[0]
  access.surface_epoch := reset_surface self 1
  return access

func rst_a (own access) =>
  access.a[0] := 10
  access.surface_epoch := reset_surface self 2
  return access

func dec_b (vals: #[U32]) -> (own access) =>
  access.b[0] := vals[0]
  access.surface_epoch := reset_surface self 10
  return access

func rst_b (own access) =>
  access.b[0] := 20
  access.surface_epoch := reset_surface self 20
  return access

func restore_into (flag: Bool) -> decode -> reset -> (own access) -> (vals: #[U32]) =>
  if flag:
    access := decode vals (own access)
  else:
    access := reset (own access)
  return access

func decode_schema (own access) -> (f1: Bool) -> (f2: Bool) -> (v1: #[U32]) -> (v2: #[U32]) =>
  access := restore_into f1 dec_a rst_a access v1
  access := restore_into f2 dec_b rst_b access v2
  return access

io main (): #[U32] =>
  let access = $Access { a: #[0], b: #[0], surface_epoch: $State { epoch: 200 } }
  access := decode_schema access true false #[3] #[4]
  let access2 = $Access { a: #[0], b: #[0], surface_epoch: $State { epoch: 200 } }
  access2 := decode_schema access2 false true #[3] #[4]
  return #[access.surface_epoch.epoch, access.a[0], access2.surface_epoch.epoch, access2.b[0]]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("main", null) as Uint32Array),
        [221, 3, 212, 4],
      );
    },
    { stdRoot },
  );
});

Deno.test("Item 4: runtime-guarded noteStoreToSlot releases loop-local slice builders and preserves escaping stores", async () => {
  await compileAndRun(
    `
type SliceHolder = { span: &[U32], tag: U32 }
io main (): #[U32] =>
  let base: #[U32] = #[10, 20, 30, 40]
  let total = 0
  for round in 0 .. 4000:
    let local: #[SliceHolder] = #[]
    for i in 0 .. 16:
      @storage.push local { span: &base[0..4], tag: (round + i) % 4 }
    let items = #[{ span: &base[0..4], tag: (round + j) % 4 } | j <- base]
    total := self + local[round % 16].span[local[0].tag] + items[0].span[items[1].tag]
  return #[total]
`,
    (guest, bytes) => {
      const result = Array.from(guest.call("main", null) as Uint32Array);
      assert.equal(result.length, 1);
      assert.ok(result[0] > 0);
      const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes));
      const exports = instance.exports;
      (exports.main as CallableFunction)();
      const memory = exports["squid:memory"] as WebAssembly.Memory;
      assert.ok(memory instanceof WebAssembly.Memory);
      assert.ok(
        memory.buffer.byteLength <= 131072,
        `expected loop-local slice builders to stay bounded, got ${memory.buffer.byteLength} bytes`,
      );
    },
    { stdRoot },
  );
  await compileAndRun(
    `
func append_rows (dst: own #[#[U32]]) -> (n: U32): #[#[U32]] =>
  for i in 0 .. n:
    let row = #[i + 1, i + 10]
    @storage.push dst row
  return dst
io main (): #[U32] =>
  let rows: #[#[U32]] = #[]
  rows := append_rows self 4
  return #[rows[0][0], rows[1][1], rows[2][0], rows[3][1]]
`,
    (guest) => {
      assert.deepEqual(
        Array.from(guest.call("main", null) as Uint32Array),
        [1, 11, 3, 13],
      );
    },
    { stdRoot },
  );
});
