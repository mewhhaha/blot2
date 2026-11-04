import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("application arrays survive entries while frame storage and failed calls are reclaimed", async () => {
  await compileAndRun(
    `
const values: ResizeArray U32 = #[40]
const other: GrowArray {amount: U32} = #[{amount: 7}]
const append = func (n: U32) => return @storage.push values n
entry const count = func (add: Bool) => return do:
  if add:
    let written = append 9
  return @storage.length values
entry const advance = func (n: U32) => return do:
  let scratch: GrowArray U32 = #[n]
  let previous = @storage.copy values
  let written = @storage.write (&values[0]) scratch[0]
  return previous[0]
entry const read = func (index: U32) => return do:
  let scratch: GrowArray U32 = #[17]
  return @u32.add values[index] (@u32.sub scratch[0] 17)
entry const second = func () => return other[0].amount
`,
    (guest, bytes) => {
      equal(guest.call("count", false), 1);
      equal(guest.call("second", null), 7);
      equal(guest.call("advance", 42), 40);
      equal(guest.call("read", 0), 42);
      equal(guest.call("count", true), 2);
      equal(guest.call("read", 1), 9);
      let trapped = false;
      try {
        guest.call("read", 2);
      } catch {
        trapped = true;
      }
      equal(trapped, true);
      equal(guest.call("read", 0), 42);
      for (let n = 0; n < 512; n++) {
        equal(guest.call("advance", n), n === 0 ? 42 : n - 1);
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
      equal(guest.call("read", 0), 511);
    },
  );
});

Deno.test("application storage rejects borrowed elements and ignores unreachable initializers", async () => {
  await compileExpectedFailure(
    `
const values: GrowArray {borrow: &U32} = #[]
entry const answer = func () => return @storage.length values
`,
    "storage_unsupported",
  );
  await compileAndRun(
    `
const unused: GrowArray {borrow: &U32} = #[]
const live: GrowArray U32 = #[42]
entry const answer = func () => return live[0]
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

Deno.test("scoped source arrays keep references views and links stable across growth without RC", async () => {
  await compileAndRun(
    `
const make = func (): GrowArray U32 => return #[40]
const peek = func (item: &U32) => return @storage.load item
entry const answer = func () => return do:
  let items: GrowArray U32 = make ()
  let first: &U32 = &items[0]
  let link: ^U32 = ^items[0]
  let view: &[U32] = &items[0..1]
  let grown = @storage.push items 7
  let changed = @storage.write first 42
  let saved = peek first
  let copied = @storage.copy items
  let copy_ref = &copied[0]
  let copy_change = @storage.write copy_ref 99
  break @u32.add (@u32.add saved (@storage.load link)) view[0]
entry const staged = func () => return #do:
  break @u32.add 40 2
entry const resized = func () => return do:
  let items: ResizeArray U32 = #[7, 8]
  let popped = @storage.pop items
  let grown = @storage.push items 42
  let trimmed = @storage.truncate items 1
  break @u32.add popped (@storage.length items)
entry const frozen = func () => return do:
  let items: GrowArray U32 = #[]
  let grown = @storage.push items 42
  let fixed: Array U32 = @storage.freeze items
  break fixed[0]
entry const scalar_ref = func () => return do:
  let value = 41
  let snapshot = value
  let reference = &value
  let changed = @storage.write reference 42
  break @u32.add snapshot value
entry const checked = func (index: U32) => return do:
  let items: GrowArray U32 = #[42]
  break items[index]
`,
    (guest, bytes) => {
      equal(guest.call("answer", null), 126);
      equal(guest.call("resized", null), 9);
      equal(guest.call("staged", null), 42);
      equal(guest.call("frozen", null), 42);
      equal(guest.call("scalar_ref", null), 83);
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
          ["answer", "staged", "resized", "frozen", "scalar_ref", "checked"]
            .includes(name)
        ),
        true,
      );
    },
  );
});

Deno.test("scoped storage rejects mode coercion invalidation and unsupported escaping values", async () => {
  await compileExpectedFailure(
    `
entry const bad = func () => return do:
  let fixed = #[42]
  let grow: GrowArray U32 = fixed
  break 0
`,
    "type_mismatch",
  );
  await compileExpectedFailure(
    `
entry const bad = func () => return do:
  let items: ResizeArray U32 = #[42]
  let first = &items[0]
  let alias = items
  let shrunk = @storage.truncate alias 0
  break @storage.load first
`,
    "storage_borrow_conflict",
  );
  await compileExpectedFailure(
    `
entry const bad = func () => return do:
  let items: GrowArray U32 = #[42]
  let alias = items
  let fixed = @storage.freeze items
  let grown = @storage.push alias 1
  break fixed[0]
`,
    "storage_borrow_conflict",
  );
  await compileExpectedFailure(
    `
const bad = func () => return &(#[42])[0]
entry const answer = func () => return do:
  let items: GrowArray U32 = #[42]
  let first = bad ()
  break @storage.load first
`,
    "storage_escape",
  );
  await compileExpectedFailure(
    `
entry const bad = func () => return do:
  let items: GrowArray U32 = #[42]
  let staged = #run @storage.length items
  break staged
`,
    "storage_unsupported",
  );
});

Deno.test("data stacks reclaim lexical owners and admit shrinking after the final borrow use", async () => {
  await compileAndRun(
    `
const temporary = func (x: U32) => return do:
  let items: GrowArray U32 = #[x]
  break items[0]
const choose = func (flag: Bool): GrowArray U32 => return
  if flag then #[40] else #[41]
entry const grow = func () => return do:
  let items: GrowArray U32 = #[42]
  let reference = &items[0]
  for i in 0..5000:
    let pushed = @storage.push items i
    let used = temporary i
  break @u32.add (@storage.load reference) (@storage.length items)
entry const shrink = func () => return do:
  let items: ResizeArray U32 = #[42, 7]
  let reference = &items[0]
  let saved = @storage.load reference
  let removed = @storage.pop items
  break @u32.add saved removed
entry const returned = func (flag: Bool) => return do:
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
  await compileExpectedFailure(
    `
const escape = func () => return do:
  let items: GrowArray U32 = #[42]
  break {reference: &items[0]}
entry const bad = func () => return @storage.load (escape ()).reference
`,
    "storage_escape",
  );
});

Deno.test("data-stack arrays store records and preserve the roots of their links", async () => {
  await compileAndRun(
    `
entry const answer = func () => return do:
  let pool: GrowArray U32 = #[40, 42]
  let rows: GrowArray {value: U32, target: ^U32} = #[]
  let grown = @storage.push rows {value: 1, target: ^pool[0]}
  let grown = @storage.push rows {target: ^pool[1], value: 2}
  let row = rows[1]
  let copied = @storage.copy rows
  let changed = @storage.write (&copied[0]) {value: 9, target: ^pool[1]}
  break @u32.add (@storage.load row.target) rows[0].value
`,
    (guest) => equal(guest.call("answer", null), 43),
  );
  await compileExpectedFailure(
    `
const escape = func () => return do:
  let pool: GrowArray U32 = #[42]
  let rows: GrowArray {target: ^U32} = #[{target: ^pool[0]}]
  break rows
entry const bad = func () => return @storage.load (escape ())[0].target
`,
    "storage_escape",
  );
});

Deno.test("data-stack numeric layouts preserve F32 fields and reclaim loop exits", async () => {
  await compileAndRun(
    `
entry const numeric = func (input: F32) => return do:
  let rows: GrowArray {x: F32, y: U32} = #[{y: 1, x: input}]
  let pushed = @storage.push rows {x: @f32.add input 1.0, y: 2}
  break @f32.add rows[0].x rows[1].x
entry const exits = func (limit: U32) => return do:
  let outer: GrowArray U32 = #[42]
  let total = 0
  for i in 0..limit:
    let temporary: GrowArray U32 = #[i]
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
entry const answer = func () => return do:
  let items: GrowArray U32 = #[40]
  let reference = &items[0]
  let read = func (offset: U32) => return @u32.add (@storage.load reference) offset
  let plus_one = add 1
  let grown = @storage.push items 99
  break apply read (plus_one 1)
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
  await compileExpectedFailure(
    `
entry const bad = func () => return do:
  let items: ResizeArray U32 = #[42]
  let reference = &items[0]
  let read = func () => return @storage.load reference
  let shrunk = @storage.truncate items 0
  break read ()
`,
    "storage_borrow_conflict",
  );
});

Deno.test("joined aliases and caller temporaries retain every possible borrow root", async () => {
  await compileAndRun(
    `
entry const answer = func (flag: Bool) => return do:
  let left: GrowArray U32 = #[40]
  let right: GrowArray U32 = #[42]
  let selected = left
  if flag:
    selected := right
  let reference = &selected[0]
  let pushed = @storage.push selected 1
  break @storage.load reference
`,
    (guest) => {
      equal(guest.call("answer", true), 42);
      equal(guest.call("answer", false), 40);
    },
  );
  await compileExpectedFailure(
    `
entry const bad = func (flag: Bool) => return do:
  let left: ResizeArray U32 = #[40]
  let right: ResizeArray U32 = #[42]
  let reference = if flag then &left[0] else &right[0]
  let shrunk = @storage.truncate right 0
  break @storage.load reference
`,
    "storage_borrow_conflict",
  );
  await compileExpectedFailure(
    `
const consume = func (reference: &U32) -> (removed: U32) => return @storage.load reference
entry const bad = func () => return do:
  let items: ResizeArray U32 = #[42]
  break consume (&items[0]) (@storage.pop items)
`,
    "storage_borrow_conflict",
  );
});

Deno.test("conditional owned returns release earlier loop iterations and transfer only the selected owner", async () => {
  await compileAndRun(
    `
const choose = func (limit: U32): GrowArray U32 => do:
  for i in 0..limit:
    let items: GrowArray U32 = #[i]
    if i == 5:
      return items
  return #[42]
entry const answer = func (limit: U32) => return do:
  let selected = choose limit
  let independent: GrowArray U32 = #[100]
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
entry const branch = func (stop: Bool) => return do:
  let values = #[2, if stop then 0 else 3, 9]
  return scan (&values[0..values.length])
entry const pattern = func (stop: Bool) => return do:
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
