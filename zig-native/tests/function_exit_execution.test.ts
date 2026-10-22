import { deepStrictEqual as equal } from "node:assert/strict";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("return exits the function while break value finishes the nearest do", async () => {
  await compileAndRun(
    `entry const answer = fn (flag: Bool) -> U32 => do:
  let inner = do:
    if flag:
      return 7
    break 3
  break inner + 1
`,
    (guest) => {
      equal(guest.call("answer", true), 7);
      equal(guest.call("answer", false), 4);
    },
  );
});

Deno.test("return works in inferred and once closures", async () => {
  await compileAndRun(
    `const identity = fn value => do:
  return value
const make_once = fn () -> once (Unit -> U32) => fn () => do:
  return 7
entry const generic = fn () => identity 9
entry const one_shot = fn () => (make_once ()) ()
`,
    (guest) => {
      equal(guest.call("generic", null), 9);
      equal(guest.call("one_shot", null), 7);
    },
  );
});

Deno.test("return without a function is diagnosed at its source", async () => {
  const source = "const value = do:\n  return 7\nentry const answer = value\n";
  const start = source.indexOf("return 7");
  await compileExpectedFailure(source, "return_outside_function", undefined, {
    span: [start, start + "return 7".length],
  });
});

Deno.test("return exits from a statement case arm and stays within the innermost function", async () => {
  await compileAndRun(
    `entry const choose = fn (flag: Bool) -> U32 => do:
  let count = 9
  case flag of
    #True => do:
      return 7
    #False => do:
      count := self + 1
  break count
entry const nested = fn (value: U32) -> U32 => do:
  let inner = fn (input: U32) -> U32 => do:
    return input + 1
  break inner value + 10
entry const expression_case = fn (flag: Bool) -> U32 => do:
  let choice = case flag of
    #True => do:
      return 42
    #False => do:
      break 7
  break choice + 1
`,
    (guest) => {
      equal(guest.call("choose", true), 7);
      equal(guest.call("choose", false), 10);
      equal(guest.call("nested", 20), 31);
      equal(guest.call("expression_case", true), 42);
      equal(guest.call("expression_case", false), 8);
    },
  );
});

Deno.test("break value leaves do through a loop while bare break leaves only the loop", async () => {
  await compileAndRun(
    `entry const choose = fn (stop: Bool) -> U32 => do:
  let inner = do:
    for index in 0..4:
      if stop:
        break 20
      break
    break 5
  break inner + 1
`,
    (guest) => {
      equal(guest.call("choose", true), 21);
      equal(guest.call("choose", false), 6);
    },
  );
});

Deno.test("return exits through if let, let else, and a loop", async () => {
  await compileAndRun(
    `entry const matched = fn (flag: Bool) -> U32 => do:
  let candidate = if flag then #Some 42 else #Nothing
  if let #Some value = candidate:
    return value
  break 7
entry const fallback = fn (flag: Bool) -> U32 => do:
  let #Some value = if flag then #Some 42 else #Nothing else:
    return 9
  break value
entry const looped = fn (flag: Bool) -> U32 => do:
  for index in 0..3:
    if flag:
      return index + 40
  break 7
`,
    (guest) => {
      equal(guest.call("matched", true), 42);
      equal(guest.call("matched", false), 7);
      equal(guest.call("fallback", true), 42);
      equal(guest.call("fallback", false), 9);
      equal(guest.call("looped", true), 40);
      equal(guest.call("looped", false), 7);
    },
  );
});

Deno.test("return across a monadic continuation has a source diagnostic", async () => {
  const source = `const choose = fn (flag: Bool) -> Maybe U32 => do:
  let wrapped = do (monad Maybe):
    if flag:
      return #Some 42
    break 7
  break wrapped
entry const answer = fn (flag: Bool) -> U32 => Maybe.unwrap_or 0 (choose flag)
`;
  const start = source.indexOf("return #Some 42");
  await compileExpectedFailure(source, "return_across_continuation", undefined, {
    span: [start, start + "return #Some 42".length],
  });
});

Deno.test("return from a request handler cancels the captured computation", async () => {
  await compileAndRun(
    `type Tick is effect = { read: Unit -> U32 }
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      effect Tick.read () =>
        return 42
      complete value =>
        break value
entry const answer = fn () => handled (@computation (fn () => do:
  use Tick.read ()
  break @panic "cancelled computation continued"
))
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});

Deno.test("return through a nested request callback has a source diagnostic", async () => {
  const source = `type Tick is effect = { read: Unit -> U32 }
const handled = fn computation => do:
  let inner = do:
    for request in @requests computation:
      case request of
        effect Tick.read () =>
          return 42
        complete value =>
          break value
    break 0
  break inner
entry const answer = fn () => handled (@computation (fn () => Tick.read ()))
`;
  const start = source.indexOf("return 42");
  await compileExpectedFailure(source, "return_across_continuation", undefined, {
    span: [start, start + "return 42".length],
  });
});
