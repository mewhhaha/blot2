import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

// Ownership is checked at run time (tasks/LANGUAGE_COHERENCE.md A6): a program
// that reads storage its own writes invalidated compiles and traps there.
async function trapsAtRun(source: string, input: unknown = null) {
  await compileAndRun(source, (guest) => {
    let trapped = false;
    try {
      guest.call("bad", input);
    } catch (error) {
      trapped = error instanceof WebAssembly.RuntimeError;
    }
    equal(trapped, true);
  });
}

Deno.test("application arrays survive entries while frame storage and failed calls are reclaimed", async () => {
  await compileAndRun(
    `
const values: Array U32 = #[40, 9]
const other: Array {amount: U32} = #[{amount: 7}]
#entry const count = func (add: Bool) => return do:
  let local = @storage.copy values
  if add:
    @storage.push local 11
  return @storage.length local
#entry const advance = func (n: U32) => return do:
  let scratch: Array U32 = #[n]
  let local = @storage.copy values
  let previous = @storage.copy local
  @storage.truncate local 0
  @storage.push local scratch[0]
  return @u32.add previous[0] local[0]
#entry const read = func (index: U32) => return do:
  let scratch: Array U32 = #[17]
  return @u32.add values[index] (@u32.sub scratch[0] 17)
#entry const second = func () => return other[0].amount
`,
    (guest, bytes) => {
      equal(guest.call("count", false), 2);
      equal(guest.call("second", null), 7);
      equal(guest.call("advance", 42), 82);
      equal(guest.call("read", 0), 40);
      equal(guest.call("count", true), 3);
      equal(guest.call("read", 1), 9);
      let trapped = false;
      try {
        guest.call("read", 2);
      } catch {
        trapped = true;
      }
      equal(trapped, true);
      equal(guest.call("read", 0), 40);
      for (let n = 0; n < 512; n++) {
        equal(guest.call("advance", n), 40 + n);
      }
      equal(guest.call("second", null), 7);
      const module = new WebAssembly.Module(bytes);
      equal(WebAssembly.Module.imports(module).length, 0);
      equal(
        WebAssembly.Module.exports(module).some(({ name }) =>
          /retain|release|cycle|arena/.test(name)
        ),
        false,
      );
      const fresh = new WebAssembly.Instance(module).exports;
      equal((fresh.read as CallableFunction)(0), 40);
    },
  );
});

Deno.test("application storage holds borrowed elements and ignores unreachable initializers", async () => {
  await compileAndRun(
    `
const values: Array {borrow: &U32} = #[]
#entry const answer = func () => return @storage.length values
`,
    (guest) => equal(guest.call("answer", null), 0),
  );
  await compileAndRun(
    `
const unused: Array {borrow: &U32} = #[]
const live: Array U32 = #[42]
#entry const answer = func () => return live[0]
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

Deno.test("source arrays keep references views and links stable across growth", async () => {
  await compileAndRun(
    `
const make = func (): Array U32 => return #[40]
const peek = func (item: &U32) => return @storage.load item
#entry const answer = func () => return do:
  let items: Array U32 = make ()
  let grown = @storage.push items 7
  items[0] := 42
  let first: &U32 = &items[0]
  let link: ^U32 = ^items[0]
  let view: &[U32] = &items[0..1]
  let saved = peek first
  let copied = @storage.copy items
  copied[0] := 99
  break @u32.add (@u32.add saved (@storage.load link)) view[0]
#entry const resized = func () => return do:
  let items: Array U32 = #[7, 8]
  let popped = @storage.pop items
  let grown = @storage.push items 42
  let trimmed = @storage.truncate items 1
  break @u32.add popped (@storage.length items)
#entry const frozen = func () => return do:
  let items: Array U32 = #[]
  let grown = @storage.push items 42
  let fixed: *#[U32] = @storage.share items
  break fixed[0]
#entry const checked = func (index: U32) => return do:
  let items: Array U32 = #[42]
  break items[index]
`,
    (guest, bytes) => {
      equal(guest.call("answer", null), 126);
      equal(guest.call("resized", null), 9);
      equal(guest.call("frozen", null), 42);
      for (let index = 0; index < 128; index++) {
        equal(
          guest.call("answer", null),
          126,
        );
      }
      let trapped = false;
      try {
        guest.call("checked", 1);
      } catch {
        trapped = true;
      }
      equal(trapped, true);
      equal(guest.call("checked", 0), 42);
      const module = new WebAssembly.Module(bytes);
      equal(WebAssembly.Module.imports(module).length, 0);
      equal(
        WebAssembly.Module.exports(module).every(({ name }) =>
          ["answer", "resized", "frozen", "checked", "blot:finish_invocation"]
            .includes(name)
        ),
        true,
      );
    },
  );
});

// Direct backend gap: staging expressions (`#do:`) are not supported (tasks/DELETE_SCOPED.md).
Deno.test.ignore("staged values and references to scalar locals", async () => {
  await compileAndRun(
    `
#entry const staged = func () => return #do:
  break @u32.add 40 2
#entry const scalar_ref = func () => return do:
  let value = 41
  let snapshot = value
  let reference = &value
  break @u32.add snapshot (@storage.load reference)
`,
    (guest) => {
      equal(guest.call("staged", null), 42);
      equal(guest.call("scalar_ref", null), 83);
    },
  );
  await compileExpectedFailure(
    `
#entry const bad = func () => return do:
  let items: Array U32 = #[42]
  let staged = #run @storage.length items
  break staged
`,
    "storage_unsupported",
  );
});

Deno.test("storage rejects fixed-length push and invalidated borrows", async () => {
  await compileExpectedFailure(
    `
#entry const bad = func () => return do:
  let fixed: #[1; U32] = #[42]
  @storage.push fixed 1
  break 0
`,
    "type_mismatch",
  );
  await compileExpectedFailure(
    `
#entry const bad = func () => return do:
  let items: Array U32 = #[42]
  let first = &items[0]
  let alias = items
  let shrunk = @storage.truncate alias 0
  break @storage.load first
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
#entry const bad = func () => return do:
  let items: Array U32 = #[42]
  let alias = items
  let fixed = @storage.share items
  let grown = @storage.push alias 1
  break fixed[0]
`,
    "own_argument",
  );
});

Deno.test("data stacks reclaim lexical owners and admit shrinking after the final borrow use", async () => {
  await compileAndRun(
    `
const temporary = func (x: U32) => return do:
  let items: Array U32 = #[x]
  break items[0]
const choose = func (flag: Bool): Array U32 => return
  if flag then #[40] else #[41]
#entry const grow = func () => return do:
  let items: Array U32 = #[42]
  for i in 0..5000:
    let pushed = @storage.push items i
    let used = temporary i
  let reference = &items[0]
  break @u32.add (@storage.load reference) (@storage.length items)
#entry const shrink = func () => return do:
  let items: Array U32 = #[42, 7]
  let reference = &items[0]
  let saved = @storage.load reference
  let removed = @storage.pop items
  break @u32.add saved removed
#entry const returned = func (flag: Bool) => return do:
  let items = choose flag
  let grown = @storage.push items 1
  let holder = {items: items, value: 1}
  break holder.items[0]
`,
    (guest) => {
      equal(guest.call("grow", null), 5043);
      equal(guest.call("shrink", null), 49);
      equal(guest.call("returned", true), 40);
      equal(guest.call("returned", false), 41);
    },
  );
});

Deno.test("data-stack arrays store records and preserve the roots of their links", async () => {
  await compileAndRun(
    `
#entry const answer = func () => return do:
  let pool: Array U32 = #[40, 42]
  let rows: Array {value: U32, target: ^U32} = #[]
  let grown = @storage.push rows {value: 1, target: ^pool[0]}
  let grown = @storage.push rows {target: ^pool[1], value: 2}
  let row = rows[1]
  let copied = @storage.copy rows
  copied[0] := {value: 9, target: ^pool[1]}
  break @u32.add (@storage.load row.target) rows[0].value
`,
    (guest) => equal(guest.call("answer", null), 43),
  );
});

Deno.test("data-stack numeric layouts preserve F32 fields and reclaim loop exits", async () => {
  await compileAndRun(
    `
#entry const numeric = func (input: F32) => return do:
  let rows: Array {x: F32, y: U32} = #[{y: 1, x: input}]
  let pushed = @storage.push rows {x: @f32.add input 1.0, y: 2}
  break @f32.add rows[0].x rows[1].x
#entry const exits = func (limit: U32) => return do:
  let outer: Array U32 = #[42]
  let total = 0
  for i in 0..limit:
    let temporary: Array U32 = #[i]
    if i == 2:
      continue
    if i == 5:
      break
    total := @u32.add self temporary[0]
  break @u32.add outer[0] total
`,
    (guest) => {
      equal(guest.call("numeric", 20.5), 42);
      equal(guest.call("exits", 100), 50);
    },
  );
});

Deno.test("known callbacks and partial applications preserve captured storage roots", async () => {
  await compileAndRun(
    `
const apply = func transform -> value => return transform value
const add = func (left: U32) -> (right: U32) => return @u32.add left right
#entry const answer = func () => return do:
  let items: Array U32 = #[40]
  let grown = @storage.push items 99
  let reference = &items[0]
  let read = func (offset: U32) => return @u32.add (@storage.load reference) offset
  let plus_one = add 1
  break apply read (plus_one 1)
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
  await compileExpectedFailure(
    `
#entry const bad = func () => return do:
  let items: Array U32 = #[42]
  let reference = &items[0]
  let read = func () => return @storage.load reference
  let shrunk = @storage.truncate items 0
  break read ()
`,
    "aliased_update",
  );
});

Deno.test("joined aliases and caller temporaries retain every possible borrow root", async () => {
  await compileAndRun(
    `
#entry const answer = func (flag: Bool) => return do:
  let left: Array U32 = #[40]
  let right: Array U32 = #[42]
  let selected = if flag then right else left
  let pushed = @storage.push selected 1
  let reference = &selected[0]
  break @storage.load reference
`,
    (guest) => {
      equal(guest.call("answer", true), 42);
      equal(guest.call("answer", false), 40);
    },
  );
  await compileExpectedFailure(
    `
#entry const bad = func (flag: Bool) => return do:
  let left: Array U32 = #[40]
  let right: Array U32 = #[42]
  let reference = if flag then &left[0] else &right[0]
  let shrunk = @storage.truncate right 0
  break @storage.load reference
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `
const consume = func (reference: &U32) -> (removed: U32) => return @storage.load reference
#entry const bad = func () => return do:
  let items: Array U32 = #[42]
  break consume (&items[0]) (@storage.pop items)
`,
    "aliased_update",
  );
});

Deno.test("conditional owned returns release earlier loop iterations and transfer only the selected owner", async () => {
  await compileAndRun(
    `
const choose = func (limit: U32): Array U32 => do:
  for i in 0..limit:
    let items: Array U32 = #[i]
    if i == 5:
      return items
  return #[42]
#entry const answer = func (limit: U32) => return do:
  let selected = choose limit
  let independent: Array U32 = #[100]
  let grown = @storage.push selected 7
  break @u32.add selected[0] independent[0]
`,
    (guest) => {
      equal(guest.call("answer", 0), 142);
      equal(guest.call("answer", 5), 142);
      equal(guest.call("answer", 100), 105);
    },
  );
});

Deno.test("loop backedges use the surviving branch while break keeps its own values", async () => {
  await compileAndRun(
    `
const scan = func (items: &[U32]) => return do:
  let total = 0
  let valid = true
  for value in items:
    if value != 0:
      total := self + value
    else:
      valid := false
      break
  return total + (if valid then 100 else 0)
const matched = func (items: &[U32]) => return do:
  let total = 0
  let valid = true
  for value in items:
    case value == 0 of
      true => do:
        valid := false
        break
      false => do:
        total := self + value
  return total + (if valid then 100 else 0)
#entry const branch = func (stop: Bool) => return do:
  let values = #[2, if stop then 0 else 3, 9]
  return scan (&values[0..values.length])
#entry const pattern = func (stop: Bool) => return do:
  let values = #[2, if stop then 0 else 3, 9]
  return matched (&values[0..values.length])
`,
    (guest) => {
      for (const name of ["branch", "pattern"]) {
        equal(guest.call(name, false), 114);
        equal(guest.call(name, true), 2);
      }
    },
  );
});

Deno.test("read-only &local and &record.field references (A4)", async () => {
  await compileAndRun(
    `
type Big is data = $Big {
  a: U32, b: U32, c: U32, d: U32, e: U32, f: U32,
  g: U32, h: U32, i: U32, j: U32, k: U32, l: U32
}
type Chain is data = $Nil | $Cons (U32, Chain)

const base_const: U32 = 42
const const_refs: #[&U32] = #[&base_const]

const peek_u32 = func (r: &U32): U32 => return @storage.load r
const ref_of = func (x: a): &a => return &x

#entry func scalar_and_rebind (): U32 =>
  let value = 41
  let reference = &value
  value := 99
  return @u32.add value (@storage.load reference)

#entry func field_and_nested (): U32 =>
  let point = { x: 17, y: 25 }
  let rx = &point.x
  let ry = &point.y
  let rrx = &rx
  let unit_val = ()
  let ru = &unit_val
  let _ = @storage.load ru
  return @u32.add (peek_u32 (@storage.load rrx)) (@storage.load ry)

#entry func boxed_and_recursive (): U32 =>
  let big = $Big { a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10, k: 11, l: 12 }
  let rb = ref_of big
  let loaded = @storage.load rb
  let list = $Cons (10, $Cons (20, $Nil))
  let rl = &list
  let head = case @storage.load rl of
    $Cons (h, _) => h
    $Nil => 0
  return @u32.add (@u32.add loaded.a loaded.l) head

#entry func helper_and_loop (): U32 =>
  let sum = 0
  for i in 0..5000:
    let r = &i
    sum := @u32.add sum (@storage.load r)
  let seed = 0
  let carried = &seed
  for i in 1..6:
    carried := &i
  return @u32.add sum (@storage.load carried)

#entry func persistent_ref (): U32 =>
  return @storage.load const_refs[0]

#entry func borrow_and_return (): U32 =>
  let xs = #[10, 20]
  let r = &xs
  let first = (@storage.load r)[0]
  xs[0] := 99
  let pool: Array U32 = #[3, 4]
  let lk = ^pool[0]
  let linked = @storage.load lk
  pool[0] := 77
  return @u32.add (@u32.add first xs[0]) (@u32.add linked pool[0])
`,
    (guest) => {
      equal(guest.call("scalar_and_rebind", null), 140);
      equal(guest.call("field_and_nested", null), 42);
      equal(guest.call("boxed_and_recursive", null), 23);
      equal(guest.call("helper_and_loop", null), (4999 * 5000) / 2 + 5);
      equal(guest.call("persistent_ref", null), 42);
      equal(guest.call("persistent_ref", null), 42);
      equal(guest.call("borrow_and_return", null), 10 + 99 + 3 + 77);
    },
  );
  // Updating an array while &arr, a chained @storage.load, or ^pool[0] is still live fails with aliased_update.
  for (
    const snippet of [
      `#entry func bad (): U32 =>
  let xs = #[1, 2]
  let r = &xs
  xs[0] := 9
  return (@storage.load r)[0]`,
      `#entry func bad (): U32 =>
  let xs = #[1, 2]
  let r = &xs
  let alias = @storage.load r
  xs[0] := 9
  return alias[0]`,
      `#entry func bad (): U32 =>
  let pool: Array U32 = #[1, 2]
  let lk = ^pool[0]
  pool[0] := 9
  return @storage.load lk`,
    ]
  ) {
    await compileExpectedFailure(snippet + "\n", "aliased_update");
  }
});
