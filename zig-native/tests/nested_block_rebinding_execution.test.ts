import { deepStrictEqual as same, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

// Issue #11: a nested do: keeps its own scope, so a := of an enclosing name
// that is never read inside the block would silently change nothing.
Deno.test("an unread rebinding inside a case arm block is rejected", async () => {
  await compileExpectedFailure(`
type Beat is data = #Up | #Down
entry const main = fn (n: U32) -> U32 => do:
  let beat = if n > 0 then #Up else #Down
  let count = 0
  case beat of
    #Up => do:
      count := 7
    #Down => do:
      count := 3
  return count
`, "dead_rebinding");
});

Deno.test("an unread rebinding inside a statement do block is rejected", async () => {
  await compileExpectedFailure(`
entry const main = fn (n: U32) -> U32 => do:
  let count = n
  do:
    count := self + 1
  return count
`, "dead_rebinding");
});

Deno.test("rebinding read in its block or its branches, or carried out by if, case values and loops, still compiles", async () => {
  await compileAndRun(`
type Beat is data = #Up | #Down
const step = fn n => n + 1
const build = fn start => do:
  start := step self
  start := step self
  return start
entry const arm = fn (n: U32) -> U32 => do:
  let beat = if n > 0 then #Up else #Down
  let count = 2
  let result = case beat of
    #Up => do:
      count := count + 5
      return count
    #Down => do:
      count := self + 1
      return count
  return result
entry const branch = fn (n: U32) -> U32 => do:
  let count = 0
  if n > 0:
    count := 7
  else:
    count := 3
  return count
entry const chosen = fn (n: U32) -> U32 => do:
  let beat = if n > 0 then #Up else #Down
  let count = 0
  count := case beat of
    #Up => 7
    #Down => 3
  return count
entry const guarded = fn (n: U32) -> U32 => do:
  let held = n
  return case n of
    0 => do:
      let total = 1
      if held == 0:
        held := 9
        total := held + 1
      return total
    _ => 2
entry const looped = fn (n: U32) -> U32 => do:
  let total = 0
  for 0 .. n:
    total := self + 2
  return total + build 0
`, (guest) => {
    equal(guest.call("arm", 1), 7);
    equal(guest.call("arm", 0), 3);
    equal(guest.call("branch", 1), 7);
    equal(guest.call("branch", 0), 3);
    equal(guest.call("chosen", 1), 7);
    equal(guest.call("chosen", 0), 3);
    equal(guest.call("guarded", 0), 10);
    equal(guest.call("guarded", 1), 2);
    equal(guest.call("looped", 3), 8);
  });
});
