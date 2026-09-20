import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";
import { createEcsRuntime } from "./ecs_runtime.ts";
import { ecsWorkload } from "./ecs_workload.ts";
import type { TypeId } from "./host.ts";

const identity = (declaration: string): TypeId => ({
  $: "TypeId",
  module_name: "main",
  declaration,
});

Deno.test("gdev-style source ECS executes with inferred queries and ordered resources", async () => {
  const compiler = await createSourceCompiler();
  try {
    const source = await Deno.readTextFile(
      new URL("../examples/ecs_runtime.blot", import.meta.url),
    );
    const artifact = compiler.compileEcs(source);
    ok(WebAssembly.validate(artifact.bytes));
    const { systems } = artifact.analysis.world;
    equal(
      systems.find((system) => system.name === "move")?.query.map((
        descriptor,
      ) => descriptor.identity.declaration),
      ["Position", "Velocity"],
    );
    equal(
      systems.find((system) => system.name === "add_ghost")?.query.map(
        (descriptor) => descriptor.identity.declaration,
      ),
      ["Position"],
    );
    equal(
      systems.find((system) => system.name === "increment")?.query,
      [],
    );
    equal(
      artifact.analysis.functions.find((fn) => fn.name === "write_position")
        ?.parameter,
      { $: "AppliedTy", identity: identity("Position"), arguments: [] },
    );
    const runtime = await createEcsRuntime(artifact);
    const initial = runtime.createWorld({
      entityCount: 4,
      components: [
        { identity: identity("Position"), values: [2, 100, 8, null] },
        { identity: identity("Velocity"), values: [3, null, 4, 99] },
        { identity: identity("Visits"), values: [0, 0, null, null] },
      ],
      resources: [
        { identity: identity("DeltaTime"), value: 2 },
        { identity: identity("Counter"), value: 0 },
      ],
    });
    const next = runtime.run(initial);
    equal(
      [0, 1, 2, 3].map((entity) =>
        runtime.readComponent(next, identity("Position"), entity)
      ),
      [8, 100, 16, null],
    );
    equal(
      [0, 1, 2, 3].map((entity) =>
        runtime.readComponent(next, identity("Velocity"), entity)
      ),
      [2, null, 2, 2],
    );
    equal(runtime.readComponent(next, identity("Visits"), 0), 1);
    equal(runtime.readComponent(next, identity("Visits"), 1), 1);
    equal(runtime.readResource(next, identity("Counter")), 2);
    equal(
      [0, 1, 2, 3].map((entity) =>
        runtime.readComponent(next, identity("Ghost"), entity)
      ),
      [3, 3, 3, null],
    );
    equal(runtime.readComponent(initial, identity("Position"), 0), 2);
    equal(runtime.readComponent(initial, identity("Ghost"), 0), null);
    equal(runtime.readResource(initial, identity("Counter")), 0);
    equal(
      runtime.readComponent(runtime.run(initial), identity("Position"), 0),
      8,
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("ECS get resolves a type name independently of its constructor", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compileEcs(`
#[component] data Position = At U32
export fn move () => do:
  use position <- @ecs.get Position
  let At value = position
  use @ecs.set (At (value + 1))
  return ()
`);
    equal(artifact.storage[0].identity, identity("Position"));
    equal(artifact.storage[0].constructor, "At");
    const runtime = await createEcsRuntime(artifact);
    const initial = runtime.createWorld({
      entityCount: 1,
      components: [{ identity: identity("Position"), values: [41] }],
      resources: [],
    });
    equal(
      runtime.readComponent(runtime.run(initial), identity("Position"), 0),
      42,
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("ECS source rejects unsupported tags, implicit providers and invalid accesses", async () => {
  const compiler = await createSourceCompiler();
  try {
    const declaration = "#[component]\ndata Position = Position U32\n";
    const cases = [
      ["#[anything]\ndata Position = Position U32", "unsupported_attribute"],
      ["#[component]\nfn move () => ()", "storage_attribute"],
      [
        "#[component]\n#[resource]\ndata Position = Position U32",
        "storage_attribute",
      ],
      ["#[component]\ndata Box a = Box a", "generic_storage_type"],
      [
        "data Position = Position U32\nexport fn move () => @ecs.get Position",
        "unknown_storage",
      ],
      [declaration + "export fn move () => @ecs.get missing", "storage_type"],
      [
        declaration + "export fn move () => @ecs.get (Position 1)",
        "storage_type",
      ],
      [
        declaration + "export fn move () => @ecs.get Position Position",
        "call_arity",
      ],
      [declaration + "export fn move () => @ecs.set", "call_arity"],
      [
        declaration + "export fn move () => @ecs.set 1",
        "invalid_storage_access",
      ],
      [declaration + "const position = @ecs.get Position", "const_effect"],
      [
        declaration +
        "export fn move () => do:\n  let position = @ecs.get Position\n  return ()",
        "let_effect",
      ],
    ];
    for (const [source, code] of cases) {
      throws(() => compiler.analyze(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, `${source}\n${error.message}`);
        return true;
      });
    }
    throws(
      () =>
        compiler.compile(
          declaration + "export fn move () => @ecs.set (Position 1)",
        ),
      (error) =>
        error instanceof SourceError && error.code === "backend_effect",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("scaled ECS workload compiles independent systems and executes every generated query", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compileEcs(ecsWorkload(8));
    equal(artifact.analysis.world.systems.length, 8);
    equal(artifact.analysis.world.registrations.length, 17);
    equal(artifact.analysis.world.batches.length, 1);
    const runtime = await createEcsRuntime(artifact);
    const initial = runtime.createWorld({
      entityCount: 2,
      components: Array.from({ length: 8 }, (_, index) => [
        { identity: identity(`Position${index}`), values: [index, 100] },
        { identity: identity(`Velocity${index}`), values: [2, null] },
      ]).flat(),
      resources: [{ identity: identity("DeltaTime"), value: 3 }],
    });
    const next = runtime.run(initial);
    for (let index = 0; index < 8; index++) {
      equal(
        runtime.readComponent(next, identity(`Position${index}`), 0),
        index + 6,
      );
      equal(runtime.readComponent(next, identity(`Position${index}`), 1), 100);
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("ECS nominal diagnostics point to their source type declaration", async () => {
  const compiler = await createSourceCompiler();
  try {
    for (
      const [declaration, body, code] of [
        ["Box a = Box a", "", "generic_storage_type"],
        [
          "Position = Position Bool",
          "export fn set_position () => @ecs.set (Position True)",
          "backend_ecs_layout",
        ],
      ]
    ) {
      const source =
        `const unrelated = 1\n\n#[component]\ndata ${declaration}\n${body}\n`;
      throws(() => compiler.compileEcs(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code);
        equal(error.start, source.indexOf(declaration));
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});
