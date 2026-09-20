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
fn combine left => fn right => left + right
fn with_answer transform => transform 42
export const answer = U32.mul 2 $ U32.add 1 $ 20
export fn arithmetic () => identity $ 2 + 4 * 10
export fn named () => identity $ 20 \`combine\` 22
export fn generic () => Maybe.unwrap_or 0 $ Maybe.map identity $ Some $ 42
export fn partial () => apply (U32.add 40) 2
export fn eager (enabled: Bool) => always 42 $ do:
  if enabled:
    use @panic "eager argument"
  return 0
export fn lambda () => with_answer $ fn value => value + 1
export fn block (enabled: Bool) => identity $ do:
  if enabled:
    return 42
  return 7
export fn matched (enabled: Bool) => identity $ case enabled of
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
fn choose_right ignored => fn value => value
export const answer = 0 $ 42
`,
    );
    equal((exports.answer as WebAssembly.Global).value, 42);
    await rejectSource(
      reference,
      native,
      "export fn answer () => 0 $ 42",
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
fn read () => Reader.ask ()
fn call_read () => read $ ()
export const reads = @effect.has (@effect.of call_read) Reader.ask
`;
    const { exports } = await compile(
      reference,
      native,
      declarations + `
export fn answer () => do reader:
  return call_read $ ()
export const expected = answer ()
`,
    );
    equal((exports.reads as WebAssembly.Global).value, 1);
    equal((exports.expected as WebAssembly.Global).value, 42);
    equal(call(exports, "answer"), 42);
    await rejectSource(
      reference,
      native,
      declarations + "export fn answer () => call_read $ ()",
      "backend_effect",
    );
    await rejectSource(
      reference,
      native,
      declarations + `
export fn answer () => do reader:
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
export fn discard () => do:
  use identity $ 42
export fn last_expression () => do:
  42
export fn early (enabled: Bool) => do:
  if enabled:
    return ()
  use 42
export fn expression_body () => 42
export fn discarded_panic (enabled: Bool) => do:
  if enabled:
    use @panic "discarded does not mean skipped"
export fn nested () => do:
  use do:
    return 7
  use identity $ 42
export const unit = discard ()
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
        "export fn missing () -> U32 => do:\n  use 42",
        "export fn mixed (enabled: Bool) => do:\n  if enabled:\n    return 42\n  use ()",
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
      "fn invalid () => do:\n  return $ identity $ 42",
      "resolver_required",
    );
    const { exports } = await compile(
      reference,
      native,
      `
export fn valid () => do:
  return identity $ 42
`,
    );
    equal(call(exports, "valid"), 42);
  },
);
