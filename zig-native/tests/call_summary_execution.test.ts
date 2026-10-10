import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  chainGeneric,
  chainMono,
  diamond,
} from "../../scripts/bench/corpus.ts";
import { compileAndRun } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;

Deno.test("structured residual graphs preserve imported array record nominal and operation instances through saved state and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (invalid: boolean, repeatedOperation = false) => {
    const member = invalid ? "missing" : "first";
    const lines = [
      "type Box a is data = #Box a",
      "type Signal a is effect = { get: Unit -> a }",
      `const array_0 = fn value => #[value.${member}]`,
      `const record_0 = fn value => {result: value.${member}}`,
      `const nominal_0 = fn value => #Box value.${member}`,
      "const operation_0: a -> a ! {| e} where { operation Signal.get a } = fn token => Signal.get a ()",
    ];
    for (let i = 1; i <= 8; i++) {
      for (const shape of ["array", "record", "nominal"]) {
        lines.push(
          `const ${shape}_${i} = fn value => do:`,
          `  let ignored = ${shape}_${i - 1} value`,
          `  return ${shape}_${i - 1} value`,
        );
      }
      lines.push(
        `const operation_${i} = fn token => do:`,
        `  use result <- operation_${i - 1} token`,
        repeatedOperation
          ? `  return operation_${i - 1} token`
          : "  return result",
      );
    }
    for (const shape of ["array", "record", "nominal", "operation"]) {
      lines.push(`const ${shape}_factory = do:`, `  return ${shape}_8`);
    }
    return lines.join("\n") + "\n";
  };
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(false));
    await Deno.writeTextFile(
      entry,
      `import * as library from "./library"
entry const integer = fn (value: U32) -> U32 => do:
  let array = library.array_factory {first: value}
  let record = library.record_factory {first: array[0]}
  let #library.Box result = library.nominal_factory {first: record.result}
  return result
entry const floating = fn (value: F32) -> F32 => do:
  let array = library.array_factory {first: value}
  let record = library.record_factory {first: array[0]}
  let #library.Box result = library.nominal_factory {first: record.result}
  return result
entry const requested = fn (value: U32) -> U32 => do (@effect.provider (library.Signal.get U32) (fn () => value)):
  return library.operation_factory value
entry const floating_requested = fn (value: F32) -> F32 => do (@effect.provider (library.Signal.get F32) (fn () => value)):
  return library.operation_factory value
`,
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      expected = first.bytes;
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
        const [invalid, repeatedOperation] of [[false, false], [true, false], [
          false,
          true,
        ], [false, false]]
      ) {
        const sources = { [library]: source(invalid, repeatedOperation) };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(
            current.success,
            !invalid,
            JSON.stringify({
              success: current.success,
              diagnostics: "diagnostics" in current ? current.diagnostics : [],
            }),
          );
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            const guest = await instantiateGuest(current.bytes);
            try {
              for (const value of [0, 37, 0xffff_ffff]) {
                assert.equal(guest.call("integer", value), value);
                assert.equal(guest.call("requested", value), value);
              }
              for (const value of [0, 1.5, -2.25]) {
                assert.equal(guest.call("floating", value), Math.fround(value));
                assert.equal(
                  guest.call("floating_requested", value),
                  Math.fround(value),
                );
              }
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
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

Deno.test("result principal graphs preserve deep nominal instances through imported factories and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (double: boolean, invalid: boolean) => {
    const lines = [
      "type Box a is data = #Box a",
      "const Box.from = fn (box: Box a) -> Box a => case box of",
      `  #Box value => #Box (${
        invalid
          ? "value + #True"
          : double
          ? '@type.call "add" value value'
          : "value"
      })`,
      'const f_0 = fn value => @type.result "from" value',
    ];
    for (let i = 1; i <= 8; i++) {
      lines.push(`const f_${i} = fn value => f_${i - 1} (f_${i - 1} value)`);
    }
    lines.push("const factory = do:", "  return f_8");
    return lines.join("\n") + "\n";
  };
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(false, false));
    await Deno.writeTextFile(
      entry,
      `import * as library from "./library"
entry const integer = fn (value: U32) -> U32 => do:
  let #library.Box result: library.Box U32 = library.factory (#library.Box value)
  return result
entry const floating = fn (value: F32) -> F32 => do:
  let #library.Box result: library.Box F32 = library.factory (#library.Box value)
  return result
`,
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      expected = first.bytes;
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
        const [double, invalid] of [
          [false, false],
          [true, false],
          [true, true],
          [false, false],
        ]
      ) {
        const sources = { [library]: source(double, invalid) };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, !invalid, JSON.stringify(current));
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            const guest = await instantiateGuest(current.bytes);
            try {
              const factor = double ? 2 ** 256 : 1;
              assert.equal(guest.call("integer", 37), (37 * factor) >>> 0);
              assert.equal(
                guest.call("floating", 1.5),
                Math.fround(1.5 * factor),
              );
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
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

Deno.test("inferred graph edges preserve result witnesses through diamonds, imports and failed edits", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const source = (double: boolean, invalid: boolean) => {
    const lines = [
      `const f_0 = fn value => ${
        invalid
          ? "value + #True"
          : double
          ? '@type.call "add" value value'
          : "value"
      }`,
    ];
    for (let i = 1; i <= 4; i++) {
      lines.push(`const f_${i} = fn value => f_${i - 1} (f_${i - 1} value)`);
    }
    return lines.join("\n") + `
const first = fn value => value.first
type Box a is data = #Box a
const factory = do:
  return f_4
const Box.from = fn value => #Box (factory value)
`;
  };
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(true, false));
    await Deno.writeTextFile(
      entry,
      `
import * as library from "./library"
const from = fn value => @type.result "from" value
entry const integer = fn (value: U32) => do:
  let #library.Box result: library.Box U32 = from (library.first ({first: value}))
  return result
entry const floating = fn (value: F32) => do:
  let #library.Box result: library.Box F32 = from (library.first ({first: value}))
  return result
`,
    );
    const retained = await createZigProjectCompiler(options);
    try {
      for (
        const [double, invalid] of [
          [true, false],
          [false, false],
          [true, true],
          [true, false],
        ]
      ) {
        const sources = { [library]: source(double, invalid) };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, !invalid, JSON.stringify(current));
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            const guest = await instantiateGuest(current.bytes);
            try {
              const factor = double ? 65536 : 1;
              assert.equal(guest.call("integer", 37), 37 * factor);
              assert.equal(guest.call("floating", 1.5), 1.5 * factor);
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
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

Deno.test("summary jobs preserve executed deep chains and shared diamonds", async () => {
  for (
    const [program, increment] of [
      [chainMono(1000), 1001],
      [chainGeneric(300), 301],
      [diamond(16), 65536],
    ] as const
  ) {
    await compileAndRun(program.source, (guest) => {
      assert.equal(guest.call("main", 7), 7 + increment);
      assert.equal(guest.call("main", 0xffff_ffff), increment - 1);
    });
  }
});

for (const asynchronous of [false, true]) {
  Deno.test(`parametric callbacks retain captures and effects (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `
effect Read: Unit -> U32
const apply = fn callback => fn value => callback value
const compose = fn outer => fn inner => fn value => outer (inner value)
const plus = fn amount => fn value => @u32.add amount value
const reading = fn () => apply (fn () => Read ()) ()
entry const integer = fn (value: U32) => apply (compose (plus 2) (plus 3)) value
entry const floating = fn (value: F32) => apply (fn item => @f32.add item 0.5) value
entry const answer = fn (value: U32) => do @effect.provider Read (fn () => value):
  use result <- reading ()
  return @u32.add result 5
`,
      async (guest) => {
        const call = asynchronous ? guest.callAsync : guest.call;
        for (const value of [0, 37, 0xffff_ffff]) {
          assert.equal(await call("integer", value), (value + 5) >>> 0);
          assert.equal(await call("answer", value), (value + 5) >>> 0);
        }
        assert.equal(await call("floating", 1.5), 2);
      },
      { prelude: "none", asynchronous },
    );
  });
}

function chain(leaf: string, depth: number): string {
  const lines = [leaf];
  for (let i = 1; i <= depth; i++) {
    lines.push(`const f_${i} = fn value => f_${i - 1} value`);
  }
  return lines.join("\n") + "\n";
}

Deno.test("failed summary jobs retain leaf diagnostics beyond the former depth limit", async () => {
  const directory = await Deno.makeTempDir();
  const input = `${directory}/main.blot`;
  try {
    for (
      const leaf of [
        "const f_0 = fn value => value + value",
        "const f_0 = fn value => @u32.add value #True",
      ]
    ) {
      const diagnostics = [];
      for (const depth of [0, 300]) {
        await Deno.writeTextFile(
          input,
          chain(leaf, depth) +
            `entry const answer = fn () => f_${depth} ${
              leaf.includes("@u32") ? "0" : "#True"
            }\n`,
        );
        const result = await new Deno.Command(executable, {
          args: [
            "build",
            input,
            `${directory}/main.wasm`,
            "--prelude",
            prelude,
          ],
          stdout: "piped",
          stderr: "piped",
        }).output();
        assert(!result.success);
        const records = new TextDecoder().decode(result.stdout).trim().split(
          "\n",
        )
          .map((line) => JSON.parse(line));
        const errors = records.filter((record) => record.kind === "diagnostic");
        assert(errors.length > 0, new TextDecoder().decode(result.stderr));
        assert(errors.every((record) => record.code !== "constant_fuel"));
        assert.equal(
          records.find((record) => record.kind === "compilation").memory
            .live_bytes,
          0,
        );
        diagnostics.push(errors);
      }
      assert.deepEqual(diagnostics[1], diagnostics[0]);
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("summary jobs survive dependencies checkpoints edits and failed revision recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (value: string) =>
    chain(`const f_0 = fn value => @u32.add value ${value}`, 300) +
    "const apply = fn callback => fn value => callback value\n" +
    "const callback = fn value => apply f_300 value\n";
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(library, source("1"));
    await Deno.writeTextFile(
      entry,
      'import { callback } from "./library"\nentry const answer = fn (value: U32) => callback value\n',
    );
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
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      expected = first.bytes;
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
      for (const value of ["2", "#True", "1"]) {
        const sources = { [library]: source(value) };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            assert.equal(
              current.stats.nativeWorkSteps,
              reference.stats.nativeWorkSteps,
            );
            const guest = await instantiateGuest(current.bytes);
            try {
              assert.equal(guest.call("answer", 40), 40 + Number(value));
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
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

Deno.test("written predicate summaries preserve independent witnesses through imports and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (double: boolean) =>
    chain(
      'const f_0: a -> a where { associated "add" a a a } = fn value => ' +
        (double ? '@type.call "add" value value' : "value"),
      128,
    ) +
    'const first: a -> b where { field "first" a b } = fn value => value.first\n' +
    `type Box a is data = #Box a
const Box.read: Box a -> b where { field "first" a b } = fn box => case box of
  #Box value => first value
const Box.twice: Box a -> Box a where { associated "add" a a a } = fn box => case box of
  #Box value => #Box (f_128 value)
const Box.add: Box a -> Box a -> Box a where { associated "add" a a a } = fn left => fn right => case left, right of
  #Box value, #Box other => #Box (f_128 value)
const Box.from: a -> Box a where { associated "add" a a a } = fn value => #Box (f_128 value)
const integer_factory: U32 -> U32 = do:
  return f_128
const floating_factory: F32 -> F32 = do:
  return f_128
`;
  const program = (invalid: boolean) =>
    'import * as library from "./library"\n' +
    'const add = fn left => fn right => @type.call "add" left right\n' +
    'const from = fn value => @type.result "from" value\n' +
    `entry const integer = fn (value: U32) => case (#library.Box ((#library.Box (${
      invalid ? "#True" : "{first: value}"
    })).read)).twice of\n  #library.Box result => result\n` +
    `entry const floating = fn (value: F32) => case (#library.Box ((#library.Box ({first: value})).read)).twice of
  #library.Box result => result
entry const associated = fn (value: U32) => case add (#library.Box value) (#library.Box value) of
  #library.Box result => result
entry const constructed = fn (value: F32) => do:
  let #library.Box result: library.Box F32 = from value
  return result
entry const integer_factory = fn (value: U32) => library.integer_factory value
entry const floating_factory = fn (value: F32) => library.floating_factory value
`;
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(true));
    await Deno.writeTextFile(entry, program(false));
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    let initial: Uint8Array<ArrayBuffer>;
    try {
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      initial = first.bytes;
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
      assert.deepEqual(restored.bytes, initial);
      for (
        const [double, invalid] of [[false, false], [true, true], [true, false]]
      ) {
        const sources = {
          [library]: source(double),
          [entry]: program(invalid),
        };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, !invalid, JSON.stringify(current));
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            const guest = await instantiateGuest(current.bytes);
            try {
              const factor = double ? 2 : 1;
              assert.equal(
                guest.call("integer", 0xffff_ffff),
                (0xffff_ffff * factor) >>> 0,
              );
              assert.equal(guest.call("floating", 1.25), 1.25 * factor);
              assert.equal(guest.call("associated", 21), 21 * factor);
              assert.equal(guest.call("constructed", 1.25), 1.25 * factor);
              assert.equal(guest.call("integer_factory", 21), 21 * factor);
              assert.equal(guest.call("floating_factory", 1.25), 1.25 * factor);
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
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
