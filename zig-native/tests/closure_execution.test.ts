import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("runtime nested closures capture immutable lexical versions transitively", async () => {
  await compileAndRun(`
const add = fn (left: U32) => fn (right: U32) => left + right
entry const snapshot = fn (input: U32) -> U32 => do:
  let saved = input
  let nested = fn (first: U32) => fn (second: U32) => saved + first + second
  saved := 0
  let partial = add input
  let inner = nested 1
  return inner (partial 1)
`, guest => {
    for (const input of [0, 1, 20, 2000, 0x7fffffff]) equal(guest.call("snapshot", input), (input * 2 + 2) >>> 0);
    for (let input = 0; input < 2000; input++) equal(guest.call("snapshot", input), input * 2 + 2);
  });
});

Deno.test("runtime partial named and higher-order calls share generic U32 and F32 bodies", async () => {
  await compileAndRun(`
const combine = fn left => fn right => left + right
const apply = fn callable => fn value => callable value
entry const integer = fn (value: U32) -> U32 => apply (combine value) 22
entry const floating = fn (value: F32) -> F32 => apply (combine value) 1.5
`, guest => {
    equal(guest.call("integer", 20), 42);
    equal(guest.call("integer", 0xffffffff), 21);
    for (const value of [0, -0, 1.23456789, -7.5]) equal(guest.call("floating", value), Math.fround(Math.fround(value) + 1.5));
  });
});

Deno.test("runtime first-class constructors and local closure pattern bindings retain typed payloads", async () => {
  await compileAndRun(`
type Box value is data = #Box value
entry const boxed = fn (input: U32) -> U32 => do:
  let wrap = #Box
  let choose = fn box -> U32 => case box of
    #Box value => value + input
  return choose (wrap 21)
entry const direct = fn (value: U32) -> U32 => (fn (argument: U32) => argument + 1) value
`, guest => {
    equal(guest.call("boxed", 21), 42);
    equal(guest.call("boxed", 0), 21);
    equal(guest.call("direct", 41), 42);
  });
});
