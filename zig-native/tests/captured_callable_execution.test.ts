import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("retained callable bound-method sync", async () => {
  await compileAndRun("\ntype Box is data = #Box { value: U32 }\nconst Box.plus = fn box => fn delta => @u32.add box.value delta\nconst invoke: a -> U32 where { receiver \"plus\" a Unit (U32 -> U32) } = fn box => do:\n  let bound = box.plus\n  return bound 1\nentry const answer = fn () => invoke (#Box { value: 41 })\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained callable bound-method JSPI", async () => {
  await compileAndRun("\ntype Box is data = #Box { value: U32 }\nconst Box.plus = fn box => fn delta => @u32.add box.value delta\nconst invoke: a -> U32 where { receiver \"plus\" a Unit (U32 -> U32) } = fn box => do:\n  let bound = box.plus\n  return bound 1\nentry const answer = fn () => invoke (#Box { value: 41 })\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained callable bound-snapshot sync", async () => {
  await compileAndRun("data Box = #Box { value: U32 }\nconst Box.plus = fn box => fn delta => @u32.add box.value delta\nentry const answer = fn () => do:\n  let box = #Box { value: 41 }\n  let bound = box.plus\n  box.value := 99\n  return bound 1\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained callable bound-snapshot JSPI", async () => {
  await compileAndRun("data Box = #Box { value: U32 }\nconst Box.plus = fn box => fn delta => @u32.add box.value delta\nentry const answer = fn () => do:\n  let box = #Box { value: 41 }\n  let bound = box.plus\n  box.value := 99\n  return bound 1\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained callable captured-snapshot sync", async () => {
  await compileAndRun("entry const answer = fn () => do:\n  let bias = 40\n  let bound = fn value => @u32.add bias value\n  bias := 99\n  return bound 2\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained callable captured-snapshot JSPI", async () => {
  await compileAndRun("entry const answer = fn () => do:\n  let bias = 40\n  let bound = fn value => @u32.add bias value\n  bias := 99\n  return bound 2\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained callable bound-cache-nominals sync", async () => {
  await compileAndRun("data First = #First { value: U32 }\ndata Second = #Second { value: U32 }\nconst First.plus = fn box => fn delta => @u32.add box.value delta\nconst Second.plus = fn box => fn delta => @u32.add box.value (@u32.mul delta 2)\nconst invoke: a -> U32 where { receiver \"plus\" a Unit (U32 -> U32) } = fn box => do:\n  let bound = box.plus\n  return bound 1\nentry const answer = fn () => @u32.add (invoke (#First { value: 40 })) (invoke (#Second { value: 40 }))\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 83);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 83);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained callable bound-cache-nominals JSPI", async () => {
  await compileAndRun("data First = #First { value: U32 }\ndata Second = #Second { value: U32 }\nconst First.plus = fn box => fn delta => @u32.add box.value delta\nconst Second.plus = fn box => fn delta => @u32.add box.value (@u32.mul delta 2)\nconst invoke: a -> U32 where { receiver \"plus\" a Unit (U32 -> U32) } = fn box => do:\n  let bound = box.plus\n  return bound 1\nentry const answer = fn () => @u32.add (invoke (#First { value: 40 })) (invoke (#Second { value: 40 }))\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 83);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 83);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained callable bound-cache-effects sync", async () => {
  await compileAndRun("type Read is effect = { get: Unit -> U32 }\nconst call = fn callback => do:\n  let bound = fn value => callback value\n  return bound 1\nconst provider = @effect.provider Read.get (fn () => 41)\nentry const answer = fn () => do provider:\n  let pure = call (fn value => @u32.add value 40)\n  use effectful <- call (fn value => do:\n    use seed <- Read.get ()\n    return @u32.add seed value\n  )\n  return @u32.add pure effectful\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 83);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 83);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained callable bound-cache-effects JSPI", async () => {
  await compileAndRun("type Read is effect = { get: Unit -> U32 }\nconst call = fn callback => do:\n  let bound = fn value => callback value\n  return bound 1\nconst provider = @effect.provider Read.get (fn () => 41)\nentry const answer = fn () => do provider:\n  let pure = call (fn value => @u32.add value 40)\n  use effectful <- call (fn value => do:\n    use seed <- Read.get ()\n    return @u32.add seed value\n  )\n  return @u32.add pure effectful\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 83);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 83);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained callable captured-builtin sync", async () => {
  await compileAndRun("const make_adder = fn value => fn other => @u32.add value other\nconst compose = fn first => fn second => fn value => first (second value)\nentry const add_forty = make_adder 40\nentry const expected = add_forty 2\nentry const answer = fn () => do:\n  let value = 999\n  let increment = make_adder 1\n  let result = compose increment add_forty\n  return result 1\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained callable captured-builtin JSPI", async () => {
  await compileAndRun("const make_adder = fn value => fn other => @u32.add value other\nconst compose = fn first => fn second => fn value => first (second value)\nentry const add_forty = make_adder 40\nentry const expected = add_forty 2\nentry const answer = fn () => do:\n  let value = 999\n  let increment = make_adder 1\n  let result = compose increment add_forty\n  return result 1\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained callable captured-effect sync", async () => {
  await compileAndRun("type Read is effect = { get: Unit -> U32 }\nconst make = fn value => fn other => do:\n  use seed <- Read.get ()\n  return @u32.add value (@u32.add seed other)\nconst compose = fn first => fn second => fn value => first (second value)\nconst add_forty = make 40\nconst provider = @effect.provider Read.get (fn () => 1)\nentry const answer = fn () => do provider:\n  let increment = fn value => @u32.add value 1\n  use result <- (compose increment add_forty) 0\n  return result\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained callable captured-effect JSPI", async () => {
  await compileAndRun("type Read is effect = { get: Unit -> U32 }\nconst make = fn value => fn other => do:\n  use seed <- Read.get ()\n  return @u32.add value (@u32.add seed other)\nconst compose = fn first => fn second => fn value => first (second value)\nconst add_forty = make 40\nconst provider = @effect.provider Read.get (fn () => 1)\nentry const answer = fn () => do provider:\n  let increment = fn value => @u32.add value 1\n  use result <- (compose increment add_forty) 0\n  return result\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained callable captured-original sync", async () => {
  await compileAndRun("\nconst make_adder = fn value => fn other => value + other\nentry const add_forty = make_adder 40\nentry const expected = add_forty 2\nentry const answer = fn () => do:\n  let value = 999\n  let increment = make_adder 1\n  let result = compose increment add_forty\n  return result 1\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    equal(guest.read("expected"), 42);
    for (let count = 0; count < 100; count++) {
      equal(guest.call("answer", null), 42);
      equal(guest.call("add_forty", 2), 42);
    }
  }, { prelude: "std/prelude.blot", asynchronous: false });
});

Deno.test("retained callable captured-original JSPI", async () => {
  await compileAndRun("\nconst make_adder = fn value => fn other => value + other\nentry const add_forty = make_adder 40\nentry const expected = add_forty 2\nentry const answer = fn () => do:\n  let value = 999\n  let increment = make_adder 1\n  let result = compose increment add_forty\n  return result 1\nentry const folded = answer ()\n", async guest => {
    equal(guest.read("folded"), 42);
    equal(guest.read("expected"), 42);
    for (let count = 0; count < 100; count++) {
      equal(await guest.callAsync("answer", null), 42);
      equal(await guest.callAsync("add_forty", 2), 42);
    }
  }, { prelude: "std/prelude.blot", asynchronous: true });
});

Deno.test("retained callable rejects bound-cache-missing", async () => {
  await compileExpectedFailure("data First = #First { value: U32 }\ndata Second = #Second { value: U32 }\nconst First.plus = fn box => fn delta => @u32.add box.value delta\nconst invoke: a -> U32 where { receiver \"plus\" a Unit (U32 -> U32) } = fn box => do:\n  let bound = box.plus\n  return bound 1\nentry const answer = fn () => @u32.add (invoke (#First { value: 40 })) (invoke (#Second { value: 40 }))\nentry const folded = answer ()\n", "missing_member", undefined, { prelude: "none" });
});

Deno.test("retained callable rejects captured-wrong-row", async () => {
  await compileExpectedFailure("type Read is effect = { get: Unit -> U32 }\nconst make = fn value => fn other => do:\n  use seed <- Read.get ()\n  return @u32.add value (@u32.add seed other)\nconst add_forty = make 40\nentry const answer: Unit -> U32 ! {} = fn () => add_forty 2\n", "effect_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained callable rejects captured-wrong-input", async () => {
  await compileExpectedFailure("const make = fn value => fn other => @u32.add value other\nconst add_forty = make 40\nentry const answer = fn () => add_forty 2.5\n", "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained callable rejects captured-unknown-source", async () => {
  await compileExpectedFailure("const make = fn value => fn other => value\nconst ignored = make (fn value => value)\nentry const answer = fn () => ignored 1\n", "entry_type", undefined, { prelude: "none" });
});
