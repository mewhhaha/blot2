import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import {
  chainGeneric,
  chainMono,
  diamond,
} from "../../benchmarks/tools/corpus.ts";
import { compileAndRun } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url);
const prelude = new URL("../../std/prelude.sq", import.meta.url).pathname;

Deno.test("source closed State witness diamonds retain unrelated argument instances", async () => {
  const lines = [
    "type Cell a is data = $Cell a",
    "const f_0 = func ignored => return @state.get ($Cell 0)",
  ];
  for (let i = 1; i <= 12; i++) {
    lines.push(
      `const f_${i} = func witness => return do:`,
      `  use ignored <- f_${i - 1} witness`,
      `  break f_${i - 1} witness`,
    );
  }
  lines.push(
    "const factory = do:",
    "  break f_12",
    "io const integer = func (value: U32) : U32 => return do:",
    "  let (_, $Cell result) = @state.run ($Cell value) (func () => return factory value)",
    "  break result",
    "io const floating = func (value: F32) : U32 => return do:",
    "  let (_, $Cell result) = @state.run ($Cell 42) (func () => return factory value)",
    "  break result",
  );
  await compileAndRun(lines.join("\n") + "\n", (guest) => {
    for (const value of [0, 37, 0xffff_ffff]) {
      assert.equal(guest.call("integer", value), value);
    }
    for (const value of [0, 1.25, -2.5]) {
      assert.equal(guest.call("floating", value), 42);
    }
  });
});

Deno.test("source parametric State witness heads preserve independent nominal arguments", async () => {
  const lines = [
    "type Cell a is data = $Cell a",
    "const f_0 = func (witness: Cell a) : Cell a => return @state.get witness",
  ];
  for (let i = 1; i <= 12; i++) {
    lines.push(
      `const f_${i} = func witness => return do:`,
      `  use ignored <- f_${i - 1} witness`,
      `  break f_${i - 1} witness`,
    );
  }
  lines.push(
    "const factory = do:",
    "  break f_12",
    "io const integer = func (value: U32) : U32 => return do:",
    "  let (_, $Cell result) = @state.run ($Cell value) (func () => return factory ($Cell 0))",
    "  break result",
    "io const floating = func (value: F32) : F32 => return do:",
    "  let (_, $Cell result) = @state.run ($Cell value) (func () => return factory ($Cell 0.0))",
    "  break result",
  );
  await compileAndRun(lines.join("\n") + "\n", (guest) => {
    for (const value of [0, 37, 0xffff_ffff]) {
      assert.equal(guest.call("integer", value), value);
    }
    for (const value of [0, 1.25, -2.5]) {
      assert.equal(guest.call("floating", value), Math.fround(value));
    }
  });
});

Deno.test("inferred graph edges preserve result witnesses through diamonds, imports and failed edits", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.sq`;
  const library = `${directory}/library.sq`;
  const source = (double: boolean, invalid: boolean) => {
    const lines = [
      `const f_0 = func value => return ${
        invalid
          ? "value + true"
          : double
          ? '@type.call "add" value value'
          : "value"
      }`,
    ];
    for (let i = 1; i <= 4; i++) {
      lines.push(`const f_${i} = func value => return f_${i - 1} (f_${i - 1} value)`);
    }
    return lines.join("\n") + `
const first = func value => return value.first
type Box a is data = $Box a
const factory = do:
  break f_4
const Box.from = func value => return $Box (factory value)
`;
  };
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(true, false));
    await Deno.writeTextFile(
      entry,
      `
import * as library from "./library"
const from = func value => return @type.result "from" value
io const integer = func (value: U32) => return do:
  let $library.Box result: library.Box U32 = from (library.first ({first: value}))
  break result
io const floating = func (value: F32) => return do:
  let $library.Box result: library.Box F32 = from (library.first ({first: value}))
  break result
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
const apply = func callback => return func value => return callback value
const compose = func outer => return func inner => return func value => return outer (inner value)
const plus = func amount => return func value => return @u32.add amount value
const reading = func () => return apply (func () => return Read ()) ()
io const integer = func (value: U32) => return apply (compose (plus 2) (plus 3)) value
io const floating = func (value: F32) => return apply (func item => return @f32.add item 0.5) value
io const answer = func (value: U32) => return do @effect.provider Read (func () => return value):
  use result <- reading ()
  break @u32.add result 5
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
    lines.push(`const f_${i} = func value => return f_${i - 1} value`);
  }
  return lines.join("\n") + "\n";
}

for (
  const [kind, leaf, resultType] of [
    ["operator", "const f_0 = func value => return value + value", "Bool"],
    ["intrinsic", "const f_0 = func value => return @u32.add value true", "U32"],
  ]
) {
  // Direct backend: missing_associated for `true + true` has no related prelude location (tasks/DELETE_SCOPED.md).
  const test = kind === "operator" ? Deno.test.ignore : Deno.test;
  test(`failed summary jobs retain ${kind} leaf diagnostics beyond the former depth limit`, async () => {
    const directory = await Deno.makeTempDir();
    const input = `${directory}/main.sq`;
    try {
      {
        const diagnostics = [];
        for (const depth of [0, 300]) {
          let argument = "true";
          if (leaf.includes("@u32")) argument = "0";
          const use = `f_${depth} ${argument}`;
          const source = chain(leaf, depth) +
            `io const answer = func () : ${resultType} => return ${use}\n`;
          await Deno.writeTextFile(
            input,
            source,
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
          if (!leaf.includes("@u32")) {
            const start = source.lastIndexOf(use);
            assert.equal(errors.length, 1);
            assert.equal(errors[0].code, "missing_associated");
            assert.equal(errors[0].start, start);
            assert.equal(errors[0].end, start + use.length);
            assert.equal(errors[0].related.filename, prelude);
            diagnostics.push(
              errors.map((issue) => ({ ...issue, start: 0, end: 0 })),
            );
          } else {
            diagnostics.push(errors);
          }
        }
        assert.deepEqual(diagnostics[1], diagnostics[0]);
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("summary jobs survive dependencies edits and failed revision recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.sq`;
  const library = `${directory}/library.sq`;
  const bundle = `${directory}/library.sqdep`;
  const source = (value: string) =>
    chain(`const f_0 = func value => return @u32.add value ${value}`, 300) +
    "const apply = func callback => return func value => return callback value\n" +
    "const callback = func value => return apply f_300 value\n";
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(library, source("1"));
    await Deno.writeTextFile(
      entry,
      'import { callback } from "./library"\nio const answer = func (value: U32) => return callback value\n',
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      expected = first.bytes;
    } finally {
      await producer.dispose();
    }
    const retained = await createZigProjectCompiler({
      ...options,
      dependencies: bundle,
    });
    try {
      const restored = await retained.build();
      assert(restored.success, JSON.stringify(restored));
      assert.deepEqual(restored.bytes, expected);
      for (const value of ["2", "true", "1"]) {
        const sources = { [library]: source(value) };
        const current = await retained.build({ sources });
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
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

// Pending the traits redesign (tasks/LANGUAGE_COHERENCE.md C).
Deno.test.ignore("written predicate summaries preserve independent witnesses through imports and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.sq`;
  const library = `${directory}/library.sq`;
  const bundle = `${directory}/library.sqdep`;
  const source = (double: boolean) =>
    chain(
      'const f_0: a -> a where { associated "add" a a a } = func value => return ' +
        (double ? '@type.call "add" value value' : "value"),
      128,
    ) +
    'const first: a -> b where { field "first" a b } = func value => return value.first\n' +
    `type Box a is data = $Box a
const Box.read: Box a -> b where { field "first" a b } = func box => return case box of
  $Box value => first value
const Box.twice: Box a -> Box a where { associated "add" a a a } = func box => return case box of
  $Box value => $Box (f_128 value)
const Box.add: Box a -> Box a -> Box a where { associated "add" a a a } = func left => return func right => return case left, right of
  $Box value, $Box other => $Box (f_128 value)
const Box.from: a -> Box a where { associated "add" a a a } = func value => return $Box (f_128 value)
const integer_factory: U32 -> U32 = do:
  break f_128
const floating_factory: F32 -> F32 = do:
  break f_128
`;
  const program = (invalid: boolean) =>
    'import * as library from "./library"\n' +
    'const add = func left => return func right => return @type.call "add" left right\n' +
    'const from = func value => return @type.result "from" value\n' +
    `io const integer = func (value: U32) => return case ($library.Box (($library.Box (${
      invalid ? "true" : "{first: value}"
    })).read)).twice of\n  $library.Box result => result\n` +
    `io const floating = func (value: F32) => return case ($library.Box (($library.Box ({first: value})).read)).twice of
  $library.Box result => result
io const associated = func (value: U32) => return case add ($library.Box value) ($library.Box value) of
  $library.Box result => result
io const constructed = func (value: F32) => return do:
  let $library.Box result: library.Box F32 = from value
  break result
io const integer_factory = func (value: U32) => return library.integer_factory value
io const floating_factory = func (value: F32) => return library.floating_factory value
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
    let initial: Uint8Array<ArrayBuffer>;
    try {
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      initial = first.bytes;
    } finally {
      await producer.dispose();
    }
    const retained = await createZigProjectCompiler({
      ...options,
      dependencies: bundle,
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
