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
  readonly $: "CodegenJob";
  readonly key: string;
  readonly parameter: string;
  readonly body: Node;
  readonly captures: List<string>;
}
interface EntryCode {
  readonly $: "EntryCode";
  readonly key: string;
  readonly code: {
    readonly $: "Code";
    readonly fragments: List<Node>;
    readonly locals: bigint;
  };
}
interface Prepared {
  readonly jobs: List<Job>;
}
interface BytePlan {
  readonly $: "BytePlan";
  readonly length: bigint;
  readonly chunks: List<List<number>>;
}
const backend = compiled as unknown as {
  analyze(source: Node, steps: bigint): Result<Analysis>;
  "wasm.prepare"(
    checked: Node,
    constants: List<Node>,
    linkage: Node,
  ): Result<Prepared>;
  "wasm.prepare_ecs"(
    checked: Node,
    constants: List<Node>,
  ): Result<Prepared>;
  "wasm.prepared_storage"(prepared: Prepared): List<Node>;
  "ecs_abi.bindings"(checked: Node): Result<List<Node>>;
  "wasm.compile_entry"(job: Job): Result<EntryCode>;
  "wasm.compile_entries"(jobs: List<Job>): Result<List<EntryCode>>;
  "wasm.link"(
    prepared: Prepared,
    entries: List<EntryCode>,
  ): Result<List<number>>;
  "wasm.emit"(checked: Node, constants: List<Node>): Result<List<number>>;
  "wasm.emit_ecs"(checked: Node, constants: List<Node>): Result<List<number>>;
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
const integer = (value: number) => node("U32Expr", { value });
const local = (name: string) => node("LocalExpr", { name });
const constant = (name: string) => node("ConstantExpr", { name });
const call = (callee: string, argument = unit) =>
  node("CallExpr", { callee, argument });
const apply = (callee: Node, argument: Node) =>
  node("ApplyExpr", { callee, argument });
const add = (left: Node, right: Node) =>
  node("ScalarExpr", { operator: node("model.Add"), left, right });
const binding = (name: string, value: Node, body: Node) =>
  node("LetExpr", { name, value, body });
const lambda = (identity: bigint, parameter: string, body: Node) =>
  node("LambdaExpr", {
    identity,
    parameter,
    parameter_type: none,
    result_type: none,
    body,
  });
const construct = (constructor: string, payload: Node | null = null) =>
  node("ConstructExpr", {
    constructor,
    payload: payload === null ? none : some(payload),
  });
const dataType = (name: string, constructors: readonly Node[]) =>
  node("DataType", {
    identity: node("TypeId", {
      module_name: "codegen/test",
      declaration: name,
    }),
    parameters: 0n,
    constructors: list(constructors),
  });
const variant = (name: string, payload: Node | null = null) =>
  node("Constructor", {
    name,
    payload: payload === null ? none : some(payload),
  });
const fn = (
  name: string,
  body: Node,
  options: { exported?: boolean; parameter_type?: Node } = {},
) =>
  node("Function", {
    name,
    exported: options.exported ?? true,
    parameter: "value",
    parameter_type: some(options.parameter_type ?? unitType),
    result_type: none,
    body,
  });
const constDefinition = (name: string, value: Node) =>
  node("Constant", { name, value, exported: false, annotation: none });
const source = (
  functions: readonly Node[],
  options: {
    constants?: readonly Node[];
    data_types?: readonly Node[];
    descriptors?: readonly Node[];
  } = {},
) =>
  node("Module", {
    functions: list(functions),
    constants: list(options.constants ?? []),
    data_types: list(options.data_types ?? []),
    descriptors: list(options.descriptors ?? []),
  });
const matched = (value: Node, constructor: string, body: Node) =>
  node("MatchExpr", {
    value,
    arms: list([
      node("MatchArm", {
        pattern: node("ConstructorPattern", {
          constructor,
          payload: some(node("BindingPattern", { name: "payload" })),
        }),
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

function prepare(program: Node, mode: "pure" | "ecs" = "pure") {
  const analysis = unwrap(backend.analyze(program, 100_000n));
  const prepared = unwrap(
    mode === "pure"
      ? backend["wasm.prepare"](
        analysis.checked,
        analysis.constants,
        node("wasm.PureLink"),
      )
      : backend["wasm.prepare_ecs"](analysis.checked, analysis.constants),
  );
  return { analysis, prepared, jobs: array(prepared.jobs) };
}

function cached(
  program: Node,
  cache: Map<string, EntryCode>,
  mode: "pure" | "ecs" = "pure",
) {
  const prepared = prepare(program, mode);
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
    mode === "pure"
      ? backend["wasm.emit"](
        prepared.analysis.checked,
        prepared.analysis.constants,
      )
      : backend["wasm.emit_ecs"](
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
    (_, index) => fn(`unrelated_${index}`, integer(index), { exported: false }),
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
            node("ConstructorRefExpr", { constructor: "Box" }),
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
    constDefinition("incrementer", node("FunctionExpr", { name: "increment" })),
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
      fn("unrelated", integer(0), { exported: false }),
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

Deno.test("constructor references depend on arity, not unrelated declarations or type annotations", () => {
  const cache = new Map<string, EntryCode>();
  const definitions = [
    fn("reference", node("ConstructorRefExpr", { constructor: "Choice" }), {
      exported: false,
    }),
    fn("answer", integer(0)),
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
      node("SourceExpr", {
        offset: 987n,
        annotation: some(u32Type),
        value: integer(0),
      }),
    ),
  ]);
  equal(cached(located, cache).created, []);
});

Deno.test("cached ECS instructions relocate storage tags and pure entry allocator imports", async () => {
  const cache = new Map<string, EntryCode>();
  const position = dataType("Position", [variant("Position", u32Type)]);
  const identity = node("TypeId", {
    module_name: "codegen/test",
    declaration: "Position",
  });
  const descriptor = node("Descriptor", {
    identity,
    storage: node("model.Component"),
  });
  const pureFunctions = [
    fn(
      "answer",
      node("SequenceExpr", {
        first: apply(node("FunctionExpr", { name: "increment" }), integer(1)),
        next: unit,
      }),
    ),
    fn("increment", add(local("value"), integer(1)), {
      exported: false,
      parameter_type: u32Type,
    }),
  ];
  const first = cached(source(pureFunctions), cache);
  equal(await answer(first.bytes), 0);
  const update = fn(
    "update",
    node("UseExpr", {
      name: "position",
      value: node("ReadExpr", { identity }),
      body: node("WriteExpr", { value: local("position") }),
    }),
  );
  const ecs = (types: readonly Node[]) =>
    source([update, ...pureFunctions], {
      data_types: types,
      descriptors: [descriptor],
    });
  const withImports = cached(ecs([position]), cache, "ecs");
  equal(withImports.created, ["fn:update", "constructor:Position"]);
  const relocated = cached(
    ecs([
      dataType("Other", [variant("First"), variant("Second")]),
      position,
    ]),
    cache,
    "ecs",
  );
  equal(relocated.created, []);
  const operations: unknown[] = [];
  const { instance } = await WebAssembly.instantiate(relocated.bytes, {
    "blot:ecs": {
      read(tag: number) {
        operations.push(["read", tag]);
        return 0xffff_ffff;
      },
      write(tag: number, value: number) {
        operations.push(["write", tag, value >>> 0]);
        return 0;
      },
      insert() {
        throw new Error("unexpected insert");
      },
    },
  });
  const updateSystem = instance.exports.update;
  const pureSystem = instance.exports.answer;
  ok(typeof updateSystem === "function" && typeof pureSystem === "function");
  equal(updateSystem(0), 0);
  equal(pureSystem(0), 0);
  equal(operations, [["read", 2], ["write", 2, 0xffff_ffff]]);
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
      node("NamedCall", { key: "fn:missing" }),
      node("EntryIndex", { key: "fn:missing" }),
      node("ConstantReference", { name: "missing" }),
      node("ConstructorIndex", { name: "missing" }),
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

Deno.test("prepared storage shares canonical metadata without conflating nominal identities", async () => {
  const identities = [
    node("TypeId", { module_name: "a::b", declaration: "c" }),
    node("TypeId", { module_name: "a", declaration: "b::c" }),
    node("TypeId", { module_name: "𐐀", declaration: "é" }),
    node("TypeId", { module_name: "𐐀", declaration: "e\u0301" }),
  ];
  const constructors = ["Left", "Right", "Composed", "Decomposed"];
  const definitions = identities.map((identity, index) =>
    node("DataType", {
      identity,
      parameters: 0n,
      constructors: list([variant(constructors[index], u32Type)]),
    })
  );
  const program = source([
    ...identities.map((identity, index) =>
      fn(
        `copy_${index}`,
        node("UseExpr", {
          name: "component",
          value: node("ReadExpr", { identity }),
          body: node("WriteExpr", { value: local("component") }),
        }),
      )
    ),
    fn("private_read", node("ReadExpr", { identity: identities[0] }), {
      exported: false,
    }),
  ], {
    data_types: definitions,
    descriptors: identities.map((identity) =>
      node("Descriptor", { identity, storage: node("model.Component") })
    ),
  });
  const prepared = cached(program, new Map(), "ecs");
  const storage = array(backend["wasm.prepared_storage"](prepared.prepared));
  equal(
    storage,
    array(unwrap(backend["ecs_abi.bindings"](prepared.analysis.checked))),
  );
  equal(storage.map((binding) => [binding.constructor, binding.tag]), [
    ["Right", 1n],
    ["Left", 0n],
    ["Decomposed", 3n],
    ["Composed", 2n],
  ]);
  equal(
    array(backend["wasm.prepared_storage"](
      prepare(source([fn("answer", integer(0))])).prepared,
    )),
    [],
  );
  const seen: number[] = [];
  const { instance } = await WebAssembly.instantiate(prepared.bytes, {
    "blot:ecs": {
      read(tag: number) {
        seen.push(tag);
        return tag + 10;
      },
      write(tag: number, value: number) {
        equal(value, tag + 10);
        return 0;
      },
      insert() {
        throw new Error("unexpected insert");
      },
    },
  });
  for (let index = 0; index < identities.length; index++) {
    const invoke = instance.exports[`copy_${index}`];
    ok(typeof invoke === "function");
    equal(invoke(0), 0);
  }
  equal(seen, [0, 1, 2, 3]);
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
