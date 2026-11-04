import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("explicit function returns and arrow separated currying execute in Wasm", async () => {
  await compileAndRun(
    `
const add = func x -> y => return x + y
const fn = 40
const add_typed = func (x: U32) -> (y: U32): U32 => return x + y
type Box is data = $Box U32
const unbox = func ($Box value) => do:
  return value
const choose = func flag => do:
  if flag:
    return 42
  return 7
const nested = func () => do:
  let value = do:
    break 40
  return value + 2
entry const direct = func (x: U32) => return x
entry const partial = func () => return (add 40) 2
entry const old_identifier = func () => return add fn 2
entry const annotated = func () => return add_typed 40 2
entry const matched = func () => return unbox ($Box 42)
entry const selected = func (flag: Bool) => return choose flag
entry const block = func () => return nested ()
entry const returned_block = func () => return do:
  break 42
`,
    (guest) => {
      equal(guest.call("direct", 42), 42);
      equal(guest.call("partial", null), 42);
      equal(guest.call("old_identifier", null), 42);
      equal(guest.call("annotated", null), 42);
      equal(guest.call("matched", null), 42);
      equal(guest.call("selected", true), 42);
      equal(guest.call("selected", false), 7);
      equal(guest.call("block", null), 42);
      equal(guest.call("returned_block", null), 42);
    },
  );
});

Deno.test("function do blocks reject fallthrough and block results without a return", async () => {
  for (
    const source of [
      "entry const invalid = func () => do:\n  break 42\n",
      "entry const invalid = func (flag: Bool) => do:\n  if flag:\n    return ()\n",
      "entry const invalid = func () => do:\n  let inner = func () => return 42\n  break inner ()\n",
      "type Box is data = $Box U32\nentry const invalid = func ($Box value) => do:\n  break value\n",
    ]
  ) await compileExpectedFailure(source, "function_return_required");
});
