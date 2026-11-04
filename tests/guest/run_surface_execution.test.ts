import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("run staging evaluates target expressions and dollar constructors through Wasm", async () => {
  await compileAndRun(
    `
type Choice is data = $Some U32 | $None
const double = func value => return value + value
const base = 21
const prepared = #run double base
entry const answer = func () => return do:
  let values = #run #[prepared, 7]
  let selected = $Some values[0]
  break case selected of
    $Some value => value
    $None => 0
entry const rounded = func () => return #run 16777216.0 + 1.0
entry const flag = func () => return true
entry const lists = func () => return @list.length [1, 2]
entry const nested = func () => return #run @u32.add (#run 20) 22
entry const wrapped = func () => return #run @u32.add 4294967295 1
entry const block = func () => return #run do:
  let value = 40
  break @u32.add value 2
entry const short_block = func () => return #do:
  let value = 40
  break @u32.add value 2
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      equal(guest.call("rounded", null), 16777216);
      equal(guest.call("flag", null), true);
      equal(guest.call("lists", null), 2);
      equal(guest.call("nested", null), 42);
      equal(guest.call("wrapped", null), 0);
      equal(guest.call("block", null), 42);
      equal(guest.call("short_block", null), guest.call("block", null));
    },
  );
});

Deno.test("run staging rejects runtime inputs and does not publish failed evaluation", async () => {
  await compileExpectedFailure(
    "entry const invalid = func (value: U32) => return #run value\n",
    "stage_unavailable",
  );
  await compileExpectedFailure(
    'entry const invalid = func () : U32 => return #run @panic "static failure"\n',
    "const_panic",
  );
  await compileExpectedFailure(
    "effect Read: Unit -> U32\nentry const invalid = func () => return #run Read ()\n",
    "effect_mismatch",
  );
  await compileExpectedFailure(
    "entry const invalid = func (value: U32) => return #do:\n  let next = value + 1\n  break next\n",
    "stage_unavailable",
  );
  await compileExpectedFailure(
    'entry const invalid = func () : U32 => return #do:\n  break @panic "static failure"\n',
    "const_panic",
  );
  await compileExpectedFailure(
    "effect Read: Unit -> U32\nentry const invalid = func () => return #do:\n  use value <- Read ()\n  break value\n",
    "effect_mismatch",
  );
});
