import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createNativeCompiler } from "../../compiler/native.ts";
import type { EcsArtifact } from "../../compiler/host.ts";
import { createGame, type Game, renderGame, stepGame } from "./game.ts";
import type { GameEvent, PickHit } from "./protocol.ts";
import { validateFrame } from "./renderer.ts";
import { component, noEntity, resource } from "./test_world.ts";

const viewport = { width: 800, height: 600 };
const center = { x: 400, y: 300 };
const hit: PickHit = {
  entity: 0,
  draw_index: 1,
  distance: 5,
  position: { x: -1.4, y: 0, z: 0 },
};
const key = (value: string): readonly GameEvent[] => [
  { tag: "KeyDown", value },
  { tag: "KeyUp", value },
];
const tick = (
  game: Game,
  events: readonly GameEvent[] = [],
  dt = 0,
  pick: () => PickHit | undefined = () => hit,
) => stepGame(game, { events, dt, viewport, pick });

function close(actual: number, expected: number, epsilon = 1e-5): void {
  ok(Math.abs(actual - expected) < epsilon, `${actual} ~= ${expected}`);
}

async function transientMemory(artifact: EcsArtifact): Promise<void> {
  const module = await WebAssembly.compile(artifact.bytes);
  equal(WebAssembly.Module.imports(module), []);
  const instance = await WebAssembly.instantiate(module);
  const exported = (name: string): number => {
    const value = instance.exports[`__blot_${name}`];
    ok(value instanceof WebAssembly.Global);
    return value.value as number;
  };
  const { start, update, render, memory } = instance.exports;
  ok(typeof start === "function" && typeof update === "function");
  ok(typeof render === "function" && memory instanceof WebAssembly.Memory);
  const input = exported("input_base");
  const view = () => new DataView(memory.buffer);
  view().setFloat32(input + 32, 1 / 60, true);
  view().setFloat32(input + 36, viewport.width, true);
  view().setFloat32(input + 40, viewport.height, true);
  view().setFloat32(input + 44, 1, true);
  start(0);
  // Source code owns query execution and world banks. These calls also exceed
  // the scratch heap's capacity unless each entrypoint reclaims temporaries.
  for (let tick = 0; tick < 20_000; tick++) update(0);
  render(0);
  const current = view().getUint32(exported("world_base") + 16, true);
  equal(view().getUint32(current, true), 2);
  const capacity = exported("entity_capacity");
  let offset = 16 + capacity * 4;
  for (const storage of artifact.storage) {
    if (storage.identity.declaration === "RotationY") break;
    offset += storage.storage.$ === "Component" ? capacity * 8 : 8;
  }
  const angle = view().getFloat32(current + offset, true);
  ok(Number.isFinite(angle) && angle >= 0 && angle < 2 * Math.PI);
  equal(view().getUint32(exported("render_base"), true), 3);
}

Deno.test("native-compiled Blot sandbox owns simulation and editor policy", async (test) => {
  const compiler = await createNativeCompiler();
  try {
    const source = await Deno.readTextFile(
      new URL("./game.blot", import.meta.url),
    );
    const artifact = await compiler.compileApp(source);
    ok(WebAssembly.validate(artifact.bytes));
    equal(
      [
        ...new Set(
          artifact.analysis.functions.find((fn) => fn.name === "animate")!
            .effects.flatMap((effect) =>
              effect.$ === "Effect" &&
                effect.descriptor.storage.$ === "Component"
                ? [effect.descriptor.identity.declaration]
                : []
            ),
        ),
      ].sort(),
      ["RotationY", "Spin"],
    );
    equal(
      artifact.analysis.functions.find((fn) => fn.name === "camera_tick")!
        .effects.filter((effect) =>
          effect.$ === "Effect" && effect.descriptor.storage.$ === "Component"
        ),
      [],
    );

    await test.step("F32 animation, camera input, focus loss and snapshots", async () => {
      const initial = await createGame(artifact);
      const before = initial.runtime.exportWorld(initial.world);
      const animated = tick(initial, [], 0.1);
      close(component(animated, "RotationY"), 0.06);
      close(component(animated, "RotationY", 1), 0.54);
      const turning = tick(
        animated,
        [{ tag: "KeyDown", value: "ArrowRight" }],
        0.1,
      );
      ok(resource(turning, "CameraYaw") > resource(animated, "CameraYaw"));
      const held = tick(turning, [], 0.1);
      ok(resource(held, "CameraYaw") > resource(turning, "CameraYaw"));
      const stopped = tick(held, [{ tag: "FocusLost" }], 0.1);
      equal(resource(stopped, "HeldRight"), 0);
      close(resource(stopped, "CameraYaw"), resource(held, "CameraYaw"));
      equal(initial.runtime.exportWorld(initial.world), before);
      const unmapped = tick(initial, [
        { tag: "KeyDown", value: "Ā" },
      ], 0.1);
      equal(resource(unmapped, "HeldLeft"), 0);
      equal(resource(unmapped, "CameraYaw"), resource(initial, "CameraYaw"));
      validateFrame(renderGame(stopped, viewport));
      const middle = renderGame(animated, viewport, {
        previous: initial,
        alpha: 0.5,
      });
      close(middle.draws[1].transform[0], Math.cos(0.03));
      const cameraMiddle = renderGame(turning, viewport, {
        previous: animated,
        alpha: 0.5,
      });
      close(cameraMiddle.view[0], Math.cos(0.47));
    });

    await test.step("ordered one-shots suppress repeats and support upper/lowercase keys", async () => {
      const initial = await createGame(artifact);
      let game = tick(initial, [
        { tag: "KeyDown", value: "TAB" },
        { tag: "KeyDown", value: "Tab" },
      ]);
      equal(resource(game, "Editing"), 1);
      const unchanged = tick(game, [], 0.1);
      equal(component(unchanged, "RotationY"), component(game, "RotationY"));
      game = tick(game, [
        { tag: "KeyUp", value: "tab" },
        ...key("Tab"),
        ...key("tab"),
      ]);
      equal(resource(game, "Editing"), 1);
      game = tick(game, [{ tag: "PointerMove", value: center }, {
        tag: "KeyDown",
        value: "P",
      }, { tag: "KeyDown", value: "p" }]);
      equal(game.world.entityCount, 3);
      equal(resource(game, "Selected"), 2);
      equal(component(game, "Material", 2), 2);
      close(component(game, "ScaleX", 2), 0.75);
      game = tick(game, [
        { tag: "KeyUp", value: "p" },
        ...key("X"),
        ...key("p"),
      ]);
      equal(game.world.entityCount, 4);
      equal(game.runtime.isAlive(game.world, 2), false);
      equal(resource(game, "Selected"), 3);
      equal(initial.world.entityCount, 2);
      equal(initial.runtime.isAlive(initial.world, 0), true);
      const after = tick(game);
      equal(after.world.entityCount, game.world.entityCount);
      equal(resource(after, "Selected"), 3);
      const ignored = tick(after, key("constructor"));
      equal(
        ignored.runtime.exportWorld(ignored.world),
        after.runtime.exportWorld(after.world),
      );
    });

    await test.step("selection, drag offset, scale, rotation, material and removal", async () => {
      let game = tick(await createGame(artifact), [
        ...key("Tab"),
        { tag: "PointerDown", value: { ...center, button: 0 } },
      ]);
      equal(resource(game, "Selected"), 0);
      equal(resource(game, "Dragging"), 1);
      const selectedFrame = renderGame(game, viewport);
      const outline = selectedFrame.draws.filter((draw) =>
        draw.material === "highlight.material.json"
      );
      equal(outline.length, 12);
      ok(outline.every((draw) => draw.entity === 0));
      validateFrame(selectedFrame);
      const startX = component(game, "PositionX");
      const startZ = component(game, "PositionZ");
      const groundX = resource(game, "GroundX");
      const groundZ = resource(game, "GroundZ");
      game = tick(game, [{ tag: "PointerMove", value: { x: 470, y: 340 } }]);
      close(
        component(game, "PositionX"),
        startX + resource(game, "GroundX") - groundX,
      );
      close(
        component(game, "PositionZ"),
        startZ + resource(game, "GroundZ") - groundZ,
      );
      const moved = game;
      game = tick(game, [
        { tag: "PointerUp", value: { x: 470, y: 340, button: 0 } },
        { tag: "PointerMove", value: center },
        ...key("="),
        ...key("R"),
        ...key("m"),
      ]);
      equal(component(game, "PositionX"), component(moved, "PositionX"));
      close(component(game, "ScaleX"), 1.1);
      close(component(game, "RotationY"), Math.PI / 12);
      equal(component(game, "Material"), 1);
      game = tick(game, [...key("-"), ...key("r"), ...key("M")]);
      close(component(game, "ScaleX"), 0.99);
      close(component(game, "RotationY"), Math.PI / 6);
      equal(component(game, "Material"), 2);
      game = tick(game, key("x"));
      equal(game.runtime.isAlive(game.world, 0), false);
      equal(resource(game, "Selected"), noEntity);
      equal(renderGame(game, viewport).draws.length, 2);
      ok(moved.runtime.isAlive(moved.world, 0));
    });

    await test.step("orbit/zoom clamp and empty selection use explicit capabilities", async () => {
      let game = await createGame(artifact);
      game = tick(game, [
        { tag: "Wheel", value: { ...center, delta: -100_000 } },
        { tag: "PointerDown", value: { ...center, button: 2 } },
        { tag: "PointerMove", value: { x: 480, y: 10_000 } },
      ]);
      equal(resource(game, "CameraDistance"), 3);
      close(resource(game, "CameraPitch"), 1.35);
      ok(resource(game, "CameraYaw") !== Math.fround(0.4));
      game = tick(
        game,
        [
          { tag: "PointerUp", value: { ...center, button: 2 } },
          { tag: "Wheel", value: { ...center, delta: 100_000 } },
          ...key("TAB"),
          { tag: "PointerDown", value: { ...center, button: 0 } },
        ],
        0,
        () => undefined,
      );
      equal(resource(game, "CameraDistance"), 24);
      equal(resource(game, "Orbiting"), 0);
      equal(resource(game, "Selected"), noEntity);
      equal(resource(game, "Dragging"), 0);
      validateFrame(renderGame(game, viewport));
    });

    await test.step("code reload preserves held input and latest immutable world", async () => {
      const initial = await createGame(artifact);
      let game = tick(initial, [{ tag: "KeyDown", value: "ArrowLeft" }], 0.1);
      const revised = await compiler.compileApp(
        source.replace("const spin_speed = 0.6", "const spin_speed = 1.2"),
      );
      const plan = await game.runtime.prepareReload(revised);
      game = tick(game, [], 0.1);
      const before = game.runtime.exportWorld(game.world);
      const reloaded = { artifact: revised, ...plan.apply(game.world) };
      equal(reloaded.runtime.exportWorld(reloaded.world), before);
      const next = tick(reloaded, [], 0.1);
      close(
        component(next, "RotationY") - component(reloaded, "RotationY"),
        0.12,
      );
      close(
        resource(next, "CameraYaw"),
        (resource(reloaded, "CameraYaw") - 0.14 + 2 * Math.PI) % (2 * Math.PI),
      );
      equal(game.runtime.exportWorld(game.world), before);
      validateFrame(
        renderGame(next, viewport, { previous: reloaded, alpha: 0.5 }),
      );
    });

    await test.step("invalid clocks/frames fail without changing snapshots", async () => {
      const game = await createGame(artifact);
      const before = game.runtime.exportWorld(game.world);
      for (const dt of [-0.1, 0.3, NaN, Infinity]) {
        throws(() => tick(game, [], dt), /Delta time|finite F32/);
      }
      throws(
        () => tick(game, [{ tag: "PointerMove", value: { x: NaN, y: 0 } }]),
        /finite F32/,
      );
      throws(() => renderGame(game, { width: 0, height: 600 }), /Viewport/);
      throws(() => renderGame(game, viewport, { alpha: NaN }), /finite F32/);
      const seed = game.runtime.exportWorld(game.world);
      throws(() =>
        game.runtime.createWorld({
          ...seed,
          resources: seed.resources!.map((entry) =>
            entry.identity.declaration === "CameraYaw"
              ? { ...entry, value: NaN }
              : entry
          ),
        }), /finite F32/);
      const invalid = {
        ...game,
        world: game.runtime.createWorld({
          ...seed,
          resources: seed.resources!.map((entry) =>
            entry.identity.declaration === "CameraDistance"
              ? { ...entry, value: 0 }
              : entry
          ),
        }),
      };
      throws(
        () => renderGame(invalid, viewport),
        /CameraDistance must be positive/,
      );
      equal(game.runtime.exportWorld(game.world), before);
    });

    await test.step("long-running Wasm ticks reclaim temporary allocations", async () => {
      const game = await createGame(artifact);
      await transientMemory(artifact);
      let current = game;
      for (let frame = 0; frame < 1_000; frame++) {
        current = tick(current, [], 1 / 60);
      }
      validateFrame(renderGame(current, viewport));
      equal(component(game, "RotationY"), 0);
      equal(game.world.entityCount, 2);
    });
  } finally {
    await compiler.dispose();
  }
});
