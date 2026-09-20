import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import type { CompileOptions } from "./host.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

type Reference = Awaited<ReturnType<typeof createSourceCompiler>>;
type Native = Awaited<ReturnType<typeof createNativeCompiler>>;

function effectTest(
  name: string,
  run: (reference: Reference, native: Native) => Promise<void>,
) {
  Deno.test(name, async () => {
    const reference = await createSourceCompiler({ prelude: "none" });
    const native = await createNativeCompiler({ prelude: "none" });
    try {
      await run(reference, native);
    } finally {
      reference.dispose();
      await native.dispose();
    }
  });
}

async function compile(
  reference: Reference,
  native: Native,
  source: string,
  options: CompileOptions = {},
) {
  const expected = reference.compile(source, options);
  const artifact = await native.compile(source, options);
  equal(artifact, expected, "native and reference results must be lossless");
  ok(WebAssembly.validate(artifact.bytes));
  const module = new WebAssembly.Module(artifact.bytes);
  equal(WebAssembly.Module.imports(module), []);
  const instance = new WebAssembly.Instance(module);
  return { ...artifact, exports: instance.exports };
}

function invoke(exports: WebAssembly.Exports, name: string, argument = 0) {
  const fn = exports[name];
  ok(typeof fn === "function", `missing exported function ${name}`);
  return fn(argument);
}

function constant(exports: WebAssembly.Exports, name: string) {
  const value = exports[name];
  ok(value instanceof WebAssembly.Global, `missing exported constant ${name}`);
  return value.value;
}

async function rejectSource(
  reference: Reference,
  native: Native,
  source: string,
  code?: string,
  options: CompileOptions = {},
) {
  let expected: SourceError | undefined;
  throws(() => reference.compile(source, options), (error) => {
    ok(error instanceof SourceError, String(error));
    if (code !== undefined) equal(error.code, code, error.message);
    expected = error;
    return true;
  });
  await rejects(() => native.compile(source, options), (error) => {
    ok(error instanceof SourceError, String(error));
    ok(expected);
    equal(
      [error.code, error.message, error.start, error.end],
      [expected.code, expected.message, expected.start, expected.end],
    );
    return true;
  });
}

effectTest(
  "source-defined Reader example agrees in const and import-free Wasm",
  async (reference, native) => {
    const source = await Deno.readTextFile(
      new URL("../examples/generic_effects.blot", import.meta.url),
    );
    const { exports } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(constant(exports, "const_answer"), 42);
    equal(invoke(exports, "deferred"), 7);
    equal(constant(exports, "effect_count"), 1);
    equal(constant(exports, "reads_reader"), 1);
    equal(constant(exports, "reads_other"), 0);
  },
);

effectTest(
  "operation-valued providers forward to the enclosing provider",
  async (reference, native) => {
    const source = `
effect Reader.ask: Unit -> U32
const operation = Reader.ask
const base = @effect.provider Reader.ask (fn () => 42)
const forwarding = @effect.provider Reader.ask operation
fn read () => operation ()
export fn answer () => do base:
  return do forwarding:
    return do forwarding:
      return read ()
export const expected = answer ()
`;
    const { exports, analysis } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(constant(exports, "expected"), 42);
    equal(
      analysis.constants.find((entry) => entry.name === "operation")?.value,
      {
        $: "OperationValue",
        identity: {
          $: "TypeId",
          module_name: "main",
          declaration: "Reader.ask",
        },
      },
    );
  },
);

effectTest(
  "handler implementations run outside intervening inner providers",
  async (reference, native) => {
    const source = `
effect Reader.ask: Unit -> U32
effect Computation.answer: Unit -> U32
const base = @effect.provider Reader.ask (fn () => 40)
const interference = @effect.provider Reader.ask (fn () => 999)
fn delegated () => do:
  use value <- Reader.ask ()
  return @u32.add value 2
const computation = @effect.provider Computation.answer delegated
export fn answer () => do base:
  return do computation:
    return do interference:
      return Computation.answer ()
export const expected = answer ()
`;
    const { exports } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(constant(exports, "expected"), 42);
  },
);

effectTest(
  "escaped closures retain latent effects but capture ordinary values",
  async (reference, native) => {
    const source = `
effect Reader.ask: Unit -> U32
fn invoke work => work ()
fn make extra => fn () => do:
  use value <- Reader.ask ()
  return @u32.add value extra
const creation_provider = @effect.provider Reader.ask (fn () => 900)
const delayed = do creation_provider:
  return make 2
fn force () => invoke delayed
const call_provider = @effect.provider Reader.ask (fn () => 40)
export fn answer () => do call_provider:
  return force ()
export const expected = answer ()
const creation_effects = @effect.of make
const invocation_effects = @effect.of force
export const creation_count = @effect.count creation_effects
export const invocation_count = @effect.count invocation_effects
`;
    const { exports } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(constant(exports, "expected"), 42);
    equal(constant(exports, "creation_count"), 0);
    equal(constant(exports, "invocation_count"), 1);
  },
);

effectTest(
  "provider creation and provider invocation have distinct effects",
  async (reference, native) => {
    const source = `
effect Seed.read: Unit -> U32
effect Reader.ask: Unit -> U32
fn build_reader () => do:
  use seed <- Seed.read ()
  return @effect.provider Reader.ask (fn () => seed)
const seed_provider = @effect.provider Seed.read (fn () => 21)
export fn answer () => do seed_provider:
  use selected <- build_reader ()
  return do selected:
    use left <- Reader.ask ()
    use right <- Reader.ask ()
    return @u32.add left right
export const expected = answer ()
const creation = @effect.of build_reader
export const creation_count = @effect.count creation
export const needs_seed = @effect.has creation Seed.read
export const needs_reader = @effect.has creation Reader.ask
`;
    const { exports } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(constant(exports, "expected"), 42);
    equal(constant(exports, "creation_count"), 1);
    equal(constant(exports, "needs_seed"), 1);
    equal(constant(exports, "needs_reader"), 0);
  },
);

effectTest(
  "generic operations support nominal ADTs and F32 arguments/results",
  async (reference, native) => {
    const source = `
data Box = Box U32
effect Boxes.wrap: U32 -> Box
effect Numbers.double: F32 -> F32
const boxes = @effect.provider Boxes.wrap Box
const numbers = @effect.provider Numbers.double (fn value => @f32.mul value 2.0)
export fn answer () => do boxes:
  use wrapped <- Boxes.wrap 42
  return case wrapped of
    Box value => value
export fn doubled (value: F32) => do numbers:
  return Numbers.double value
export const expected_box = answer ()
export const expected_number = doubled 1.25
`;
    const { exports } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(invoke(exports, "doubled", 1.25), 2.5);
    equal(constant(exports, "expected_box"), 42);
    equal(constant(exports, "expected_number"), 2.5);
  },
);

effectTest(
  "handled const computations share one exact evaluation budget",
  async (reference, native) => {
    const source = `
effect Reader.ask: Unit -> U32
const provider = @effect.provider Reader.ask (fn () => 21)
fn twice () => do provider:
  use left <- Reader.ask ()
  use right <- Reader.ask ()
  return @u32.add left right
export const answer = twice ()
export const second = twice ()
`;
    const baseline = reference.analyze(source, { const_steps: 1000n });
    const used = 1000n - baseline.remaining_steps;
    ok(used > 1n);
    const { analysis, exports } = await compile(reference, native, source, {
      const_steps: used,
    });
    equal(analysis.remaining_steps, 0n);
    equal(constant(exports, "answer"), 42);
    equal(constant(exports, "second"), 42);
    await rejectSource(reference, native, source, "const_budget", {
      const_steps: used - 1n,
    });
    await rejectSource(reference, native, source, "const_budget", {
      const_steps: 0n,
    });
  },
);

effectTest(
  "a returned effectful closure is not silently handled or callable unprovided",
  async (reference, native) => {
    const prefix = `
effect Reader.ask: Unit -> U32
const provider = @effect.provider Reader.ask (fn () => 42)
const delayed = do provider:
  return fn () => Reader.ask ()
`;
    await rejectSource(
      reference,
      native,
      `${prefix}\nconst wrong = delayed ()\n`,
    );
    await rejectSource(
      reference,
      native,
      `${prefix}\nexport fn wrong () => delayed ()\n`,
    );
    const valid = `${prefix}
export fn answer () => do provider:
  return delayed ()
`;
    equal(
      invoke((await compile(reference, native, valid)).exports, "answer"),
      42,
    );
  },
);

effectTest(
  "provider bodies short-circuit and generic panic fails only if evaluated",
  async (reference, native) => {
    const source = `
effect Reader.ask: Unit -> U32
fn bad_provider () => @panic "reader should not run"
const provider = @effect.provider Reader.ask bad_provider
export fn answer () => do provider:
  if False:
    use Reader.ask ()
  return 42
export const expected = answer ()
`;
    const { exports } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(constant(exports, "expected"), 42);
    await rejectSource(
      reference,
      native,
      source.replace("if False:", "if True:"),
      "const_panic",
    );
  },
);

effectTest(
  "provider implementations are checked against their declared operation",
  async (reference, native) => {
    for (
      const source of [
        "effect Reader.ask: Unit -> U32\nconst wrong = @effect.provider Reader.ask (fn () => True)\n",
        "effect Reader.ask: Unit -> U32\nconst wrong = @effect.provider Reader.ask (fn (value: U32) => value)\n",
        "effect Reader.ask: Unit -> U32\nconst wrong = Reader.ask 1\n",
      ]
    ) {
      await rejectSource(reference, native, source);
    }
  },
);

effectTest(
  "ordinary const helpers consume opaque nominal effect descriptors",
  async (reference, native) => {
    const source = `
effect Reader.ask: Unit -> U32
effect Other.ask: Unit -> U32
fn read_twice () => do:
  use Reader.ask ()
  return Reader.ask ()
fn count effects => @effect.count effects
fn contains effects => fn operation => @effect.has effects operation
fn same left => fn right => @effect.same left right
const requirements = @effect.of read_twice
const reader = @effect.descriptor Reader.ask
const other = @effect.descriptor Other.ask
export const total = count requirements
export const includes_reader = contains requirements reader
export const includes_other = contains requirements other
export const equal_reader = same reader (@effect.descriptor Reader.ask)
export const unequal_operations = same reader other
export fn answer () => total
`;
    const { analysis, exports } = await compile(reference, native, source);
    equal(constant(exports, "total"), 1);
    equal(constant(exports, "includes_reader"), 1);
    equal(constant(exports, "includes_other"), 0);
    equal(constant(exports, "equal_reader"), 1);
    equal(constant(exports, "unequal_operations"), 0);
    equal(invoke(exports, "answer"), 1);
    equal(
      analysis.constants.find((entry) => entry.name === "requirements")?.value,
      {
        $: "EffectSetValue",
        operations: [{
          $: "TypeId",
          module_name: "main",
          declaration: "Reader.ask",
        }],
      },
    );
  },
);

effectTest(
  "open rows and runtime descriptor use are rejected explicitly",
  async (reference, native) => {
    await rejectSource(
      reference,
      native,
      "fn invoke work => work ()\nconst wrong = @effect.of invoke\n",
      "open_effect_descriptor",
    );
    for (
      const body of [
        "export fn wrong () => @effect.count requirements",
        "fn count effects => @effect.count effects\nexport fn wrong () => count requirements",
        "export const wrong = requirements",
      ]
    ) {
      await rejectSource(
        reference,
        native,
        `effect Reader.ask: Unit -> U32
fn read () => Reader.ask ()
const requirements = @effect.of read
${body}
`,
        "backend_const_only",
      );
    }
  },
);

effectTest(
  "multi-column matching selects complete rows with nested bindings",
  async (reference, native) => {
    const source = `
data Maybe a = Some a | Nothing
fn classify left => fn right => fn enabled => case left, right, enabled of
  Some (Some first), Some second, True => @u32.add first second
  Some (Some _), Some _, False => 1
  Some Nothing, _, _ => 2
  Nothing, _, _ => 3
  _, Nothing, _ => 4
export fn answer () => classify (Some (Some 40)) (Some 2) True
export fn disabled () => classify (Some (Some 40)) (Some 2) False
export fn nested_missing () => classify (Some Nothing) Nothing True
export fn left_missing () => classify Nothing (Some 2) False
export fn right_missing () => classify (Some (Some 40)) Nothing True
export const expected = answer ()
`;
    const { exports } = await compile(reference, native, source);
    equal(invoke(exports, "answer"), 42);
    equal(invoke(exports, "disabled"), 1);
    equal(invoke(exports, "nested_missing"), 2);
    equal(invoke(exports, "left_missing"), 3);
    equal(invoke(exports, "right_missing"), 4);
    equal(constant(exports, "expected"), 42);
  },
);

effectTest(
  "multi-column matching checks combinations, arity, and duplicate names",
  async (reference, native) => {
    for (
      const source of [
        "fn wrong left => fn right => case left, right of\n  True, True => 1\n  False, False => 0\n",
        "fn wrong left => fn right => case left, right of\n  value => value\n",
        "fn wrong left => fn right => case left, right of\n  value, value => value\n",
        "fn wrong value => case value:\n  True => 1\n  False => 0\n",
      ]
    ) {
      await rejectSource(reference, native, source);
    }
  },
);

effectTest(
  "multi-column const scrutinees run once and left-to-right",
  async (reference, native) => {
    const source = `
effect Reader.ask: U32 -> U32
const provider = @effect.provider Reader.ask (fn value => value)
fn choose () => do provider:
  return case Reader.ask 40, Reader.ask 2 of
    first, second => @u32.add first second
export const answer = choose ()
`;
    const baseline = reference.analyze(source, { const_steps: 1000n });
    const used = 1000n - baseline.remaining_steps;
    const { analysis, exports } = await compile(reference, native, source, {
      const_steps: used,
    });
    equal(analysis.remaining_steps, 0n);
    equal(constant(exports, "answer"), 42);
    await rejectSource(reference, native, source, "const_budget", {
      const_steps: used - 1n,
    });
    await rejectSource(
      reference,
      native,
      'const wrong = case @panic "first column", @panic "second column" of\n  _, _ => 42\n',
      "const_panic",
    );
  },
);
