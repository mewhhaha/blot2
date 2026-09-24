import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

type Reference = Awaited<ReturnType<typeof createSourceCompiler>>;
type Native = Awaited<ReturnType<typeof createNativeCompiler>>;

function applicationTest(
  name: string,
  test: (reference: Reference, native: Native) => Promise<void>,
  prelude: "default" | "none" = "default",
) {
  Deno.test(name, async () => {
    const reference = await createSourceCompiler({ prelude });
    const native = await createNativeCompiler({ prelude });
    try {
      await test(reference, native);
    } finally {
      reference.dispose();
      await native.dispose();
    }
  });
}

async function compile(reference: Reference, native: Native, source: string) {
  const expected = reference.compile(source);
  const actual = await native.compile(source);
  equal(actual, expected, "native/reference compiler parity");
  ok(WebAssembly.validate(actual.bytes));
  const { instance } = await WebAssembly.instantiate(actual.bytes);
  return { ...actual, exports: instance.exports };
}

function call(exports: WebAssembly.Exports, name: string, argument = 0) {
  const fn = exports[name];
  ok(typeof fn === "function");
  return fn(argument);
}

async function rejectSource(
  reference: Reference,
  native: Native,
  source: string,
  code?: string,
) {
  let expected: SourceError;
  throws(() => reference.compile(source), (error) => {
    ok(error instanceof SourceError);
    if (code) equal(error.code, code);
    expected = error;
    return true;
  });
  await rejects(() => native.compile(source), (error) => {
    ok(error instanceof SourceError);
    equal([error.code, error.start], [expected.code, expected.start]);
    return true;
  });
}

applicationTest(
  "dollar is right-associative application below arithmetic and backticks",
  async (reference, native) => {
    const { exports } = await compile(
      reference,
      native,
      `
const combine = fn left => fn right => left + right
const with_answer = fn transform => transform 42
const answer = U32.mul 2 $ U32.add 1 $ 20
const arithmetic = fn () => identity $ 2 + 4 * 10
const named = fn () => identity $ 20 \`combine\` 22
const generic = fn () => Maybe.unwrap_or 0 $ Maybe.map identity $ Some $ 42
const partial = fn () => apply (U32.add 40) 2
const eager = fn (enabled: Bool) => always 42 $ do:
  if enabled:
    use @panic "eager argument"
  return 0
const lambda = fn () => with_answer $ fn value => value + 1
const block = fn (enabled: Bool) => identity $ do:
  if enabled:
    return 42
  return 7
const matched = fn (enabled: Bool) => identity $ case enabled of
  True => 42
  False => 7
`,
    );
    equal((exports.answer as WebAssembly.Global).value, 42);
    for (const name of ["arithmetic", "named", "generic", "partial"]) {
      equal(call(exports, name), 42);
    }
    equal(call(exports, "lambda"), 43);
    equal(call(exports, "eager", 0), 42);
    throws(() => call(exports, "eager", 1), WebAssembly.RuntimeError);
    for (const name of ["block", "matched"]) {
      equal(call(exports, name, 1), 42);
      equal(call(exports, name, 0), 7);
    }
  },
);

applicationTest(
  "dollar is source-defined and can be rebound without compiler dispatch",
  async (reference, native) => {
    const { exports } = await compile(
      reference,
      native,
      `
infixr 0 ($) = choose_right
const choose_right = fn ignored => fn value => value
const answer = 0 $ 42
`,
    );
    equal((exports.answer as WebAssembly.Global).value, 42);
    await rejectSource(
      reference,
      native,
      "const answer = fn () => 0 $ 42",
      "unknown_operator",
    );
  },
  "none",
);

applicationTest(
  "dollar forwards callback effects and does not grant an implicit provider",
  async (reference, native) => {
    const declarations = `
effect Reader.ask: Unit -> U32
const reader = @effect.provider Reader.ask (fn () => 42)
const read = fn () => Reader.ask ()
const call_read = fn () => read $ ()
const reads = @effect.has (@effect.of call_read) Reader.ask
`;
    const { exports } = await compile(
      reference,
      native,
      declarations + `
const answer = fn () => do reader:
  return call_read $ ()
const expected = answer ()
`,
    );
    equal((exports.reads as WebAssembly.Global).value, 1);
    equal((exports.expected as WebAssembly.Global).value, 42);
    equal(call(exports, "answer"), 42);
    await rejectSource(
      reference,
      native,
      declarations + "const answer: Unit -> U32 = fn () => call_read $ ()",
      "effect_mismatch",
    );
    await rejectSource(
      reference,
      native,
      declarations + `
const answer = fn () => do reader:
  let result = read $ ()
  return result
`,
      "let_effect",
    );
  },
);

applicationTest(
  "plain do fallthrough returns Unit rather than its last expression",
  async (reference, native) => {
    const { exports, analysis } = await compile(
      reference,
      native,
      `
const discard = fn () => do:
  use identity $ 42
const last_expression = fn () => do:
  42
const early = fn (enabled: Bool) => do:
  if enabled:
    return ()
  use 42
const expression_body = fn () => 42
const discarded_panic = fn (enabled: Bool) => do:
  if enabled:
    use @panic "discarded does not mean skipped"
const nested = fn () => do:
  use do:
    return 7
  use identity $ 42
const unit = discard ()
`,
    );
    for (const name of ["discard", "last_expression", "early", "nested"]) {
      equal(analysis.functions.find((fn) => fn.name === name)?.result, {
        $: "UnitTy",
      });
      equal(call(exports, name, 0), 0);
      equal(call(exports, name, 1), 0);
    }
    equal(call(exports, "expression_body"), 42);
    equal(call(exports, "discarded_panic", 0), 0);
    throws(() => call(exports, "discarded_panic", 1), WebAssembly.RuntimeError);
    equal((exports.unit as WebAssembly.Global).value, 0);
    for (
      const source of [
        "const missing = fn () -> U32 => do:\n  use 42",
        "const mixed = fn (enabled: Bool) => do:\n  if enabled:\n    return 42\n  use ()",
      ]
    ) {
      await rejectSource(reference, native, source, "type_mismatch");
    }
  },
);

applicationTest(
  "return forwarding remains distinct from infix dollar application",
  async (reference, native) => {
    await rejectSource(
      reference,
      native,
      "const invalid = fn () => do:\n  return $ identity $ 42",
      "resolver_required",
    );
    const { exports } = await compile(
      reference,
      native,
      `
const valid = fn () => do:
  return identity $ 42
`,
    );
    equal(call(exports, "valid"), 42);
  },
);
