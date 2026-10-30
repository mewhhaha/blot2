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

Deno.test("source solved structural graphs preserve imported instances through checkpoints and failed edits", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (
    invalid: false | "field" | "header" | "row",
    changed: boolean,
  ) => {
    const lines = [
      "type Box a is data = #Box {left: a, keep: a}",
      "type Seed is data = #Seed",
      "const Seed.build: a -> Seed -> Box a = func value => return func seed => return #Box {left: value, keep: value}",
      "type Tick is effect = Unit -> Unit",
      "type Signal a is effect = { get: Unit -> a }",
      "const read_seven: Unit -> U32 = func () => return @u32.add 0 7",
      invalid === "row"
        ? "const Box.read: Box a -> a ! {Tick} = func box => return do:\n  use Tick ()\n  break box.left"
        : `const Box.read: Box a -> a${
          invalid === "header" ? ' where { associated "missing" a a a }' : ""
        } = func box => return box.${changed ? "keep" : "left"}`,
      "type Count is data = #Count U32",
      "type Other is data = #Other U32",
      `const project_0 = func value => return {left: value, right: value}.${
        invalid === "field" ? "missing" : "left"
      }`,
      "const merge_0 = func value => return (@record.merge {left: value} {right: value}).left",
      "const update_0 = func value => return do:",
      "  let record = {left: 0, keep: value}",
      "  record.left := value",
      "  break record.left",
      "const nominal_0 = func value => return (#Box {left: value, keep: value}).left",
      "const member_0 = func value => return (#Box {left: value, keep: value}).read",
      'const revealed_seed = func value => return @type.call "build" value #Seed',
      "const revealed_0 = func value => return (revealed_seed value).read",
      'const known_0 = func value => return @type.call "add" value (@u32.add 0 1)',
      "const handler_0: a -> a = func value => return do (@effect.provider (Signal.get U32) read_seven):\n  use ignored <- (Signal.get U32) ()\n  break value",
      `const compare_0 = func ignored => return @type.same #Count #${
        changed ? "Count" : "Other"
      }`,
    ];
    for (
      const kind of [
        "project",
        "merge",
        "update",
        "nominal",
        "member",
        "revealed",
        "known",
        "handler",
        "compare",
      ]
    ) {
      for (let i = 1; i <= 12; i++) {
        lines.push(
          `const ${kind}_${i} = func value => return do:`,
          `  ${
            (kind === "member" || kind === "revealed") && invalid === "row"
              ? "use ignored <-"
              : "let ignored ="
          } ${kind}_${i - 1} value`,
          `  break ${kind}_${i - 1} value`,
        );
      }
      lines.push(`const ${kind}_factory = do:`, `  break ${kind}_12`);
    }
    return lines.join("\n") + "\n";
  };
  const program = ['import * as library from "./library"'];
  for (
    const kind of [
      "project",
      "merge",
      "update",
      "nominal",
      "member",
      "revealed",
      "handler",
    ]
  ) {
    for (const [name, type] of [["integer", "U32"], ["floating", "F32"]]) {
      program.push(
        `entry const ${kind}_${name}${
          kind === "member" || kind === "revealed"
            ? `: ${type} -> ${type} ! {}`
            : ""
        } = func (value: ${type}) : ${type} => return library.${kind}_factory value`,
      );
    }
  }
  program.push(
    "entry const compare = func (value: U32) : Bool => return library.compare_factory value",
    "entry const known = func (value: U32) : U32 => return library.known_factory value",
  );
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(false, false));
    await Deno.writeTextFile(entry, program.join("\n") + "\n");
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
      assert(
        first.success,
        JSON.stringify({
          success: first.success,
          diagnostics: "diagnostics" in first ? first.diagnostics : [],
        }),
      );
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
      assert(
        restored.success,
        JSON.stringify({
          success: restored.success,
          diagnostics: "diagnostics" in restored ? restored.diagnostics : [],
        }),
      );
      assert(restored.stats.cachedModules > 0);
      assert.deepEqual(restored.bytes, expected);
      for (
        const [invalid, changed] of [
          [false, true],
          ["header", true],
          [
            "row",
            true,
          ],
          ["field", true],
          [
            false,
            false,
          ],
        ] as const
      ) {
        const sources = { [library]: source(invalid, changed) };
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
              for (
                const kind of [
                  "project",
                  "merge",
                  "update",
                  "nominal",
                  "member",
                  "revealed",
                  "handler",
                ]
              ) {
                for (const value of [0, 37, 0xffff_ffff]) {
                  assert.equal(guest.call(`${kind}_integer`, value), value);
                }
                for (const value of [0, 1.25, -2.5]) {
                  assert.equal(
                    guest.call(`${kind}_floating`, value),
                    Math.fround(value),
                  );
                }
              }
              assert.equal(guest.call("compare", 42), changed);
              for (const value of [0, 37, 0xffff_ffff]) {
                assert.equal(guest.call("known", value), (value + 1) >>> 0);
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

Deno.test("source closed State witness diamonds retain unrelated argument instances", async () => {
  const lines = [
    "type Cell a is data = #Cell a",
    "const f_0 = func ignored => return @state.get (#Cell 0)",
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
    "entry const integer = func (value: U32) : U32 => return do:",
    "  let (_, #Cell result) = @state.run (#Cell value) (func () => return factory value)",
    "  break result",
    "entry const floating = func (value: F32) : U32 => return do:",
    "  let (_, #Cell result) = @state.run (#Cell 42) (func () => return factory value)",
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
    "type Cell a is data = #Cell a",
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
    "entry const integer = func (value: U32) : U32 => return do:",
    "  let (_, #Cell result) = @state.run (#Cell value) (func () => return factory (#Cell 0))",
    "  break result",
    "entry const floating = func (value: F32) : F32 => return do:",
    "  let (_, #Cell result) = @state.run (#Cell value) (func () => return factory (#Cell 0.0))",
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

Deno.test("witness principal graphs preserve imported nominal state heads and comparisons through saved state and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (invalid: "head" | "comparison" | false) => {
    const lines = [
      "type Cell a is data = #Cell a",
      `const head_0 = func (witness: w) : Cell a => return @state.get ${
        invalid === "head" ? "0" : "witness"
      }`,
      `const same_0 = func left => return func right => return @type.same ${
        invalid === "comparison" ? '(@panic "uncalled witness")' : "left"
      } right`,
    ];
    for (let i = 1; i <= 12; i++) {
      lines.push(
        `const head_${i} = func witness => return do:`,
        `  use ignored <- head_${i - 1} witness`,
        `  break head_${i - 1} witness`,
        `const same_${i} = func left => return func right => return do:`,
        `  let ignored = same_${i - 1} left right`,
        `  break same_${i - 1} left right`,
      );
    }
    return lines.join("\n") + "\n";
  };
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(false));
    await Deno.writeTextFile(
      entry,
      `import * as library from "./library"
entry const integer = func (value: U32) : U32 => return do:
  let (_, #library.Cell result) = @state.run (#library.Cell value) (func () => return library.head_12 (#library.Cell 0))
  break result
entry const floating = func (value: F32) : F32 => return do:
  let (_, #library.Cell result) = @state.run (#library.Cell value) (func () => return library.head_12 (#library.Cell 0.0))
  break result
entry const same_integer = func (value: U32) : Bool => return library.same_12 value 1
entry const same_floating = func (value: F32) : Bool => return library.same_12 value 1.0
entry const different = func (value: U32) : Bool => return library.same_12 value 1.0
entry const same_nominal = func (value: U32) : Bool => return library.same_12 (#library.Cell value) (#library.Cell 1)
entry const different_nominal = func (value: U32) : Bool => return library.same_12 (#library.Cell value) (#library.Cell 1.0)
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
      assert(
        first.success,
        JSON.stringify({
          success: first.success,
          diagnostics: "diagnostics" in first ? first.diagnostics : [],
        }),
      );
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
      assert(
        restored.success,
        JSON.stringify({
          success: restored.success,
          diagnostics: "diagnostics" in restored ? restored.diagnostics : [],
        }),
      );
      assert(restored.stats.cachedModules > 0);
      assert.deepEqual(restored.bytes, expected);
      for (
        const invalid of [false, "head", false, "comparison", false] as const
      ) {
        const sources = { [library]: source(invalid) };
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
                assert.equal(guest.call("same_integer", value), true);
                assert.equal(guest.call("different", value), false);
                assert.equal(guest.call("same_nominal", value), true);
                assert.equal(guest.call("different_nominal", value), false);
              }
              for (const value of [0, 1.25, -2.5]) {
                assert.equal(guest.call("floating", value), Math.fround(value));
                assert.equal(guest.call("same_floating", value), true);
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
      `const array_0 = func value => return #[value.${member}]`,
      `const record_0 = func value => return {result: value.${member}}`,
      `const nominal_0 = func value => return #Box value.${member}`,
      "const representation_0: Box a -> Box a where { type_rep (Box a) } = func value => return value",
      "const operation_0: a -> a ! {| e} where { operation Signal.get a } = func token => return Signal.get a ()",
    ];
    for (let i = 1; i <= 8; i++) {
      for (const shape of ["array", "record", "nominal"]) {
        lines.push(
          `const ${shape}_${i} = func value => return do:`,
          `  let ignored = ${shape}_${i - 1} value`,
          `  break ${shape}_${i - 1} value`,
        );
      }
      lines.push(
        `const operation_${i} = func token => return do:`,
        `  use result <- operation_${i - 1} token`,
        repeatedOperation
          ? `  break operation_${i - 1} token`
          : "  break result",
      );
    }
    for (let i = 1; i <= 12; i++) {
      lines.push(
        `const representation_${i} = func value => return representation_${
          i - 1
        } (representation_${i - 1} value)`,
      );
    }
    lines.push(
      "const representation_factory = do:",
      "  break representation_12",
    );
    for (const shape of ["array", "record", "nominal", "operation"]) {
      lines.push(`const ${shape}_factory = do:`, `  break ${shape}_8`);
    }
    return lines.join("\n") + "\n";
  };
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(false));
    await Deno.writeTextFile(
      entry,
      `import * as library from "./library"
entry const integer = func (value: U32) : U32 => return do:
  let array = library.array_factory {first: value}
  let record = library.record_factory {first: array[0]}
  let #library.Box result = library.nominal_factory {first: record.result}
  let #library.Box represented = library.representation_factory (#library.Box result)
  break represented
entry const floating = func (value: F32) : F32 => return do:
  let array = library.array_factory {first: value}
  let record = library.record_factory {first: array[0]}
  let #library.Box result = library.nominal_factory {first: record.result}
  let #library.Box represented = library.representation_factory (#library.Box result)
  break represented
entry const requested = func (value: U32) : U32 => return do (@effect.provider (library.Signal.get U32) (func () => return value)):
  break library.operation_factory value
entry const floating_requested = func (value: F32) : F32 => return do (@effect.provider (library.Signal.get F32) (func () => return value)):
  break library.operation_factory value
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
      "const Box.from = func (box: Box a) : Box a => return case box of",
      `  #Box value => #Box (${
        invalid
          ? "value + true"
          : double
          ? '@type.call "add" value value'
          : "value"
      })`,
      'const f_0 = func value => return @type.result "from" value',
    ];
    for (let i = 1; i <= 8; i++) {
      lines.push(`const f_${i} = func value => return f_${i - 1} (f_${i - 1} value)`);
    }
    lines.push("const factory = do:", "  break f_8");
    return lines.join("\n") + "\n";
  };
  const options = { executable, entry, prelude };
  try {
    await Deno.writeTextFile(library, source(false, false));
    await Deno.writeTextFile(
      entry,
      `import * as library from "./library"
entry const integer = func (value: U32) : U32 => return do:
  let #library.Box result: library.Box U32 = library.factory (#library.Box value)
  break result
entry const floating = func (value: F32) : F32 => return do:
  let #library.Box result: library.Box F32 = library.factory (#library.Box value)
  break result
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
type Box a is data = #Box a
const factory = do:
  break f_4
const Box.from = func value => return #Box (factory value)
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
entry const integer = func (value: U32) => return do:
  let #library.Box result: library.Box U32 = from (library.first ({first: value}))
  break result
entry const floating = func (value: F32) => return do:
  let #library.Box result: library.Box F32 = from (library.first ({first: value}))
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
entry const integer = func (value: U32) => return apply (compose (plus 2) (plus 3)) value
entry const floating = func (value: F32) => return apply (func item => return @f32.add item 0.5) value
entry const answer = func (value: U32) => return do @effect.provider Read (func () => return value):
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

Deno.test("failed summary jobs retain leaf diagnostics beyond the former depth limit", async () => {
  const directory = await Deno.makeTempDir();
  const input = `${directory}/main.blot`;
  try {
    for (
      const leaf of [
        "const f_0 = func value => return value + value",
        "const f_0 = func value => return @u32.add value true",
      ]
    ) {
      const diagnostics = [];
      for (const depth of [0, 300]) {
        let argument = "true";
        if (leaf.includes("@u32")) argument = "0";
        const use = `f_${depth} ${argument}`;
        const source = chain(leaf, depth) +
          `entry const answer = func () => return ${use}\n`;
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

Deno.test("summary jobs survive dependencies checkpoints edits and failed revision recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const bundle = `${directory}/library.blotdep`;
  const source = (value: string) =>
    chain(`const f_0 = func value => return @u32.add value ${value}`, 300) +
    "const apply = func callback => return func value => return callback value\n" +
    "const callback = func value => return apply f_300 value\n";
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(library, source("1"));
    await Deno.writeTextFile(
      entry,
      'import { callback } from "./library"\nentry const answer = func (value: U32) => return callback value\n',
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
      for (const value of ["2", "true", "1"]) {
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
      'const f_0: a -> a where { associated "add" a a a } = func value => return ' +
        (double ? '@type.call "add" value value' : "value"),
      128,
    ) +
    'const first: a -> b where { field "first" a b } = func value => return value.first\n' +
    `type Box a is data = #Box a
const Box.read: Box a -> b where { field "first" a b } = func box => return case box of
  #Box value => first value
const Box.twice: Box a -> Box a where { associated "add" a a a } = func box => return case box of
  #Box value => #Box (f_128 value)
const Box.add: Box a -> Box a -> Box a where { associated "add" a a a } = func left => return func right => return case left, right of
  #Box value, #Box other => #Box (f_128 value)
const Box.from: a -> Box a where { associated "add" a a a } = func value => return #Box (f_128 value)
const integer_factory: U32 -> U32 = do:
  break f_128
const floating_factory: F32 -> F32 = do:
  break f_128
`;
  const program = (invalid: boolean) =>
    'import * as library from "./library"\n' +
    'const add = func left => return func right => return @type.call "add" left right\n' +
    'const from = func value => return @type.result "from" value\n' +
    `entry const integer = func (value: U32) => return case (#library.Box ((#library.Box (${
      invalid ? "true" : "{first: value}"
    })).read)).twice of\n  #library.Box result => result\n` +
    `entry const floating = func (value: F32) => return case (#library.Box ((#library.Box ({first: value})).read)).twice of
  #library.Box result => result
entry const associated = func (value: U32) => return case add (#library.Box value) (#library.Box value) of
  #library.Box result => result
entry const constructed = func (value: F32) => return do:
  let #library.Box result: library.Box F32 = from value
  break result
entry const integer_factory = func (value: U32) => return library.integer_factory value
entry const floating_factory = func (value: F32) => return library.floating_factory value
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
