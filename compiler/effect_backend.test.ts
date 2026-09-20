import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<T> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: T;
  readonly tail: List<T>;
};
type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: { readonly code: string; readonly message: string };
};
type Job = Node & { readonly key: string };
type Entry = Node & { readonly key: string };
type Prepared = Node & { readonly jobs: List<Job> };
const backend = compiled as unknown as {
  "wasm.prepare"(checked: Node, constants: List<Node>): Result<Prepared>;
  "wasm.compile_entry"(job: Job): Result<Entry>;
  "wasm.link"(prepared: Prepared, entries: List<Entry>): Result<List<number>>;
};

function list<T>(values: readonly T[]): List<T> {
  let result: List<T> = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index--) {
    result = { $: "Con", head: values[index], tail: result };
  }
  return result;
}
function array<T>(values: List<T>): T[] {
  const result: T[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    result.push(cursor.head);
  }
  return result;
}
function unwrap<T>(result: Result<T>): T {
  if (result.$ === "Fail") {
    throw new Error(`${result.error.code}: ${result.error.message}`);
  }
  return result.value;
}
const n = ($: string, fields: Record<string, unknown> = {}): Node => ({
  $,
  ...fields,
});
const none = n("None");
const some = (value: Node) => n("Some", { value });
const unit = n("UnitExpr");
const unitType = n("UnitTy");
const u32 = n("U32Ty");
const integer = (value: number) => n("U32Expr", { value });
const local = (name: string) => n("LocalExpr", { name });
const constant = (name: string) => n("ConstantExpr", { name });
const identity = (declaration: string, module_name = "effects/backend") =>
  n("TypeId", { declaration, module_name });
const reader = identity("Reader.ask");
const other = identity("Other.ask");
const row = (operations: readonly Node[] = []) =>
  n("EffectRow", { operations: list(operations), tail: n("ClosedRow") });
const declaration = (identity: Node) =>
  n("Operation", { identity, parameter: unitType, result: u32 });
const operation = (identity = reader) => n("OperationExpr", { identity });
const apply = (callee: Node, argument = unit) =>
  n("ApplyExpr", { callee, argument });
const ask = (identity = reader) => apply(operation(identity));
const call = (callee: string, argument = unit) =>
  n("CallExpr", { callee, argument });
const add = (left: Node, right: Node) =>
  n("ScalarExpr", { operator: n("Add"), left, right });
const lambda = (identity: bigint, body: Node, parameter = "value") =>
  n("LambdaExpr", {
    identity,
    parameter,
    parameter_type: none,
    result_type: none,
    body,
  });
const provider = (implementation: Node, identity = reader) =>
  n("ProviderExpr", { identity, implementation });
const handle = (provider: Node, body: Node) =>
  n("HandleExpr", { provider, body });
const bind = (name: string, value: Node, body: Node) =>
  n("LetExpr", { name, value, body });
const sequence = (first: Node, next: Node) =>
  n("SequenceExpr", { first, next });
const block = (label: bigint, body: Node) => n("BlockExpr", { label, body });
const returns = (label: bigint, value: Node) =>
  n("ReturnExpr", { label, value });
const panic = n("PanicExpr", { message: "must not execute" });

function fn(
  name: string,
  body: Node,
  options: {
    exported?: boolean;
    parameter?: string;
    parameter_type?: Node;
    result_type?: Node;
    operations?: readonly Node[];
  } = {},
): Node {
  const parameter = options.parameter ?? "value";
  const parameter_type = options.parameter_type ?? unitType;
  const result_type = options.result_type ?? u32;
  return n("CheckedFunction", {
    function: n("Function", {
      name,
      exported: options.exported ?? true,
      parameter,
      parameter_type: some(parameter_type),
      result_type: some(result_type),
      body,
    }),
    signature: n("Signature", {
      name,
      parameter: parameter_type,
      result: result_type,
      variables: list([]),
      effects: row(options.operations),
    }),
    effects: list(
      (options.operations ?? []).map((identity) =>
        n("OperationEffect", { identity })
      ),
    ),
  });
}

function program(
  functions: readonly Node[],
  options: {
    operations?: readonly Node[];
    constants?: readonly { name: string; value: Node; type?: Node }[];
  } = {},
) {
  const constants = options.constants ?? [];
  return {
    checked: n("CheckedModule", {
      functions: list(functions),
      constants: list(constants.map(({ name, type }) =>
        n("CheckedConstant", {
          constant: n("Constant", {
            name,
            exported: false,
            annotation: none,
            value: unit,
          }),
          inferred_type: type ?? u32,
          variables: list([]),
        })
      )),
      data_types: list([]),
      operations: list(
        (options.operations ?? [reader]).map((operation) =>
          operation.$ === "Operation" ? operation : declaration(operation)
        ),
      ),
    }),
    constants: list(
      constants.map(({ name, value }) => n("Binding", { name, value })),
    ),
  };
}

function encode(
  source: ReturnType<typeof program>,
  cache = new Map<string, Entry>(),
) {
  const prepared = unwrap(
    backend["wasm.prepare"](source.checked, source.constants),
  );
  const jobs = array(prepared.jobs);
  const reused: string[] = [];
  const entries = jobs.map((job) => {
    const key = JSON.stringify(
      job,
      (_, value) => typeof value === "bigint" ? `${value}n` : value,
    );
    const previous = cache.get(key);
    if (previous) {
      reused.push(job.key);
      return previous;
    }
    const entry = unwrap(backend["wasm.compile_entry"](job));
    cache.set(key, entry);
    return entry;
  });
  const bytes = new Uint8Array(
    array(unwrap(backend["wasm.link"](prepared, list(entries)))),
  );
  ok(WebAssembly.validate(bytes));
  const module = new WebAssembly.Module(bytes);
  equal(WebAssembly.Module.imports(module), []);
  return {
    bytes,
    jobs,
    reused,
    exports: new WebAssembly.Instance(module).exports as Record<
      string,
      (value: number) => number
    >,
  };
}

Deno.test("Wasm provider handles named operation calls and lexical handler captures", () => {
  const built = encode(program([
    fn("read", ask(), { exported: false, operations: [reader] }),
    fn(
      "answer",
      bind(
        "seed",
        integer(37),
        handle(
          provider(lambda(1n, add(local("seed"), integer(5)))),
          call("read"),
        ),
      ),
    ),
  ]));
  equal(built.exports.answer(0), 42);
});

Deno.test("Wasm nested providers delegate to the matched outer scope", () => {
  const built = encode(program([fn(
    "answer",
    handle(
      provider(lambda(1n, integer(10))),
      add(
        handle(provider(lambda(2n, add(ask(), integer(1)))), ask()),
        ask(),
      ),
    ),
  )]));
  equal(built.exports.answer(0), 21);
});

Deno.test("Wasm handler residual effects ignore providers younger than the matched frame", () => {
  const built = encode(program([fn(
    "answer",
    handle(
      provider(lambda(1n, integer(1))),
      handle(
        provider(lambda(2n, ask()), other),
        handle(provider(lambda(3n, integer(20))), ask(other)),
      ),
    ),
  )], { operations: [reader, other] }));
  equal(built.exports.answer(0), 1);
});

Deno.test("Wasm nonlocal return out of a handled body restores lexical provider scope", () => {
  const built = encode(program([fn(
    "answer",
    handle(
      provider(lambda(1n, integer(1))),
      add(
        block(
          0n,
          handle(
            provider(lambda(2n, integer(2))),
            sequence(returns(0n, ask()), panic),
          ),
        ),
        ask(),
      ),
    ),
  )]));
  equal(built.exports.answer(0), 3);
});

Deno.test("Wasm escaped effectful closures use invocation-time providers", () => {
  const built = encode(program([fn(
    "answer",
    bind(
      "get",
      handle(
        provider(lambda(1n, integer(100))),
        lambda(2n, ask()),
      ),
      add(
        handle(provider(lambda(3n, integer(35))), apply(local("get"))),
        handle(provider(lambda(4n, integer(7))), apply(local("get"))),
      ),
    ),
  )]));
  equal(built.exports.answer(0), 42);
});

Deno.test("Wasm higher-order operation callbacks carry provider scope through direct calls", () => {
  const built = encode(program([
    fn("twice", add(apply(local("callback")), apply(local("callback"))), {
      exported: false,
      parameter: "callback",
      parameter_type: n("FunctionTy", {
        parameter: unitType,
        result: u32,
        effects: row([reader]),
      }),
      operations: [reader],
    }),
    fn(
      "answer",
      handle(provider(lambda(1n, integer(21))), call("twice", operation())),
    ),
  ]));
  equal(built.exports.answer(0), 42);
});

Deno.test("Wasm constant providers and operation aliases delegate without scope capture", () => {
  const built = encode(program([fn(
    "answer",
    handle(
      provider(lambda(1n, integer(42))),
      handle(constant("delegate"), apply(constant("ask"))),
    ),
  )], {
    constants: [
      { name: "ask", value: n("OperationValue", { identity: reader }) },
      {
        name: "delegate",
        value: n("ProviderValue", {
          identity: reader,
          implementation: n("OperationValue", { identity: reader }),
        }),
      },
    ],
  }));
  equal(built.exports.answer(0), 42);
});

Deno.test("Wasm generic operation calls preserve F32 payload words and typed exports", () => {
  const float = n("F32Ty");
  const double = identity("Numbers.double");
  const built = encode(
    program([fn(
      "answer",
      handle(
        provider(
          lambda(
            1n,
            n("ScalarExpr", {
              operator: n("F32Multiply"),
              left: local("value"),
              right: n("F32Expr", { value: 2 }),
            }),
          ),
          double,
        ),
        apply(operation(double), local("value")),
      ),
      {
        parameter_type: float,
        result_type: float,
      },
    )], {
      operations: [
        n("Operation", { identity: double, parameter: float, result: float }),
      ],
    }),
  );
  equal(built.exports.answer(1.25), 2.5);
  equal(built.exports.answer(-0), -0);
});

Deno.test("Wasm rejects unhandled exports and has no host fallback after an invariant trap", () => {
  throws(
    () => encode(program([fn("bad", ask(), { operations: [reader] })])),
    /backend_effect/,
  );
  // The second fixture deliberately violates the checked-row invariant to probe the runtime trap.
  const built = encode(program([
    fn("bad", ask()),
    fn("good", handle(provider(lambda(1n, integer(42))), ask())),
  ]));
  throws(() => built.exports.bad(0), WebAssembly.RuntimeError);
  equal(built.exports.good(0), 42);
});

Deno.test("Wasm operation relocations survive declaration reorder and table LEB boundaries", () => {
  const cache = new Map<string, Entry>();
  const main = fn("answer", handle(provider(lambda(1n, integer(42))), ask()));
  const before = encode(program([main]), cache);
  const operations = Array.from(
    { length: 130 },
    (_, index) => identity(`Other${index}.ask`),
  );
  const afterSource = program([fn("extra", integer(7)), main], {
    operations: [...operations, reader],
  });
  const after = encode(afterSource, cache);
  equal(before.exports.answer(0), 42);
  equal(after.exports.answer(0), 42);
  ok(after.reused.includes("fn:answer"));
  ok(after.reused.includes("lambda:1"));
  ok(after.reused.some((key) => key.endsWith("Reader.ask")));
  equal(after.bytes, encode(afterSource).bytes);
});

Deno.test("Wasm omits const-only descriptor helpers and unused captured descriptors", () => {
  const built = encode(program([
    fn(
      "describe",
      n("EffectCountExpr", {
        set: n("FunctionEffectsExpr", { callee: "read" }),
      }),
      { exported: false },
    ),
    fn("read", ask(), { exported: false, operations: [reader] }),
    fn("answer", apply(constant("get"))),
  ], {
    constants: [
      {
        name: "metadata",
        value: n("EffectSetValue", { operations: list([reader]) }),
      },
      {
        name: "get",
        value: n("ClosureValue", {
          identity: 5n,
          parameter: "value",
          body: local("captured"),
          environment: list([
            n("Binding", {
              name: "captured",
              value: n("U32Value", { value: 42 }),
            }),
            n("Binding", {
              name: "metadata",
              value: n("EffectSetValue", { operations: list([reader]) }),
            }),
          ]),
        }),
      },
    ],
  }));
  equal(built.exports.answer(0), 42);
  ok(
    !built.jobs.some((job) =>
      job.key === "fn:describe" || job.key === "fn:read"
    ),
  );
});

Deno.test("Wasm rejects runtime-reachable reflection and descriptor values", () => {
  throws(() =>
    encode(program([fn(
      "answer",
      n("EffectCountExpr", {
        set: n("FunctionEffectsExpr", { callee: "answer" }),
      }),
    )])), /backend_const_only/);
  throws(
    () =>
      encode(program([fn("answer", constant("metadata"))], {
        constants: [
          {
            name: "metadata",
            value: n("EffectDescriptorValue", { identity: reader }),
          },
        ],
      })),
    /backend_const_only/,
  );
});

Deno.test("Wasm reachability follows distinct captured functions of one constant lambda", () => {
  const closure = (name: string) =>
    n("ClosureValue", {
      identity: 8n,
      parameter: "value",
      body: apply(local("callback")),
      environment: list([n("Binding", {
        name: "callback",
        value: n("FunctionValue", { name }),
      })]),
    });
  const built = encode(program([
    fn("left", integer(20), { exported: false }),
    fn("right", integer(22), { exported: false }),
    fn("answer", add(apply(constant("first")), apply(constant("second")))),
  ], {
    constants: [
      { name: "first", value: closure("left") },
      { name: "second", value: closure("right") },
    ],
  }));
  equal(built.exports.answer(0), 42);
  equal(built.jobs.filter((job) => job.key === "lambda:8").length, 1);
  ok(built.jobs.some((job) => job.key === "fn:left"));
  ok(built.jobs.some((job) => job.key === "fn:right"));
});

Deno.test("Wasm multiple match scrutinees short-circuit nonlocal returns left to right", () => {
  const built = encode(program([fn(
    "answer",
    block(
      0n,
      n("MatchExpr", {
        values: list([returns(0n, integer(42)), panic]),
        arms: list([
          n("MatchArm", {
            patterns: list([
              n("WildcardPattern"),
              n("WildcardPattern"),
            ]),
            body: integer(0),
          }),
        ]),
      }),
    ),
  )]));
  equal(built.exports.answer(0), 42);
});

Deno.test("Wasm multiple match patterns bind distinct pre-evaluated locals", () => {
  const built = encode(program([fn(
    "answer",
    n("MatchExpr", {
      values: list([integer(20), integer(22)]),
      arms: list([
        n("MatchArm", {
          patterns: list([
            n("U32Pattern", { value: 1 }),
            n("WildcardPattern"),
          ]),
          body: panic,
        }),
        n("MatchArm", {
          patterns: list([
            n("BindingPattern", { name: "left" }),
            n("BindingPattern", { name: "right" }),
          ]),
          body: add(local("left"), local("right")),
        }),
      ]),
    }),
  )]));
  equal(built.exports.answer(0), 42);
});
