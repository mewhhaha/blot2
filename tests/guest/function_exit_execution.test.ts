import { deepStrictEqual as equal } from "node:assert/strict";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("return exits the function while break value finishes the nearest do", async () => {
  await compileAndRun(
    `#entry const answer = func (flag: Bool) : U32 => return do:
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

Deno.test("return works in inferred closures", async () => {
  await compileAndRun(
    `const identity = func value => return do:
  return value
#entry const generic = func () => return identity 9
`,
    (guest) => {
      equal(guest.call("generic", null), 9);
    },
  );
});

Deno.test("return without a function is diagnosed at its source", async () => {
  const source = "const value = do:\n  return 7\n#entry const answer = value\n";
  const start = source.indexOf("return 7");
  await compileExpectedFailure(source, "return_outside_function", undefined, {
    span: [start, start + "return 7".length],
  });
});

Deno.test("return exits from a statement case arm and stays within the innermost function", async () => {
  await compileAndRun(
    `#entry const choose = func (flag: Bool) : U32 => return do:
  let count = 9
  case flag of
    true => do:
      return 7
    false => do:
      count := self + 1
  break count
#entry const nested = func (value: U32) : U32 => return do:
  let inner = func (input: U32) : U32 => return do:
    return input + 1
  break inner value + 10
#entry const expression_case = func (flag: Bool) : U32 => return do:
  let choice = case flag of
    true => do:
      return 42
    false => do:
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
    `#entry const choose = func (stop: Bool) : U32 => return do:
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
    `#entry const matched = func (flag: Bool) : U32 => return do:
  let candidate = if flag then $Some 42 else $Nothing
  if let $Some value = candidate:
    return value
  break 7
#entry const fallback = func (flag: Bool) : U32 => return do:
  let $Some value = if flag then $Some 42 else $Nothing else:
    return 9
  break value
#entry const looped = func (flag: Bool) : U32 => return do:
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
