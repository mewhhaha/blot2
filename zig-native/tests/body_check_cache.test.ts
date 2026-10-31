import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

function primitiveSpine(value: string) {
  for (let step = 0; step < 12; step++) value = `@u32.add (${value}) 0`;
  return value;
}
function genericSpine(value: string) {
  for (let step = 0; step < 12; step++) value = `(func item => return item) (${value})`;
  return value;
}

Deno.test("body checker reuse relocates and follows executable edits through rejected revisions", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-check-" });
  const entry = `${directory}/main.blot`;
  const source = (seed: string, prefix = "", helper = "@u32.add value seed") =>
    `${prefix}const seed = ${seed}
const helper = func (value: U32) : U32 => return ${
      helper.replaceAll("value", `(${primitiveSpine("value")})`)
    }
entry const answer = func (argument: U32) : U32 => return helper argument
entry const captured = func (outer: U32) : U32 => return (func (inner: U32) : U32 => return @u32.add outer inner) seed
entry const pair = func (value: U32) => return #[value, seed]
const unrelated = 7
`;
  const inserted =
    "const fresh_spelling = func (earlier: F32) : F32 => return @f32.add earlier 4.0\n";
  const revisions = [
    [source("2"), 42],
    [source("@u32.add 2 1", inserted), 43],
    [source("@u32.add 2 1", inserted), 43],
    [source("4", inserted, "@u32.add value (@u32.mul seed 2)"), 48],
    [source("missing_name", inserted), null],
    [source("4", inserted, "@u32.add value (@u32.mul seed 2)"), 48],
    [source("2"), 42],
  ] as const;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (const [text, answer] of revisions) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          if (answer !== null) console.error(result.diagnostics);
          assert.equal(answer, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        assert.equal(guest.call("answer", 40), answer);
        assert.ok(answer !== null);
        let seed = answer - 40;
        if (answer === 48) seed = 4;
        for (let i = 0; i < 100; i++) {
          assert.equal(guest.call("captured", 40), 40 + seed);
          assert.deepEqual(guest.call("pair", 40), new Uint32Array([40, seed]));
        }
        const work = result.stats.frontend as {
          body_elaborations: number;
        };
        const ordinary = expected.stats.frontend as {
          body_elaborations: number;
        };
        if (text.includes(inserted) && answer !== 48) {
          assert.ok(work.body_elaborations < ordinary.body_elaborations);
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse tracks original imported producer names at stable slots", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-identity-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/dep.blot`;
  const source = (name: string, constant: number) => ({
    [producer]:
      `const ${name} = func (x: U32) : U32 => return @u32.add x ${constant}\n`,
    [entry]:
      `import {${name} as exposed} from "./dep"\nentry const run = func (x: U32) : U32 => return exposed x\nconst untouched = 7\n`,
  });
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [name, constant] of [["first", 2], ["first", 3], ["second", 4], [
        "second",
        5,
      ]] as const
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = source(name, constant);
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.ok(expected.success && result.success);
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        assert.equal(guest.call("run", 40), 40 + constant);
        if (name === "second" && constant === 4) {
          const work = result.stats.attemptStats.fallback as {
            body_elaborations: number;
          };
          assert.equal(work.body_elaborations, 3);
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates generic binders and updates specialized reference results", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-binders-" });
  const entry = `${directory}/main.blot`;
  const source = (identity: string, prefix = "") =>
    `${prefix}const identity = func outer => return (${identity}) (${
      genericSpine("outer")
    })
const box = func x => return #[${genericSpine("x")}]
entry const scalar = func (x: U32) : U32 => return identity x
entry const floating = func (x: F32) : F32 => return identity x
entry const reference = func (x: U32) => return box (identity x)
`;
  const revisions = [
    source("func x => return x"),
    source(
      "func x => return x",
      "const new_type_and_spelling = func (x: Bool) : Bool => return x\n",
    ),
    source("func x => return (func inner => return inner) x"),
    source("func x => return missing_name"),
    source("func x => return x"),
  ];
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (const [revision, text] of revisions.entries()) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.equal(revision, 3);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        for (let index = 0; index < 100; index++) {
          assert.equal(guest.call("scalar", 42), 42);
          assert.equal(guest.call("floating", 42.5), 42.5);
          assert.deepEqual(guest.call("reference", 42), new Uint32Array([42]));
        }
        if (revision !== 0) {
          assert.ok(
            Number(result.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse preserves symbolic Foreign callback effects after binder relocation", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-effects-" });
  const entry = `${directory}/main.blot`;
  const body = `const apply = func callback => return func argument => return callback (${
    genericSpine("argument")
  })
entry const run = func (host: U32 -> U32 ! {Foreign}) => return apply host 42
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [index, text] of [
        body,
        `const earlier_spelling = func (x: F32) : F32 => return @f32.add x 2.0\n${body}`,
      ].entries()
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.ok(result.success && expected.success);
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        const trace: number[] = [];
        assert.equal(
          guest.call(
            "run",
            guest.capability({
              parameter: "U32",
              result: "U32",
              call(value: number) {
                trace.push(value);
                return value + 1;
              },
            }),
          ),
          43,
        );
        assert.deepEqual(trace, [42]);
        if (index === 1) {
          assert.equal(Number(result.stats.frontend.body_elaborations), 2);
          assert.equal(Number(expected.stats.frontend.body_elaborations), 3);
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates opaque receipts through source and compiled imports", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-opaque-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/tokens.blot`;
  const bundle = `${directory}/tokens.blotdep`;
  const library = `opaque type Token = U32
const make = func (value: U32) => return $Token value
const read = func ($Token value) => return value
`;
  const source = (seed: number, prefix = "") =>
    `import {Token, make, read} from "./tokens"
${prefix}const seed = ${seed}
entry const run = func (value: U32) => return @u32.add (read (make (${
      primitiveSpine("value")
    }))) seed
`;
  try {
    await Deno.writeTextFile(entry, source(2));
    await Deno.writeTextFile(producer, library);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [index, text] of [
            source(2),
            source(
              3,
              "const earlier_spelling = func (x: Bool) : Bool => return x\n",
            ),
            source(4),
          ].entries()
        ) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: text, [producer]: library };
            const expected = await fresh.build({ sources });
            const result = await retained.build({ sources });
            assert.ok(result.success && expected.success);
            assert.deepEqual(result.bytes, expected.bytes);
            const guest = await instantiateGuest(result.bytes);
            for (let call = 0; call < 100; call++) {
              assert.equal(guest.call("run", 40), 42 + index);
            }
            guest.dispose();
            if (index !== 0) {
              assert.ok(
                Number(result.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
          } finally {
            await fresh.close();
          }
        }
        const referenceLibrary = `opaque type Token = Array U32
const make = func (value: U32) => return $Token #[value]
const read = func ($Token value) => return @array.get value 0
`;
        await Deno.writeTextFile(producer, referenceLibrary);
        if (dependencies !== undefined) {
          const repacked = await new Deno.Command(executable, {
            args: ["dependencies", entry, bundle, "--prelude", "none"],
            stdout: "piped",
            stderr: "piped",
          }).output();
          assert.ok(
            repacked.success,
            new TextDecoder().decode(repacked.stderr),
          );
        }
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = { [entry]: source(5), [producer]: referenceLibrary };
          const expected = await fresh.build({ sources });
          const result = await retained.build({ sources });
          assert.ok(result.success && expected.success);
          assert.deepEqual(result.bytes, expected.bytes);
          const fallback = result.stats.attemptStats.fallback as {
            body_elaborations: number;
          };
          assert.ok(
            Number(result.stats.frontend.body_elaborations) +
              Number(fallback.body_elaborations) >= 2,
          );
          const guest = await instantiateGuest(result.bytes);
          for (let call = 0; call < 500; call++) {
            assert.equal(guest.call("run", 40), 45);
          }
          guest.dispose();
        } finally {
          await fresh.close();
        }
      } finally {
        await retained.close();
      }
      // Restore an exact scalar bundle for the independent compiled-import
      // sequence; each lane then performs its own scalar-to-reference edit.
      await Deno.writeTextFile(producer, library);
      const restored = await new Deno.Command(executable, {
        args: ["dependencies", entry, bundle, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert.ok(restored.success, new TextDecoder().decode(restored.stderr));
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates generic opaque scalar and owning reference recipes", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-generic-box-",
  });
  const entry = `${directory}/main.blot`;
  const source = (prefix = "", helper = "make") =>
    `${prefix}opaque type Box a = a
const make = func value => return $Box value
const read = func ($Box value) => return value
const identity = func (value: Box a) : Box a => return ${genericSpine("value")}
type Pair [left, right] = (left, right)
const shaped = func (value: Pair [U32, F32]) : U32 => return ${genericSpine("40")}
const arrayed = func (value: Array a) : Array a => return ${genericSpine("value")}
entry const pair = func (value: U32) => return shaped (value, 2.0)
entry const array_value = func (value: U32) => return arrayed #[value]
entry const unsigned = func (value: U32) => return read (identity (${helper} (${
      primitiveSpine("value")
    })))
entry const floating = func (value: F32) => return read (identity (${helper} (${
      genericSpine("value")
    })))
entry const reference = func (value: U32) => return read (identity (${helper} #[${
      primitiveSpine("value")
    }]))
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [index, text] of [
        source(),
        source(
          "type Earlier is data = $Earlier Bool\nconst fresh_spelling = 2.0\n",
        ),
        source("", "missing_name"),
        source(),
      ].entries()
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          if (index !== 2) {
            console.error(result.diagnostics, expected.diagnostics);
          }
          assert.equal(index, 2);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        assert.equal(guest.call("pair", 40), 40);
        assert.deepEqual(guest.call("array_value", 40), new Uint32Array([40]));
        for (let call = 0; call < 200; call++) {
          assert.equal(guest.call("unsigned", 42), 42);
          assert.equal(guest.call("floating", 42.5), 42.5);
          assert.deepEqual(guest.call("reference", 42), new Uint32Array([42]));
        }
        guest.dispose();
        if (index === 1) {
          assert.ok(
            Number(result.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse reconstructs shared predicates and revokes selected Foreign interfaces", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-evidence-" });
  const entry = `${directory}/main.blot`;
  const source = (prefix = "", operation = "@u32.add", annotated = false) => {
    let annotation = "";
    if (annotated) annotation = ": Number -> Number -> Number ! {Foreign}";
    return `${prefix}type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add${annotation} = func ($Number left) => return func ($Number right) => return $Number (${operation} (${
      primitiveSpine("left")
    }) right)
const add = func left => return func right => return @type.call "add" (${
      genericSpine("left")
    }) right
const forwarded = func left => return func right => return add (${genericSpine("left")}) right
const alias = func left => return func right => return forwarded (${genericSpine("left")}) right
const require_pure = func (callback: U32 -> U32) => return callback 40
entry const run = func (value: U32) => return read (alias (make (${
      primitiveSpine("value")
    })) (make 2))
entry const strict = func (value: U32) => return require_pure run
`;
  };
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    const cases = [
      [source(), 42],
      [source("const earlier_spelling = 3.0\n"), 42],
      [source("const earlier_spelling = 3.0\n", "@u32.sub"), 38],
      [source("const earlier_spelling = 3.0\n", "@u32.add", true), null],
      [source("const earlier_spelling = 3.0\n", "@u32.sub"), 38],
      [source(), 42],
    ] as const;
    for (const [text, answer] of cases) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          if (answer !== null) console.error(result.diagnostics);
          assert.equal(answer, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          assert.ok(
            result.diagnostics.some((diagnostic) =>
              diagnostic.code === "effect_mismatch"
            ),
          );
          continue;
        }
        assert.ok(answer !== null);
        assert.deepEqual(result.bytes, expected.bytes);
        if (text.includes("earlier_spelling") && answer === 42) {
          assert.ok(
            Number(expected.stats.frontend.body_elaborations) -
                Number(result.stats.frontend.body_elaborations) >= 3,
          );
        }
        const guest = await instantiateGuest(result.bytes);
        for (let call = 0; call < 200; call++) {
          assert.equal(guest.call("run", 40), answer);
          assert.equal(guest.call("strict", 0), answer);
        }
        guest.dispose();
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates shaped records with owning payloads and reversed spelling order", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-record-" });
  const entry = `${directory}/main.blot`;
  const source = (prefix = "", read = "read") =>
    `${prefix}opaque type Entry { head, tail } = { head: head, tail: tail }
const make = func value => return $Entry value
const read = func ($Entry { tail }) => return tail
entry const unsigned = func (value: U32) => return ${read} (make { head: value, tail: #[${
      primitiveSpine("value")
    }] })
entry const floating = func (value: F32) => return ${read} (make { head: value, tail: #[${
      genericSpine("value")
    }] })
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    const prefix = "const earlier_spelling = { tail: 2.0, head: 3.0 }\n";
    for (
      const text of [
        source(),
        source(prefix),
        source(prefix, "missing_read"),
        source(prefix),
        source(),
      ]
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.ok(text.includes("missing_read"));
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(result.bytes, expected.bytes);
        if (text.includes("earlier_spelling")) {
          assert.ok(
            Number(result.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
        const guest = await instantiateGuest(result.bytes);
        for (let call = 0; call < 200; call++) {
          assert.deepEqual(guest.call("unsigned", 42), new Uint32Array([42]));
          assert.deepEqual(
            guest.call("floating", 1.5),
            new Float32Array([1.5]),
          );
        }
        guest.dispose();
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates shared producer schemes through source and compiled imports", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-shared-import-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/numbers.blot`;
  const bundle = `${directory}/numbers.blotdep`;
  const library = (operation = "@u32.add") =>
    `type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
const add = func left => return func right => return @type.call "add" left right
const forwarded = func left => return func right => return add left right
`;
  const source = (prefix = "", target = "forwarded") =>
    `import {Number, make, read, forwarded} from "./numbers"
${prefix}const wrapper = func left => return func right => return ${target} (${
      genericSpine("left")
    }) right
entry const run = func (value: U32) => return read (wrapper (make value) (make 2))
`;
  async function pack() {
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(result.success, new TextDecoder().decode(result.stderr));
  }
  try {
    await Deno.writeTextFile(entry, source());
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        const prefix = "const earlier_spelling = func (x: F32) => return x\n";
        for (
          const [index, text] of [
            source(),
            source(prefix),
            source(prefix, "missing_forwarded"),
            source(prefix),
          ].entries()
        ) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: text, [producer]: library() };
            const expected = await fresh.build({ sources });
            const result = await retained.build({ sources });
            assert.equal(result.success, expected.success);
            if (!result.success || !expected.success) {
              assert.ok(!result.success && !expected.success);
              assert.equal(index, 2);
              assert.deepEqual(result.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(result.bytes, expected.bytes);
            if (index !== 0) {
              assert.ok(
                Number(result.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(result.bytes);
            assert.equal(guest.call("run", 40), 42);
            guest.dispose();
          } finally {
            await fresh.close();
          }
        }
        await Deno.writeTextFile(producer, library("@u32.sub"));
        if (dependencies !== undefined) await pack();
        const fresh = await createZigProjectCompiler(options);
        try {
          const sources = {
            [entry]: source(prefix),
            [producer]: library("@u32.sub"),
          };
          const expected = await fresh.build({ sources });
          const result = await retained.build({ sources });
          assert.ok(result.success && expected.success);
          assert.deepEqual(result.bytes, expected.bytes);
          const guest = await instantiateGuest(result.bytes);
          assert.equal(guest.call("run", 40), 38);
          guest.dispose();
        } finally {
          await fresh.close();
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse recreates declared qualifications with current evidence and diagnostics", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-where-" });
  const entry = `${directory}/main.blot`;
  const source = (
    prefix = "",
    clause = 'associated "add" a a a',
    operation = "@u32.add",
    foreign = false,
  ) => {
    let annotation = "";
    if (foreign) annotation = ": Number -> Number -> Number ! {Foreign}";
    return `${prefix}type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add${annotation} = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
const twice: a -> a where { ${clause} } = func value => return @type.call "add" (${
      genericSpine("value")
    }) value
const identity: a -> a where { type_rep a } = func value => return ${
      genericSpine("value")
    }
const require_pure = func (callback: U32 -> U32) => return callback 40
entry const run = func (value: U32) => return read (identity (twice (make value)))
entry const strict = func () => return require_pure run
`;
  };
  const prefix = "const new_spelling = func (x: F32) => return x\n";
  const cases = [
    [source(), 80],
    [source(prefix), 80],
    [source(prefix, 'associated "add" a a a', "@u32.sub"), 0],
    [source(prefix, 'associated "sub" a a a'), null],
    [source(prefix, 'associated "add" a a a', "@u32.add", true), null],
    [source(prefix, 'associated "add" a a a', "@u32.sub"), 0],
    [source(), 80],
  ] as const;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (const [text, answer] of cases) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.ok(answer !== null);
        assert.deepEqual(result.bytes, expected.bytes);
        if (text.includes(prefix) && answer === 80) {
          assert.ok(
            Number(expected.stats.frontend.body_elaborations) -
                Number(result.stats.frontend.body_elaborations) >= 2,
          );
        }
        const guest = await instantiateGuest(result.bytes);
        assert.equal(guest.call("run", 40), answer);
        assert.equal(guest.call("strict", null), answer);
        guest.dispose();
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse preserves portable qualified producer origins after earlier body edits", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-qualified-import-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/numbers.blot`;
  const bundle = `${directory}/numbers.blotdep`;
  const library = (
    earlier = "value",
    operation = "@u32.add",
    clause = 'associated "add" a a a',
  ) =>
    `const earlier = func value => return ${earlier}
type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
const twice: a -> a where { ${clause} } = func value => return @type.call "add" value value
`;
  const source = (prefix = "", target = "twice") =>
    `import {Number, make, read, twice} from "./numbers"
${prefix}const wrapper: a -> a where {associated "add" a a a} = func value => return ${target} (${
      genericSpine("value")
    })
entry const run = func (value: U32) => return read (wrapper (make value))
`;
  async function pack() {
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(result.success, new TextDecoder().decode(result.stderr));
  }
  try {
    await Deno.writeTextFile(entry, source());
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        const prefix = "const new_spelling = func (x: F32) => return x\n";
        for (
          const [index, text] of [
            source(),
            source(prefix),
            source(prefix, "missing_twice"),
            source(prefix),
          ].entries()
        ) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: text, [producer]: library() };
            const expected = await fresh.build({ sources });
            const result = await retained.build({ sources });
            assert.equal(result.success, expected.success);
            if (!result.success || !expected.success) {
              assert.ok(!result.success && !expected.success);
              assert.equal(index, 2);
              assert.deepEqual(result.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(result.bytes, expected.bytes);
            if (index !== 0) {
              assert.ok(
                Number(result.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(result.bytes);
            assert.equal(guest.call("run", 40), 80);
            guest.dispose();
          } finally {
            await fresh.close();
          }
        }
        // Changes earlier AST/type nodes and first-use spellings in the
        // producer without changing any declaration's global binding ordinal.
        for (const operation of ["@u32.add", "@u32.sub"]) {
          const lib = library(
            "{fresh_spelling: value}",
            operation,
          );
          await Deno.writeTextFile(producer, lib);
          if (dependencies !== undefined) await pack();
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: source(prefix), [producer]: lib };
            const expected = await fresh.build({ sources });
            const result = await retained.build({ sources });
            assert.ok(result.success && expected.success);
            assert.deepEqual(result.bytes, expected.bytes);
            assert.ok(
              Number(result.stats.frontend.body_elaborations) <
                Number(expected.stats.frontend.body_elaborations),
              `lane=${dependencies} operation=${operation} reused=${result.stats.frontend.body_elaborations} fresh=${expected.stats.frontend.body_elaborations}`,
            );
            const guest = await instantiateGuest(result.bytes);
            let answer = 80;
            if (operation === "@u32.sub") answer = 0;
            assert.equal(guest.call("run", 40), answer);
            guest.dispose();
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates block scope mutation joins and case binders", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-scopes-" });
  const entry = `${directory}/main.blot`;
  const source = (seed: string, prefix = "", operation = "@u32.add") =>
    `${prefix}const seed = ${seed}
const helper = func (value: U32) : U32 => return do:
  let count = ${primitiveSpine("value")}
  if @u32.lt value 8:
    count := ${operation} self seed
  else:
    count := @u32.add self 1
  break case count of
    0 => seed
    result => @u32.add result seed
entry const run = func (value: U32) : U32 => return helper value
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [text, small, large] of [
        [source("2"), 7, 43],
        [source("@u32.add 2 1", "const earlier_spelling = 4.0\n"), 9, 44],
        [source("missing_name"), null, null],
        [source("3", "", "@u32.mul"), 12, 44],
        [source("2"), 7, 43],
      ] as const
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.equal(small, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.notEqual(small, null);
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(await guest.call("run", 3), small);
          assert.equal(await guest.call("run", 40), large);
        } finally {
          await guest.dispose();
        }
        if (text.includes("earlier_spelling")) {
          assert.equal(result.stats.frontend.body_elaborations, 3);
          assert.equal(expected.stats.frontend.body_elaborations, 4);
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse preserves owning constructor case payloads across field relocation", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-patterns-" });
  const entry = `${directory}/main.blot`;
  const source = (prefix = "", increment = "1", variant = false) => {
    let recipe = "$Packet { head: U32, tail: Array U32 }";
    let fallback = "";
    if (variant) {
      recipe = "$Unused | " + recipe;
      fallback = "\n  $Unused => #[0]";
    }
    return `${prefix}type Packet is data = ${recipe}
const make = func (value: U32) => return $Packet { head: value, tail: #[value, @u32.add value ${increment}] }
const read = func (packet: Packet) => return case packet of
  $Packet { tail } => ${genericSpine("tail")}${fallback}
entry const run = func (value: U32) => return read (make value)
`;
  };
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [text, answer] of [
        [source(), [40, 41]],
        [source("const new_spelling = { tail: 3.0, head: 2 }\n"), [40, 41]],
        [source("", "2"), [40, 42]],
        [source("", "missing_name"), null],
        [source("", "2", true), [40, 42]],
        [source(), [40, 41]],
      ] as const
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.notEqual(answer, null);
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          for (let repeat = 0; repeat < 3; repeat++) {
            assert.deepEqual(
              await guest.call("run", 40),
              new Uint32Array(answer!),
            );
          }
        } finally {
          await guest.dispose();
        }
        if (text.includes("new_spelling")) {
          assert.equal(result.stats.frontend.body_elaborations, 3);
          assert.equal(expected.stats.frontend.body_elaborations, 4);
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse restores generic local binders rows and owning results", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-local-principal-",
  });
  const entry = `${directory}/main.blot`;
  const source = (seed = "2", prefix = "", argument = "argument") =>
    `${prefix}const seed = ${seed}
const helper = func callback => return func (value: U32) => return do:
  let identity = func item => return item
  let apply = func action => return func argument => return action ${argument}
  let fraction = identity 3.0
  let owning = identity #[value]
  break @u32.add (apply callback (${genericSpine("value")})) seed
const copy = func (value: Array U32) : Array U32 => return do:
  let identity = func item => return item
  break identity (${genericSpine("value")})
entry const run = func (host: U32 -> U32 ! {Foreign}) => return helper host 42
entry const packed = func (value: U32) => return copy #[value, seed]
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [text, answer, callbackArgument, packed] of [
        [source(), 45, 42, [40, 2]],
        [
          source("3", "const earlier_spelling = { tail: 3.0, head: 2 }\n"),
          46,
          42,
          [40, 3],
        ],
        [source("missing_name"), null, null, null],
        [source("3", "", "(@u32.add argument 1)"), 47, 43, [40, 3]],
        [source(), 45, 42, [40, 2]],
      ] as const
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.notEqual(answer, null);
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        const trace: number[] = [];
        try {
          assert.equal(
            guest.call(
              "run",
              guest.capability({
                parameter: "U32",
                result: "U32",
                call(value: number) {
                  trace.push(value);
                  return value + 1;
                },
              }),
            ),
            answer,
          );
          assert.deepEqual(trace, [callbackArgument]);
          assert.deepEqual(guest.call("packed", 40), new Uint32Array(packed!));
        } finally {
          await guest.dispose();
        }
        if (text.includes("earlier_spelling")) {
          assert.equal(result.stats.frontend.body_elaborations, 4);
          assert.equal(expected.stats.frontend.body_elaborations, 6);
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse restores complete dotted field paths after failed revisions", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-access-path-",
  });
  const entry = `${directory}/main.blot`;
  const source = (seed = "2", prefix = "") =>
    `${prefix}const seed = ${seed}
const helper = func (value: { head: U32, tail: F32 }) : U32 => return @u32.add (${
      genericSpine("value.head")
    }) seed
entry const run = func (value: U32) : U32 => return helper { head: value, tail: 1.0 }
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [text, answer] of [
        [source(), 42],
        [source("3", "const earlier_spelling = { tail: 3.0, head: 2 }\n"), 43],
        [source("missing_name"), null],
        [source("3"), 43],
        [source(), 42],
      ] as const
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("run", 40), answer);
        } finally {
          await guest.dispose();
        }
        if (text !== source()) {
          assert.ok(
            Number(result.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates concrete postfix field variants and owning results", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-fields-" });
  const entry = `${directory}/main.blot`;
  const source = (
    prefix = "",
    increment = "1",
    constructor = "Packet",
    extra = "",
  ) =>
    `${prefix}type Packet is data = $Packet { head: U32, tail: Array U32 } | $Alternate { tail: Array U32, head: U32 } ${extra}
const get = func (value: { head: U32, tail: Array U32 }) => return ${
      genericSpine("(value).tail")
    }
const read = func (value: Packet) => return ${genericSpine("(value).tail")}
const make = func (value: U32) => return $${constructor} { head: value, tail: #[value, @u32.add value ${increment}] }
entry const run = func (value: U32) => return read (make value)
entry const plain = func (value: U32) => return get { head: value, tail: #[value] }
`;
  const options = { executable, entry, prelude: null };
  const retained = await createZigProjectCompiler(options);
  try {
    for (
      const [text, answer] of [
        [source(), [40, 41]],
        [source("const earlier_spelling = { tail: 3.0, head: 2 }\n"), [40, 41]],
        [source("", "2", "Alternate"), [40, 42]],
        [source("", "missing_name"), null],
        [source("", "2", "Packet", "| $Missing { head: U32 }"), null],
        [source("", "2"), [40, 42]],
        [source(), [40, 41]],
      ] as const
    ) {
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert.ok(!actual.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        if (text !== source()) {
          assert.ok(
            Number(actual.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
        assert.ok(answer !== null);
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.deepEqual(guest.call("run", 40), new Uint32Array(answer));
          assert.deepEqual(guest.call("plain", 40), new Uint32Array([40]));
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse restores chained dotted nominal paths from source and compiled producers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-dotted-import-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/packets.blot`;
  const bundle = `${directory}/packets.blotdep`;
  const library = (increment = "1", extra = "") =>
    `type Packet is data = $Packet { head: U32, nested: { tail: Array U32, marker: F32 } } | $Alternate { nested: { marker: F32, tail: Array U32 }, head: U32 } ${extra}
const make = func value => return $Alternate { nested: { marker: 1.0, tail: #[value, @u32.add value ${increment}] }, head: value }
`;
  const source = (prefix = "", body = "value.nested.tail") =>
    `import {Packet, make} from "./packets"
${prefix}type LocalPacket = Packet
const read = func (value: LocalPacket) => return ${genericSpine(body)}
entry const run = func (value: U32) => return read (make value)
`;
  async function pack() {
    await Deno.writeTextFile(
      entry,
      `import {Packet, make} from "./packets"
entry const pack = func (value: U32) => return value
`,
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
    await Deno.writeTextFile(entry, source());
  }
  try {
    await Deno.writeTextFile(entry, source());
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        const prefix =
          "const earlier_spelling = { marker: 3.0, tail: 2, nested: 1, head: 4 }\n";
        for (
          const [index, [text, producerText, answer]] of ([
            [source(), library(), [40, 41]],
            [source(prefix), library(), [40, 41]],
            [source(prefix), library("2"), [40, 42]],
            [source(prefix, "missing_name"), library("2"), null],
            [source(prefix), library("2", "| $Missing { head: U32 }"), null],
            [source(prefix), library("2"), [40, 42]],
            [source(), library(), [40, 41]],
          ] as const).entries()
        ) {
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack();
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: text,
              [producer]: producerText,
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.equal(answer, null);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (index !== 0) {
              assert.ok(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            assert.ok(answer !== null);
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.deepEqual(
                guest.call("run", 40),
                new Uint32Array(answer),
              );
              assert.deepEqual(
                guest.call("run", 7),
                new Uint32Array([7, 7 + answer[1] - 40]),
              );
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse owns inferred local associated principals and candidate revocation", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-local-requirements-",
  });
  const entry = `${directory}/main.blot`;
  const source = (
    prefix = "",
    operation = "@u32.add",
    member = "add",
    extra = "",
  ) =>
    `${prefix}type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
type FloatNumber is data = $FloatNumber F32
const make_float = func value => return $FloatNumber value
const read_float = func ($FloatNumber value) => return value
const FloatNumber.add = func ($FloatNumber left) => return func ($FloatNumber right) => return $FloatNumber (@f32.add left right)
type Numbers is data = $Numbers (Array U32)
const make_numbers = func value => return $Numbers value
const read_numbers = func ($Numbers value) => return value
const Numbers.add = func ($Numbers left) => return func ($Numbers right) => return $Numbers (@array.concat left right)
${extra}const twice = func value => return do:
  let local = func amount => return @type.call "${member}" (${
      genericSpine("amount")
    }) amount
  break local value
entry const unsigned = func (value: U32) => return read (twice (make value))
entry const floating = func (value: F32) => return read_float (twice (make_float value))
entry const packed = func (value: U32) => return read_numbers (twice (make_numbers #[value, @u32.add value 1]))
`;
  const prefix = "const earlier_spelling = { tail: 3.0, head: 2 }\n";
  const extra =
    "type Extra is data = $Extra U32\nconst Extra.add = func ($Extra left) => return func ($Extra right) => return $Extra left\n";
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [index, [text, answer]] of ([
        [source(), 80],
        [source(prefix), 80],
        [source(prefix, "@u32.sub"), 0],
        [source(prefix, "@u32.sub", "add", extra), 0],
        [source(prefix, "@u32.sub", "missing_member"), null],
        [source(prefix, "@u32.sub"), 0],
        [source(), 80],
      ] as const).entries()
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert.ok(!actual.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        if (index === 1 || index === 2 || index === 6) {
          assert.ok(
            Number(actual.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
        if (index === 3) {
          assert.equal(
            actual.stats.frontend.body_elaborations,
            expected.stats.frontend.body_elaborations,
          );
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          for (let call = 0; call < 200; call++) {
            assert.equal(guest.call("unsigned", 40), answer);
            assert.equal(guest.call("floating", 1.5), 3);
            assert.deepEqual(
              guest.call("packed", 40),
              new Uint32Array([40, 41, 40, 41]),
            );
          }
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse revokes local principals for source and compiled selected effects", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-local-import-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/numbers.blot`;
  const bundle = `${directory}/numbers.blotdep`;
  const library = (operation = "@u32.add", foreign = false) => {
    let annotation = "";
    if (foreign) annotation = ": Number -> Number -> Number ! {Foreign}";
    return `type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add${annotation} = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
`;
  };
  const source = (prefix = "", name = "local") =>
    `import {Number, make, read} from "./numbers"
${prefix}const twice = func value => return do:
  let local = func amount => return @type.call "add" (${genericSpine("amount")}) amount
  break ${name} value
const require_pure = func (callback: U32 -> U32) => return callback 40
entry const run = func (value: U32) => return read (twice (make value))
entry const strict = func () => return require_pure run
`;
  async function pack() {
    await Deno.writeTextFile(
      entry,
      `import {Number, make, read} from "./numbers"
entry const pack = func (value: U32) => return value
`,
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
    await Deno.writeTextFile(entry, source());
  }
  try {
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        const prefix = "const earlier_spelling = { tail: 3.0, head: 2 }\n";
        for (
          const [index, [text, producerText, answer]] of ([
            [source(), library(), 80],
            [source(prefix), library(), 80],
            [source(prefix), library("@u32.sub"), 0],
            [source(prefix, "missing_local"), library(), null],
            [source(prefix), library("@u32.add", true), null],
            [source(prefix), library("@u32.sub"), 0],
            [source(), library(), 80],
          ] as const).entries()
        ) {
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack();
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: text, [producer]: producerText };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.equal(answer, null);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (index !== 0) {
              assert.ok(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("run", 40), answer);
              assert.equal(guest.call("strict", null), answer);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse owns result directed local principals", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-local-result-",
  });
  const entry = `${directory}/main.blot`;
  const source = (prefix = "", increment = "0", member = "from") =>
    `${prefix}type Number is data = $Number U32
const Number.from = func (value: U32) => return $Number (@u32.add value ${increment})
const read = func ($Number value) => return value
const convert = func (value: U32) : Number => return do:
  let local = func amount => return @type.result "${member}" (${genericSpine("amount")})
  break local value
entry const run = func (value: U32) => return read (convert value)
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    const prefix = "const earlier_spelling = { tail: 3.0, head: 2 }\n";
    for (
      const [index, [text, answer]] of ([
        [source(), 40],
        [source(prefix), 40],
        [source(prefix, "2"), 42],
        [source(prefix, "2", "missing_from"), null],
        [source(prefix, "2"), 42],
        [source(), 40],
      ] as const).entries()
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert.ok(!actual.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        if (index !== 0) {
          assert.ok(
            Number(actual.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.equal(guest.call("run", 40), answer);
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse preserves selected Foreign traces in inferred local principals", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-local-foreign-",
  });
  const entry = `${directory}/main.blot`;
  const source = (prefix = "", operation = "@u32.add", callbackType = "Host") =>
    `${prefix}type Host = U32 -> U32 ! {Foreign}
type Pure = U32 -> U32
type Input is data = $Input { value: U32, callback: ${callbackType} }
const make = func callback => return $Input { value: 40, callback: callback }
const read = func (value: Input) => return (value).value
const Input.add = func ($Input { value: left, callback: invoke }) => return func ($Input { value: right, callback: ignored }) => return $Input { value: invoke (${operation} left right), callback: invoke }
const twice = func value => return do:
  let local = func amount => return @type.call "add" (${genericSpine("amount")}) amount
  break local value
entry const run = func (callback: Host) => return read (twice (make callback))
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    const prefix = "const earlier_spelling = { value: 2, callback: 3.0 }\n";
    for (
      const [index, [text, input, answer]] of ([
        [source(), 80, 81],
        [source(prefix), 80, 81],
        [source(prefix, "@u32.sub"), 0, 1],
        [source(prefix, "@u32.sub", "Pure"), null, null],
        [source(prefix, "@u32.sub"), 0, 1],
        [source(), 80, 81],
      ] as const).entries()
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert.ok(!actual.success && !expected.success);
          if (answer !== null) console.error(actual.diagnostics);
          assert.equal(answer, null);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        if (index !== 0) {
          assert.ok(
            Number(actual.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          const trace: number[] = [];
          assert.equal(
            guest.call(
              "run",
              guest.capability({
                parameter: "U32",
                result: "U32",
                call(value: number) {
                  trace.push(value);
                  return value + 1;
                },
              }),
            ),
            answer,
          );
          assert.deepEqual(trace, [input]);
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates written local association and representation origins", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-local-written-",
  });
  const entry = `${directory}/main.blot`;
  const source = (
    prefix = "",
    clause = "add",
    operation = "@u32.add",
    foreign = false,
  ) => {
    let annotation = "";
    if (foreign) annotation = ": Number -> Number -> Number ! {Foreign}";
    return `${prefix}type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add${annotation} = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
const twice = func value => return do:
  let identity: a -> a where { type_rep a } = func amount => return ${
      genericSpine("amount")
    }
  let local: a -> a where { associated "${clause}" a a a } = func amount => return @type.call "add" amount amount
  break identity (local value)
const require_pure = func (callback: U32 -> U32) => return callback 40
entry const run = func (value: U32) => return read (twice (make value))
entry const strict = func () => return require_pure run
`;
  };
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    const prefix = "const earlier_spelling = { tail: 3.0, head: 2 }\n";
    for (
      const [index, [text, answer]] of ([
        [source(), 80],
        [source(prefix), 80],
        [source(prefix, "add", "@u32.sub"), 0],
        [source(prefix, "sub"), null],
        [source(prefix, "add", "@u32.add", true), null],
        [source(prefix, "add", "@u32.sub"), 0],
        [source(), 80],
      ] as const).entries()
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert.ok(!actual.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        if (index !== 0) {
          assert.ok(
            Number(actual.stats.frontend.body_elaborations) <
              Number(expected.stats.frontend.body_elaborations),
          );
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.equal(guest.call("run", 40), answer);
          assert.equal(guest.call("strict", null), answer);
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse preserves exported local qualification origins in source and compiled producers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-local-origin-import-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/numbers.blot`;
  const bundle = `${directory}/numbers.blotdep`;
  const library = (
    earlier = "value",
    operation = "@u32.add",
    clause = "add",
    foreign = false,
  ) => {
    let annotation = "";
    if (foreign) annotation = ": Number -> Number -> Number ! {Foreign}";
    return `const earlier = func value => return ${earlier}
type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add${annotation} = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
const factory = func amount => return do:
  let local: a -> a where { associated "${clause}" a a a } = func value => return @type.call "add" value value
  break local amount
`;
  };
  const source = (prefix = "", factory = "factory") =>
    `import {Number, make, read, factory} from "./numbers"
${prefix}const require_pure = func (callback: U32 -> U32) => return callback 40
entry const run = func (value: U32) => return read (${factory} (make (${
      genericSpine("value")
    })))
entry const strict = func () => return require_pure run
`;
  async function pack() {
    await Deno.writeTextFile(
      entry,
      `import {Number, make, read, factory} from "./numbers"
entry const pack = func (value: U32) => return value
`,
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
    await Deno.writeTextFile(entry, source());
  }
  try {
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        const prefix = "const earlier_spelling = { tail: 3.0, head: 2 }\n";
        for (
          const [index, [text, producerText, answer]] of ([
            [source(), library(), 80],
            [source(prefix), library("{ tail: 3.0, head: value }"), 80],
            [
              source(prefix),
              library("{ tail: 3.0, head: value }", "@u32.sub"),
              0,
            ],
            [
              source(prefix, "missing_factory"),
              library("{ tail: 3.0, head: value }"),
              null,
            ],
            [
              source(prefix),
              library("{ tail: 3.0, head: value }", "@u32.add", "add", true),
              null,
            ],
            [
              source(prefix),
              library("{ tail: 3.0, head: value }", "@u32.sub"),
              0,
            ],
            [source(), library(), 80],
          ] as const).entries()
        ) {
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack();
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: text, [producer]: producerText };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.equal(answer, null);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (index !== 0) {
              assert.ok(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("run", 40), answer);
              assert.equal(guest.call("strict", null), answer);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse relocates producer units and bindings through source and compiled origins", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-origin-ordinals-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/numbers.blot`;
  const replacement = `${directory}/replacement.blot`;
  const pad = `${directory}/pad.blot`;
  const bundle = `${directory}/numbers.blotdep`;
  const library = (
    inserted = false,
    operation = "@u32.add",
    foreign = false,
  ) => {
    let prefix = "";
    if (inserted) {
      prefix =
        "type Earlier is data = $Earlier F32\nconst earlier = { tail: 3.0, head: 2 }\n";
    }
    let annotation = "";
    if (foreign) annotation = ": Number -> Number -> Number ! {Foreign}";
    return `${prefix}type Number is data = $Number U32
const make = func value => return $Number value
const read = func ($Number value) => return value
const Number.add${annotation} = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
const factory = func amount => return do:
  let local: a -> a where { associated "add" a a a } = func value => return @type.call "add" value value
  break local amount
type Box is data = $Box {payload: Number, tail: Array U32}
const make_box = func value => return $Box {payload: make value, tail: #[value, @u32.add value 1]}
const scalar = func (value: U32) => return @u32.add value 2
`;
  };
  const imports = (inserted: boolean, target: string) => {
    let prefix = "";
    if (inserted) prefix = 'import {ignored} from "./pad"\n';
    return `${prefix}import {Number, make, read, factory, Box, make_box, scalar as exposed} from "./${target}"\n`;
  };
  const source = (inserted = false, target = "numbers", missing = false) => {
    let factory = "factory";
    if (missing) factory = "missing_factory";
    return `${
      imports(inserted, target)
    }const require_pure = func (callback: U32 -> U32) => return callback 40
entry const run = func (value: U32) => return read (${factory} (make (${
      genericSpine("value")
    })))
entry const strict = func () => return require_pure run
entry const primitive = func (value: U32) => return exposed (${genericSpine("value")})
entry const shape = func (value: U32) => return do:
  let chosen = ${genericSpine("(make_box value)")}
  break read chosen.payload
entry const owned = func (value: U32) => return do:
  let chosen = ${genericSpine("(make_box value)")}
  break chosen.tail
`;
  };
  async function pack(inserted = false, target = "numbers") {
    await Deno.writeTextFile(
      entry,
      `${
        imports(inserted, target)
      }entry const pack = func (value: U32) => return value\n`,
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
  }
  try {
    await Deno.writeTextFile(producer, library());
    await Deno.writeTextFile(replacement, library(false, "@u32.sub"));
    await Deno.writeTextFile(pad, "const ignored = 7\n");
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [index, [inserted, target, operation, missing, foreign, answer]]
            of ([
              [false, "numbers", "@u32.add", false, false, 80],
              [true, "numbers", "@u32.add", false, false, 80],
              [true, "numbers", "@u32.sub", false, false, 0],
              [false, "numbers", "@u32.sub", false, false, 0],
              [true, "replacement", "@u32.add", false, false, 0],
              [true, "numbers", "@u32.add", true, false, null],
              [true, "numbers", "@u32.add", false, true, null],
              [true, "numbers", "@u32.sub", false, false, 0],
              [false, "numbers", "@u32.add", false, false, 80],
            ] as const).entries()
        ) {
          const producerText = library(inserted, operation, foreign);
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack(inserted, target);
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: source(inserted, target, missing),
              [producer]: producerText,
              [replacement]: library(false, "@u32.sub"),
              [pad]: "const ignored = 7\n",
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.equal(answer, null);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (index !== 0 && index !== 7 && target === "numbers") {
              assert.ok(
                Number(expected.stats.frontend.body_elaborations) -
                    Number(actual.stats.frontend.body_elaborations) >= 4,
                `lane=${dependencies} index=${index} actual=${
                  JSON.stringify(actual.stats.frontend)
                } fresh=${JSON.stringify(expected.stats.frontend)}`,
              );
            }
            if (target === "replacement") {
              assert.equal(
                actual.stats.frontend.body_elaborations,
                expected.stats.frontend.body_elaborations,
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("run", 40), answer);
              assert.equal(guest.call("strict", null), answer);
              assert.equal(guest.call("primitive", 40), 42);
              assert.equal(guest.call("shape", 40), 40);
              assert.deepEqual(
                guest.call("owned", 40),
                new Uint32Array([40, 41]),
              );
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse resolves imported annotation heads with exact source and compiled recipes", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-imported-heads-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/library.blot`;
  const pad = `${directory}/pad.blot`;
  const bundle = `${directory}/library.blotdep`;
  const library = (inserted = false, concrete = false) => {
    let prefix = "";
    if (inserted) {
      prefix = "type Earlier is data = $Earlier F32\nconst earlier = 7\n";
    }
    let element = "a";
    if (concrete) element = "U32";
    return `${prefix}type Wrapper a is data = $Wrapper {value: a, owning: Array U32}
type Alias a = Wrapper ${element}
const make = func value => return $Wrapper {value, owning: #[value, @u32.add value 1]}
`;
  };
  const imports = (mode: string, inserted: boolean) => {
    let text = "";
    if (inserted) text += 'import {ignored} from "./pad"\n';
    if (mode === "namespace") {
      return text + 'import * as lib from "./library"\n';
    }
    return text +
      'import {Wrapper, Alias as Imported, make} from "./library"\n';
  };
  const source = (
    mode: string,
    inserted = false,
    missing = false,
    concrete = false,
  ) => {
    let marker = "7";
    if (concrete) marker = "{fresh_spelling: 3.0, chosen: 8}";
    let head = "Wrapper";
    let make = "make";
    let constructor = "Wrapper";
    if (mode === "alias") head = "Imported";
    if (mode === "namespace") {
      head = "lib.Alias";
      make = "lib.make";
      constructor = "lib.Wrapper";
    }
    if (missing) head = "Missing";
    return `${imports(mode, inserted)}const marker = ${marker}
const hold = func (value: ${head} U32) => return ${genericSpine("value")}
entry const run = func (value: U32) => return do:
  let $${constructor} {value: result, owning: items} = hold (${make} value)
  break @u32.add result (@array.length items)
entry const owned = func (value: U32) => return do:
  let $${constructor} {value: result, owning: items} = hold (${make} value)
  break items
`;
  };
  async function pack(mode: string, inserted = false) {
    await Deno.writeTextFile(
      entry,
      `${imports(mode, inserted)}entry const pack = func (value: U32) => return value\n`,
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
  }
  try {
    await Deno.writeTextFile(pad, "const ignored = 7\n");
    for (const mode of ["direct", "alias", "namespace"]) {
      await Deno.writeTextFile(producer, library());
      await pack(mode);
      for (const dependencies of [undefined, bundle]) {
        const options = { executable, entry, prelude: null, dependencies };
        const retained = await createZigProjectCompiler(options);
        try {
          for (
            const [index, [inserted, concrete, missing]] of ([
              [false, false, false],
              [true, false, false],
              [true, true, false],
              [true, true, true],
              [true, true, false],
              [false, true, false],
              [false, false, false],
              [true, false, false],
            ] as const).entries()
          ) {
            const producerText = library(inserted, concrete);
            await Deno.writeTextFile(producer, producerText);
            if (dependencies !== undefined) await pack(mode, inserted);
            const fresh = await createZigProjectCompiler(options);
            try {
              const sources = {
                [entry]: source(mode, inserted, missing, concrete),
                [producer]: producerText,
                [pad]: "const ignored = 7\n",
              };
              const expected = await fresh.build({ sources });
              const actual = await retained.build({ sources });
              assert.equal(actual.success, expected.success);
              if (!actual.success || !expected.success) {
                assert.ok(!actual.success && !expected.success);
                assert.ok(missing);
                assert.deepEqual(actual.diagnostics, expected.diagnostics);
                continue;
              }
              assert.deepEqual(actual.bytes, expected.bytes);
              const difference =
                Number(expected.stats.frontend.body_elaborations) -
                Number(actual.stats.frontend.body_elaborations);
              if (index !== 0) {
                if ((index === 2 || index === 6) && mode !== "direct") {
                  // The instantiated type stays Wrapper U32. The generic alias
                  // recipe still changes and must revoke its annotation read.
                  assert.ok(
                    difference === 0 ||
                      Number(actual.stats.frontend.syntax_nodes) === 0,
                    `mode=${mode} lane=${dependencies} index=${index} actual=${
                      JSON.stringify(actual.stats.frontend)
                    } fresh=${JSON.stringify(expected.stats.frontend)}`,
                  );
                } else {
                  assert.ok(
                    difference >= 1,
                    `mode=${mode} lane=${dependencies} index=${index} actual=${
                      JSON.stringify(actual.stats.frontend)
                    } fresh=${JSON.stringify(expected.stats.frontend)}`,
                  );
                }
              }
              const guest = await instantiateGuest(actual.bytes);
              try {
                assert.equal(guest.call("run", 40), 42);
                assert.deepEqual(
                  guest.call("owned", 40),
                  new Uint32Array([40, 41]),
                );
              } finally {
                await guest.dispose();
              }
            } finally {
              await fresh.close();
            }
          }
        } finally {
          await retained.close();
        }
        await Deno.writeTextFile(producer, library());
        await pack(mode);
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse owns shared local relays through source and compiled changes", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-shared-local-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/numbers.blot`;
  const pad = `${directory}/pad.blot`;
  const bundle = `${directory}/numbers.blotdep`;
  const library = (
    inserted = false,
    operation = "@u32.add",
    foreign = false,
    qualified = true,
    owning = false,
  ) => {
    let prefix = "";
    if (inserted) {
      prefix = "type Earlier is data = $Earlier F32\nconst earlier = 7\n";
    }
    let annotation = "";
    if (foreign) annotation = ": Number -> Number -> Number ! {Foreign}";
    let payload = "U32";
    let make = "$Number value";
    let read = "value";
    if (owning) {
      payload = "Array U32";
      make = "$Number #[value, @u32.add value 1]";
      read = "@array.length value";
      operation = "@array.concat";
    }
    let twice = '@type.call "add" amount amount';
    if (!qualified) twice = "amount";
    return `${prefix}type Number is data = $Number ${payload}
const make = func (value: U32) => return ${make}
const read = func ($Number value) => return ${read}
const Number.add${annotation} = func ($Number left) => return func ($Number right) => return $Number (${operation} left right)
const twice = func amount => return ${twice}
`;
  };
  const imports = (inserted: boolean) => {
    let text = "";
    if (inserted) text = 'import {ignored} from "./pad"\n';
    return text +
      'import {Number, make, read, twice as exposed} from "./numbers"\n';
  };
  const source = (inserted = false, missing = false) => {
    let target = "exposed";
    if (missing) target = "missing_twice";
    return `${imports(inserted)}const pipeline = func value => return do:
  let local = func amount => return ${target} (${genericSpine("amount")})
  let relay = func amount => return local amount
  break relay value
const require_pure = func (callback: U32 -> U32) => return callback 40
entry const run = func (value: U32) => return read (pipeline (make value))
entry const strict = func () => return require_pure run
`;
  };
  async function pack(inserted = false) {
    await Deno.writeTextFile(
      entry,
      `${imports(inserted)}entry const pack = func (value: U32) => return value\n`,
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
  }
  try {
    await Deno.writeTextFile(pad, "const ignored = 7\n");
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [
            index,
            [inserted, operation, foreign, qualified, missing, owning, answer],
          ] of ([
            [false, "@u32.add", false, true, false, false, 80],
            [true, "@u32.add", false, true, false, false, 80],
            [true, "@u32.sub", false, true, false, false, 0],
            [true, "@u32.add", false, true, true, false, null],
            [true, "@u32.add", true, true, false, false, null],
            [true, "@u32.add", false, true, false, false, 80],
            [true, "@u32.add", false, false, false, false, 40],
            [true, "@u32.add", false, false, false, true, 2],
            [true, "@u32.add", false, true, false, true, 4],
            [false, "@u32.add", false, true, false, true, 4],
            [false, "@u32.add", false, true, false, false, 80],
          ] as const).entries()
        ) {
          const producerText = library(
            inserted,
            operation,
            foreign,
            qualified,
            owning,
          );
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack(inserted);
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: source(inserted, missing),
              [producer]: producerText,
              [pad]: "const ignored = 7\n",
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.equal(answer, null);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (index === 1 || index === 2 || index === 5 || index === 9) {
              assert.ok(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
                `lane=${dependencies} index=${index} actual=${
                  JSON.stringify(actual.stats.frontend)
                } fresh=${JSON.stringify(expected.stats.frontend)}`,
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("run", 40), answer);
              assert.equal(guest.call("strict", null), answer);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse owns Foreign arrows through source compiled changes and rejection", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-foreign-arrow-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/callbacks.blot`;
  const bundle = `${directory}/callbacks.blotdep`;
  const library = (changed = false, pure = false) => {
    let effects = "Foreign";
    if (pure) effects = "";
    let value = "value";
    if (changed) value = "@u32.add value 1";
    return `const invoke = func (host: U32 -> U32 ! {${effects}}) => return func (value: U32) => return host (${value})\n`;
  };
  const source = (inserted = false, pure = false, missing = false) => {
    let prefix = "";
    if (inserted) prefix = "const earlier_spelling = {tail: 3.0, head: 2}\n";
    let effects = "Foreign";
    let target = "host";
    if (pure) {
      effects = "";
      target = "func (value: U32) => return value";
    }
    let helper = "invoke";
    if (missing) helper = "missing_invoke";
    return `import {invoke} from "./callbacks"
${prefix}const relay = func (host: U32 -> U32 ! {${effects}}) => return ${helper} host (${
      genericSpine("40")
    })
entry const run = func (host: U32 -> U32 ! {Foreign}) => return relay (${target})
`;
  };
  async function pack() {
    await Deno.writeTextFile(
      entry,
      'import {invoke} from "./callbacks"\nentry const pack = func (value: U32) => return value\n',
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
  }
  try {
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [index, [inserted, changed, pure, missing, accepted, answer]]
            of ([
              [false, false, false, false, true, 41],
              [true, false, false, false, true, 41],
              [true, true, false, false, true, 42],
              [true, true, false, true, false, 0],
              [true, true, false, "closed", false, 0],
              [true, true, true, false, true, 41],
              [true, true, false, false, true, 42],
              [false, false, false, false, true, 41],
            ] as const).entries()
        ) {
          const producerText = library(changed, pure);
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack();
          const fresh = await createZigProjectCompiler(options);
          try {
            let entryText = source(inserted, pure, missing === true);
            if (missing === "closed") {
              entryText = entryText.replace(
                "const relay = func",
                "const relay: (U32 -> U32 ! {Foreign}) -> U32 ! {} = func",
              );
            }
            const sources = {
              [entry]: entryText,
              [producer]: producerText,
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, accepted);
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (index === 1) {
              assert.ok(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            const trace: number[] = [];
            try {
              assert.equal(
                guest.call(
                  "run",
                  guest.capability({
                    parameter: "U32",
                    result: "U32",
                    call(value: number) {
                      trace.push(value);
                      return value + 1;
                    },
                  }),
                ),
                answer,
              );
              let expectedTrace: number[] = [40];
              if (changed) expectedTrace = [41];
              if (pure) expectedTrace = [];
              assert.deepEqual(trace, expectedTrace);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse owns array selectors through source compiled changes and rejection", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-array-index-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/arrays.blot`;
  const bundle = `${directory}/arrays.blotdep`;
  const library = (changed = false) => {
    let index = "0";
    if (changed) index = "1";
    return `const first = func (values: Array a) => return (${
      genericSpine("values")
    })[${index}]\n`;
  };
  const source = (index = "0", inserted = false) => {
    let prefix = "";
    if (inserted) prefix = "const earlier_spelling = {tail: 3.0, head: 2}\n";
    return `import {first} from "./arrays"
${prefix}const slot = ${index}
const select = func (values: Array a) => return (${genericSpine("values")})[slot]
entry const run = func (value: U32) => return select #[value, @u32.add value 1]
entry const floating = func (value: F32) => return select #[value, @f32.add value 1.0]
entry const packed = func (value: U32) => return select #[#[value], #[@u32.add value 1]]
entry const imported = func (value: U32) => return first #[value, @u32.add value 1]
`;
  };
  async function pack() {
    await Deno.writeTextFile(
      entry,
      'import {first} from "./arrays"\nentry const pack = func (value: U32) => return value\n',
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
  }
  try {
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [revision, [slot, inserted, changed, accepted]] of ([
            ["0", false, false, true],
            ["0", true, false, true],
            ["1", true, false, true],
            ["1.0", true, false, false],
            ["1", true, true, true],
            ["0", false, false, true],
          ] as const).entries()
        ) {
          const producerText = library(changed);
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack();
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: source(slot, inserted),
              [producer]: producerText,
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, accepted);
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (revision === 1 || revision === 2 || revision === 4) {
              assert.ok(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            let answer = 40;
            if (slot === "1") answer += 1;
            let imported = 40;
            if (changed) imported += 1;
            try {
              for (let repeat = 0; repeat < 3; repeat++) {
                assert.equal(guest.call("run", 40), answer);
                assert.equal(guest.call("floating", 40.5), answer + 0.5);
                assert.deepEqual(
                  guest.call("packed", 40),
                  new Uint32Array([answer]),
                );
                assert.equal(guest.call("imported", 40), imported);
              }
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse owns generic explicit and dotted fields through source compiled recipes", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-body-generic-field-",
  });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/boxes.blot`;
  const bundle = `${directory}/boxes.blotdep`;
  const library = (
    reordered = false,
    owning = false,
    missing = false,
    candidate: boolean | "foreign" = false,
  ) => {
    let field = "item";
    if (missing) field = "other";
    let value = "value";
    let shape = "U32";
    if (owning) {
      value = "#[value, @u32.add value 1]";
      shape = "Array U32";
    }
    let fields = `tail: F32, ${field}: ${shape}`;
    let values = `tail: 2.0, ${field}: ${value}`;
    if (reordered) {
      fields = `${field}: ${shape}, head: F32`;
      values = `${field}: ${value}, head: 2.0`;
    }
    let operation = "@u32.add";
    if (reordered) operation = "@u32.sub";
    let annotation = "";
    if (candidate === "foreign") annotation = ": Scalar -> U32 ! {Foreign}";
    let member =
      `const Scalar.item${annotation} = func ($Scalar value) => return ${operation} value 1\n`;
    if (candidate === true) {
      member += "const F32.item = func (value: F32) => return value\n";
    }
    return `type Scalar is data = $Scalar U32
const wrap = func (value: U32) => return $Scalar value
type Box is data = $Box {${fields}}
const make = func (value: U32) => return $Box {${values}}
const project: a -> b where { field "item" a b } = func value => return ${
      genericSpine("value.item")
    }
${member}`;
  };
  const source = (inserted = false, dotted = false, declared = false) => {
    let getter = `(${genericSpine("value")}).item`;
    let local = `(${genericSpine("row")}).item`;
    if (dotted) {
      getter = genericSpine("value.item");
      local = genericSpine("row.item");
    }
    let prefix = "";
    if (inserted) prefix = "const earlier_spelling = {head: 3.0, tail: 2}\n";
    const requirement = declared ? ': a -> b where { field "item" a b }' : "";
    // Written field constraints require an actual field. Keep the existing
    // associated-method controls under their inferred member principal.
    const methodGetter = declared
      ? `const method_extract = func value => return ${getter}\n`
      : "";
    return `import {Box, make, Scalar, wrap, project} from "./boxes"
${prefix}const extract${requirement} = func value => return ${getter}
${methodGetter}const scoped = func value => return do:
  let local${requirement} = func row => return ${local}
  break local value
const require_pure = func (callback: U32 -> U32) => return callback 40
entry const selected = func (value: U32) => return ${
      declared ? "method_extract" : "extract"
    } (wrap value)
entry const strict = func () => return require_pure selected
entry const local = func (value: U32) => return scoped (make value)
entry const run = func (value: U32) => return extract (make value)
entry const forwarded = func (value: U32) => return ${
      genericSpine("project (make value)")
    }
entry const packed = func (value: U32) => return extract {tail: 3.0, item: #[value]}
`;
  };
  async function pack() {
    await Deno.writeTextFile(
      entry,
      'import {Box, make, Scalar, wrap, project} from "./boxes"\nentry const pack = func (value: U32) => return value\n',
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
  }
  try {
    await Deno.writeTextFile(producer, library());
    await pack();
    for (
      const [dotted, declared] of [
        [false, false],
        [true, false],
        [false, true],
        [true, true],
      ]
    ) {
      for (const dependencies of [undefined, bundle]) {
        const options = {
          executable,
          entry,
          prelude: null,
          dependencies,
          cacheDirectory: false as const,
        };
        const retained = await createZigProjectCompiler(options);
        try {
          for (
            const [revision, [inserted, reordered, owning, missing, candidate]]
              of ([
                [false, false, false, false, false],
                [true, false, false, false, false],
                [true, true, false, false, false],
                [true, true, false, true, false],
                [true, true, true, false, false],
                [true, true, true, false, true],
                [true, true, false, false, "foreign"],
                [false, false, false, false, false],
              ] as const).entries()
          ) {
            const producerText = library(reordered, owning, missing, candidate);
            await Deno.writeTextFile(producer, producerText);
            if (dependencies !== undefined) await pack();
            const fresh = await createZigProjectCompiler(options);
            try {
              const sources = {
                [entry]: source(inserted, dotted, declared),
                [producer]: producerText,
              };
              const expected = await fresh.build({ sources });
              const actual = await retained.build({ sources });
              if (!actual.success && !missing && candidate !== "foreign") {
                throw new Error(
                  JSON.stringify({
                    dependencies,
                    revision,
                    diagnostics: actual.diagnostics,
                  }),
                );
              }
              assert.equal(actual.success, !missing && candidate !== "foreign");
              assert.equal(actual.success, expected.success);
              if (!actual.success || !expected.success) {
                assert.ok(!actual.success && !expected.success);
                assert.deepEqual(actual.diagnostics, expected.diagnostics);
                continue;
              }
              assert.deepEqual(actual.bytes, expected.bytes);
              if (revision === 1 || revision === 2) {
                assert.ok(
                  Number(actual.stats.frontend.body_elaborations) <
                    Number(expected.stats.frontend.body_elaborations),
                  JSON.stringify({
                    dotted,
                    declared,
                    dependencies,
                    revision,
                    actual: actual.stats.frontend,
                    expected: expected.stats.frontend,
                  }),
                );
              }
              if (declared && revision === 1) {
                const invalidSources = {
                  ...sources,
                  [entry]: source(inserted, dotted, true).replaceAll(
                    'field "item" a b',
                    'field "absent" a b',
                  ),
                };
                const ordinary = await createZigProjectCompiler(options);
                try {
                  const invalidExpected = await ordinary.build({
                    sources: invalidSources,
                  });
                  const invalidActual = await retained.build({
                    sources: invalidSources,
                  });
                  assert.ok(!invalidExpected.success && !invalidActual.success);
                  if (!invalidExpected.success && !invalidActual.success) {
                    assert.deepEqual(
                      invalidActual.diagnostics,
                      invalidExpected.diagnostics,
                    );
                  }
                  const recovered = await retained.build({ sources });
                  assert.ok(recovered.success);
                  if (recovered.success) {
                    assert.deepEqual(recovered.bytes, actual.bytes);
                  }
                } finally {
                  await ordinary.dispose();
                }
              }
              const guest = await instantiateGuest(actual.bytes);
              try {
                for (let repeat = 0; repeat < 3; repeat++) {
                  let selected = 41;
                  if (reordered) selected = 39;
                  assert.equal(guest.call("selected", 40), selected);
                  assert.equal(guest.call("strict", null), selected);
                  if (owning) {
                    assert.deepEqual(
                      guest.call("run", 40),
                      new Uint32Array([40, 41]),
                    );
                    assert.deepEqual(
                      guest.call("forwarded", 40),
                      new Uint32Array([40, 41]),
                    );
                  } else assert.equal(guest.call("run", 40), 40);
                  if (!owning) assert.equal(guest.call("forwarded", 40), 40);
                  if (owning) {
                    assert.deepEqual(
                      guest.call("local", 40),
                      new Uint32Array([40, 41]),
                    );
                  } else assert.equal(guest.call("local", 40), 40);
                  assert.deepEqual(
                    guest.call("packed", 40),
                    new Uint32Array([40]),
                  );
                }
              } finally {
                await guest.dispose();
              }
            } finally {
              await fresh.close();
            }
          }
        } finally {
          await retained.close();
        }
        await Deno.writeTextFile(producer, library());
        await pack();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body checker reuse owns if let joins captures and effect traces through compiled changes", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-if-let-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/maybe.blot`;
  const bundle = `${directory}/maybe.blotdep`;
  const library = (variant = false) => {
    let extra = "";
    if (variant) extra = "$Earlier | ";
    return `type Maybe a is data = ${extra}$None | $Some a
const some = func value => return $Some value
const none = $None
`;
  };
  const source = (seed = "2", inserted = false, fallback = "3") => {
    let prefix = "";
    if (inserted) prefix = "const earlier_spelling = {head: 3.0, tail: 2}\n";
    return `import {Maybe, Some, some, none} from "./maybe"
${prefix}const seed = ${seed}
const choose = func (value: Maybe U32) => return do:
  let result = seed
  if let $Some amount = value:
    result := @u32.add (${genericSpine("amount")}) seed
  else:
    result := ${fallback}
  break result
const pack = func (value: Maybe (Array U32)) => return do:
  let result = #[seed]
  if let $Some amount = value:
    result := @array.identity (${genericSpine("amount")})
  break result
const negative = func (value: F32) => return -(${genericSpine("value")})
const matching = func (value: U32) => return do:
  if let ^seed = value:
    break 1
  break 0
const collected = func (value: U32) => return @array.slice (@array.concat (@array.prepend (@array.append #[value] seed) seed) (@array.fill 2 value)) 0 3
const listed = func (value: U32) => return @list.from_array (@array.from_list (@list.append [value] seed))
const generated = func (value: U32) => return @array.generate 2 (func (index: U32) => return @u32.add value index)
const projected = func (value: U32) => return @product.get (3.0, value) 1
const action = func callback => return func (value: Maybe U32) => return do:
  if let $Some amount = value:
    break callback (${genericSpine("amount")})
  break callback seed
entry const fraction = func (value: F32) => return negative value
entry const matched = func (value: U32) => return matching value
entry const collection = func (value: U32) => return collected value
entry const list_count = func (value: U32) => return @list.length (listed value)
entry const generator = func (value: U32) => return @array.get (generated value) 1
entry const pair = func (value: U32) => return projected value
entry const run = func (value: U32) => return choose (some value)
entry const empty = func () => return choose none
entry const packed = func (value: U32) => return pack (some #[value, seed])
entry const empty_packed = func () => return pack none
entry const invoke = func (host: U32 -> U32 ! {Foreign}) => return action host (some 40)
entry const absent = func (host: U32 -> U32 ! {Foreign}) => return action host none
`;
  };
  async function pack() {
    await Deno.writeTextFile(
      entry,
      'import {Maybe, Some, some, none} from "./maybe"\nentry const pack = func (value: U32) => return value\n',
    );
    const result = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      result.success,
      new TextDecoder().decode(result.stdout) +
        new TextDecoder().decode(result.stderr),
    );
  }
  try {
    await Deno.writeTextFile(producer, library());
    await pack();
    for (const dependencies of [undefined, bundle]) {
      const options = { executable, entry, prelude: null, dependencies };
      const retained = await createZigProjectCompiler(options);
      try {
        for (
          const [revision, [seed, inserted, fallback, variant, accepted]] of ([
            ["2", false, "3", false, true],
            ["3", true, "3", false, true],
            ["3", true, "4", false, true],
            ["missing_seed", true, "4", false, false],
            ["3", true, "4", true, true],
            ["2", false, "3", false, true],
          ] as const).entries()
        ) {
          const producerText = library(variant);
          await Deno.writeTextFile(producer, producerText);
          if (dependencies !== undefined) await pack();
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: source(seed, inserted, fallback),
              [producer]: producerText,
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            if (!actual.success && accepted) {
              throw new Error(JSON.stringify(actual.diagnostics));
            }
            assert.equal(actual.success, accepted);
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            if (revision === 1 || revision === 2) {
              assert.ok(
                Number(actual.stats.frontend.body_elaborations) <
                  Number(expected.stats.frontend.body_elaborations),
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            const trace: number[] = [];
            const capability = guest.capability({
              parameter: "U32",
              result: "U32",
              call(value: number) {
                trace.push(value);
                return value + 1;
              },
            });
            try {
              for (let repeat = 0; repeat < 3; repeat++) {
                assert.equal(guest.call("run", 40), 40 + Number(seed));
                assert.equal(guest.call("fraction", 40.5), -40.5);
                assert.equal(guest.call("matched", Number(seed)), 1);
                assert.equal(guest.call("matched", 40), 0);
                assert.deepEqual(
                  guest.call("collection", 40),
                  new Uint32Array([Number(seed), 40, Number(seed)]),
                );
                assert.equal(guest.call("list_count", 40), 2);
                assert.equal(guest.call("generator", 40), 41);
                assert.equal(guest.call("pair", 40), 40);
                assert.equal(guest.call("empty", null), Number(fallback));
                assert.deepEqual(
                  guest.call("packed", 40),
                  new Uint32Array([40, Number(seed)]),
                );
                assert.deepEqual(
                  guest.call("empty_packed", null),
                  new Uint32Array([Number(seed)]),
                );
                assert.equal(guest.call("invoke", capability), 41);
                assert.equal(
                  guest.call("absent", capability),
                  Number(seed) + 1,
                );
              }
              assert.deepEqual(trace, [
                40,
                Number(seed),
                40,
                Number(seed),
                40,
                Number(seed),
              ]);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
      await Deno.writeTextFile(producer, library());
      await pack();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("body cache directory preserves dependency execution through bootstrap and reordered recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-directory-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/dep.blot`;
  const earlier = `${directory}/earlier.blot`;
  const text = (seed: string) =>
    `const changed = ${seed}
const read = func (value: U32) => return @u32.add (${primitiveSpine("value")}) changed
const stable = func (value: U32) => return @u32.add (${primitiveSpine("value")}) 41
`;
  const main = `import * as dep from "./dep"
entry const answer = func (value: U32) => return @u32.add (dep.read value) (dep.stable value)
`;
  const reordered = `import {value} from "./earlier"
import * as dep from "./dep"
entry const answer = func (argument: U32) => return @u32.add (dep.read argument) (@u32.add (dep.stable argument) value)
`;
  const retained = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
  });
  try {
    for (
      const [source, consumer, answer] of [
        [text("8"), main, 129],
        [text("@u32.add 8 1"), main, 130],
        [text("@u32.add 8 1"), reordered, 130],
        [text("false"), reordered, null],
        [text("8"), reordered, 129],
      ] as const
    ) {
      const fresh = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
      });
      try {
        const sources = {
          [entry]: consumer,
          [producer]: source,
          [earlier]: "const value = 0\n",
        };
        const expected = await fresh.build({ sources });
        const result = await retained.build({ sources });
        assert.equal(result.success, expected.success);
        if (!result.success || !expected.success) {
          assert.ok(!result.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(result.bytes, expected.bytes);
        assert.equal(
          result.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        const guest = await instantiateGuest(result.bytes);
        assert.equal(guest.call("answer", 40), answer);
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});
