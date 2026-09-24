import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

Deno.test("top-level let initializers run at instantiation, including unused values", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const source = 'let failure = @panic "startup"\n';
    const artifact = reference.compile(source, { const_steps: 1n });
    equal(await native.compile(source, { const_steps: 1n }), artifact);
    const module = new WebAssembly.Module(artifact.bytes);
    throws(() => new WebAssembly.Instance(module), WebAssembly.RuntimeError);
    throws(
      () => reference.compile('const failure = @panic "compile"\n'),
      (error) => error instanceof SourceError && error.code === "const_panic",
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("runtime initialization orders dependencies and runs once per instance", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 8 });
  try {
    const source = `
let answer = @u32.add base 2
let fraction = @f32.add 1.25 0.5
let base = @u32.add 20 20
const read = fn () => answer
const read_fraction = fn () => fraction
`;
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const module = new WebAssembly.Module(artifact.bytes);
    const first = new WebAssembly.Instance(module).exports;
    const second = new WebAssembly.Instance(module).exports;
    ok(first.answer instanceof WebAssembly.Global);
    ok(second.answer instanceof WebAssembly.Global);
    ok(typeof first.read === "function");
    ok(typeof first.read_fraction === "function");
    equal(first.answer.value, 42);
    equal(first.read(), 42);
    equal(first.read_fraction(), 1.75);
    first.answer.value = 7;
    equal(first.read(), 7);
    equal(first.read(), 7);
    equal(second.answer.value, 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("runtime arrays and factory closures survive subsequent call arena resets", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 8 });
  try {
    const source = `
const factory = fn captured => fn value => @u32.add captured value
let values = @array.fill 4 42
let add = factory 40
const disturb = fn () => @array.get (@array.fill 100 0) 0
const read = fn () => @array.get values 3
const retained = fn () => values
const answer = fn () => add 2
`;
    const artifact = reference.compile(source, { const_steps: 1n });
    equal(await native.compile(source, { const_steps: 1n }), artifact);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    ok(typeof exports.disturb === "function");
    ok(typeof exports.read === "function");
    ok(typeof exports.answer === "function");
    const reset = exports["blot:reset"];
    ok(typeof reset === "function");
    for (let iteration = 0; iteration < 3; iteration++) {
      equal(exports.disturb(), 0);
      reset();
      equal(exports.read(), 42);
      equal(exports.answer(), 42);
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("runtime startup and globals coexist with host callback imports", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const source = `
let base = @u32.add 20 20
const answer = fn (callback: U32 -> U32 ! {Foreign}) => do:
  use extra <- callback 1
  return @u32.add base extra
`;
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes), {
        "blot:host/1": {
          call_u32_u32: (_token: unknown, value: number) => value + 1,
        },
      }).exports;
    ok(typeof exports.answer === "function");
    equal(exports.answer({}), 42);
    equal(exports.answer({}), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("const evaluation cannot read runtime values or let functions", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const source of [
        "let runtime = 42\nconst copied = runtime\n",
        "let runtime = fn () => 42\nconst copied = runtime ()\n",
        "let runtime = fn () => 42\nconst copied = runtime\n",
        "let runtime = 42\nconst read = fn () => runtime\nconst copied = read ()\n",
      ]
    ) {
      throws(
        () => compiler.compile(source),
        (error) =>
          error instanceof SourceError &&
          error.code === "const_runtime_dependency",
      );
    }
    throws(
      () => compiler.compile("let first = second\nlet second = first\n"),
      (error) =>
        error instanceof SourceError && error.code === "initialization_cycle",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("runtime initialization requires all effects to have providers", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    throws(
      () =>
        compiler.compile(`
effect ask: Unit -> U32
let value = do:
  use answer <- ask ()
  return answer
`),
      (error) =>
        error instanceof SourceError && error.code === "initializer_effect",
    );
  } finally {
    compiler.dispose();
  }
});

for (const backend of ["native", "javascript"] as const) {
  Deno.test(`${backend} sessions relink const-to-let and runtime initializer edits`, async () => {
    const session = backend === "native"
      ? await createNativeIncrementalCompiler({ prelude: "none" })
      : await createIncrementalCompiler({ prelude: "none" });
    const reference = await createSourceCompiler({ prelude: "none" });
    try {
      const revisions: [string, number][] = [
        ["const value = 40\nconst read = fn () => value\n", 40],
        ["let value = 40\nconst read = fn () => value\n", 40],
        ["let value = @u32.add 40 2\nconst read = fn () => value\n", 42],
        ["let value = @f32.add 1.25 0.5\nconst read = fn () => value\n", 1.75],
        [
          `const factory = fn array => fn index => @array.get array index
let values = @array.fill 4 41
let lookup = factory values
const read = fn () => lookup 3
`,
          41,
        ],
        [
          `const factory = fn array => fn index => @array.get array index
let values = @array.fill 4 42
let lookup = factory values
const read = fn () => lookup 3
`,
          42,
        ],
      ];
      for (const [source, expected] of revisions) {
        const compiled = await session.compile(source);
        const clean = reference.compile(source);
        const actual = new WebAssembly.Instance(
          new WebAssembly.Module(compiled.artifact.bytes),
        ).exports;
        const cleanExports =
          new WebAssembly.Instance(new WebAssembly.Module(clean.bytes)).exports;
        ok(typeof actual.read === "function");
        ok(typeof cleanExports.read === "function");
        equal(actual.read(), expected);
        equal(cleanExports.read(), expected);
        const repeated = await session.compile(source);
        equal(repeated.artifact.bytes, compiled.artifact.bytes);
        equal(repeated.stats.entries_compiled, 0);
      }
    } finally {
      reference.dispose();
      await session.dispose();
    }
  });
}
