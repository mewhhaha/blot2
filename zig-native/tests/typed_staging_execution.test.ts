import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { strict as assert } from "node:assert";
import { rm } from "node:fs/promises";

// A detached Linux restart-cache writer may publish files after dispose.
// Deno does not currently honor Node rm maxRetries, so bound the retry here.
async function removeFixture(directory: string) {
  for (let attempt = 0;; attempt++) {
    try {
      await rm(directory, { recursive: true, force: true });
      return;
    } catch (error) {
      if (
        !(error instanceof Error) || !("code" in error) ||
        error.code !== "ENOTEMPTY" || attempt >= 400
      ) throw error;
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  }
}
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("quoted affine parameters keep move ownership in sync and JSPI guests", async () => {
  const source = `const generated = @code.quote (func (value: unique U32) => return do:
  let first = value
  break first)
const borrowed = @code.quote (func (value: unique U32) => return @usage.borrow value (func loan => return @usage.read loan))
const identity: unique U32 -> unique U32 = @code.emit generated
const read: unique U32 -> U32 = @code.emit borrowed
const read_again: unique U32 -> U32 = @code.emit borrowed
entry const answer = func (value: unique U32) => return identity value
entry const inspect = func (value: unique U32) => return read value
entry const inspect_again = func (value: unique U32) => return read_again value
`;
  for (const asynchronous of [false, true]) {
    await compileAndRun(source, async (guest) => {
      let owner;
      if (asynchronous) owner = await guest.callAsync("answer", 42);
      else owner = guest.call("answer", 42);
      let result;
      if (asynchronous) result = await guest.callAsync("inspect", owner);
      else result = guest.call("inspect", owner);
      equal(result, 42);
      if (asynchronous) {
        await assert.rejects(guest.callAsync("inspect", owner), {
          code: "use_after_move",
        });
      } else {
        assert.throws(() => guest.call("inspect", owner), {
          code: "use_after_move",
        });
      }
      if (asynchronous) {
        const next = await guest.callAsync("answer", 43);
        equal(await guest.callAsync("inspect_again", next), 43);
      } else {
        const next = guest.call("answer", 43);
        equal(guest.call("inspect_again", next), 43);
      }
    }, { asynchronous });
  }
  await compileExpectedFailure(
    source.replace("break first)", "break value)"),
    "use_after_move",
  );
  await compileExpectedFailure(
    source.replace("identity value", "(@code.emit generated) value"),
    "multiplicity_unknown",
  );
});

Deno.test("typed code composes lifts evaluates descriptors and emits ordinary Wasm", async () => {
  await compileAndRun(
    `const left: code [U32, row {}] = @code.quote 40
const right: code [U32, row {}] = @code.quote 2
const answer_code = @code.quote (@u32.add (@code.splice left) (@code.splice right))
const make = func (value: U32) => return @code.quote (@u32.add (@code.lift value) 2)
const generated = make 40
const description = @code.describe (@code.quote {number: 1, flag: true})
const fields = @descriptor.fields description.result
entry const same: Bool = @descriptor.same fields.number (@code.describe left).result
entry const checked_answer: U32 = @code.run answer_code
entry const answer = func () => return @code.emit generated
`,
    (guest) => {
      equal(guest.read("same"), true);
      equal(guest.read("checked_answer"), 42);
      equal(guest.call("answer", null), 42);
    },
    { prelude: "none" },
  );
});

Deno.test("repeated typed-code emissions preserve independent locals beside caller bindings", async () => {
  await compileAndRun(
    `const generated = @code.quote (do:
  let value = 19
  break @u32.add value 2)
entry const answer = func () => return do:
  let value = 100
  let local = @code.quote 1
  let first = @code.emit generated
  let second = @code.emit generated
  break @u32.add value (@u32.add first (@u32.add second (@code.emit local)))
`,
    (guest) => equal(guest.call("answer", null), 143),
    { prelude: "none" },
  );
});

Deno.test("typed staging rejects runtime construction and stage data at guest boundaries", async () => {
  await compileExpectedFailure(
    `const make = func (value: U32) => return @code.quote (@code.lift value)
entry const answer = func (value: U32) => return @code.emit (make value)
`,
    "stage_unavailable",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    "entry const answer = @code.quote 42",
    "entry_type",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("typed code preserves future closures and delays quoted traps until emission", async () => {
  await compileAndRun(
    `const make = func (value: U32) => return @code.quote (func (argument: U32) => return @u32.add argument (@code.lift value))
const first = make 2
const second = make 3
const run_first = @code.run first
const latent: code [U32, row {}] = @code.quote (@panic "generated trap")
entry const answer = func (argument: U32) => return @u32.add ((@code.emit first) argument) ((@code.emit second) argument)
entry const evaluated = func (argument: U32) => return run_first argument
entry const guarded = func (flag: Bool) => return if flag then @code.emit latent else 7
`,
    (guest) => {
      equal(guest.call("answer", 20), 45);
      equal(guest.call("evaluated", 40), 42);
      equal(guest.call("guarded", false), 7);
      let trapped = false;
      try {
        guest.call("guarded", true);
      } catch (error) {
        trapped = error instanceof WebAssembly.RuntimeError;
      }
      equal(trapped, true);
      equal(guest.call("guarded", false), 7);
    },
    { prelude: "none" },
  );
});

Deno.test("nested typed quotes carry explicit lifts through each stage", async () => {
  await compileAndRun(
    `const make = func (value: U32) => return @code.quote (@code.quote (@u32.add (@code.lift (@code.lift value)) 2))
const outer = make 40
const inner = @code.run outer
entry const answer = func () => return @code.emit inner
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "none" },
  );
});

Deno.test("imported typed generators preserve hygiene retained edits failures and restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-staging-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/generator.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url);
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  };
  const library =
    "const make = func (step: U32) => return @code.quote (func (value: U32) => return @u32.add value (@code.lift step))\n";
  const source = `import {make} from "./generator"
const generated = make 2
entry const answer = func (value: U32) => return (@code.emit generated) value
`;
  const compiler = await createZigProjectCompiler(options);
  const observe = async (bytes: Uint8Array<ArrayBuffer>, expected: number) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        if (asynchronous) {
          equal(await guest.callAsync("answer", 40), expected);
        } else {
          equal(guest.call("answer", 40), expected);
        }
      } finally {
        guest.dispose();
      }
    }
  };
  try {
    const sources = { [entry]: source, [dependency]: library };
    const first = await compiler.build({ sources });
    assert(first.success, JSON.stringify(first));
    await observe(first.bytes, 42);
    const retained = await compiler.build({ sources });
    assert(retained.success, JSON.stringify(retained));
    assert.deepEqual(retained.bytes, first.bytes);
    const changed = await compiler.build({
      sources: {
        ...sources,
        [dependency]: library.replace(
          "@code.lift step",
          "@code.lift (@u32.add step 1)",
        ),
      },
    });
    assert(changed.success, JSON.stringify(changed));
    await observe(changed.bytes, 43);
    const failed = await compiler.build({
      sources: {
        ...sources,
        [dependency]: library.replace("@code.lift step", "step"),
      },
    });
    assert(!failed.success);
    assert(
      failed.diagnostics.some((diagnostic) =>
        diagnostic.code === "stage_unavailable"
      ),
      JSON.stringify(failed),
    );
    const recovered = await compiler.build({ sources });
    assert(recovered.success, JSON.stringify(recovered));
    assert.deepEqual(recovered.bytes, first.bytes);
    await observe(recovered.bytes, 42);
    const restarted = await createZigProjectCompiler(options);
    try {
      const resumed = await restarted.build({ sources });
      assert(resumed.success, JSON.stringify(resumed));
      assert.deepEqual(resumed.bytes, first.bytes);
      await observe(resumed.bytes, 42);
    } finally {
      await restarted.dispose();
    }
  } finally {
    await compiler.dispose();
    await removeFixture(directory);
  }
});

Deno.test("imported staging tracks fixed-type inputs and future bodies across independent expansions", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-staging-inputs-" });
  const entry = `${directory}/main.blot`;
  const generator = `${directory}/generator.blot`;
  const inputs = `${directory}/inputs.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const cached = { ...options, cacheDirectory: `${directory}/cache` };
  const library =
    `const make = func (step: U32) => return @code.quote (func (value: U32) => return do:
  let step = @u32.add value (@code.lift step)
  let value = 1
  break @u32.add step value)
`;
  const source = `import {make} from "./generator"
import {left, right} from "./inputs"
const first = make left
const second = make right
entry const same: Bool = @descriptor.same (@code.describe first).result (@code.describe second).result
entry const answer = func (argument: U32) => return do:
  let value = 100
  let step = 1000
  let a = (@code.emit first) argument
  let b = (@code.emit second) argument
  let again = (@code.emit first) argument
  break @u32.add (@u32.add value step) (@u32.add a (@u32.add b again))
`;
  const compiler = await createZigProjectCompiler(cached);
  const observe = async (bytes: Uint8Array<ArrayBuffer>, expected: number) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        equal(guest.read("same"), true);
        if (asynchronous) equal(await guest.callAsync("answer", 40), expected);
        else equal(guest.call("answer", 40), expected);
      } finally {
        guest.dispose();
      }
    }
  };
  const versions = [
    { left: 2, library, expected: 1231 },
    { left: 2, library, expected: 1231 },
    { left: 5, library, expected: 1237 },
    {
      left: 5,
      library: library.replace("break @u32.add", "break @u32.sub"),
      expected: 1231,
    },
    {
      left: 5,
      library: library.replace(
        "@code.lift step",
        "@code.lift (if @u32.eq step 4 then @u32.div step 0 else step)",
      ),
      expected: null,
    },
    { left: 2, library, expected: 1231 },
  ];
  let accepted: Uint8Array<ArrayBuffer> | undefined;
  try {
    for (const [index, version] of versions.entries()) {
      const sources = {
        [entry]: source,
        [generator]: version.library,
        [inputs]: `const left: U32 = ${version.left}\nconst right: U32 = 4\n`,
      };
      const result = await compiler.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert.equal(result.success, expected.success);
        if (version.expected === null) {
          assert(!result.success && !expected.success);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          assert(accepted);
          await observe(accepted, 1231);
          continue;
        }
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        if (index === 1) {
          assert.equal(result.stats.attemptStats.reused_output, true);
          assert.equal(result.stats.nativeWorkSteps, 0);
        } else {
          assert.equal(
            result.stats.nativeWorkSteps,
            expected.stats.nativeWorkSteps,
          );
        }
        await observe(result.bytes, version.expected);
        accepted = result.bytes;
        if (index === 2 || index === 3 || index === versions.length - 1) {
          const restarted = await createZigProjectCompiler(cached);
          try {
            const resumed = await restarted.build({ sources });
            assert(resumed.success, JSON.stringify(resumed));
            assert.equal(resumed.stats.restartCacheLoaded, true);
            assert.deepEqual(resumed.bytes, expected.bytes);
            assert(
              resumed.stats.nativeWorkSteps <= expected.stats.nativeWorkSteps,
            );
            await observe(resumed.bytes, version.expected);
          } finally {
            await restarted.dispose();
          }
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await removeFixture(directory);
  }
});

for (
  const helper of [
    "monomorphic",
    "generic",
    "producer-data",
    "locals",
    "nominal",
    "nominal-read",
    "nominal-read-development",
    "collections",
    "collections-development",
  ]
) {
  Deno.test(`imported generators own exact named future helper bodies (${helper})`, async () => {
    const generic = helper === "generic";
    const collections = helper.startsWith("collections");
    const nominalRead = helper.startsWith("nominal-read");
    let codegenTier: "development" | "optimized" = "optimized";
    if (helper.endsWith("-development")) codegenTier = "development";
    const directory = await Deno.makeTempDir({ prefix: "blot-staging-named-" });
    const entry = `${directory}/main.blot`;
    const producer = `${directory}/generator.blot`;
    const options = {
      executable: Deno.args[0] ??
        new URL("../zig-out/bin/blotc", import.meta.url),
      entry,
      prelude: null,
      codegenTier,
    };
    const cached = { ...options, cacheDirectory: `${directory}/cache` };
    let library = `const helper = func (value: U32) => return @u32.add value 2
const twice = func (value: U32) => return helper (helper value)
const make = func (value: U32) => return @code.quote (twice (@code.lift value))
const callable = @code.quote (func (value: U32) => return twice value)
`;
    let source = `import {make, callable} from "./generator"
const generated = make 38
entry const checked: U32 = @code.run generated
entry const run = func (seed: U32) => return do:
  let value = 100
  let first = @code.emit generated
  let second = @code.emit generated
  break @u32.add value (@u32.add first (@u32.add second ((@code.emit callable) seed)))
`;
    if (generic) {
      library = `const identity = func value => return value
const pair = func value => return (identity value, identity value)
const choose = func (flag: Bool) => return func left => return func right => return if flag then left else right
const floating = @code.quote (choose true (identity 1.5) (identity 2.5))
` +
        library.replace(
          "helper (helper value)",
          "helper (helper (@product.get (pair value) 0))",
        );
      source =
        source.replace("{make, callable}", "{make, callable, floating}") +
        "entry const fraction = @code.run floating\n";
    }
    if (helper === "producer-data") {
      library = "const configuration = {step: @u32.add 1 1}\n" +
        library.replace(
          "@u32.add value 2",
          "@u32.add value configuration.step",
        );
    }
    if (helper === "locals") {
      library = library.replace(
        "=> return @u32.add value 2",
        "=> return do:\n  let incremented = @u32.add value 2\n  let value = incremented\n  break value",
      );
    }
    if (helper === "nominal") {
      library = `type Packet a is data = $Packet {item: a}
const helper = func (value: U32) => return @u32.add value 2
const twice = func (value: U32) => return $Packet {item: helper (helper value)}
const make = func (value: U32) => return @code.quote (twice (@code.lift value)).item
const callable = @code.quote (func (value: U32) => return (twice value).item)
`;
    }
    if (nominalRead) {
      library = `type Packet a is data = $Packet {item: a, shadow: a}
const helper = func (value: U32) => return @u32.add value 2
const read = func (packet: Packet a) => return packet.item
const twice = func (value: U32) => return read ($Packet {item: helper (helper value), shadow: 0})
const make = func (value: U32) => return @code.quote (twice (@code.lift value))
const callable = @code.quote (func (value: U32) => return twice value)
const float_callable = @code.quote (func (value: F32) => return read ($Packet {shadow: 9.5, item: value}))
`;
      source =
        source.replace("{make, callable}", "{make, callable, float_callable}") +
        "entry const fraction = func (value: F32) => return (@code.emit float_callable) value\n";
    }
    if (collections) {
      library = library.replace(
        "=> return @u32.add value 2",
        `=> return do:
  let items = @array.concat #[0] #[2]
  let window = @array.slice items 0 2
  let restored = @array.from_list (@list.from_array window)
  break @u32.add value (@array.get restored (@u32.sub (@list.length (@list.from_array window)) 1))`,
      );
    }
    const compiler = await createZigProjectCompiler(cached);
    const observe = async (
      bytes: Uint8Array<ArrayBuffer>,
      checked: number,
      expected: number,
    ) => {
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(bytes, { asynchronous });
        try {
          assert.equal(guest.read("checked"), checked);
          if (generic) assert.equal(guest.read("fraction"), 1.5);
          if (nominalRead) {
            if (asynchronous) {
              assert.equal(await guest.callAsync("fraction", 1.5), 1.5);
            } else assert.equal(guest.call("fraction", 1.5), 1.5);
          }
          if (asynchronous) {
            assert.equal(await guest.callAsync("run", 10), expected);
          } else assert.equal(guest.call("run", 10), expected);
        } finally {
          guest.dispose();
        }
      }
    };
    try {
      for (const step of [2, 3]) {
        let revision = library.replace("value 2", `value ${step}`);
        let expression = `@u32.add value ${step}`;
        if (helper === "producer-data") {
          revision = library.replace("@u32.add 1 1", `@u32.add 1 ${step - 1}`);
          expression = "@u32.add value configuration.step";
        }
        if (collections) {
          revision = library.replace("#[2]", `#[${step}]`);
          expression =
            "@u32.add value (@array.get restored (@u32.sub (@list.length (@list.from_array window)) 1))";
        }
        const sources = {
          [entry]: source,
          [producer]: revision,
        };
        const fresh = await createZigProjectCompiler({
          ...options,
          cacheDirectory: false,
        });
        try {
          const expected = await fresh.build({ sources });
          assert(expected.success, JSON.stringify(expected));
          const result = await compiler.build({ sources });
          assert(result.success, JSON.stringify(result));
          assert.deepEqual(result.bytes, expected.bytes);
          await observe(result.bytes, 38 + 2 * step, 186 + 6 * step);
          const unchanged = await compiler.build({ sources });
          assert(unchanged.success, JSON.stringify(unchanged));
          assert.deepEqual(unchanged.bytes, result.bytes);
          assert.equal(unchanged.stats.attemptStats.reused_output, true);
          assert.equal(unchanged.stats.nativeWorkSteps, 0);
          let failure = "@u32.div value 0";
          if (collections) failure = "@array.get restored 4294967295";
          const failed = await compiler.build({
            sources: {
              ...sources,
              [producer]: sources[producer].replace(
                expression,
                failure,
              ),
            },
          });
          assert(!failed.success, JSON.stringify(failed));
          if (collections) {
            assert(
              failed.diagnostics.some((diagnostic) =>
                diagnostic.code === "array_bounds"
              ),
              JSON.stringify(failed),
            );
          }
          await observe(result.bytes, 38 + 2 * step, 186 + 6 * step);
          const recovered = await compiler.build({ sources });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, expected.bytes);
          const restarted = await createZigProjectCompiler(cached);
          try {
            const resumed = await restarted.build({ sources });
            assert(resumed.success, JSON.stringify(resumed));
            assert.deepEqual(resumed.bytes, expected.bytes);
            await observe(resumed.bytes, 38 + 2 * step, 186 + 6 * step);
            console.log(JSON.stringify({
              kind: "staging_named_work",
              step,
              fresh: expected.stats.nativeWorkSteps,
              retained: result.stats.nativeWorkSteps,
              unchanged: unchanged.stats.nativeWorkSteps,
              recovery: recovered.stats.nativeWorkSteps,
              restart: resumed.stats.nativeWorkSteps,
            }));
          } finally {
            await restarted.dispose();
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await removeFixture(directory);
    }
  });
}

Deno.test("typed generators track exact host asset bytes through edits failures and restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-staging-asset-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/generator.blot`;
  const source = `import * as config from "./config.json"
import {make} from "./generator"
const generated = make (config.value).step
entry const answer = func (value: U32) => return (@code.emit generated) value
`;
  const library =
    `const make = func (step: U32) => return @code.quote (func (value: U32) => return @u32.add value (@code.lift step))\n`;
  const changed = library.replace(
    "@code.lift step",
    "@code.lift (@u32.add step 1)",
  );
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
    nativeAssets: {
      imports: [{
        module: "./config.json",
        path: "./config.json",
        kind: "json" as const,
      }],
    },
  };
  const cached = { ...options, cacheDirectory: `${directory}/cache` };
  const compiler = await createZigProjectCompiler(cached);
  const edits: [string, string, number | null][] = [
    ['{"step":2}', library, 42],
    ['{"step":3}', library, 43],
    ['{"step":3}', changed, 44],
    ["{", changed, null],
    [
      '{"step":3}',
      changed.replace("@code.lift (@u32.add step 1)", "step"),
      null,
    ],
    ['{"step":false}', library, null],
    ['{"step":2}', library, 42],
  ];
  let accepted: Uint8Array<ArrayBuffer> | undefined;
  let acceptedAnswer = 0;
  const observe = async (bytes: Uint8Array<ArrayBuffer>, answer: number) => {
    const guest = await instantiateGuest(bytes);
    try {
      assert.equal(guest.call("answer", 40), answer);
    } finally {
      guest.dispose();
    }
  };
  try {
    for (const [asset, generator, answer] of edits) {
      const inputs = {
        sources: { [entry]: source, [producer]: generator },
        assetSources: { "./config.json": asset },
      };
      const fresh = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const expected = await fresh.build(inputs);
        const actual = await compiler.build(inputs);
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert(!actual.success && !expected.success);
          assert.equal(answer, null);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          assert(accepted);
          await observe(accepted, acceptedAnswer);
          continue;
        }
        assert.notEqual(answer, null);
        assert.deepEqual(actual.bytes, expected.bytes);
        assert.equal(
          actual.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        await observe(actual.bytes, answer!);
        accepted = actual.bytes;
        acceptedAnswer = answer!;
        const unchanged = await compiler.build(inputs);
        assert(unchanged.success, JSON.stringify(unchanged));
        assert.deepEqual(unchanged.bytes, accepted);
        assert.equal(unchanged.stats.nativeWorkSteps, 0);
        assert.equal(unchanged.stats.attemptStats.reused_output, true);
        const restarted = await createZigProjectCompiler(cached);
        try {
          const resumed = await restarted.build(inputs);
          assert(resumed.success, JSON.stringify(resumed));
          assert.deepEqual(resumed.bytes, expected.bytes);
          await observe(resumed.bytes, answer!);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await removeFixture(directory);
  }
});

Deno.test("imported typed generators lift nominal payloads through edits and restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-staging-nominal-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/generator.blot`;
  const source = `import {generated, empty, description} from "./generator"
entry const answer = func () => return @u32.add (@code.emit generated) (@code.emit empty)
entry const same = @descriptor.same description.result (@code.describe generated).result
`;
  const library = `type Packet a is data = $Packet {item: a}
type Option a is data = $Absent | $Present a
const make = func (value: Option (Packet U32)) => return @code.quote (case @code.lift value of
  $Absent => 0
  $Present ($Packet item) => item)
const generated = make ($Present ($Packet {item: 42}))
const empty = make $Absent
const description = @code.describe generated
`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const cached = { ...options, cacheDirectory: `${directory}/cache` };
  const retained = await createZigProjectCompiler(cached);
  const observe = async (bytes: Uint8Array<ArrayBuffer>, expected: number) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        assert.equal(guest.read("same"), true);
        if (asynchronous) {
          assert.equal(await guest.callAsync("answer", null), expected);
        } else assert.equal(guest.call("answer", null), expected);
      } finally {
        guest.dispose();
      }
    }
  };
  try {
    for (const value of [42, 43, 42]) {
      const sources = {
        [entry]: source,
        [producer]: library.replace("item: 42", `item: ${value}`),
      };
      const fresh = await createZigProjectCompiler({
        ...options,
        cacheDirectory: false,
      });
      try {
        const expected = await fresh.build({ sources });
        assert(expected.success, JSON.stringify(expected));
        const result = await retained.build({ sources });
        assert(result.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        assert.equal(
          result.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        await observe(result.bytes, value);
        const failed = await retained.build({
          sources: {
            ...sources,
            [producer]: sources[producer].replace(
              `item: ${value}`,
              "item: true",
            ),
          },
        });
        assert(!failed.success, JSON.stringify(failed));
        await observe(result.bytes, value);
        const restored = await retained.build({ sources });
        assert(restored.success, JSON.stringify(restored));
        assert.deepEqual(restored.bytes, expected.bytes);
        const restarted = await createZigProjectCompiler(cached);
        try {
          const resumed = await restarted.build({ sources });
          assert(resumed.success, JSON.stringify(resumed));
          assert.deepEqual(resumed.bytes, expected.bytes);
          await observe(resumed.bytes, value);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await removeFixture(directory);
  }
});

Deno.test("nominal lifts reject hidden callable payloads before publication", async () => {
  await compileExpectedFailure(
    `type Hidden is data = $Hidden (Unit -> U32)
const generated = @code.quote (@code.lift ($Hidden (func () => return 42)))
entry const answer = func () => return case @code.emit generated of
  $Hidden callback => callback ()
`,
    "cross_stage_authority",
    undefined,
    { prelude: "none" },
  );
});

Deno.test("public nominal descriptors retain field owners across imports edits and restart", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-nominal-fields-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  const archive = `${directory}/producer.blotdep`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const source = `import {future, choice} from "./producer"
const fields = @descriptor.fields (@code.describe future).result
const shared = @descriptor.fields (@code.describe choice).result
entry const same = @descriptor.same fields.item (@code.describe (@code.quote 1)).result
entry const common = @descriptor.same shared.value (@code.describe (@code.quote true)).result
entry const answer = func () => return (@code.emit future).item
`;
  const library = `type Packet a is data = $Packet {item: a, flag: Bool}
type Choice a is data = $Left {value: a, left: U32} | $Right {value: a, right: Bool}
const future = @code.quote $Packet {item: 42, flag: true}
const choice = @code.quote $Left {value: true, left: 1}
`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = { executable, entry, prelude: null, codegenTier };
      const cached = {
        ...options,
        cacheDirectory: `${directory}/cache-${codegenTier}`,
      };
      const retained = await createZigProjectCompiler(cached);
      const observe = async (bytes: Uint8Array<ArrayBuffer>, value: number) => {
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(bytes, { asynchronous });
          try {
            assert.equal(guest.read("same"), value === 42);
            assert.equal(guest.read("common"), true);
            if (asynchronous) {
              assert.equal(await guest.callAsync("answer", null), value);
            } else assert.equal(guest.call("answer", null), value);
          } finally {
            guest.dispose();
          }
        }
      };
      try {
        for (const value of [42, 1.5, 42]) {
          const sources = {
            [entry]: source,
            [producer]: library.replace("item: 42", `item: ${value}`),
          };
          await Deno.writeTextFile(entry, source);
          await Deno.writeTextFile(producer, sources[producer]);
          const fresh = await createZigProjectCompiler({
            ...options,
            cacheDirectory: false,
          });
          try {
            const expected = await fresh.build({ sources });
            assert(expected.success, JSON.stringify(expected));
            const built = await retained.build({ sources });
            assert(built.success, JSON.stringify(built));
            assert.deepEqual(built.bytes, expected.bytes);
            assert.equal(
              built.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            await observe(built.bytes, value);
            const failed = await retained.build({
              sources: {
                ...sources,
                [entry]: source.replace("shared.value", "shared.left"),
              },
            });
            assert(!failed.success, JSON.stringify(failed));
            await observe(built.bytes, value);
            const restored = await retained.build({ sources });
            assert(restored.success, JSON.stringify(restored));
            assert.deepEqual(restored.bytes, expected.bytes);
            const packed = await new Deno.Command(executable, {
              args: ["dependencies", entry, archive, "--prelude", "none"],
              stdout: "piped",
              stderr: "piped",
            }).output();
            assert(packed.success, new TextDecoder().decode(packed.stderr));
            for (const dependencies of [undefined, archive]) {
              const restarted = await createZigProjectCompiler({
                ...cached,
                dependencies,
              });
              try {
                const resumed = await restarted.build({ sources });
                assert(resumed.success, JSON.stringify(resumed));
                assert.deepEqual(resumed.bytes, expected.bytes);
                await observe(resumed.bytes, value);
              } finally {
                await restarted.dispose();
              }
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await removeFixture(directory);
  }
});
