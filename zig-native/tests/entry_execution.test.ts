import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("generic exported functions infer numeric evidence through actual closure captures", async () => {
  await compileAndRun(`
entry const increment = fn value => value + 1
entry const doubled = fn value => value * 2
const compose = fn outer => fn inner => fn value => outer (inner value)
entry const composed = compose doubled increment
entry const factorial = fn value => do:
  if value <= 1:
    return 1
  return value * factorial (value - 1)
entry const floating = fn value => value + 1.5
`, guest => {
    for (const value of [0, 1, 20, 41, 0xffffffff]) {
      equal(guest.call("increment", value), (value + 1) >>> 0);
      equal(guest.call("doubled", value), Math.imul(value, 2) >>> 0);
      equal(guest.call("composed", value), Math.imul((value + 1) >>> 0, 2) >>> 0);
    }
    for (const [value, result] of [[0, 1], [1, 1], [2, 2], [5, 120], [8, 40320]]) {
      equal(guest.call("factorial", value), result);
    }
    for (const value of [0, 1.25, -2.5]) equal(guest.call("floating", value), Math.fround(value + 1.5));
  }, { prelude: "std/prelude.blot" });
});

Deno.test("entry inference preserves unhandled operations and unresolved host parameters", async () => {
  await compileExpectedFailure(`
effect Read: Unit -> U32
entry const invalid = fn value => do:
  use ignored <- Read ()
  return value + 1
`, "entry_type", undefined, { prelude: "std/prelude.blot" });
  await compileExpectedFailure(`entry const identity = fn value => value\n`, "entry_type");
  await compileExpectedFailure(`
effect Read: Unit -> U32
entry const invalid = fn (callback: Unit -> U32 ! {Read}) => callback ()
`, "entry_type");
});

Deno.test("repository prelude and syntax examples execute their exported functions", async () => {
  const prelude = await Deno.readTextFile("examples/prelude.blot");
  await compileAndRun(prelude, guest => {
    equal(guest.call("increment", 41), 42);
    equal(guest.call("doubled", 21), 42);
    equal(guest.call("add_two", 40), 42);
    equal(guest.call("transform", 20), 42);
    equal(guest.read("const_answer"), 42);
    equal(guest.call("answer", null), 42);
    equal(guest.call("generic_identity", null), 42);
    equal(guest.call("named_operator", null), 42);
    equal(guest.call("inspect", true), 42);
    equal(guest.call("inspect", false), 0);
    equal(guest.call("recover", true), 42);
    equal(guest.call("recover", false), 0);
  }, { prelude: "std/prelude.blot" });
  const syntax = await Deno.readTextFile("examples/syntax.blot");
  await compileAndRun(syntax, guest => {
    equal(guest.call("short_circuit", null), false);
    equal(guest.call("lazy_fallback", null), 42);
    equal(guest.call("factorial", 5), 120);
    equal(guest.read("operator_example"), 7);
    equal(guest.call("recursive_example", 8), 40320);
    equal(guest.call("matching_example", null), 42);
    equal(guest.call("event_example", null), 42);
    equal(guest.call("vector_example", null), 50);
    equal(guest.call("array_snapshot", null), 22);
    equal(guest.call("provider_example", null), 42);
  }, { prelude: "std/prelude.blot" });
});
