import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

type Compiler = Awaited<ReturnType<typeof createSourceCompiler>>;

function preludeTest(
  name: string,
  test: (compiler: Compiler) => void | Promise<void>,
) {
  Deno.test(name, async () => {
    const compiler = await createSourceCompiler();
    try {
      await test(compiler);
    } finally {
      compiler.dispose();
    }
  });
}

async function instantiate(compiler: Compiler, source: string) {
  const artifact = compiler.compile(source);
  ok(
    WebAssembly.validate(artifact.bytes),
    "the Bend backend must emit valid Wasm",
  );
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  return { ...artifact, exports: instance.exports };
}

function call(
  exports: WebAssembly.Exports,
  name: string,
  argument = 0,
): number {
  const fn = exports[name];
  ok(typeof fn === "function", `${name} must be an exported function`);
  return fn(argument) as number;
}

function rejects(compiler: Compiler, source: string, code: string) {
  throws(() => compiler.compile(source), (error) => {
    ok(error instanceof SourceError, String(error));
    equal(error.code, code, error.message);
    return true;
  });
}

preludeTest(
  "generic prelude example executes in const evaluation and Wasm",
  async (compiler) => {
    const source = await Deno.readTextFile(
      new URL("../examples/prelude.blot", import.meta.url),
    );
    const { analysis, exports } = await instantiate(compiler, source);
    ok(exports.const_answer instanceof WebAssembly.Global);
    equal(exports.const_answer.value, 42);
    equal(
      analysis.constants.find((constant) => constant.name === "const_answer")
        ?.value,
      {
        $: "U32Value",
        value: 42,
      },
    );
    equal(call(exports, "answer"), 42);
    equal(call(exports, "generic_identity"), 42);
    equal(call(exports, "named_operator"), 42);
    equal(call(exports, "inspect", 1), 42);
    equal(call(exports, "inspect", 0), 0);
    equal(call(exports, "recover", 1), 42);
    equal(call(exports, "recover", 0), 0);
    equal(Object.keys(exports).sort(), [
      "answer",
      "const_answer",
      "generic_identity",
      "inspect",
      "named_operator",
      "recover",
    ]);
  },
);

preludeTest(
  "source closures retain captured values after their creator returns",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
fn make_adder value => fn other => value + other
const add_forty = make_adder 40
export const expected = add_forty 2
export fn answer () => do:
  let value = 999
  let increment = make_adder 1
  let result = compose increment add_forty
  return result 1
`,
    );
    equal((exports.expected as WebAssembly.Global).value, 42);
    equal(call(exports, "answer"), 42);
  },
);

preludeTest(
  "arena growth and reset preserve nested static algebraic closures",
  async (compiler) => {
    const allocations = Array.from(
      { length: 64 },
      (_, index) => `  use Some ${index}`,
    ).join("\n");
    const { exports } = await instantiate(
      compiler,
      `
const stored = Some (U32.add 40)
fn churn (remaining: U32) => do:
  if remaining == 0:
    return ()
${allocations}
  use churn (remaining - 1)
export fn answer () => do:
  use churn 256
  return case stored:
    Some add_forty => add_forty 2
    Nothing => 0
`,
    );
    // Each call crosses a Wasm page; together they exceed the private arena.
    for (let iteration = 0; iteration < 140; iteration++) {
      equal(call(exports, "answer"), 42);
    }
  },
);

preludeTest(
  "source global functions and pure local lets instantiate independently",
  async (compiler) => {
    const { analysis, exports } = await instantiate(
      compiler,
      `
fn same value => value
export fn answer () => do:
  let local_same = fn value => value
  let enabled = same (local_same True)
  if enabled:
    return local_same (same 42)
  return 0
`,
    );
    equal(call(exports, "answer"), 42);
    const same = analysis.functions.find((fn) => fn.name === "same");
    ok(same);
    equal(same.variables.length, 1);
    equal(same.parameter.$, "VariableTy");
    equal(same.parameter, same.result);
  },
);

preludeTest(
  "Maybe and Result preserve nested alternatives and payload types",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
fn inspect candidate => case candidate:
  Ok (Some value) => value
  Ok Nothing => 1
  Err True => 2
  Err False => 3
export fn some () => inspect (Ok (Some 42))
export fn nothing () => inspect (Ok Nothing)
export fn failed () => inspect (Err False)
export fn mapped_error () => inspect (Result.map_error Bool.not (Err False))
export fn bound () => Maybe.unwrap_or 0 (Maybe.bind (Some 41) (fn value => Some (value + 1)))
`,
    );
    equal(call(exports, "some"), 42);
    equal(call(exports, "nothing"), 1);
    equal(call(exports, "failed"), 3);
    equal(call(exports, "mapped_error"), 2);
    equal(call(exports, "bound"), 42);
  },
);

preludeTest(
  "concrete data and function annotations cross the source FFI recursively",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
const candidate: Maybe (Result U32 Bool) = Some (Ok 42)
fn apply (transform: U32 -> U32) => transform 42
export fn answer () => apply (fn value => value)
export fn nested () => case candidate:
  Some (Ok value) => value
  Some (Err _) => 0
  Nothing => 0
`,
    );
    equal(call(exports, "answer"), 42);
    equal(call(exports, "nested"), 42);
  },
);

preludeTest(
  "operators use source fixities and backtick functions",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
infixr 60 (++) = combine
infixl 70 \`difference\`
fn combine left => fn right => left * 10 + right
fn difference left => fn right => left - right
fn plus left => fn right => left + right
export fn precedence () => 2 + 4 * 10
export fn right_association () => 1 ++ 2 ++ 3
export fn explicit_named () => 20 \`difference\` 3 \`difference\` 2
export fn default_named () => 20 \`plus\` 22 * 2
export fn applied_named () => identity 20 \`plus\` identity 22
`,
    );
    equal(call(exports, "precedence"), 42);
    equal(call(exports, "right_association"), 33);
    equal(call(exports, "explicit_named"), 15);
    equal(call(exports, "default_named"), 84);
    equal(call(exports, "applied_named"), 42);
  },
);

preludeTest(
  "ambiguous non-associative operator chains require parentheses",
  (compiler) => {
    rejects(
      compiler,
      "export fn invalid () => 1 < 2 < 3\n",
      "operator_associativity",
    );
    rejects(compiler, "export fn invalid () => 1 ^ 2\n", "unknown_operator");
  },
);

preludeTest(
  "root shadowing does not alter bindings inside prelude definitions",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
fn Bool.not value => value
export fn local_not () => Bool.not True
export fn prelude_not () => U32.ne 7 7
`,
    );
    equal(call(exports, "local_not"), 1);
    equal(call(exports, "prelude_not"), 0);
  },
);

preludeTest(
  "same-named local data remain nominally distinct from prelude data",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
data Maybe a = Some a | Nothing
export fn local_answer () => case Some 42:
  Some value => value
  Nothing => 0
export fn prelude_answer () => Maybe.unwrap_or 0 (Maybe.pure 42)
`,
    );
    equal(call(exports, "local_answer"), 42);
    equal(call(exports, "prelude_answer"), 42);
    rejects(
      compiler,
      `
data Maybe a = Some a | Nothing
export fn invalid () => case Maybe.pure 42:
  Some value => value
  Nothing => 0
`,
      "type_mismatch",
    );
  },
);

preludeTest(
  "constructor arity, payload types, and type application arity are checked",
  (compiler) => {
    rejects(
      compiler,
      `
export fn invalid () => case Some 42:
  Some => 0
  Nothing => 0
`,
      "constructor_arity",
    );
    rejects(
      compiler,
      `
export fn invalid () => case Nothing:
  Some _ => 0
  Nothing value => value
`,
      "constructor_arity",
    );
    rejects(
      compiler,
      "const invalid: Maybe U32 = Some True\n",
      "type_mismatch",
    );
    rejects(compiler, "const invalid: Maybe = Nothing\n", "type_arity");
  },
);

preludeTest(
  "pattern coverage checks nested constructors and finite Boolean payloads",
  (compiler) => {
    rejects(
      compiler,
      `
fn invalid candidate => case candidate:
  Some (Some value) => value
  Nothing => 0
`,
      "non_exhaustive_match",
    );
    rejects(
      compiler,
      `
fn invalid candidate => case candidate:
  Some True => 1
  Nothing => 0
`,
      "non_exhaustive_match",
    );
  },
);

preludeTest(
  "guarded let requires its fallback to exit the enclosing block",
  (compiler) => {
    rejects(
      compiler,
      `
export fn invalid () => do:
  let Some(value) = Some 42 else:
    0
  return value
`,
      "guard_fallthrough",
    );
    rejects(
      compiler,
      `
export fn invalid () => do:
  let Some(value) = Some 42 else:
    do:
      return 0
  return value
`,
      "guard_fallthrough",
    );
    rejects(
      compiler,
      `
export fn invalid () => do:
  let Some(value) = Some 42
  return value
`,
      "non_exhaustive_match",
    );
  },
);

preludeTest(
  "self-application fails the occurs check instead of inventing recursive types",
  (compiler) => {
    rejects(compiler, "fn invalid value => value value\n", "infinite_type");
  },
);
