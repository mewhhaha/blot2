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
    equal(call(exports, "increment", 41), 42);
    equal(call(exports, "doubled", 21), 42);
    equal(call(exports, "transform", 20), 42);
    equal(Object.keys(exports).sort(), [
      "add_two",
      "answer",
      "const_answer",
      "doubled",
      "generic_identity",
      "increment",
      "inspect",
      "named_operator",
      "recover",
      "transform",
    ]);
  },
);

preludeTest(
  "source closures retain captured values after their creator returns",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
const make_adder = fn value => fn other => value + other
entry const add_forty = make_adder 40
entry const expected = add_forty 2
entry const answer = fn () => do:
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
entry const churn = fn (remaining: U32) => do:
  if remaining == 0:
    return ()
${allocations}
  use churn (remaining - 1)
entry const answer = fn () => do:
  use churn 256
  return case stored of
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
const same = fn value => value
entry const answer = fn () => do:
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
const inspect = fn candidate => case candidate of
  Ok (Some value) => value
  Ok Nothing => 1
  Err True => 2
  Err False => 3
entry const some = fn () => inspect (Ok (Some 42))
entry const nothing = fn () => inspect (Ok Nothing)
entry const failed = fn () => inspect (Err False)
entry const mapped_error = fn () => inspect (Result.map_error Bool.not (Err False))
entry const bound = fn () => Maybe.unwrap_or 0 (Maybe.bind (Some 41) (fn value => Some (value + 1)))
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
const candidate: Maybe (Result [U32, Bool]) = Some (Ok 42)
const apply = fn (transform: U32 -> U32) => transform 42
entry const answer = fn () => apply (fn value => value)
entry const nested = fn () => case candidate of
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
const combine = fn left => fn right => left * 10 + right
const difference = fn left => fn right => left - right
const plus = fn left => fn right => left + right
entry const precedence = fn () => 2 + 4 * 10
entry const right_association = fn () => 1 ++ 2 ++ 3
entry const explicit_named = fn () => 20 \`difference\` 3 \`difference\` 2
entry const default_named = fn () => 20 \`plus\` 22 * 2
entry const applied_named = fn () => identity 20 \`plus\` identity 22
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
      "const invalid = fn () => 1 < 2 < 3\n",
      "operator_associativity",
    );
    rejects(compiler, "const invalid = fn () => 1 ^ 2\n", "unknown_operator");
  },
);

preludeTest(
  "root shadowing does not alter bindings inside prelude definitions",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `
const Bool.not = fn value => value
entry const local_not = fn () => Bool.not True
entry const prelude_not = fn () => U32.ne 7 7
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
entry const local_answer = fn () => case Some 42 of
  Some value => value
  Nothing => 0
entry const prelude_answer = fn () => Maybe.unwrap_or 0 (Maybe.pure 42)
`,
    );
    equal(call(exports, "local_answer"), 42);
    equal(call(exports, "prelude_answer"), 42);
    rejects(
      compiler,
      `
data Maybe a = Some a | Nothing
const invalid = fn () => case Maybe.pure 42 of
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
const invalid = fn () => case Some 42 of
  Some => 0
  Nothing => 0
`,
      "constructor_arity",
    );
    rejects(
      compiler,
      `
const invalid = fn () => case Nothing of
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
const invalid = fn candidate => case candidate of
  Some (Some value) => value
  Nothing => 0
`,
      "non_exhaustive_match",
    );
    rejects(
      compiler,
      `
const invalid = fn candidate => case candidate of
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
const invalid = fn () => do:
  let Some(value) = Some 42 else:
    0
  return value
`,
      "guard_fallthrough",
    );
    rejects(
      compiler,
      `
const invalid = fn () => do:
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
const invalid = fn () => do:
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
    rejects(
      compiler,
      "const invalid = fn value => value value\n",
      "infinite_type",
    );
  },
);
