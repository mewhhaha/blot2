import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

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
  await compileExpectedFailure("data First = #First { value: U32 }\ndata Second = #Second { value: U32 }\nconst First.plus = fn box => fn delta => @u32.add box.value delta\nconst invoke: a -> U32 where { receiver \"plus\" a Unit (U32 -> U32) } = fn box => do:\n  let bound = box.plus\n  return bound 1\nentry const answer = fn () => @u32.add (invoke (#First { value: 40 })) (invoke (#Second { value: 40 }))\nentry const folded = answer ()\n", "missing_member", undefined, { prelude: "none", span: [335, 341] });
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

Deno.test("curried callable environments stay owned until consumption and retire after each invocation", async () => {
  await compileAndRun(
    `
type Box is data = #Box { value: U32 }
const Box.plus = fn box => fn delta => @u32.add box.value delta
const invoke: a -> U32 where { receiver "plus" a Unit (U32 -> U32) } = fn box => do:
  let bound = box.plus
  return bound 1
entry const answer = fn (value: U32) => invoke (#Box { value: value })
entry const memory = fn () -> Array U32 => #[]
`,
    (_guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const manifest = new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      );
      equal(manifest.join(","), "2,2,0");
      const raw = new WebAssembly.Instance(module).exports;
      const count = (name: string) =>
        Number((raw[`blot:rc_${name}`] as WebAssembly.Global).value);
      const answer = raw.answer as CallableFunction;
      for (let index = 0; index < 64; index++) equal(answer(41), 42);
      const retired = count("destroyed");
      const retains = count("retains");
      const releases = count("releases");
      const memory = raw["blot:memory"] as WebAssembly.Memory;
      const warm = memory.buffer.byteLength;
      for (let index = 0; index < 2048; index++) {
        equal(answer(index), index + 1);
        equal(count("roots"), 0);
        equal(count("leases"), 0);
        equal(memory.buffer.byteLength, warm);
      }
      if (count("destroyed") <= retired) {
        throw new Error(
          "Callable graphs did not retire",
        );
      }
      // Every fresh acyclic owner retires once; field/alias retains balance
      // their releases independently of how many environment boxes survive.
      equal(
        count("releases") - releases - (count("retains") - retains),
        count("destroyed") - retired,
      );
      (raw["blot:ownership_leave"] as CallableFunction)(2);
    },
    { prelude: "none", asynchronous: false },
  );
});

Deno.test("single-reference named captures preserve static aliases and later curry stages", async () => {
  await compileAndRun(
    `
const add = fn (values: Array U32) => fn (bias: U32) => fn (index: U32) => @u32.add values[index] bias
const first = fn (values: Array U32) => fn (index: U32) => values[index]
const saved = first #[41, 8192]
entry const run = fn (count: U32) => do:
  let original = #[41, 8192]
  let shared = add original
  let biased = shared 8192
  let changed = @array.set original 0 99
  let later = first changed
  let readers = #[saved, later]
  let chosen = readers[@u32.rem count 2]
  let total = 0
  for index in 0..count:
    let reader = first (@array.fill 16 index)
    total := @u32.add self (reader 0)
  return #[biased 0, later 0, chosen 0, original[0], total]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const manifest = new Uint8Array(
        WebAssembly.Module.customSections(module, "blot:ownership")[0],
      );
      equal(manifest.join(","), "2,2,0");
      const read = (count: number) => {
        const result = guest.call("run", count) as Uint32Array;
        let expected = 41;
        if (count % 2) expected = 99;
        equal(
          result.join(","),
          `8233,99,${expected},41,${count * (count - 1) / 2}`,
        );
      };
      read(64);
      const warm = guest.memoryBytes();
      read(8192);
      read(8193);
      equal(guest.memoryBytes(), warm);
    },
    { prelude: "none", asynchronous: false },
  );
});

Deno.test("named environment roles keep scalar bits distinct in both tiers and invocation modes", async () => {
  const directory = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "blot-callable-roles-",
  });
  const entry = `${directory}/main.blot`;
  try {
    await Deno.writeTextFile(entry, `
const read = fn (values: Array U32) => fn (index: U32) => values[index]
const scalar = fn (value: U32) => fn (index: U32) => @u32.add value index
const offset = fn (value: F32) => fn (other: F32) => @f32.add value other
const saved = read #[41, 8192]
entry const run = fn (seed: U32) => do:
  let choices = #[saved, read #[seed, 65536]]
  let selected = choices[@u32.rem seed 2]
  let arithmetic = #[scalar 8192, scalar seed]
  let calculate = arithmetic[@u32.rem seed 2]
  return @u32.add (selected 0) (calculate 1)
entry const floating = fn (values: Array F32) => do:
  let choices = #[offset values[0], offset 8192.0]
  let selected = choices[@u32.rem (@array.length values) 2]
  return selected 1.0
`);
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url),
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build();
        if (!result.success) throw new Error(JSON.stringify(result.diagnostics));
        const module = new WebAssembly.Module(result.bytes);
        equal(
          new Uint8Array(WebAssembly.Module.customSections(module, "blot:ownership")[0]).join(","),
          "2,2,0",
        );
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            for (const [seed, expected] of [[0, 8234], [8192, 8234], [41, 83]]) {
              if (asynchronous) equal(await guest.callAsync("run", seed), expected);
              else equal(guest.call("run", seed), expected);
            }
            for (const [values, expected] of [[Float32Array.of(41.5, 1), 42.5], [Float32Array.of(41.5), 8193]] as const) {
              if (asynchronous) equal(await guest.callAsync("floating", values), expected);
              else equal(guest.call("floating", values), expected);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
