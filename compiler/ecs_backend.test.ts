import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  compile,
  compileEcs,
  CompilerError,
  type CoreModule,
  type DataType,
  type Descriptor,
  type Expr,
  type Type,
} from "./host.ts";
import {
  add,
  call,
  descriptor,
  fn,
  integer,
  local,
  module,
  read,
  u32Type,
  unit,
} from "./fixtures.ts";
import { createSourceCompiler } from "./source.ts";
import { ecsWorkload } from "./ecs_workload.ts";

const position = descriptor("Position", "Component", "test/ecs");
const velocity = descriptor("Velocity", "Component", "test/ecs");
const frame = descriptor("Frame", "Resource", "test/ecs");
const ghost = descriptor("Ghost", "Component", "test/ecs");
const descriptors = [position, velocity, frame, ghost];
const scalarStorage = (storage: Descriptor): DataType => ({
  identity: storage.identity,
  parameters: 0n,
  constructors: [{ name: storage.identity.declaration, payload: u32Type }],
});
const types: readonly DataType[] = [
  {
    identity: { $: "TypeId", module_name: "test/ecs", declaration: "Choice" },
    parameters: 0n,
    constructors: [{ name: "First", payload: null }, {
      name: "Second",
      payload: null,
    }],
  },
  ...descriptors.map(scalarStorage),
];
const registered = (declaration: Descriptor): Type => ({
  $: "AppliedTy",
  identity: declaration.identity,
  arguments: [],
});
const construct = (constructor: string, payload: Expr): Expr => ({
  $: "ConstructExpr",
  constructor,
  payload,
});
const use = (name: string, value: Expr, body: Expr): Expr => ({
  $: "UseExpr",
  name,
  value,
  body,
});
const extract = (
  value: Expr,
  constructor: string,
  name: string,
  body: Expr,
): Expr => ({
  $: "MatchExpr",
  value,
  arms: [{
    pattern: {
      $: "ConstructorPattern",
      constructor,
      payload: { $: "BindingPattern", name },
    },
    body,
  }],
});
const apply = (callee: Expr, argument: Expr): Expr => ({
  $: "ApplyExpr",
  callee,
  argument,
});

function system(instance: WebAssembly.Instance, name: string) {
  const exported = instance.exports[name];
  ok(typeof exported === "function", `${name} must be a system function`);
  return () => exported(0);
}

async function instantiate(source: CoreModule) {
  const artifact = compileEcs(source);
  ok(WebAssembly.validate(artifact.bytes));
  const values = new Map<number, number>();
  const operations: [string, number, number?][] = [];
  const { instance } = await WebAssembly.instantiate(artifact.bytes, {
    "blot:ecs": {
      read(tag: number) {
        operations.push(["read", tag]);
        ok(values.has(tag), `storage ${tag} must exist before a read`);
        return values.get(tag)!;
      },
      write(tag: number, payload: number) {
        operations.push(["write", tag, payload >>> 0]);
        values.set(tag, payload >>> 0);
        return 987; // The language result is Unit even if the foreign callback is sloppy.
      },
      insert(tag: number, payload: number) {
        operations.push(["insert", tag, payload >>> 0]);
        values.set(tag, payload >>> 0);
        return 654;
      },
    },
  });
  const tag = (constructor: string) => {
    const binding = artifact.storage.find((storage) =>
      storage.constructor === constructor
    );
    ok(binding, `missing storage binding for ${constructor}`);
    return binding.tag;
  };
  return { artifact, instance, values, operations, tag };
}

Deno.test("ECS Wasm links source helpers to typed component and resource storage", async () => {
  const source = module([
    fn("get_position", read(position.identity), { exported: false }),
    fn("set_position", { $: "WriteExpr", value: local("value") }, {
      exported: false,
      parameter_type: registered(position),
    }),
    fn(
      "move",
      use(
        "position",
        call("get_position"),
        use(
          "velocity",
          read(velocity.identity),
          extract(
            local("position"),
            "Position",
            "x",
            extract(
              local("velocity"),
              "Velocity",
              "dx",
              call(
                "set_position",
                construct("Position", add(local("x"), local("dx"))),
              ),
            ),
          ),
        ),
      ),
    ),
    fn(
      "advance_frame",
      use(
        "frame",
        read(frame.identity),
        extract(local("frame"), "Frame", "ticks", {
          $: "WriteExpr",
          value: construct("Frame", add(local("ticks"), integer(1))),
        }),
      ),
    ),
  ], { descriptors, data_types: types });
  const runtime = await instantiate(source);
  equal(
    runtime.artifact.storage.map((
      { constructor, tag, storage },
    ) => [constructor, tag, storage.$]),
    [
      ["Frame", 4, "Resource"],
      ["Position", 2, "Component"],
      ["Velocity", 3, "Component"],
    ],
  );
  runtime.values.set(runtime.tag("Position"), 40);
  runtime.values.set(runtime.tag("Velocity"), 2);
  runtime.values.set(runtime.tag("Frame"), 10);
  equal(system(runtime.instance, "move")(), 0);
  equal(system(runtime.instance, "advance_frame")(), 0);
  equal(runtime.values.get(runtime.tag("Position")), 42);
  equal(runtime.values.get(runtime.tag("Frame")), 11);
  equal(runtime.operations, [
    ["read", 2],
    ["read", 3],
    ["write", 2, 42],
    ["read", 4],
    ["write", 4, 11],
  ]);
  equal(
    WebAssembly.Module.imports(new WebAssembly.Module(runtime.artifact.bytes)),
    [
      { module: "blot:ecs", name: "read", kind: "function" },
      { module: "blot:ecs", name: "write", kind: "function" },
      { module: "blot:ecs", name: "insert", kind: "function" },
    ],
  );
  throws(
    () => compile(source),
    (error) =>
      error instanceof CompilerError && error.code === "backend_effect",
  );
});

Deno.test("ECS Wasm evaluates write payloads once and preserves U32 insertion bits", async () => {
  const runtime = await instantiate(module([
    fn("copy", { $: "WriteExpr", value: read(position.identity) }),
    fn("spawn", {
      $: "InsertExpr",
      value: construct("Ghost", integer(0xffff_ffff)),
    }),
  ], { descriptors, data_types: types }));
  runtime.values.set(runtime.tag("Position"), 0xffff_ffff);
  equal(system(runtime.instance, "copy")(), 0);
  equal(system(runtime.instance, "spawn")(), 0);
  equal(runtime.operations, [["read", 2], ["write", 2, 0xffff_ffff], [
    "insert",
    5,
    0xffff_ffff,
  ]]);
});

Deno.test("ECS imports preserve direct calls, closure tables, and serialized function references", async () => {
  const runtime = await instantiate(module([
    fn("increment", add(local("value"), integer(1)), {
      exported: false,
      parameter_type: u32Type,
    }),
    fn("make_adder", {
      $: "LambdaExpr",
      identity: 1n,
      parameter: "extra",
      parameter_type: null,
      result_type: null,
      body: add(local("value"), local("extra")),
    }, { exported: false, parameter_type: u32Type }),
    fn(
      "update",
      use(
        "position",
        read(position.identity),
        extract(local("position"), "Position", "number", {
          $: "WriteExpr",
          value: construct(
            "Position",
            apply(
              { $: "ConstantExpr", name: "increment_alias" },
              apply(
                { $: "FunctionExpr", name: "increment" },
                apply(call("make_adder", local("number")), integer(1)),
              ),
            ),
          ),
        }),
      ),
    ),
  ], {
    descriptors,
    data_types: types,
    constants: [{
      name: "increment_alias",
      exported: false,
      annotation: null,
      value: { $: "FunctionExpr", name: "increment" },
    }],
  }));
  runtime.values.set(runtime.tag("Position"), 39);
  equal(system(runtime.instance, "update")(), 0);
  equal(runtime.values.get(runtime.tag("Position")), 42);
});

Deno.test("ECS schema includes private helper effects, while effect-free modules need no imports", async () => {
  const withHelper = compileEcs(module([
    fn("private_read", read(frame.identity), { exported: false }),
    fn("noop", unit),
  ], { descriptors, data_types: types }));
  equal(withHelper.storage.map(({ constructor }) => constructor), ["Frame"]);
  ok(WebAssembly.validate(withHelper.bytes));

  const pure = compileEcs(module([fn("noop", unit)]));
  equal(pure.storage, []);
  equal(WebAssembly.Module.imports(new WebAssembly.Module(pure.bytes)), []);
  const { instance } = await WebAssembly.instantiate(pure.bytes);
  equal(system(instance, "noop")(), 0);
});

Deno.test("ECS linking rejects storage without a single concrete U32 payload layout", () => {
  const systemSource = (data_types: readonly DataType[]) =>
    module([
      fn("read_and_discard", use("position", read(position.identity), unit)),
    ], { descriptors: [position], data_types });
  const unsupported: readonly (readonly DataType[])[] = [
    [],
    [{
      ...scalarStorage(position),
      constructors: [{ name: "Position", payload: null }],
    }],
    [{
      ...scalarStorage(position),
      constructors: [{ name: "Position", payload: { $: "BoolTy" } }],
    }],
    [{
      ...scalarStorage(position),
      constructors: [{ name: "Position", payload: u32Type }, {
        name: "Missing",
        payload: null,
      }],
    }],
  ];
  for (const declaration of unsupported) {
    throws(
      () => compileEcs(systemSource(declaration)),
      (error) =>
        error instanceof CompilerError && error.code === "backend_ecs_layout",
    );
  }
  throws(
    () =>
      compileEcs(
        systemSource([{ ...scalarStorage(position), parameters: 1n }]),
      ),
    (error) =>
      error instanceof CompilerError && error.code === "generic_storage_type",
  );
});

Deno.test("ECS metadata reports the first canonical layout error regardless of declaration order", () => {
  const alpha = descriptor("Alpha", "Component", "layout/errors");
  const zeta = descriptor("Zeta", "Component", "layout/errors");
  const invalid: readonly DataType[] = [
    {
      ...scalarStorage(zeta),
      constructors: [{ name: "Zeta", payload: null }],
    },
    {
      ...scalarStorage(alpha),
      constructors: [{ name: "Alpha", payload: { $: "BoolTy" } }],
    },
  ];
  for (const declarations of [invalid, [...invalid].reverse()]) {
    const program = module([
      fn("zeta", read(zeta.identity), { exported: false }),
      fn("alpha", read(alpha.identity), { exported: false }),
      fn("noop", unit),
    ], { descriptors: [zeta, alpha], data_types: declarations });
    throws(
      () => compileEcs(program),
      (error) =>
        error instanceof CompilerError &&
        error.code === "backend_ecs_layout" &&
        error.subject === "layout/errors::Alpha",
    );
  }
});

Deno.test("ECS exported systems must be Unit to Unit", () => {
  for (
    const definition of [
      fn("bad_result", integer(1)),
      fn("bad_parameter", unit, { parameter_type: u32Type }),
    ]
  ) {
    throws(
      () => compileEcs(module([definition])),
      (error) =>
        error instanceof CompilerError &&
        error.code === "backend_ecs_signature",
    );
  }
});

Deno.test("ECS Wasm retains private arena reset across repeated system calls", async () => {
  const runtime = await instantiate(module([
    fn(
      "increment",
      use(
        "position",
        read(position.identity),
        extract(local("position"), "Position", "number", {
          $: "WriteExpr",
          value: construct("Position", add(local("number"), integer(1))),
        }),
      ),
    ),
  ], { descriptors, data_types: types }));
  runtime.values.set(runtime.tag("Position"), 0);
  const increment = system(runtime.instance, "increment");
  for (let i = 0; i < 5000; i++) equal(increment(), 0);
  equal(runtime.values.get(runtime.tag("Position")), 5000);
  equal(
    WebAssembly.Module.exports(new WebAssembly.Module(runtime.artifact.bytes)),
    [
      { name: "increment", kind: "function" },
    ],
  );
});

Deno.test("ECS Wasm serializes and executes a 64-system code section without host recursion", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compileEcs(ecsWorkload(64));
    equal(artifact.analysis.world.systems.length, 64);
    equal(artifact.storage.length, 129);
    ok(
      artifact.bytes.length > 16_384,
      "exercise a byte section larger than the old recursive traversal limit",
    );
    ok(WebAssembly.validate(artifact.bytes));
    const writes = new Map<number, number>();
    let readCount = 0;
    const { instance } = await WebAssembly.instantiate(artifact.bytes, {
      "blot:ecs": {
        read() {
          readCount++;
          return 1;
        },
        write(tag: number, payload: number) {
          writes.set(tag, payload);
          return 0;
        },
        insert() {
          throw new Error("movement systems do not insert storage");
        },
      },
    });
    for (const plan of artifact.analysis.world.systems) {
      equal(system(instance, plan.name)(), 0);
    }
    equal(readCount, 192);
    equal(writes.size, 64);
    equal([...writes.values()], Array.from({ length: 64 }, () => 2));
  } finally {
    compiler.dispose();
  }
});
