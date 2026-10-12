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
  for (let step = 0; step < 12; step++) value = `(fn item => item) (${value})`;
  return value;
}

Deno.test("body checker reuse relocates and follows executable edits through rejected revisions", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-check-" });
  const entry = `${directory}/main.blot`;
  const source = (seed: string, prefix = "", helper = "@u32.add value seed") =>
    `${prefix}const seed = ${seed}
const helper = fn (value: U32) -> U32 => ${
      helper.replaceAll("value", `(${primitiveSpine("value")})`)
    }
entry const answer = fn (argument: U32) -> U32 => helper argument
entry const captured = fn (outer: U32) -> U32 => (fn (inner: U32) -> U32 => @u32.add outer inner) seed
entry const pair = fn (value: U32) => #[value, seed]
const unrelated = 7
`;
  const inserted =
    "const fresh_spelling = fn (earlier: F32) -> F32 => @f32.add earlier 4.0\n";
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
      `const ${name} = fn (x: U32) -> U32 => @u32.add x ${constant}\n`,
    [entry]:
      `import {${name} as exposed} from "./dep"\nentry const run = fn (x: U32) -> U32 => exposed x\nconst untouched = 7\n`,
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
    `${prefix}const identity = fn outer => (${identity}) (${
      genericSpine("outer")
    })
const box = fn x => #[${genericSpine("x")}]
entry const scalar = fn (x: U32) -> U32 => identity x
entry const floating = fn (x: F32) -> F32 => identity x
entry const reference = fn (x: U32) => box (identity x)
`;
  const revisions = [
    source("fn x => x"),
    source(
      "fn x => x",
      "const new_type_and_spelling = fn (x: Bool) -> Bool => x\n",
    ),
    source("fn x => (fn inner => inner) x"),
    source("fn x => missing_name"),
    source("fn x => x"),
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
  const body = `const apply = fn callback => fn argument => callback (${
    genericSpine("argument")
  })
entry const run = fn (host: U32 -> U32 ! {Foreign}) => apply host 42
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
        `const earlier_spelling = fn (x: F32) -> F32 => @f32.add x 2.0\n${body}`,
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
const make = fn (value: U32) => #Token value
const read = fn (#Token value) => value
`;
  const source = (seed: number, prefix = "") =>
    `import {Token, make, read} from "./tokens"
${prefix}const seed = ${seed}
entry const run = fn (value: U32) => @u32.add (read (make (${
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
              "const earlier_spelling = fn (x: Bool) -> Bool => x\n",
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
const make = fn (value: U32) => #Token #[value]
const read = fn (#Token value) => @array.get value 0
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
          assert.ok(Number(result.stats.frontend.body_elaborations) >= 2);
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
const make = fn value => #Box value
const read = fn (#Box value) => value
const identity = fn (value: Box a) -> Box a => ${genericSpine("value")}
type Pair [left, right] = (left, right)
const shaped = fn (value: Pair [U32, F32]) -> U32 => ${genericSpine("40")}
const arrayed = fn (value: Array a) -> Array a => ${genericSpine("value")}
entry const pair = fn (value: U32) => shaped (value, 2.0)
entry const array_value = fn (value: U32) => arrayed #[value]
entry const unsigned = fn (value: U32) => read (identity (${helper} (${
      primitiveSpine("value")
    })))
entry const floating = fn (value: F32) => read (identity (${helper} (${
      genericSpine("value")
    })))
entry const reference = fn (value: U32) => read (identity (${helper} #[${
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
          "type Earlier is data = #Earlier Bool\nconst fresh_spelling = 2.0\n",
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
    return `${prefix}type Number is data = #Number U32
const make = fn value => #Number value
const read = fn (#Number value) => value
const Number.add${annotation} = fn (#Number left) => fn (#Number right) => #Number (${operation} (${
      primitiveSpine("left")
    }) right)
const add = fn left => fn right => @type.call "add" (${
      genericSpine("left")
    }) right
const forwarded = fn left => fn right => add (${genericSpine("left")}) right
const alias = fn left => fn right => forwarded (${genericSpine("left")}) right
const require_pure = fn (callback: U32 -> U32) => callback 40
entry const run = fn (value: U32) => read (alias (make (${
      primitiveSpine("value")
    })) (make 2))
entry const strict = fn (value: U32) => require_pure run
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
const make = fn value => #Entry value
const read = fn (#Entry { tail }) => tail
entry const unsigned = fn (value: U32) => ${read} (make { head: value, tail: #[${
      primitiveSpine("value")
    }] })
entry const floating = fn (value: F32) => ${read} (make { head: value, tail: #[${
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
    `type Number is data = #Number U32
const make = fn value => #Number value
const read = fn (#Number value) => value
const Number.add = fn (#Number left) => fn (#Number right) => #Number (${operation} left right)
const add = fn left => fn right => @type.call "add" left right
const forwarded = fn left => fn right => add left right
`;
  const source = (prefix = "", target = "forwarded") =>
    `import {Number, make, read, forwarded} from "./numbers"
${prefix}const wrapper = fn left => fn right => ${target} (${
      genericSpine("left")
    }) right
entry const run = fn (value: U32) => read (wrapper (make value) (make 2))
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
        const prefix = "const earlier_spelling = fn (x: F32) => x\n";
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
    return `${prefix}type Number is data = #Number U32
const make = fn value => #Number value
const read = fn (#Number value) => value
const Number.add${annotation} = fn (#Number left) => fn (#Number right) => #Number (${operation} left right)
const twice: a -> a where { ${clause} } = fn value => @type.call "add" (${
      genericSpine("value")
    }) value
const identity: a -> a where { type_rep a } = fn value => ${
      genericSpine("value")
    }
const require_pure = fn (callback: U32 -> U32) => callback 40
entry const run = fn (value: U32) => read (identity (twice (make value)))
entry const strict = fn () => require_pure run
`;
  };
  const prefix = "const new_spelling = fn (x: F32) => x\n";
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
    `const earlier = fn value => ${earlier}
type Number is data = #Number U32
const make = fn value => #Number value
const read = fn (#Number value) => value
const Number.add = fn (#Number left) => fn (#Number right) => #Number (${operation} left right)
const twice: a -> a where { ${clause} } = fn value => @type.call "add" value value
`;
  const source = (prefix = "", target = "twice") =>
    `import {Number, make, read, twice} from "./numbers"
${prefix}const wrapper: a -> a where {associated "add" a a a} = fn value => ${target} (${
      genericSpine("value")
    })
entry const run = fn (value: U32) => read (wrapper (make value))
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
        const prefix = "const new_spelling = fn (x: F32) => x\n";
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
