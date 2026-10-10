import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("higher order summaries preserve callback captures rows and returned stages across retained imports", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const depth = 6;
  const repetitions = 2 ** depth;
  const lib = [
    "type Count is data = #Count U32",
    "type Other is data = #Other U32",
  ];
  for (
    const [kind, invocation] of [
      ["apply", "callback value"],
      ["reduce", "callback value value"],
      ["returned", "callback () value"],
    ]
  ) {
    lib.push(
      `const ${kind}_0 = fn callback => fn value => do:`,
      "  let compared = @type.same #Count #Other",
      `  use result <- ${invocation}`,
      "  return result",
    );
    for (let i = 1; i <= depth; i++) {
      lib.push(
        `const ${kind}_${i} = fn callback => fn value => do:`,
        `  use first <- ${kind}_${i - 1} callback value`,
        `  use second <- ${kind}_${i - 1} callback first`,
        "  return second",
      );
    }
    lib.push(`const ${kind}_factory = do:`, `  return ${kind}_${depth}`);
  }
  lib.push("const unused = fn callback => fn value => value");
  const program = (
    provider: number,
    invalid: false | "row" | "result" | "body",
  ) =>
    [
      'import * as library from "./library"',
      "type Tick is effect = Unit -> U32",
      "type Other is effect = Unit -> U32",
      "const tick: U32 -> U32 ! {Tick} = fn value => do:",
      "  use extra <- Tick ()",
      `  return @u32.add value ${invalid === "body" ? "#True" : "extra"}`,
      "entry const pure = fn (delta: U32) =>",
      "  library.apply_factory (fn current => @u32.add current delta) 7",
      "entry const reducer = fn (delta: U32) =>",
      "  library.reduce_factory (fn current => fn ignored => @u32.add current delta) 7",
      "entry const returned = fn (delta: U32) =>",
      "  library.returned_factory (fn () => fn current => @u32.add current delta) 7",
      `entry const handled: U32 -> U32 ! {} = fn value => do (@effect.provider ${
        invalid === "row" ? "Other" : "Tick"
      } (fn () => ${provider})):`,
      "  use result <- library.apply_factory tick value",
      "  return result",
      "entry const unused: U32 -> U32 ! {} = fn value => library.unused tick value",
      invalid === "result"
        ? "entry const incompatible: U32 -> U32 = fn value => library.apply_factory (fn current => #True) value"
        : "entry const incompatible: U32 -> U32 = fn value => library.apply_factory (fn current => current) value",
      "",
    ].join("\n");
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(library, lib.join("\n") + "\n");
    await Deno.writeTextFile(entry, program(1, false));
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const initial = await producer.build();
      assert(initial.success, JSON.stringify(initial));
      expected = initial.bytes;
      checkpoint = await producer.exportCheckpoint();
    } finally {
      await producer.dispose();
    }
    const retained = await createZigProjectCompiler({
      ...options,
      dependencies: bundle,
      checkpoint,
    });
    try {
      const restored = await retained.build();
      assert(restored.success, JSON.stringify(restored));
      assert(restored.stats.cachedModules > 0);
      assert.deepEqual(restored.bytes, expected);
      for (
        const [provider, invalid] of [
          [2, false],
          [2, "row"],
          [2, false],
          [2, "result"],
          [2, false],
          [2, "body"],
          [1, false],
        ] as const
      ) {
        const sources = { [entry]: program(provider, invalid) };
        const actual = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(actual.success, reference.success);
          assert.equal(actual.success, invalid === false);
          if (actual.success && reference.success) {
            assert.deepEqual(actual.bytes, reference.bytes);
            const guest = await instantiateGuest(actual.bytes);
            try {
              for (const delta of [0, 1, 3]) {
                for (const name of ["pure", "reducer", "returned"]) {
                  assert.equal(
                    guest.call(name, delta),
                    7 + repetitions * delta,
                  );
                }
              }
              assert.equal(
                guest.call("handled", 7),
                7 + repetitions * provider,
              );
              assert.equal(guest.call("unused", 7), 7);
              assert.equal(guest.call("incompatible", 7), 7);
            } finally {
              guest.dispose();
            }
          } else if (!actual.success && !reference.success) {
            assert.deepEqual(actual.diagnostics, reference.diagnostics);
            if (invalid === "row") {
              assert(
                actual.diagnostics.some((diagnostic) =>
                  diagnostic.code === "effect_mismatch"
                ),
              );
            }
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("predicate bearing callback witnesses remain mandatory for invoked and unused callback values", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const source = (invalid: boolean) =>
    [
      "type Count is data = #Count U32",
      "const Count.add: Count -> Count -> Count = fn left => fn right => case left, right of\n  #Count a, #Count b => #Count (@u32.add a b)",
      `const callback: a -> a where { associated "${
        invalid ? "missing" : "add"
      }" a Count a } = fn value => @type.call "add" value (#Count 1)`,
      'const invoke_0 = fn callback => fn value => do:\n  use next <- callback value\n  return @type.call "add" next (#Count 1)',
      ...Array.from({ length: 6 }, (_, i) =>
        `const invoke_${
          i + 1
        } = fn callback => fn value => invoke_${i} callback (invoke_${i} callback value)`),
      "const factory = do:\n  return invoke_6",
      "const unused = fn callback => fn value => value",
      "",
    ].join("\n");
  const program = (unused: boolean) =>
    [
      'import { Count, callback, factory, unused } from "./library"',
      "entry const answer = fn (value: U32) => do:",
      "  let checked: Count -> Count = callback",
      `  let #Count result = ${
        unused ? "unused" : "factory"
      } checked (#Count value)`,
      "  return result",
      "",
    ].join("\n");
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(library, source(false));
    await Deno.writeTextFile(entry, program(false));
    const retained = await createZigProjectCompiler(options);
    try {
      for (
        const [invalid, unused] of [
          [false, false],
          [true, false],
          [false, true],
          [true, true],
          [false, false],
        ]
      ) {
        const sources = {
          [library]: source(invalid),
          [entry]: program(unused),
        };
        const actual = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const expected = await fresh.build({ sources });
          assert.equal(actual.success, expected.success);
          assert.equal(actual.success, !invalid, JSON.stringify(actual));
          if (actual.success && expected.success) {
            assert.deepEqual(actual.bytes, expected.bytes);
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("answer", 7), unused ? 7 : 135);
            } finally {
              guest.dispose();
            }
          } else if (!actual.success && !expected.success) {
            assert.deepEqual(actual.diagnostics, expected.diagnostics);
            assert(
              actual.diagnostics.some((diagnostic) =>
                diagnostic.code === "missing_predicate"
              ),
              JSON.stringify(actual.diagnostics),
            );
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
