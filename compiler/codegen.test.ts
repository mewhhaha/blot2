import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<A> =
  | { readonly $: "Nil" }
  | { readonly $: "Con"; readonly head: A; readonly tail: List<A> };
type Node = { readonly $: string; readonly [field: string]: unknown };
type Result<A> =
  | { readonly $: "Done"; readonly value: A }
  | {
    readonly $: "Fail";
    readonly error: {
      readonly code: string;
      readonly subject: string;
      readonly message: string;
    };
  };
interface Analysis {
  readonly checked: Node;
  readonly constants: List<Node>;
}
interface Job {
  readonly $: "wasm.CodegenJob";
  readonly key: string;
  readonly parameter: string;
  readonly body: Node;
  readonly captures: List<string>;
}
interface EntryCode {
  readonly $: "wasm.EntryCode";
  readonly key: string;
  readonly code: {
    readonly $: "wasm.Code";
    readonly fragments: List<Node>;
    readonly locals: bigint;
  };
}
interface Prepared {
  readonly jobs: List<Job>;
}
interface BytePlan {
  readonly $: "wasm.BytePlan";
  readonly length: bigint;
  readonly chunks: List<List<number>>;
}
const backend = compiled as unknown as {
  analyze(source: Node, steps: bigint): Result<Analysis>;
  "wasm.prepare"(
    checked: Node,
    constants: List<Node>,
  ): Result<Prepared>;
  "wasm.compile_entry"(job: Job): Result<EntryCode>;
  "wasm.compile_entries"(jobs: List<Job>): Result<List<EntryCode>>;
  "wasm.link"(
    prepared: Prepared,
    entries: List<EntryCode>,
  ): Result<List<number>>;
  "wasm.emit"(checked: Node, constants: List<Node>): Result<List<number>>;
  "wasm.byte_plan"(bytes: List<number>): BytePlan;
  "wasm.plan_sequence"(plans: List<BytePlan>): BytePlan;
  "wasm.plan_vector"(plans: List<BytePlan>): BytePlan;
  "wasm.plan_section"(id: number, plan: BytePlan): BytePlan;
  "wasm.plan_finish"(plan: BytePlan): List<number>;
  "wasm.body_plan"(
    plan: BytePlan,
    locals: bigint,
    parameters: bigint,
  ): BytePlan;
  "wasm.body_bytes"(
    bytes: List<number>,
    locals: bigint,
    parameters: bigint,
  ): List<number>;
  "wasm.section"(id: number, bytes: List<number>): List<number>;
  "wasm.vector"(entries: List<List<number>>): List<number>;
};

function list<A>(values: readonly A[]): List<A> {
  let result: List<A> = { $: "Nil" };
  for (let index = values.length - 1; index >= 0; index--) {
    result = { $: "Con", head: values[index], tail: result };
  }
  return result;
}

function array<A>(values: List<A>): A[] {
  const result: A[] = [];
  for (let cursor = values; cursor.$ === "Con"; cursor = cursor.tail) {
    result.push(cursor.head);
  }
  return result;
}

function unwrap<A>(result: Result<A>): A {
  if (result.$ === "Fail") {
    throw new Error(`${result.error.code}: ${result.error.message}`);
  }
  return result.value;
}

const node = ($: string, fields: Record<string, unknown> = {}): Node => ({
  $,
  ...fields,
});
const none = node("None");
const some = (value: Node) => node("Some", { value });
const unit = node("model.UnitExpr");
const unitType = node("model.UnitTy");
const u32Type = node("model.U32Ty");
const integer = (value: number) => node("model.U32Expr", { value });
const local = (name: string) => node("model.LocalExpr", { name });
const constant = (name: string) => node("model.ConstantExpr", { name });
const call = (callee: string, argument = unit) =>
  node("model.CallExpr", { callee, argument });
const apply = (callee: Node, argument: Node) =>
  node("model.ApplyExpr", { callee, argument });
const add = (left: Node, right: Node) =>
  node("model.ScalarExpr", { operator: node("model.Add"), left, right });
const binding = (name: string, value: Node, body: Node) =>
  node("model.LetExpr", { name, value, body });
const lambda = (identity: bigint, parameter: string, body: Node) =>
  node("model.LambdaExpr", {
    identity,
    parameter,
    parameter_type: none,
    result_type: none,
    body,
  });
const construct = (constructor: string, payload: Node | null = null) =>
  node("model.ConstructExpr", {
    constructor,
    payload: payload === null ? none : some(payload),
  });
const dataType = (name: string, constructors: readonly Node[]) =>
  node("model.DataType", {
    identity: node("model.TypeId", {
      module_name: "codegen/test",
      declaration: name,
    }),
    parameters: 0n,
    constructors: list(constructors),
  });
const variant = (name: string, payload: Node | null = null) =>
  node("model.Constructor", {
    fields: list([]),
    name,
    payload: payload === null ? none : some(payload),
  });
const fn = (
  name: string,
  body: Node,
  options: { exported?: boolean; parameter_type?: Node } = {},
) =>
  node("model.Function", {
    name,
    exported: options.exported ?? true,
    parameter: "value",
    parameter_type: some(options.parameter_type ?? unitType),
    result_type: none,
    body,
  });
const constDefinition = (name: string, value: Node) =>
  node("model.Constant", { name, value, exported: false, annotation: none });
const source = (
  functions: readonly Node[],
  options: {
    constants?: readonly Node[];
    data_types?: readonly Node[];
    operations?: readonly Node[];
  } = {},
) =>
  node("model.Module", {
    functions: list(functions),
    constants: list(options.constants ?? []),
    data_types: list(options.data_types ?? []),
    operations: list(options.operations ?? []),
  });
const matched = (value: Node, constructor: string, body: Node) =>
  node("model.MatchExpr", {
    values: list([value]),
    arms: list([
      node("model.MatchArm", {
        patterns: list([node("model.ConstructorPattern", {
          constructor,
          payload: some(node("model.BindingPattern", { name: "payload" })),
        })]),
        body,
      }),
    ]),
  });

function fingerprint(value: unknown): string {
  return JSON.stringify(
    value,
    (_, field) => typeof field === "bigint" ? `${field}n` : field,
  );
}

function containsNode(value: unknown, tag: string): boolean {
  if (value === null || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return record.$ === tag ||
    Object.values(record).some((child) => containsNode(child, tag));
}

function prepare(program: Node) {
  const analysis = unwrap(backend.analyze(program, 100_000n));
  const prepared = unwrap(
    backend["wasm.prepare"](analysis.checked, analysis.constants),
  );
  return { analysis, prepared, jobs: array(prepared.jobs) };
}

function cached(
  program: Node,
  cache: Map<string, EntryCode>,
) {
  const prepared = prepare(program);
  const created: string[] = [];
  const entries = prepared.jobs.map((job) => {
    const key = fingerprint(job);
    const previous = cache.get(key);
    if (previous) return previous;
    const compiled = unwrap(backend["wasm.compile_entry"](job));
    cache.set(key, compiled);
    created.push(job.key);
    return compiled;
  });
  const bytes = Uint8Array.from(array(unwrap(
    backend["wasm.link"](prepared.prepared, list(entries)),
  )));
  const clean = unwrap(
    backend["wasm.emit"](
      prepared.analysis.checked,
      prepared.analysis.constants,
    ),
  );
  equal(
    bytes,
    Uint8Array.from(array(clean)),
    "cached linking must equal clean emission",
  );
  ok(WebAssembly.validate(bytes));
  return { ...prepared, entries, bytes, created };
}

async function answer(bytes: Uint8Array<ArrayBuffer>) {
  const { instance } = await WebAssembly.instantiate(bytes);
  const invoke = instance.exports.answer;
  ok(typeof invoke === "function");
  return invoke(0);
}

Deno.test("cached codegen relocates reordered calls across index and body-size LEB boundaries", async () => {
  const cache = new Map<string, EntryCode>();
  const calls = Array.from({ length: 11 }, () => call("helper", integer(0)));
  const functions = [
    fn("answer", calls.reduce(add)),
    fn("helper", add(local("value"), integer(2)), {
      exported: false,
      parameter_type: u32Type,
    }),
  ];
  const first = cached(source(functions), cache);
  equal(await answer(first.bytes), 22);
  const fillers = Array.from(
    { length: 140 },
    (_, index) => fn(`unrelated_${index}`, integer(index)),
  );
  const expanded = cached(source([...fillers, ...functions]), cache);
  equal(expanded.created.length, fillers.length);
  equal(expanded.jobs.at(-2), first.jobs[0]);
  equal(await answer(expanded.bytes), 22);
  const reordered = cached(
    source([...functions].reverse().concat(fillers)),
    cache,
  );
  equal(reordered.created, []);
  equal(await answer(reordered.bytes), 22);
  equal(
    array(unwrap(backend["wasm.compile_entries"](first.prepared.jobs))),
    first.entries,
    "balanced native jobs preserve deterministic order",
  );
});

Deno.test("cached codegen relinks constant addresses, captured values, function slots, and constructor tags", async () => {
  const cache = new Map<string, EntryCode>();
  const box = dataType("Box", [variant("Box", u32Type)]);
  const functions = [
    fn(
      "answer",
      matched(
        constant("wrapped"),
        "Box",
        matched(
          apply(
            node("model.ConstructorRefExpr", { constructor: "Box" }),
            apply(constant("adder"), local("payload")),
          ),
          "Box",
          apply(constant("incrementer"), local("payload")),
        ),
      ),
    ),
    fn("increment", add(local("value"), integer(1)), {
      exported: false,
      parameter_type: u32Type,
    }),
  ];
  const constants = (captured: number) => [
    constDefinition("wrapped", construct("Box", integer(2))),
    constDefinition(
      "adder",
      binding(
        "captured",
        integer(captured),
        lambda(71n, "number", add(local("captured"), local("number"))),
      ),
    ),
    constDefinition(
      "incrementer",
      node("model.FunctionExpr", { name: "increment" }),
    ),
  ];
  const first = cached(
    source(functions, {
      data_types: [box],
      constants: constants(40),
    }),
    cache,
  );
  equal(await answer(first.bytes), 43);
  const second = cached(
    source([
      fn("unrelated", matched(constant("padding"), "Box", local("payload"))),
      ...functions,
    ], {
      data_types: [dataType("Unused", [variant("Unused")]), box],
      constants: [
        constDefinition("padding", construct("Box", integer(999))),
        ...constants(41),
      ],
    }),
    cache,
  );
  equal(second.created, ["fn:unrelated"]);
  equal(await answer(second.bytes), 44);
});

Deno.test("nested lambda bodies are independent jobs but capture layouts invalidate their creators", async () => {
  const cache = new Map<string, EntryCode>();
  const program = (body: Node) =>
    source([
      fn("make", binding("other", integer(10), lambda(93n, "number", body)), {
        exported: false,
        parameter_type: u32Type,
      }),
      fn("answer", apply(call("make", integer(40)), integer(2))),
    ]);
  const first = cached(program(add(local("value"), local("number"))), cache);
  const caller = first.jobs.find((job) => job.key === "fn:answer")!;
  ok(
    containsNode(caller.body, "codegen_ir.ApplyExpr"),
    "an outer binding before the returned lambda keeps the ordinary call path",
  );
  equal(await answer(first.bytes), 42);
  const bodyOnly = cached(
    program(add(local("value"), add(local("number"), integer(3)))),
    cache,
  );
  equal(bodyOnly.created, ["lambda:93"]);
  equal(await answer(bodyOnly.bytes), 45);
  const capturesChanged = cached(
    program(add(local("other"), local("number"))),
    cache,
  );
  equal(capturesChanged.created, ["fn:make", "lambda:93"]);
  equal(await answer(capturesChanged.bytes), 12);
});

Deno.test("saturated literal curried calls eliminate intermediate applications and closures", async () => {
  const pair = apply(call("pair", integer(40)), integer(2));
  const triple = apply(
    apply(call("triple", integer(10)), integer(20)),
    integer(12),
  );
  const captured = binding(
    "base",
    integer(40),
    apply(
      apply(
        lambda(
          213n,
          "first",
          lambda(
            214n,
            "second",
            add(local("base"), add(local("first"), local("second"))),
          ),
        ),
        integer(1),
      ),
      integer(1),
    ),
  );
  const result = cached(
    source([
      fn("pair", lambda(210n, "right", add(local("value"), local("right"))), {
        exported: false,
        parameter_type: u32Type,
      }),
      fn(
        "triple",
        lambda(
          211n,
          "middle",
          lambda(
            212n,
            "last",
            add(add(local("value"), local("middle")), local("last")),
          ),
        ),
        { exported: false, parameter_type: u32Type },
      ),
      fn("answer", add(add(pair, triple), captured)),
    ]),
    new Map(),
  );
  equal(await answer(result.bytes), 126);
  const caller = result.jobs.find((job) => job.key === "fn:answer")!;
  ok(!containsNode(caller.body, "codegen_ir.ApplyExpr"));
  ok(!containsNode(caller.body, "codegen_ir.ClosureExpr"));
});

Deno.test("saturated call arguments keep caller bindings when parameter names overlap", async () => {
  const result = cached(
    source([
      fn("pair", lambda(215n, "right", add(local("value"), local("right"))), {
        exported: false,
        parameter_type: u32Type,
      }),
      fn(
        "answer",
        binding(
          "value",
          integer(10),
          apply(
            call("pair", add(local("value"), integer(1))),
            add(local("value"), integer(2)),
          ),
        ),
      ),
    ]),
    new Map(),
  );
  equal(await answer(result.bytes), 23);
});

Deno.test("expanded curried callee body changes invalidate the saturated caller cache", async () => {
  const cache = new Map<string, EntryCode>();
  const program = (body: Node) =>
    source([
      fn("pair", lambda(216n, "right", body), {
        exported: false,
        parameter_type: u32Type,
      }),
      fn("answer", apply(call("pair", integer(40)), integer(2))),
    ]);
  const first = cached(program(add(local("value"), local("right"))), cache);
  equal(await answer(first.bytes), 42);
  const changed = cached(
    program(add(local("value"), add(local("right"), integer(3)))),
    cache,
  );
  equal(await answer(changed.bytes), 45);
  equal([...changed.created].sort(), ["fn:answer", "lambda:216"]);
  const unchanged = cached(
    program(add(local("value"), add(local("right"), integer(3)))),
    cache,
  );
  equal(unchanged.created, []);
});

Deno.test("stored partial applications retain captures across repeated calls", async () => {
  const result = cached(
    source([
      fn("pair", lambda(217n, "right", add(local("value"), local("right"))), {
        exported: false,
        parameter_type: u32Type,
      }),
      fn(
        "answer",
        binding(
          "later",
          call("pair", integer(40)),
          add(
            apply(local("later"), integer(1)),
            apply(local("later"), integer(2)),
          ),
        ),
      ),
    ]),
    new Map(),
  );
  equal(await answer(result.bytes), 83);
  const creator = result.jobs.find((job) => job.key === "fn:pair")!;
  const caller = result.jobs.find((job) => job.key === "fn:answer")!;
  ok(containsNode(creator.body, "codegen_ir.ClosureExpr"));
  ok(containsNode(caller.body, "codegen_ir.ApplyExpr"));
});

Deno.test("annotated saturated array initializers preserve forever carry compaction", async () => {
  const f32Type = node("model.F32Ty");
  const result = cached(
    source([
      fn(
        "seed",
        lambda(
          218n,
          "right",
          node("model.ArrayExpr", {
            elements: list([local("value"), local("right")]),
          }),
        ),
        { exported: false, parameter_type: f32Type },
      ),
      fn(
        "answer",
        binding(
          "seed",
          node("model.SourceExpr", {
            offset: 123n,
            annotation: some(node("model.ArrayTy", { element: f32Type })),
            value: apply(
              call("seed", node("model.F32Expr", { value: 41 })),
              node("model.F32Expr", { value: 42 }),
            ),
          }),
          node("model.BlockExpr", {
            label: 219n,
            body: node("model.ForeverExpr", {
              state: "state",
              initial: local("seed"),
              body: node("model.ReturnExpr", {
                label: 219n,
                value: node("model.ArrayGetExpr", {
                  array: local("state"),
                  index: integer(1),
                }),
              }),
            }),
          }),
        ),
      ),
    ]),
    new Map(),
  );
  equal(await answer(result.bytes), 42);
  const caller = result.jobs.find((job) => job.key === "fn:answer")!;
  ok(!containsNode(caller.body, "codegen_ir.ApplyExpr"));
  ok(!containsNode(caller.body, "codegen_ir.ClosureExpr"));
  equal(caller.body.$, "codegen_ir.LetExpr");
  const block = caller.body.body as Node;
  equal(block.$, "codegen_ir.BlockExpr");
  const loop = block.body as Node;
  equal(loop.$, "codegen_ir.ForeverExpr");

  equal(loop.compact, true);
});

Deno.test("constructor references depend on arity, not unrelated declarations or type annotations", () => {
  const cache = new Map<string, EntryCode>();
  const definitions = [
    fn(
      "reference",
      node("model.ConstructorRefExpr", { constructor: "Choice" }),
      {
        exported: false,
      },
    ),
    fn(
      "answer",
      node("model.SequenceExpr", {
        first: call("reference"),
        next: integer(0),
      }),
    ),
  ];
  const first = cached(
    source(definitions, {
      data_types: [dataType("Choice", [variant("Choice", u32Type)])],
    }),
    cache,
  );
  const second = cached(
    source(definitions, {
      data_types: [dataType("Choice", [variant("Choice")])],
    }),
    cache,
  );
  equal(second.created, ["fn:reference"]);
  equal(first.jobs.length, second.jobs.length + 1);
  const located = source([
    fn(
      "answer",
      node("model.SourceExpr", {
        offset: 987n,
        annotation: some(u32Type),
        value: integer(0),
      }),
    ),
  ]);
  const locations = new Map<string, EntryCode>();
  cached(source([fn("answer", integer(0))]), locations);
  equal(cached(located, locations).created, []);
});

Deno.test("unreachable private functions and constants do not create runtime entries", () => {
  const cache = new Map<string, EntryCode>();
  const first = cached(source([fn("answer", integer(42))]), cache);
  const second = cached(
    source([
      fn("unused", integer(7), { exported: false }),
      fn("answer", integer(42)),
    ], { constants: [constDefinition("unused_constant", integer(9))] }),
    cache,
  );
  equal(second.created, []);
  equal(second.bytes, first.bytes);
});

Deno.test("linking rejects missing, extra, and mismatched cached entry outputs", () => {
  const first = cached(source([fn("answer", integer(42))]), new Map());
  for (
    const entries of [
      [],
      [...first.entries, ...first.entries],
      [{ ...first.entries[0], key: "fn:wrong" }],
    ]
  ) {
    const result = backend["wasm.link"](first.prepared, list(entries));
    ok(result.$ === "Fail");
    equal(result.error.code, "backend_link");
  }
});

Deno.test("indexed relocation lookup rejects cached references to missing symbols", () => {
  const first = cached(source([fn("answer", integer(42))]), new Map());
  for (
    const fragment of [
      node("wasm.NamedCall", { key: "fn:missing" }),
      node("wasm.EntryIndex", { key: "fn:missing" }),
      node("wasm.ConstantReference", { name: "missing" }),
      node("wasm.ConstructorIndex", { name: "missing" }),
    ]
  ) {
    const entry = first.entries[0];
    const result = backend["wasm.link"](
      first.prepared,
      list([{
        ...entry,
        code: { ...entry.code, fragments: list([fragment]) },
      }]),
    );
    ok(result.$ === "Fail");
    equal(result.error.code, "backend_link");
    ok(result.error.subject.endsWith("missing"));
  }
});

Deno.test("chunked assembly matches byte encoders across body and section LEB boundaries", () => {
  for (const length of [0, 1, 125, 126, 127, 128, 16_383, 16_384]) {
    const bytes = Array.from({ length }, (_, index) => index % 256);
    const chunks: List<number>[] = [];
    for (let offset = 0; offset < bytes.length; offset += 113) {
      chunks.push(list(bytes.slice(offset, offset + 113)));
    }
    const plans = list(chunks.map((chunk) => backend["wasm.byte_plan"](chunk)));
    const joined = backend["wasm.plan_sequence"](plans);
    equal(joined.length, BigInt(length));
    equal(array(backend["wasm.plan_finish"](joined)), bytes);
    for (const locals of [2n, 130n]) {
      const body = backend["wasm.body_plan"](joined, locals, 2n);
      const encoded = array(backend["wasm.plan_finish"](body));
      equal(
        encoded,
        array(backend["wasm.body_bytes"](list(bytes), locals, 2n)),
      );
      equal(body.length, BigInt(encoded.length));
    }
    const section = backend["wasm.plan_section"](
      10,
      backend["wasm.plan_vector"](plans),
    );
    const encoded = array(backend["wasm.plan_finish"](section));
    equal(
      encoded,
      array(backend["wasm.section"](10, backend["wasm.vector"](list(chunks)))),
    );
    equal(section.length, BigInt(encoded.length));
  }
});
