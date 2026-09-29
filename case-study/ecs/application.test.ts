import assert from "node:assert/strict";
import { createNativeCompiler } from "../../compiler/native.ts";
import { createGame, renderGame, stepGame } from "./game.ts";
import type { GameEvent } from "./protocol.ts";
import { parseMaterial, parseMesh } from "./asset_store.ts";
import { validateFrame } from "./renderer.ts";
import { component, resource } from "./test_world.ts";

const viewport = { width: 640, height: 480 };
const key = (value: string): GameEvent[] => [
  { tag: "KeyDown", value },
  { tag: "KeyUp", value },
];

Deno.test("an unrelated Blot app owns its scene, ordered systems, input and render descriptions", async () => {
  const compiler = await createNativeCompiler();
  try {
    const source = await Deno.readTextFile(
      new URL("./fixtures/lanterns.blot", import.meta.url),
    );
    const artifact = await compiler.compileApp(source);
    const module = await WebAssembly.compile(artifact.bytes);
    assert.deepEqual(WebAssembly.Module.imports(module), []);
    assert.deepEqual(
      WebAssembly.Module.exports(module).filter((entry) =>
        entry.kind === "function"
      )
        .map((entry) => entry.name).sort(),
      ["event", "render", "start", "update"],
    );
    assert.deepEqual(
      artifact.storage.map((slot) => slot.identity.declaration).sort(),
      [
        "LumenTint",
        "OrbitX",
        "Pulses",
        "Retired",
      ],
    );
    const initial = await createGame(artifact);
    assert.equal(initial.world.entityCount, 3);
    assert.equal(resource(initial, "Pulses"), 2);
    const frame = renderGame(initial, viewport);
    validateFrame(frame);
    assert.equal(frame.draws.length, 3);
    assert.ok(frame.draws.every((draw) => draw.mesh === "lantern.mesh.json"));
    assert.deepEqual(frame.draws.map((draw) => draw.material), [
      "lantern.material.json",
      "blue.material.json",
      "lantern.material.json",
    ]);
    assert.ok(Math.abs(frame.draws[0].transform[12] + 0.6) < 1e-6);
    assert.deepEqual(frame.commands.at(-1), {
      kind: "title",
      title: "Lantern laboratory",
    });
    const before = initial.runtime.exportWorld(initial.world);
    const advance = (game: typeof initial, events: readonly GameEvent[] = []) =>
      stepGame(game, { dt: 0.1, viewport, events, pick: () => undefined });
    const moved = advance(initial);
    assert.equal(
      resource(moved, "Pulses"),
      5,
      "double then increment, not declaration order",
    );
    assert.ok(component(moved, "OrbitX") > component(initial, "OrbitX"));
    const spawned = advance(moved, key("n"));
    assert.equal(spawned.world.entityCount, 4);
    assert.equal(component(spawned, "LumenTint", 3), 1);
    const removed = advance(spawned, key("x"));
    assert.equal(removed.runtime.isAlive(removed.world, 0), false);
    assert.equal(renderGame(removed, viewport).draws.length, 3);
    const commands =
      advance({ ...removed, commands: [] }, [...key("l"), ...key("o")])
        .commands;
    assert.deepEqual(commands, [{ kind: "save" }, { kind: "load" }]);
    assert.deepEqual(initial.runtime.exportWorld(initial.world), before);

    const revisedSource = source
      .replace(
        "  use @ecs.run double_pulses\n  use @ecs.run increment_pulses",
        "  use @ecs.run increment_pulses\n  use @ecs.run double_pulses",
      )
      .replace(
        '@asset.material "lantern.material.json"',
        '@asset.material "checker.material.json"',
      )
      .replace(
        "use @render.clear 0.015 0.025 0.045 1.0",
        "use @render.clear 0.2 0.1 0.05 1.0",
      )
      .replace(
        "#[component]\ndata OrbitX = #OrbitX F32\n#[component]\ndata LumenTint = #LumenTint U32",
        "#[component]\ndata LumenTint = #LumenTint U32\n#[component]\ndata OrbitX = #OrbitX F32",
      );
    assert.notEqual(revisedSource, source);
    const revised = await compiler.compileApp(revisedSource);
    const plan = await removed.runtime.prepareReload(revised);
    const live = advance(removed);
    const latest = live.runtime.exportWorld(live.world);
    const reloaded = { artifact: revised, ...plan.apply(live.world) };
    assert.equal(
      reloaded.world.entityCount,
      4,
      "reload must not rerun startup",
    );
    assert.equal(reloaded.runtime.isAlive(reloaded.world, 0), false);
    assert.equal(resource(reloaded, "Pulses"), resource(live, "Pulses"));
    for (const entity of [1, 2, 3]) {
      assert.equal(
        component(reloaded, "OrbitX", entity),
        component(live, "OrbitX", entity),
      );
      assert.equal(
        component(reloaded, "LumenTint", entity),
        component(live, "LumenTint", entity),
      );
    }
    const next = advance(reloaded);
    assert.equal(
      resource(next, "Pulses"),
      (resource(reloaded, "Pulses") + 1) * 2,
    );
    const nextFrame = renderGame(next, viewport);
    validateFrame(nextFrame);
    assert.equal(nextFrame.clear.r, Math.fround(0.2));
    assert.equal(
      nextFrame.draws.find((draw) => draw.entity === 2)?.material,
      "checker.material.json",
    );
    assert.deepEqual(live.runtime.exportWorld(live.world), latest);
    assert.equal(
      parseMesh(
        await Deno.readFile(
          new URL("./assets/lantern.mesh.json", import.meta.url),
        ),
      ).indices.length,
      24,
    );
    assert.equal(
      parseMaterial(
        await Deno.readFile(
          new URL("./assets/lantern.material.json", import.meta.url),
        ),
      ).shader,
      "scene.wgsl",
    );
  } finally {
    await compiler.dispose();
  }
});
