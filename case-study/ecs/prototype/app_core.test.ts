// Archived compiler-coupled prototype; not part of the current compiler.
import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createSourceSession } from "./source_session.ts";
import {
  type Capability,
  CompilerError,
  type Effect,
  effectsConflict,
} from "./host.ts";
import { SourceError } from "./syntax.ts";
import {
  bendArray,
  type BendList,
  bendList,
  type CheckedGroup,
  type GroupInterface,
  type GroupJob,
  invoke,
  type RawModule,
  result,
  structuralKey,
} from "./pipeline.ts";

const matrix =
  "1.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 1.0";

const application = `
#[component] data Position = #Position F32
#[component] data Velocity = #Velocity F32
#[resource] data Counter = #Counter U32
const cube: MeshAsset = @asset.mesh "models/cube.mesh.json"
const brass: MaterialAsset = @asset.material "materials/brass.json"

const store = fn value => @ecs.set value
const move = fn () => do:
  use position <- @ecs.get #Position
  use store position
  return ()
const draw = fn () => do:
  use previous <- @ecs.previous #Position
  use velocity <- @ecs.get #Velocity
  use entity <- @ecs.entity ()
  use @render.draw cube brass #True entity ${matrix}
  return ()
const start = fn () => do:
  use @window.title "Blot guest"
  use entity <- @ecs.spawn ()
  use @ecs.at entity initialize
  return ()
const initialize = fn () => do:
  use @ecs.insert (#Position 1.0)
  use @ecs.insert (#Velocity 2.0)
  use @ecs.set (#Counter 0)
  return ()
const event = fn () => do:
  use kind <- @input.event_kind ()
  use @window.save ()
  use @window.load ()
  return ()
const update = fn () => do:
  use @ecs.run move
  return ()
const render = fn () => do:
  use @render.clear 0.1 0.2 0.3 1.0
  use @render.ambient 0.2 0.2 0.2
  use @render.light_direction 0.0 1.0 0.0
  use @render.light_color 1.0 1.0 1.0
  use @render.view ${matrix}
  use @render.projection ${matrix}
  use @ecs.run draw
  return ()
`;

function grouped(module: RawModule) {
  const jobs = bendArray(result<BendList<GroupJob>>(
    "groups.plan",
    module,
  ));
  const interfaces = new Map<string, GroupInterface>();
  for (const job of jobs) {
    const dependencies = bendArray(job.dependencies).map((name) => {
      const found = interfaces.get(name);
      ok(found, `dispatch dependency ${name} must have a closed interface`);
      return found;
    });
    const subset = result<RawModule>("groups.job_module", module, job);
    const checked = result<CheckedGroup>(
      "groups.check_group",
      subset,
      bendList(dependencies),
    );
    for (const signature of bendArray(checked.interfaces)) {
      interfaces.set(signature.name, signature);
    }
  }
  const whole = result<CheckedGroup>(
    "groups.checked_group",
    result("check.check_module", module),
  );
  const ordered = (values: readonly GroupInterface[]) =>
    [...values].sort((a, b) => a.name.localeCompare(b.name));
  equal(
    ordered([...interfaces.values()]),
    ordered(bendArray(whole.interfaces)),
  );
  return { jobs, interfaces };
}

Deno.test("app dispatch preserves independent systems and ordinary monomorphic helpers", async () => {
  const frontend = await createSourceSession({ prelude: "none" });
  try {
    const source = frontend.prepare(application).module;
    const checked = grouped(source);
    const members = checked.jobs.map((job) => bendArray(job.members).sort());
    ok(members.some((names) => names.join(",") === "move,store"));
    for (
      const name of ["update", "render", "start", "event", "draw", "initialize"]
    ) {
      ok(
        members.some((names) => names.length === 1 && names[0] === name),
        name,
      );
    }
    const update = checked.interfaces.get("update")!;
    equal(bendArray(update.effects), [{
      $: "EngineEffect",
      capability: { $: "model.Dispatch" },
    }]);
    const before = result("groups.prepare_plan", source);
    const repeated = frontend.prepare(application.replace(
      "use @ecs.run move",
      "use @ecs.run move\n  use @ecs.run move",
    )).module;
    equal(
      structuralKey(result("groups.prepare_plan", repeated)),
      structuralKey(before),
    );
  } finally {
    frontend.dispose();
  }
});

Deno.test("typed engine intrinsics expose capabilities without fake storage registrations", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const checked = compiler.analyze(application);
    const draw = checked.functions.find((fn) => fn.name === "draw")!;
    equal(
      draw.effects.filter((effect) => effect.$ === "Effect").map((effect) =>
        `${effect.access.$} ${effect.descriptor.identity.declaration}`
      ).sort(),
      ["Previous Position", "Read Velocity"],
    );
    for (const system of checked.world.systems) equal(system.query, []);
    const fields = [
      ["event_kind", "U32Ty"],
      ["key", "U32Ty"],
      ["button", "U32Ty"],
      ["picked", "U32Ty"],
      ["pick_valid", "U32Ty"],
      ["pointer_x", "F32Ty"],
      ["pointer_y", "F32Ty"],
      ["wheel_delta", "F32Ty"],
      ["delta_time", "F32Ty"],
      ["viewport_width", "F32Ty"],
      ["viewport_height", "F32Ty"],
      ["alpha", "F32Ty"],
      ["hit_x", "F32Ty"],
      ["hit_y", "F32Ty"],
      ["hit_z", "F32Ty"],
    ];
    for (const [field, type] of fields) {
      const actual = compiler.analyze(
        `const value = fn () => @input.${field} ()\n`,
      );
      equal(actual.functions[0].result, { $: type });
      equal(actual.functions[0].effects, [{
        $: "EngineEffect",
        capability: { $: "InputRead" },
      }]);
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("literal asset references remain typed pure constants and preserve Unicode and escapes", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const checked = compiler.analyze(String.raw`
const identity = fn value => value
const mesh: MeshAsset = identity (@asset.mesh "models/猫//cube\"name.mesh.json")
const material: MaterialAsset = @asset.material "materials/brass.json"
const title = fn () => @window.title "Game\n\t\"guest\""
`);
    equal(checked.constants, [
      {
        name: "mesh",
        value: {
          $: "AssetValue",
          kind: { $: "MeshAsset" },
          path: 'models/猫//cube"name.mesh.json',
        },
      },
      {
        name: "material",
        value: {
          $: "AssetValue",
          kind: { $: "MaterialAsset" },
          path: "materials/brass.json",
        },
      },
    ]);
    equal(checked.functions.find((fn) => fn.name === "title")!.effects, [
      { $: "EngineEffect", capability: { $: "PlatformWrite" } },
    ]);
  } finally {
    compiler.dispose();
  }
});

Deno.test("engine operations cannot escape purity or typed static dispatch boundaries", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const failures: readonly (readonly [string, string])[] = [
      [
        "const f = fn () => do:\n  let x = @ecs.spawn ()\n  return x",
        "let_effect",
      ],
      ["const x = @input.key ()", "const_effect"],
      [
        "const f = fn () => fn value => @input.key ()",
        "effectful_function_value",
      ],
      [
        "const effect = fn () => @input.key ()\nconst f = effect",
        "effectful_function_value",
      ],
      ["const effect = fn () => ()\nconst x = @ecs.run effect", "const_effect"],
      [
        "const effect = fn () => ()\nconst f = fn () => do:\n  let x = @ecs.run effect\n  return ()",
        "let_effect",
      ],
      [
        "const effect = fn (x: U32) => ()\nconst f = fn () => @ecs.run effect",
        "system_signature",
      ],
      [
        "const effect = fn () => 1\nconst f = fn () => @ecs.run effect",
        "system_signature",
      ],
      [
        "const identity = fn x => x\nconst f = fn () => @ecs.run identity",
        "system_signature",
      ],
      ["const effect = 1\nconst f = fn () => @ecs.run effect", "system_target"],
      ["const f = fn () => @ecs.run (fn x => x)", "system_target"],
      [
        "const effect = fn () => ()\nconst f = fn () => @ecs.at 1.0 effect",
        "type_mismatch",
      ],
      ["const f = fn () => @input.key", "call_arity"],
      ["const f = fn () => @input.key 1", "call_arity"],
      ["const f = fn () => @ecs.despawn ()", "type_mismatch"],
      ["const f = fn () => @render.clear 1.0 1.0 1.0", "call_arity"],
      ["const f = fn () => @render.clear 1 1.0 1.0 1.0", "type_mismatch"],
      ["const path = 1\nconst mesh = @asset.mesh path", "literal_required"],
      ['const mesh: MaterialAsset = @asset.mesh "cube"', "type_mismatch"],
      [
        `const f = fn () => @render.draw (@asset.material "x") (@asset.mesh "x") #True 0 ${matrix}`,
        "type_mismatch",
      ],
      [
        "data Position = #Position F32\nconst f = fn () => @ecs.previous #Position",
        "unknown_storage",
      ],
      [
        'const f = fn () => do:\n  use @panic "broken"\n  let x = @input.key ()\n  return ()',
        "let_effect",
      ],
      [
        "const unused = fn () => @render.clear #True 0.0 0.0 1.0\nconst start = fn () => ()",
        "type_mismatch",
      ],
    ];
    for (const [source, code] of failures) {
      throws(
        () => compiler.analyze(source + "\n"),
        (error) =>
          (error instanceof CompilerError || error instanceof SourceError) &&
          error.code === code,
        source,
      );
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("panic joins branches as Never and does not fake a return value", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const checked = compiler.analyze(`
const validate = fn value => do:
  if value:
    use @panic "invalid value"
  return 42
const answer = fn () => validate #False
`);
    equal(checked.functions[0].result, { $: "U32Ty" });
    equal(checked.functions[1].result, { $: "U32Ty" });
    equal(checked.functions[1].effects, [{
      $: "EngineEffect",
      capability: { $: "PlatformWrite" },
    }]);
  } finally {
    compiler.dispose();
  }
});

Deno.test("engine effect equality, indexed unions and scheduling agree with explicit capabilities", () => {
  const engine = (capability: string) => ({
    $: "EngineEffect",
    capability: { $: `model.${capability}` },
  });
  const storage = {
    $: "Effect",
    access: { $: "model.Previous" },
    descriptor: {
      $: "Descriptor",
      identity: { $: "TypeId", module_name: "main", declaration: "Position" },
      storage: { $: "model.Component" },
    },
  };
  const values = [
    engine("InputRead"),
    storage,
    engine("FrameWrite"),
    engine("EntityRead"),
    engine("PlatformWrite"),
    engine("Dispatch"),
  ];
  equal(
    bendArray(
      invoke(
        "effects.union",
        bendList([...values, ...values]),
        bendList(values),
      ),
    ),
    values,
  );
  equal(bendArray(invoke("effects.registrations", bendList(values))), [
    storage.descriptor,
  ]);
  equal(bendArray(invoke("effects.query", bendList(values))), [
    storage.descriptor,
  ]);
  const publicEngine = (
    capability: Capability["$"],
  ): Effect => ({ $: "EngineEffect", capability: { $: capability } });
  const input = publicEngine("InputRead");
  const frame = publicEngine("FrameWrite");
  equal(effectsConflict(input, input), false);
  equal(effectsConflict(frame, frame), true);
  equal(effectsConflict(frame, input), false);
  for (
    const capability of [
      "InputRead",
      "FrameWrite",
      "EntityRead",
      "WorldStructure",
      "Dispatch",
      "PlatformWrite",
    ] as const
  ) {
    equal(
      effectsConflict(publicEngine("Dispatch"), publicEngine(capability)),
      true,
    );
    equal(
      effectsConflict(publicEngine(capability), publicEngine("WorldStructure")),
      true,
    );
  }
  const plans = [
    "InputRead",
    "InputRead",
    "FrameWrite",
    "FrameWrite",
    "Dispatch",
    "InputRead",
  ].map((capability, index) => ({
    $: "SystemPlan",
    name: String(index),
    effects: bendList([engine(capability)]),
    query: bendList([]),
  }));
  const batches = bendArray(
    invoke<BendList<BendList<string>>>(
      "schedule.batches",
      bendList(plans),
    ),
  ).map(bendArray);
  equal(batches, [["0", "1", "2"], ["3"], ["4"], ["5"]]);
});
