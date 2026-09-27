import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type Node = { readonly $: string; readonly [name: string]: unknown };
type List<T> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: T;
  readonly tail: List<T>;
};
type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: { readonly code: string; readonly message: string };
};
type Job = Node & { readonly key: string };
type Entry = Node & { readonly key: string };
const backend = compiled as unknown as {
  "wasm.prepare"(
    checked: Node,
    constants: List<Node>,
  ): Result<{ jobs: List<Job> }>;
  "wasm.compile_entry"(job: Job): Result<Entry>;
  "wasm.link"(prepared: unknown, entries: List<Entry>): Result<List<number>>;
};
const n = ($: string, fields: Record<string, unknown> = {}): Node => ({
  $,
  ...fields,
});
const list = <T>(values: readonly T[]): List<T> =>
  values.reduceRight<List<T>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
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
const none = n("None");
const unit = n("model.UnitExpr");
const unitType = n("model.UnitTy");
const u32 = n("model.U32Ty");
const bool = n("model.BoolTy");
const f32 = n("model.F32Ty");
const foreign = n("model.TypeId", {
  module_name: "blot:compiler",
  declaration: "Foreign",
});
const reader = n("model.TypeId", {
  module_name: "test",
  declaration: "Reader.ask",
});
const row = (operations: readonly Node[] = [], tail = n("model.ClosedRow")) =>
  n("model.EffectRow", { operations: list(operations), tail });
const callback = (parameter = u32, result = u32, effects = row([foreign])) =>
  n("model.FunctionTy", { parameter, result, effects });
const local = (name: string) => n("model.LocalExpr", { name });
const integer = (value: number) => n("model.U32Expr", { value });
const apply = (callee: Node, argument: Node) =>
  n("model.ApplyExpr", { callee, argument });
const call = (callee: string, argument = unit) =>
  n("model.CallExpr", { callee, argument });
const lambda = (identity: bigint, body: Node) =>
  n("model.LambdaExpr", {
    identity,
    parameter: "ignored",
    parameter_type: none,
    result_type: none,
    body,
  });
const bind = (name: string, value: Node, body: Node) =>
  n("model.LetExpr", { name, value, body });
const add = (left: Node, right: Node) =>
  n("model.ScalarExpr", { operator: n("model.Add"), left, right });

function fn(name: string, body: Node, options: {
  parameter?: Node;
  result?: Node;
  effects?: Node;
  exported?: boolean;
} = {}): Node {
  const parameter = options.parameter ?? unitType;
  const result = options.result ?? u32;
  const effects = options.effects ?? row();
  return n("model.CheckedFunction", {
    function: n("model.Function", {
      name,
      exported: options.exported ?? true,
      parameter: "value",
      parameter_type: n("Some", { value: parameter }),
      result_type: n("Some", { value: result }),
      body,
    }),
    signature: n("model.Signature", {
      name,
      parameter,
      result,
      variables: list([]),
      effects,
    }),
    effects: list(
      array(effects.operations as List<Node>).map((identity) =>
        n("model.OperationEffect", { identity })
      ),
    ),
  });
}
interface Constant {
  name: string;
  type: Node;
  value: Node;
  exported?: boolean;
}
function source(functions: readonly Node[], options: {
  constants?: readonly Constant[];
  operations?: readonly Node[];
  data_types?: readonly Node[];
} = {}) {
  const constants = options.constants ?? [];
  return {
    checked: n("model.CheckedModule", {
      functions: list(functions),
      constants: list(
        constants.map(({ name, type, exported }) =>
          n("model.CheckedConstant", {
            constant: n("model.Constant", {
              name,
              exported: exported ?? false,
              annotation: none,
              value: unit,
            }),
            inferred_type: type,
            variables: list([]),
          })
        ),
      ),
      operations: list(options.operations ?? []),
      data_types: list(options.data_types ?? []),
    }),
    constants: list(
      constants.map(({ name, value }) =>
        n("const_eval.Binding", { name, value })
      ),
    ),
  };
}
function build(
  input: ReturnType<typeof source>,
  cache = new Map<string, Entry>(),
) {
  const prepared = unwrap(
    backend["wasm.prepare"](input.checked, input.constants),
  );
  const reused: string[] = [];
  const jobs = array(prepared.jobs);
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
  const bytes = Uint8Array.from(
    array(unwrap(backend["wasm.link"](prepared, list(entries)))),
  );
  ok(WebAssembly.validate(bytes));
  return { bytes, module: new WebAssembly.Module(bytes), jobs, reused };
}
function exportsOf(
  module: WebAssembly.Module,
  imports: WebAssembly.Imports = {},
) {
  return new WebAssembly.Instance(module, imports).exports as Record<
    string,
    (value: unknown) => number
  >;
}
const textEncoder = new TextEncoder();
function leb(value: number): number[] {
  const bytes: number[] = [];
  do {
    const byte = value & 127;
    value >>>= 7;
    bytes.push(byte | (value ? 128 : 0));
  } while (value);
  return bytes;
}
function readerAt(bytes: Uint8Array) {
  let offset = 0;
  return {
    get offset() {
      return offset;
    },
    word() {
      let value = 0, shift = 0, byte: number;
      do {
        ok(offset < bytes.length);
        byte = bytes[offset++];
        value += (byte & 127) * 2 ** shift;
        shift += 7;
      } while (byte & 128);
      return value;
    },
    text() {
      const length = this.word();
      const value = new TextDecoder("utf-8", { fatal: true }).decode(
        bytes.subarray(offset, offset + length),
      );
      offset += length;
      return value;
    },
  };
}
function metadata(module: WebAssembly.Module) {
  const sections = WebAssembly.Module.customSections(module, "blot:abi");
  equal(sections.length, 1);
  const bytes = new Uint8Array(sections[0]);
  const reader = readerAt(bytes);
  equal(reader.word(), 2);
  const functions = Array.from({ length: reader.word() }, () => {
    const name = reader.text();
    const parameter = [reader.word()];
    if (parameter[0] === 4) parameter.push(reader.word(), reader.word());
    return { name, parameter, result: reader.word() };
  });
  const constants = Array.from(
    { length: reader.word() },
    () => ({ name: reader.text(), type: reader.word() }),
  );
  equal(reader.offset, bytes.length);
  return { functions, constants };
}

Deno.test("scalar modules publish exact UTF-8 ABI metadata without ambient imports", () => {
  const built = build(
    source(
      [fn("雪🙂", integer(42)), fn("private", unit, { exported: false })],
      {
        operations: [
          n("model.Operation", {
            identity: reader,
            parameter: unitType,
            result: u32,
          }),
        ],
        constants: [{
          name: "π",
          type: f32,
          value: n("const_eval.F32Value", { value: -0 }),
          exported: true,
        }],
      },
    ),
  );
  equal(WebAssembly.Module.imports(built.module), []);
  equal(metadata(built.module), {
    functions: [{ name: "雪🙂", parameter: [0], result: 1 }],
    constants: [{ name: "π", type: 3 }],
  });
  equal(exportsOf(built.module)["雪🙂"](0), 42);
  const instance = new WebAssembly.Instance(built.module);
  ok(Object.is((instance.exports["π"] as WebAssembly.Global).value, -0));
  equal(metadata(build(source([])).module), { functions: [], constants: [] });
});

Deno.test("all sixteen callback scalar signatures execute through explicit opaque references", () => {
  const scalars = [
    {
      type: unitType,
      name: "unit",
      expression: unit,
      input: 0,
      output: 77,
      expected: 0,
    },
    {
      type: u32,
      name: "u32",
      expression: integer(0x80000000),
      input: -2147483648,
      output: -1,
      expected: -1,
    },
    {
      type: bool,
      name: "bool",
      expression: n("model.BoolExpr", { value: true }),
      input: 1,
      output: 19,
      expected: 1,
    },
    {
      type: f32,
      name: "f32",
      expression: n("model.F32Expr", { value: -0 }),
      input: -0,
      output: -0,
      expected: -0,
    },
  ];
  const functions: Node[] = [];
  const imports: Record<string, (token: unknown, value: number) => number> = {};
  const tokens = new Map<string, object>();
  for (const parameter of scalars) {
    for (const result of scalars) {
      const name = `${parameter.name}_${result.name}`;
      const token = { name };
      tokens.set(name, token);
      imports[`call_${name}`] = (received, value) => {
        equal(received, token);
        ok(Object.is(value, parameter.input));
        return result.output;
      };
      functions.push(fn(name, apply(local("value"), parameter.expression), {
        parameter: callback(parameter.type, result.type),
        result: result.type,
        effects: row([foreign]),
      }));
    }
  }
  const built = build(source(functions));
  equal(
    WebAssembly.Module.imports(built.module).map(({ module, name, kind }) => ({
      module,
      name,
      kind,
    })),
    Object.keys(imports).map((name) => ({
      module: "blot:host/1",
      name,
      kind: "function",
    })),
  );
  const exports = exportsOf(built.module, { "blot:host/1": imports });
  for (const parameter of scalars) {
    for (const result of scalars) {
      ok(
        Object.is(
          exports[`${parameter.name}_${result.name}`](
            tokens.get(`${parameter.name}_${result.name}`),
          ),
          result.expected,
        ),
      );
    }
  }
  equal(
    metadata(built.module).functions,
    scalars.flatMap((parameter, input) =>
      scalars.map((result, output) => ({
        name: `${parameter.name}_${result.name}`,
        parameter: [4, input, output],
        result: output,
      }))
    ),
  );
});

Deno.test("callbacks remain ordinary closures through captures and lexical providers", () => {
  const built = build(source([
    fn(
      "captured",
      bind(
        "thunk",
        lambda(1n, apply(local("value"), integer(40))),
        apply(local("thunk"), unit),
      ),
      {
        parameter: callback(),
        effects: row([foreign]),
      },
    ),
    fn(
      "provided",
      n("model.HandleExpr", {
        provider: n("model.ProviderExpr", {
          identity: reader,
          implementation: local("value"),
        }),
        body: apply(n("model.OperationExpr", { identity: reader }), unit),
      }),
      { parameter: callback(unitType), effects: row([foreign]) },
    ),
    fn("again", apply(local("value"), integer(41)), {
      parameter: callback(),
      effects: row([foreign]),
    }),
  ], {
    operations: [
      n("model.Operation", {
        identity: reader,
        parameter: unitType,
        result: u32,
      }),
    ],
  }));
  equal(WebAssembly.Module.imports(built.module).length, 2);
  const token = {};
  const exports = exportsOf(built.module, {
    "blot:host/1": {
      call_u32_u32: (actual: unknown, value: number) => {
        equal(actual, token);
        return value + 1;
      },
      call_unit_u32: (actual: unknown, value: number) => {
        equal(actual, token);
        equal(value, 0);
        return 42;
      },
    },
  });
  equal(exports.captured(token), 41);
  equal(exports.provided(token), 42);
  equal(exports.again(token), 42);
});

Deno.test("callback export boundaries reject open, mixed, ordinary, and non-scalar signatures", () => {
  const unknown = n("model.AppliedTy", {
    identity: n("model.TypeId", { module_name: "m", declaration: "Box" }),
    arguments: list([]),
  });
  const badParameters = [
    callback(u32, u32, row()),
    callback(u32, u32, row([reader])),
    callback(u32, u32, row([foreign, reader])),
    callback(u32, u32, row([foreign, foreign])),
    callback(u32, u32, row([foreign], n("model.RowVariable", { index: 0n }))),
    callback(unknown),
    callback(u32, callback()),
  ];
  for (const parameter of badParameters) {
    throws(
      () => build(source([fn("bad", integer(0), { parameter })])),
      /backend_type/,
    );
  }
  for (
    const effects of [
      row([reader]),
      row([foreign, reader]),
      row([], n("model.RowVariable", { index: 0n })),
    ]
  ) {
    throws(
      () =>
        build(
          source([fn("bad", integer(0), { parameter: callback(), effects })]),
        ),
      /backend_effect/,
    );
  }
  throws(
    () => build(source([fn("bad", integer(0), { result: callback() })])),
    /backend_type/,
  );
  throws(
    () =>
      build(
        source([fn("no_authority", integer(42), { effects: row([foreign]) })]),
      ),
    /backend_effect/,
  );
});

// A test-only extra export observes cleanup without exposing the capability
// global in the emitted public module or widening the production ABI.
function withObservedCapability(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  let offset = 8;
  while (offset < bytes.length) {
    const start = offset;
    const id = bytes[offset++];
    const length = readerAt(bytes.subarray(offset));
    const size = length.word();
    offset += length.offset;
    const end = offset + size;
    if (id === 7) {
      const section = bytes.subarray(offset, end);
      const count = readerAt(section);
      const entries = count.word();
      const name = textEncoder.encode("test_capability");
      const payload = [
        ...leb(entries + 1),
        ...section.subarray(count.offset),
        ...leb(name.length),
        ...name,
        3,
        1,
      ];
      return Uint8Array.from([
        ...bytes.subarray(0, start),
        7,
        ...leb(payload.length),
        ...payload,
        ...bytes.subarray(end),
      ]);
    }
    offset = end;
  }
  throw new Error("missing export section");
}

Deno.test("wrappers clear successful callback tokens and replace trapped tokens on the next entry", () => {
  const built = build(source([
    fn("invoke", apply(local("value"), integer(1)), {
      parameter: callback(),
      effects: row([foreign]),
    }),
    fn("pure", integer(7)),
  ], {
    constants: [{
      name: "answer",
      type: u32,
      value: n("const_eval.U32Value", { value: 42 }),
      exported: true,
    }],
  }));
  equal(WebAssembly.Module.exports(built.module).map(({ name }) => name), [
    "invoke",
    "pure",
    "answer",
  ]);
  const observed = new WebAssembly.Module(withObservedCapability(built.bytes));
  const error = new Error("host failure");
  const bad = {};
  const good = {};
  const instance = new WebAssembly.Instance(observed, {
    "blot:host/1": {
      call_u32_u32: (token: unknown) => {
        if (token === bad) throw error;
        equal(token, good);
        return 42;
      },
    },
  });
  const exports = instance.exports;
  const invoke = exports.invoke as (token: object) => number;
  const token = exports.test_capability as WebAssembly.Global;
  equal((exports.answer as WebAssembly.Global).value, 42);
  equal(invoke(good), 42);
  equal(token.value, null);
  throws(() => invoke(bad), (thrown) => thrown === error);
  equal(token.value, bad);
  equal((exports.pure as (unit: number) => number)(0), 7);
  equal(token.value, null);
  equal(invoke(good), 42);
  equal(token.value, null);
});

Deno.test("cached function and allocator relocations survive callback imports and table LEB boundaries", () => {
  const cache = new Map<string, Entry>();
  const filler = Array.from(
    { length: 124 },
    (_, index) => fn(`filler_${index}`, integer(index)),
  );
  const base = [
    fn("answer", call("helper", integer(41))),
    fn(
      "saved_answer",
      apply(n("model.ConstantExpr", { name: "saved" }), integer(41)),
    ),
    ...filler,
    fn("helper", add(local("value"), integer(1)), {
      parameter: u32,
      exported: false,
    }),
  ];
  const constants = [{
    name: "saved",
    type: callback(u32, u32, row()),
    value: n("const_eval.FunctionValue", { name: "helper" }),
  }];
  const first = build(source(base, { constants }), cache);
  equal(exportsOf(first.module).answer(0), 42);
  equal(exportsOf(first.module).saved_answer(0), 42);
  const edited = source([
    fn(
      "capability",
      bind(
        "thunk",
        lambda(9n, call("helper", apply(local("value"), integer(40)))),
        apply(local("thunk"), unit),
      ),
      {
        parameter: callback(),
        effects: row([foreign]),
      },
    ),
    ...base,
    fn(
      "second_signature",
      apply(local("value"), n("model.F32Expr", { value: 1.5 })),
      {
        parameter: callback(f32, f32),
        result: f32,
        effects: row([foreign]),
      },
    ),
  ], { constants });
  const cached = build(edited, cache);
  equal(cached.bytes, build(edited).bytes);
  equal(cached.reused.length, base.length);
  const token = {};
  const exports = exportsOf(cached.module, {
    "blot:host/1": {
      call_u32_u32: (actual: unknown, value: number) => {
        equal(actual, token);
        return value + 1;
      },
      call_f32_f32: (actual: unknown, value: number) => {
        equal(actual, token);
        return value + 0.5;
      },
    },
  });
  equal(exports.answer(0), 42);
  equal(exports.saved_answer(0), 42);
  equal(exports.capability(token), 42);
  equal(exports.second_signature(token), 2);
});
