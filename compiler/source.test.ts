import {
  deepStrictEqual as equal,
  ok,
  rejects as rejectsAsync,
  throws,
} from "node:assert/strict";
import { createSourceCompiler, formatDiagnostic } from "./source.ts";
import { SourceError } from "./syntax.ts";

type Compiler = Awaited<ReturnType<typeof createSourceCompiler>>;

Deno.test("prelude syntax errors identify the prelude rather than the user file", async () => {
  const readTextFile = Deno.readTextFile;
  Deno.readTextFile = (path, options) => {
    if (path instanceof URL && path.pathname.endsWith("/std/prelude.blot")) {
      return Promise.resolve("fn broken");
    }
    return readTextFile(path, options);
  };
  try {
    await rejectsAsync(createSourceCompiler, (error) => {
      ok(error instanceof SourceError);
      equal(error.origin?.filename, "std/prelude.blot");
      ok(
        formatDiagnostic("game.blot", "", error).startsWith(
          "std/prelude.blot:",
        ),
      );
      return true;
    });
  } finally {
    Deno.readTextFile = readTextFile;
  }
});

function sourceTest(
  name: string,
  test: (compiler: Compiler) => void | Promise<void>,
) {
  Deno.test(name, async () => {
    const compiler = await createSourceCompiler({ prelude: "none" });
    try {
      await test(compiler);
    } finally {
      compiler.dispose();
    }
  });
}

async function instantiate(compiler: Compiler, source: string) {
  const artifact = compiler.compile(source);
  ok(WebAssembly.validate(artifact.bytes));
  const { instance } = await WebAssembly.instantiate(artifact.bytes);
  return { ...artifact, exports: instance.exports };
}

function call(exports: WebAssembly.Exports, name: string, value = 0): number {
  const fn = exports[name];
  ok(typeof fn === "function");
  return fn(value) as number;
}

function rejects(
  compiler: Compiler,
  source: string,
  code: string,
  offset?: number,
) {
  throws(() => compiler.compile(source), (error) => {
    ok(error instanceof SourceError, String(error));
    equal(error.code, code, error.message);
    if (offset !== undefined) equal(error.start, offset);
    return true;
  });
}

sourceTest(
  "source example produces executable functions and immutable const exports",
  async (compiler) => {
    const source = await Deno.readTextFile(
      new URL("../examples/scalar.blot", import.meta.url),
    );
    const { exports } = await instantiate(compiler, source);
    equal(call(exports, "answer"), 42);
    equal(call(exports, "bound_answer"), 42);
    equal(call(exports, "capped", 20), 20);
    equal(call(exports, "capped", 100), 42);
    equal(call(exports, "choose", 1), 20);
    equal(call(exports, "choose", 0), 22);
    equal(call(exports, "U32.increment", 41), 42);
    ok(exports.base instanceof WebAssembly.Global);
    equal(exports.base.value, 41);
    throws(() => {
      (exports.base as WebAssembly.Global).value = 0;
    }, TypeError);
    equal((exports.max_value as WebAssembly.Global).value >>> 0, 0xFFFF_FFFF);
  },
);

sourceTest(
  "source forward calls infer signatures and const calls execute in Bend",
  async (compiler) => {
    const { analysis, exports } = await instantiate(
      compiler,
      `
entry const answer = twice 21
entry const twice = fn value => @u32.mul value 2
entry const entry = fn () => identity answer
const identity = fn value => value
`,
    );
    equal(call(exports, "entry"), 42);
    const identity = analysis.functions.find((fn) => fn.name === "identity")!;
    equal(identity.parameter.$, "VariableTy");
    equal(identity.result, identity.parameter);
    equal(identity.variables.length, 1);
  },
);

sourceTest(
  "use binds pure results in const and runtime code, including continued RHSs",
  async (compiler) => {
    const { analysis, exports } = await instantiate(
      compiler,
      `entry const next = fn value => @u32.add value 1
entry const answer = do:
  use start: U32 <- 20
  use _ <- next start
  use result <-
    @u32.add start 22
  return result
entry const twice_next = fn (value: U32) => do:
  use value <- next value
  if True:
    use value <- 0
    value
  return @u32.add value value
`,
    );
    equal((exports.answer as WebAssembly.Global).value, 42);
    equal(call(exports, "twice_next", 20), 42);
    equal(analysis.functions.map((fn) => fn.effects), [[], []]);
  },
);

sourceTest(
  "use supports nested do, block returns, and immutable successor bindings",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `entry const choose = fn (condition: Bool) => do:
  use base <- do:
    if condition:
      return 20
    return 40
  use base <- @u32.add base 2
  return base
`,
    );
    equal(call(exports, "choose", 1), 22);
    equal(call(exports, "choose", 0), 42);
  },
);

sourceTest(
  "bare use compiles exactly like an explicit discard binding",
  async (compiler) => {
    const source = `entry const U32.increment = fn value => @u32.add value 1
entry const discard = fn (value: U32) => do:
  use value
  use U32.increment value
  use (U32.increment value)
  use @u32.add value 1
  use do:
    return @u32.mul value 2
  return value
`;
    const explicit = source.replaceAll("  use ", "  use _ <- ");
    const sugar = await instantiate(compiler, source);
    const desugared = compiler.compile(explicit);
    equal(sugar.bytes, desugared.bytes);
    equal(sugar.analysis, desugared.analysis);
    equal(call(sugar.exports, "discard", 42), 42);
  },
);

sourceTest(
  "bare use preserves const evaluation, scope, and block returns",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `entry const answer = do:
  use @u32.add 20 22
  return 42
entry const nested = fn (condition: Bool) => do:
  let value = 42
  use do:
    if condition:
      return 0
    return 1
  return value
`,
    );
    equal((exports.answer as WebAssembly.Global).value, 42);
    equal(call(exports, "nested", 0), 42);
    equal(call(exports, "nested", 1), 42);
    const discarded = "const bad = fn () => do:\n  use 42\n  return _";
    rejects(compiler, discarded, "unknown_value", discarded.lastIndexOf("_"));
    const unknown = "const bad = fn () => do:\n  use missing\n  return 42";
    rejects(compiler, unknown, "unknown_value", unknown.indexOf("missing"));
    for (const statement of ["use", "use value: U32", "use <- 42"]) {
      throws(
        () =>
          compiler.compile(
            `const bad = fn () => do:\n  ${statement}\n  return 42`,
          ),
        SourceError,
      );
    }
  },
);

sourceTest(
  "discarding a use result still evaluates its RHS",
  (compiler) => {
    for (const discard of ["use _ <-", "use"]) {
      const source = `const forever = fn () -> U32 => forever ()
entry const bad = do:
  ${discard} forever ()
  return 42
`;
      throws(
        () => compiler.analyze(source, { const_steps: 100n }),
        (error) =>
          error instanceof SourceError && error.code === "const_budget",
      );
    }
  },
);

sourceTest(
  "use enforces annotations and scope, and discard is not a binding",
  (compiler) => {
    const annotated =
      "const bad = fn () => do:\n  use value: Bool <- 42\n  return value";
    rejects(compiler, annotated, "type_mismatch", annotated.indexOf("use"));
    const recursive =
      "const bad = fn () => do:\n  use value <- value\n  return value";
    rejects(
      compiler,
      recursive,
      "unknown_value",
      recursive.indexOf("<- value") + 3,
    );
    const discarded = "const bad = fn () => do:\n  use _ <- 42\n  return _";
    rejects(compiler, discarded, "unknown_value", discarded.lastIndexOf("_"));
    rejects(
      compiler,
      "const bad = fn () => do:\n  if True:\n    use hidden <- 42\n  return hidden",
      "unknown_value",
    );
    for (const binding of ["use value = 42", "let value <- 42"]) {
      throws(
        () =>
          compiler.compile(
            `const bad = fn () => do:\n  ${binding}\n  return value`,
          ),
        SourceError,
      );
    }
  },
);

sourceTest(
  "branch bindings do not capture the continuation's outer locals",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `entry const scope = fn (condition: Bool) -> U32 => do:
  let value = 40
  if condition:
    let value = 2
    @u32.add value 10
  return @u32.add value 2
`,
    );
    equal(call(exports, "scope", 1), 42);
    equal(call(exports, "scope", 0), 42);
  },
);

sourceTest(
  "fallthrough conditionals do not duplicate the rest of the function",
  async (compiler) => {
    const sourceWith = (branches: number) =>
      "entry const entry = fn (condition: Bool) => do:\n" +
      "  if condition:\n    ()\n".repeat(branches) + "  return 42\n";
    const source = sourceWith(30);
    const { exports, bytes } = await instantiate(compiler, source);
    equal(call(exports, "entry", 1), 42);
    equal(call(exports, "entry", 0), 42);
    const baseline = compiler.compile(sourceWith(0)).bytes.length;
    const doubled = compiler.compile(sourceWith(60)).bytes.length;
    ok(
      doubled - baseline <= 2 * (bytes.length - baseline) + 16,
      `nonlinear continuation growth: ${baseline}, ${bytes.length}, ${doubled} bytes`,
    );
  },
);

sourceTest(
  "early-return branches have linear code growth",
  async (compiler) => {
    const sourceWith = (branches: number) =>
      "entry const entry = fn (condition: Bool) => do:\n" +
      "  if condition:\n    return 7\n".repeat(branches) + "  return 42\n";
    const { exports, bytes } = await instantiate(compiler, sourceWith(30));
    equal(call(exports, "entry", 1), 7);
    equal(call(exports, "entry", 0), 42);
    const baseline = compiler.compile(sourceWith(0)).bytes.length;
    const doubled = compiler.compile(sourceWith(60)).bytes.length;
    ok(doubled - baseline <= 2 * (bytes.length - baseline) + 16);
  },
);

sourceTest(
  "nested do returns to the block and nested branches preserve early returns",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `entry const nested = fn (value: U32) => do:
  let base = do:
    return 40
  if @u32.lt value 2:
    if @u32.eq value 0:
      return base
    else:
      return @u32.add base 1
  return @u32.add base 2
`,
    );
    equal(call(exports, "nested", 0), 40);
    equal(call(exports, "nested", 1), 41);
    equal(call(exports, "nested", 2), 42);
  },
);

sourceTest(
  "source recursion agrees between const evaluation and runtime",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `entry const count = fn value => do:
  if @u32.eq value 0:
    return 42
  return count (@u32.sub value 1)
entry const answer = count 5
entry const entry = fn () => count 5
`,
    );
    equal(call(exports, "entry"), (exports.answer as WebAssembly.Global).value);
  },
);

sourceTest(
  "parentheses close nested do suites without consuming the enclosing statement",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `entry const answer = fn () => @u32.add (do:
  return 20
) (do:
  if False:
    return 0
  return 22)
`,
    );
    equal(call(exports, "answer"), 42);
  },
);

sourceTest(
  "source handles Bool, Unit, comments, CRLF, and parenthesized continuation",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      `// header\r\nentry const truth = True\r\nentry const nothing = ()\r\nentry const answer = fn () => (@u32.add\r\n  20\r\n  22) // end`,
    );
    equal(call(exports, "answer"), 42);
    equal((exports.truth as WebAssembly.Global).value, 1);
    equal((exports.nothing as WebAssembly.Global).value, 0);
    equal(compiler.analyze("// empty").functions, []);
    rejects(compiler, "// empty", "no_entry");
  },
);

sourceTest(
  "U32 literals retain unsigned range and reject overflow before wrapping",
  async (compiler) => {
    for (const literal of ["4294967295", "0xFFFF_FFFF", "4_294_967_295"]) {
      const { exports } = await instantiate(
        compiler,
        `entry const max = fn () => ${literal}`,
      );
      equal(call(exports, "max") >>> 0, 0xFFFF_FFFF);
    }
    for (const literal of ["4294967296", "0x1_0000_0000", "9".repeat(70)]) {
      const source = `const bad = ${literal}`;
      rejects(compiler, source, "integer_range", source.indexOf(literal));
    }
  },
);

sourceTest(
  "source annotations and scalar intrinsic constraints are checked",
  (compiler) => {
    rejects(
      compiler,
      "const bad = fn (value: Bool) => @u32.add value 1",
      "type_mismatch",
    );
    const source =
      "const bad = fn () => do:\n  let value: Bool = 1\n  return value\n";
    rejects(compiler, source, "type_mismatch", source.indexOf("let"));
    rejects(compiler, "const bad = fn () -> Bool => 1", "type_mismatch");
    rejects(compiler, "const bad: F32 = 1", "type_mismatch");
    rejects(compiler, "const bad: F64 = 1", "unsupported_type");
  },
);

sourceTest(
  "name resolution respects scope and accepts first-class functions",
  (compiler) => {
    for (const expression of ["missing", "missing ()"]) {
      const source = `const bad = fn () => ${expression}`;
      rejects(compiler, source, "unknown_value", source.indexOf("missing"));
    }
    equal(
      compiler.analyze(
        "const f = fn value => value\nconst reference = fn () => f\nentry const probe = fn () => do:\n  let kept = reference\n  return 0\n",
      )
        .functions.find((fn) => fn.name === "reference")?.result.$,
      "FunctionTy",
    );
    equal(
      compiler.analyze(
        "const f = fn value => value\nconst apply = fn f => f 1\nentry const probe = fn () => do:\n  let kept = apply\n  return 0\n",
      )
        .functions.find((fn) => fn.name === "apply")?.parameter.$,
      "FunctionTy",
    );
    rejects(compiler, "const f = fn () => 1\nconst f = 2", "duplicate_name");
    rejects(
      compiler,
      "const f = fn () => do:\n  if True:\n    let hidden = 1\n  return hidden",
      "unknown_value",
    );
    rejects(
      compiler,
      "const f = fn () => do:\n  let value = value\n  return value",
      "unknown_value",
    );
  },
);

sourceTest(
  "source rejects unsupported intrinsics, arity, and dead statements",
  (compiler) => {
    rejects(compiler, "const f = fn () => @u32.div 1 2", "unknown_intrinsic");
    rejects(compiler, "const f = fn () => @u32.add 1", "call_arity");
    rejects(compiler, "const f = fn () => @u32.add 1 2 3", "call_arity");
    rejects(
      compiler,
      "const f = fn () => do:\n  return 1\n  return 2",
      "unreachable_statement",
    );
  },
);

sourceTest(
  "resolver values must be declared and typed providers",
  (compiler) => {
    rejects(
      compiler,
      "const example = fn () => do absent:\n  return 42",
      "unknown_value",
    );
    rejects(
      compiler,
      "const example = fn () => do 7:\n  return 42",
      "invalid_provider",
    );
  },
);

sourceTest(
  "domain operations are not compiler intrinsics or privileged attributes",
  (compiler) => {
    for (
      const name of [
        "@ecs.get",
        "@ecs.set",
        "@ecs.insert",
        "@ecs.run",
        "@ecs.spawn",
        "@ecs.entity",
        "@window.title",
        "@window.save",
        "@window.load",
        "@render.draw",
        "@render.clear",
        "@render.view",
        "@input.delta_time",
        "@asset.mesh",
      ]
    ) {
      rejects(
        compiler,
        `const example = fn () => ${name} ()`,
        "unknown_intrinsic",
      );
    }
    rejects(
      compiler,
      "#[component]\ndata Position = Position U32",
      "unsupported_attribute",
    );
    rejects(
      compiler,
      "#[resource]\ndata Clock = Clock U32",
      "unsupported_attribute",
    );
  },
);

sourceTest(
  "platform-named effects are ordinary source declarations without host imports",
  async (compiler) => {
    const { bytes, exports } = await instantiate(
      compiler,
      `effect window.title: U32 -> Unit
const test_window = @effect.provider window.title (fn _ => ())
entry const answer = fn () => do test_window:
  use window.title 7
  return 42
`,
    );
    equal(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), []);
    equal(call(exports, "answer"), 42);
  },
);

sourceTest(
  "provider types are checked in consts, nested blocks, and dead branches",
  (compiler) => {
    for (
      const source of [
        "const try = 0\nconst example = fn () => do try:\n  return 42",
        "const try = 0\nconst example = do try:\n  return 42",
        "const try = 0\nconst example = fn () => do:\n  let result = do try:\n    return 42\n  return result",
        "const try = 0\nconst example = fn () => do:\n  if False:\n    use do try:\n      return 42\n  return 0",
      ]
    ) {
      rejects(
        compiler,
        source,
        "invalid_provider",
      );
    }
  },
);

sourceTest(
  "return forwarding is not erased or interpreted as a free dollar operator",
  (compiler) => {
    for (
      const source of [
        "const example = fn () => do:\n  return $ 42",
        "const example = fn () => do:\n  if True:\n    return $ 42\n  return 0",
        "const example = fn () => do:\n  use do:\n    return $ 42\n  return 0",
      ]
    ) {
      rejects(compiler, source, "resolver_required", source.indexOf("$"));
    }
    for (
      const source of [
        "const example = fn () => do:\n  return $",
        "const example = fn () => $ 42",
        "const example = fn () => do:\n  use $ 42\n  return 0",
      ]
    ) {
      throws(() => compiler.compile(source), SourceError);
    }
  },
);

sourceTest(
  "monad and try remain ordinary source-defined names",
  async (compiler) => {
    const { exports } = await instantiate(
      compiler,
      "const monad = fn value => value\nentry const try = 42\nentry const answer = fn () => monad try",
    );
    equal(call(exports, "answer"), 42);
  },
);

sourceTest(
  "unsupported design syntax is rejected rather than silently erased",
  (compiler) => {
    for (
      const source of [
        'import { get } from "engine/ecs"',
        "type Scalar = U32",
        "const f = fn x:\n  return x",
        "const f = fn () => 1 + 2",
        "const value = 1 garbage",
      ]
    ) {
      throws(() => compiler.compile(source), SourceError, source);
    }
  },
);

sourceTest(
  "layout diagnoses tabs, unexpected indent, bad dedent, and missing suite",
  (compiler) => {
    rejects(compiler, "const f = fn () => do:\n\treturn 1", "layout_tab");
    rejects(compiler, "  const f = fn () => 1", "layout_indent");
    rejects(
      compiler,
      "const f = fn () => do:\n  let a = 1\n return a",
      "layout_dedent",
    );
    rejects(compiler, "const f = fn () => do:\nreturn 1", "layout_suite");
    rejects(compiler, "const f = fn () =>\n  do:\n  return 1", "layout_suite");
    rejects(compiler, "const f = fn () => \uE000", "reserved_layout");
  },
);

sourceTest(
  "parser reuse does not retain definitions and errors report original source positions",
  (compiler) => {
    compiler.compile("entry const old = 1");
    const source = "// comment\nconst entry = fn () => do:\n  return old\n";
    try {
      compiler.compile(source);
      throw new Error("expected failure");
    } catch (error) {
      ok(error instanceof SourceError);
      equal(error.start, source.indexOf("old"));
      ok(
        formatDiagnostic("game.blot", source, error).startsWith(
          "game.blot:3:10: unknown_value:",
        ),
      );
    }
  },
);
