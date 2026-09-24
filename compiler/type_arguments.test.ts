import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

Deno.test("type constructors accept one list, tuple, or named record argument", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 8 });
  const source = `
type Listed [head, tail] is data = Listed (head, tail)
type Paired (head, tail) is data = Paired (head, tail)
type Entry { head, tail } is data = Entry { head, tail }
type Nested { pair: (a, b), rest: [c, d] } is data = Nested (a, b, c, d)
const listed = fn (value: Listed [U32, a]) => do:
  let Listed (head, tail) = value
  return head
const paired = fn (value: Paired (U32, a)) => do:
  let Paired (head, tail) = value
  return head
const entry = fn (value: Entry { tail: a, head: U32 }) => do:
  let Entry { head } = value
  return head
const nested = fn (value: Nested { rest: [Bool, Unit], pair: (U32, F32) }) => do:
  let Nested (first, second, third, fourth) = value
  return first
const answer = fn () => @u32.add (listed (Listed (10, True))) (@u32.add (paired (Paired (10, 0.5))) (@u32.add (entry (Entry { tail: (), head: 10 })) (nested (Nested (12, 0.5, True, ())))))
`;
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { answer } =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    ok(typeof answer === "function");
    equal(answer(0), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("explicit curry stages preserve partial constructors through groups", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  const source = `
type Curried a => type [b, c] is data = Curried (a, b, c)
const unpack = fn (value: (Curried U32) [Bool, a]) => do:
  let Curried (first, second, third) = value
  return first
const answer = fn () => unpack (Curried (42, True, ()))
`;
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { answer } =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    ok(typeof answer === "function");
    equal(answer(0), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("free annotation names share declaration scope and generalize across callers", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 8 });
  const source = `
type Pair [left, right] is data = Pair (left, right)
const identity = fn (value: a) -> a => do:
  let copy: a = value
  return (fn (inner: a) -> a => inner) copy
const add = fn (left: a) => fn (right: a) -> a => left + right
const same = fn (value: Pair [a, a]) -> a => do:
  let Pair (first, second) = value
  return identity first
const number = fn () => add (same (Pair (40, 1))) (identity 2)
const fraction = fn () => add (identity 1.25) (identity 0.5)
`;
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { number, fraction } =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    ok(typeof number === "function" && typeof fraction === "function");
    equal(number(0), 42);
    equal(fraction(0), 1.75);
    throws(() =>
      reference.compile(`
const wrong = fn (value: a) => do:
  let incompatible: a = True
  return @u32.add value 1
`), (error) => error instanceof SourceError && error.code === "type_mismatch");
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("effect constructors use structural arguments and explicit currying", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 8 });
  const source = `
type Exchange [input, output] is effect = input -> output
type Curried input => type output is effect = input -> output
type Named { input, output } is effect = input -> output
const list_call: Unit -> Bool ! {Exchange [U32, Bool]} = fn () => do:
  use result <- Exchange [U32, Bool] 1
  return result
const record_call: Unit -> Bool ! {Named { output: Bool, input: U32 }} = fn () => do:
  use result <- Named { input: U32, output: Bool } 1
  return result
const curried_call: Unit -> Bool ! {(Curried U32) Bool} = fn () => do:
  use result <- (Curried U32) Bool 2
  return result
const answer = fn () => do (@effect.provider (Exchange [U32, Bool]) (fn value => True)):
  return do (@effect.provider ((Curried U32) Bool) (fn value => True)):
    return do (@effect.provider (Named { input: U32, output: Bool }) (fn value => True)):
      use first <- list_call ()
      use second <- curried_call ()
      use third <- record_call ()
      if first:
        if second:
          return third
      return False
`;
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { answer } =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    ok(typeof answer === "function");
    equal(answer(0), 1);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("empty argument patterns still require explicit type and effect application", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 8 });
  const source = `
type Token () is data = Token
type Ping () is effect = Unit -> U32
const token = fn (value: Token ()) => value
const answer = fn () => do (@effect.provider (Ping ()) (fn value => 42)):
  let value = token Token
  use result <- Ping () ()
  return result
`;
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { answer } =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    ok(typeof answer === "function");
    equal(answer(0), 42);
    throws(
      () =>
        reference.compile(
          "type Token () is data = Token\nconst bad = fn (value: Token) => value",
        ),
      (error) => error instanceof SourceError && error.code === "type_arity",
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("type argument shapes and unsaturated constructors have useful diagnostics", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    for (
      const [source, code] of [
        [
          "type Pair [a, b] is data = Pair (a, b)\nconst bad = fn (value: Pair U32 Bool) => ()",
          "type_argument",
        ],
        [
          "type Pair [a, b] is data = Pair (a, b)\nconst bad = fn (value: Pair [U32]) => ()",
          "type_argument",
        ],
        [
          "type Pair [a, b] is data = Pair (a, b)\nconst bad = fn (value: Pair (U32, Bool)) => ()",
          "type_argument",
        ],
        [
          "type Pair a => type b is data = Pair (a, b)\nconst bad = fn (value: Pair U32) => ()",
          "type_arity",
        ],
        [
          "type Entry { a, b } is data = Entry (a, b)\nconst bad = fn (value: Entry { a: U32, c: Bool }) => ()",
          "type_argument",
        ],
        [
          "type Entry { a, b } is data = Entry (a, b)\nconst bad = fn (value: Entry { a: U32, a: Bool }) => ()",
          "duplicate_type_field",
        ],
        ["type Pair [a, a] is data = Pair a", "duplicate_type_parameter"],
      ]
    ) {
      throws(
        () => reference.compile(source),
        (error) => error instanceof SourceError && error.code === code,
        source,
      );
      await rejects(
        () => native.compile(source),
        (error) => error instanceof SourceError && error.code === code,
        source,
      );
    }
    throws(
      () => reference.compile("type Pair a b is data = Pair (a, b)"),
      SourceError,
    );
    throws(
      () => reference.compile("export const answer = fn () => 42"),
      SourceError,
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("imported type argument patterns retain nominal identity and currying", async () => {
  const { loadSourceProject } = await import("./source_project.ts");
  const modules = new Map([
    [
      "file:///type-arguments/library.blot",
      `
type Entry { head, tail } is data = Entry { head, tail }
type Pair a => type b is data = Pair (a, b)
const first = fn (entry: Entry { head: a, tail: b }) -> a => do:
  let Entry { head } = entry
  return head
`,
    ],
    [
      "file:///type-arguments/main.blot",
      `
import { Entry as entry_type, Pair as Curried, first } from "./library"
const use_entry = fn (entry: entry_type { head: U32, tail: Bool }) => first entry
const use_pair = fn (pair: (Curried U32) Bool) => do:
  let Curried (first, second) = pair
  return first
const answer = fn () => @u32.add (use_entry (entry_type { tail: True, head: 40 })) (use_pair (Curried (2, True)))
`,
    ],
  ]);
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 8 });
  try {
    const project = await loadSourceProject(
      new URL("file:///type-arguments/main.blot"),
      {
        readSource: (url) => {
          const source = modules.get(url.href);
          if (source === undefined) throw new Error(`missing module ${url}`);
          return Promise.resolve(source);
        },
      },
    );
    const artifact = reference.compile(project);
    equal(await native.compile(project), artifact);
    const { answer } =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    ok(typeof answer === "function");
    equal(answer(0), 42);
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("changing a parameter pattern invalidates dependent native lowering", async () => {
  const { createNativeIncrementalCompiler } = await import(
    "./native_incremental.ts"
  );
  const compiler = await createNativeIncrementalCompiler({
    prelude: "none",
    threads: 8,
  });
  const source = `
type Pair [a, b] is data = Pair (a, b)
const first = fn (pair: Pair [U32, Bool]) => do:
  let Pair (first, second) = pair
  return first
const answer = fn () => first (Pair (42, True))
`;
  try {
    const before = await compiler.compile(source);
    const changed = source.replace("type Pair [a, b]", "type Pair (a, b)");
    await rejects(
      () => compiler.compile(changed),
      (error) => error instanceof SourceError && error.code === "type_argument",
    );
    const after = await compiler.compile(
      changed.replace("Pair [U32, Bool]", "Pair (U32, Bool)"),
    );
    equal(after.artifact.bytes, before.artifact.bytes);
  } finally {
    await compiler.dispose();
  }
});
