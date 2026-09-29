import assert from "node:assert/strict";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ReloadEvent } from "./code_reload.ts";
import { component, resource } from "./test_world.ts";
import type { GameEvent, RenderFrame } from "./protocol.ts";
import { validateFrame } from "./renderer.ts";
import { createGameRuntime } from "./runtime.ts";

const dt = 1 / 60;
const saves = (frame: RenderFrame) =>
  (frame.commands ?? []).filter((command) => command.kind === "save");
const key = (value: string): GameEvent[] => [
  { tag: "KeyDown", value },
  { tag: "KeyUp", value },
];
const select: GameEvent[] = [
  ...key("Tab"),
  { tag: "PointerDown", value: { x: 320, y: 240, button: 0 } },
  { tag: "PointerUp", value: { x: 320, y: 240, button: 0 } },
];
const close = (actual: number, expected: number) =>
  assert.ok(Math.abs(actual - expected) < 1e-5, `${actual} != ${expected}`);
const replace = (source: string, before: string, after: string) => {
  assert.equal(
    source.split(before).length,
    2,
    `expected one source occurrence: ${before}`,
  );
  return source.replace(before, after);
};

async function fixture(
  options: { readonly ready?: (frame: RenderFrame) => boolean } = {},
) {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-runtime-" });
  const source = await Deno.readTextFile(
    new URL("./game.blot", import.meta.url),
  );
  const sourcePath = join(root, "game.blot");
  await Deno.writeTextFile(sourcePath, source);
  const events: ReloadEvent[] = [];
  const subscribers = new Set<(event: ReloadEvent) => void>();
  const cancellations = new Set<() => void>();
  const viewport = { width: 640, height: 480 };
  let time = 0;
  let watching: Promise<void> | undefined;
  let runtime: Awaited<ReturnType<typeof createGameRuntime>>;
  try {
    runtime = await createGameRuntime({
      sourcePath,
      compilerExecutable: fileURLToPath(
        new URL("../../generated/compiler/blotc", import.meta.url),
      ),
      viewport: () => viewport,
      validate: validateFrame,
      ready: options.ready,
      pick: () => ({
        entity: 0,
        draw_index: 1,
        distance: 1,
        position: { x: 0, y: 0, z: 0 },
      }),
      report(event) {
        events.push(event);
        for (const subscriber of subscribers) subscriber(event);
      },
    });
    runtime.frame({ timestamp: 0, viewport, events: [] });
  } catch (error) {
    await Deno.remove(root, { recursive: true });
    throw error;
  }
  return {
    root,
    source,
    sourcePath,
    runtime,
    events,
    viewport,
    next(kind: ReloadEvent["kind"]): Promise<ReloadEvent> {
      const result = Promise.withResolvers<ReloadEvent>();
      const cancel = () =>
        finish(new Error(`fixture closed while waiting for ${kind}`));
      const timeout = setTimeout(
        () =>
          finish(
            new Error(`timed out waiting for ${kind}: ${
              events.map((event) => event.kind).join(", ")
            }`),
          ),
        10_000,
      );
      const receive = (event: ReloadEvent) => {
        if (event.kind === kind) finish(event);
        else if (event.kind === "failed") {
          finish(
            event.error instanceof Error
              ? event.error
              : new Error(String(event.error)),
          );
        }
      };
      function finish(value: ReloadEvent | Error) {
        clearTimeout(timeout);
        subscribers.delete(receive);
        cancellations.delete(cancel);
        if (value instanceof Error) result.reject(value);
        else result.resolve(value);
      }
      subscribers.add(receive);
      cancellations.add(cancel);
      void result.promise.catch(() => {});
      return result.promise;
    },
    watch() {
      watching = runtime.watch();
      void watching.catch(() => {});
    },
    tick(input: readonly GameEvent[] = [], elapsed = dt) {
      time += elapsed;
      return runtime.frame({ timestamp: time, viewport, events: input });
    },
    at(timestamp: number, input: readonly GameEvent[] = []) {
      time = timestamp;
      return runtime.frame({ timestamp, viewport, events: input });
    },
    async edit(text: string) {
      await Deno.writeTextFile(sourcePath, text);
      await runtime.refresh();
      await runtime.idle();
    },
    async close() {
      for (const cancel of cancellations) cancel();
      try {
        await runtime.close();
        await watching;
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    },
  };
}

Deno.test("runtime watches real source edits while frames advance and publishes queued input once", async () => {
  const test = await fixture();
  let timer: ReturnType<typeof setInterval> | undefined;
  try {
    test.tick(select);
    test.tick([{ tag: "Wheel", value: { x: 320, y: 240, delta: -120 } }]);
    test.tick([{ tag: "KeyDown", value: "ArrowRight" }]);
    const oldRuntime = test.runtime.game.runtime;
    const cameraBefore = resource(test.runtime.game, "CameraYaw");
    const distanceBefore = resource(test.runtime.game, "CameraDistance");
    test.watch();
    const ready = test.next("ready");
    let compilingFrames = 0;
    timer = setInterval(() => {
      if (test.events.at(-1)?.kind === "compiling") {
        test.tick();
        compilingFrames++;
      }
    }, 1);
    await Deno.writeTextFile(
      test.sourcePath,
      replace(test.source, "const spin_speed = 0.6", "const spin_speed = 1.2"),
    );
    await ready;
    clearInterval(timer);
    timer = undefined;
    assert.ok(
      compilingFrames > 0,
      "presentation frames must advance during the native compile",
    );
    assert.ok(resource(test.runtime.game, "CameraYaw") !== cameraBefore);
    const beforePublish = test.runtime.game;
    test.tick([{ tag: "FocusLost" }, ...key("+")], 0);
    assert.equal(
      test.runtime.game.runtime,
      oldRuntime,
      "a ready build waits for a real simulation step",
    );
    const published = test.next("published");
    const render = test.tick();
    await published;
    validateFrame(render);
    const current = test.runtime.game;
    assert.notEqual(current.runtime, oldRuntime);
    assert.equal(current.world.entityCount, beforePublish.world.entityCount);
    assert.equal(resource(current, "Selected"), 0);
    assert.equal(resource(current, "Editing"), 1);
    assert.equal(resource(current, "CameraDistance"), distanceBefore);
    assert.equal(
      resource(current, "CameraYaw"),
      resource(beforePublish, "CameraYaw"),
    );
    assert.equal(
      resource(current, "HeldRight"),
      0,
      "queued focus loss clears held input in the published world",
    );
    close(
      component(current, "ScaleX"),
      component(beforePublish, "ScaleX") * 1.1,
    );
    assert.equal(
      component(beforePublish, "ScaleX"),
      1,
      "the retired world remains immutable",
    );
    test.tick([], 5 * dt);
    close(component(test.runtime.game, "ScaleX"), 1.1);
    const rotation = component(test.runtime.game, "RotationY");
    test.tick(key("Tab"));
    close(component(test.runtime.game, "RotationY") - rotation, 1.2 * dt);
  } finally {
    clearInterval(timer);
    await test.close();
  }
});

Deno.test("runtime rejects invalid source, layout, and first-frame values without losing the old game or pending input", async () => {
  const test = await fixture();
  try {
    test.tick(select);
    const owner = test.runtime.game.runtime;
    const invalid = test.next("failed");
    await test.edit("const broken = fn () => missing\n");
    const sourceFailure = await invalid;
    assert.equal(sourceFailure.kind, "failed");
    assert.equal(test.runtime.game.runtime, owner);
    let layout = replace(
      test.source,
      "data Spin = #Spin F32",
      "data Spin = #Spin U32",
    );
    layout = layout.replaceAll(
      "@ecs.insert (Spin 1.0)",
      "@ecs.insert (Spin 1)",
    );
    layout = replace(
      layout,
      "@ecs.insert (Spin (-1.0))",
      "@ecs.insert (Spin 1)",
    );
    layout = replace(
      layout,
      "(F32.mul spin spin_speed)",
      "(F32.mul (U32.to_f32 spin) spin_speed)",
    );
    const incompatible = test.next("failed");
    await test.edit(layout);
    const layoutFailure = await incompatible;
    assert.equal(layoutFailure.kind, "failed");
    if (layoutFailure.kind === "failed") {
      assert.match(
        String(layoutFailure.error),
        /[Ii]ncompatible reload|scalar layout/,
      );
    }
    assert.equal(test.runtime.game.runtime, owner);
    const badFrame = replace(
      test.source,
      "use @ecs.set (CameraDistance (F32.clamp 3.0 24.0 (F32.add distance (F32.mul (F32.mul zoom dt) 6.0))))",
      "use @ecs.set (CameraDistance 0.0)",
    );
    const ready = test.next("ready");
    await test.edit(badFrame);
    await ready;
    const rejected = test.next("failed");
    const before = test.runtime.game;
    test.tick(key("+"), 0);
    validateFrame(test.tick());
    const failure = await rejected;
    assert.equal(failure.kind, "failed");
    if (failure.kind === "failed") {
      assert.match(String(failure.error), /CameraDistance must be positive/);
    }
    assert.equal(test.runtime.game.runtime, owner);
    assert.equal(
      resource(test.runtime.game, "CameraDistance"),
      resource(before, "CameraDistance"),
    );
    close(component(test.runtime.game, "ScaleX"), 1.1);
    test.tick([], 5 * dt);
    close(component(test.runtime.game, "ScaleX"), 1.1);
    assert.equal(component(before, "ScaleX"), 1);
    const recovered = test.next("ready");
    await test.edit(
      replace(test.source, "const spin_speed = 0.6", "const spin_speed = 1.2"),
    );
    await recovered;
    test.tick();
    assert.notEqual(test.runtime.game.runtime, owner);
    assert.equal(resource(test.runtime.game, "Selected"), 0);
    close(component(test.runtime.game, "ScaleX"), 1.1);
  } finally {
    await test.close();
  }
});

Deno.test("runtime save/load keeps queued input, rebases time, clears held keys, and caps catch-up", async () => {
  const test = await fixture();
  try {
    test.tick(select);
    test.tick([{ tag: "KeyDown", value: "ArrowRight" }]);
    const saved = test.runtime.game;
    const savedYaw = resource(saved, "CameraYaw");
    const path = join(test.root, "world.json");
    const saving = test.runtime.save(path);
    test.tick([], 1);
    close(resource(test.runtime.game, "CameraYaw") - savedYaw, 5 * dt * 1.4);
    await saving;
    const loading = test.runtime.load(path);
    test.tick(key("+"), 0);
    await loading;
    assert.equal(resource(test.runtime.game, "CameraYaw"), savedYaw);
    assert.equal(resource(test.runtime.game, "Selected"), 0);
    assert.equal(component(test.runtime.game, "ScaleX"), 1);
    test.tick([], 1);
    assert.equal(
      component(test.runtime.game, "ScaleX"),
      1,
      "load's first frame rebases instead of simulating elapsed I/O time",
    );
    test.tick();
    close(component(test.runtime.game, "ScaleX"), 1.1);
    assert.equal(resource(test.runtime.game, "CameraYaw"), savedYaw);
    assert.equal(resource(test.runtime.game, "HeldRight"), 0);
    test.tick([], 1);
    close(component(test.runtime.game, "ScaleX"), 1.1);
    assert.equal(resource(test.runtime.game, "CameraYaw"), savedYaw);
    const beforeBackward = test.runtime.game;
    test.at(0, key("+"));
    assert.equal(test.runtime.game.world, beforeBackward.world);
    test.tick();
    close(component(test.runtime.game, "ScaleX"), 1.21);
    const beforeFailure = test.runtime.game;
    await Deno.writeTextFile(path, "not JSON");
    await assert.rejects(() => test.runtime.load(path), /valid JSON/);
    assert.equal(test.runtime.game, beforeFailure);
    await test.runtime.save(path);
    const broken = JSON.parse(await Deno.readTextFile(path));
    const scale = broken.world.components.find((
      column: { identity: { declaration: string } },
    ) => column.identity.declaration === "ScaleX");
    scale.values[0] = 0;
    await Deno.writeTextFile(path, JSON.stringify(broken));
    await assert.rejects(
      () => test.runtime.load(path),
      /scale must be positive/,
    );
    assert.equal(test.runtime.game, beforeFailure);
    assert.equal(component(saved, "ScaleX"), 1);
  } finally {
    await test.close();
  }
});

Deno.test("runtime close cancels an active watched compile without failure reports or leaked work", async () => {
  const test = await fixture();
  try {
    test.watch();
    const compiling = test.next("compiling");
    await Deno.writeTextFile(
      test.sourcePath,
      replace(test.source, "const spin_speed = 0.6", "const spin_speed = 1.2"),
    );
    await compiling;
    const before = test.events.length;
    const closing = test.runtime.close();
    assert.equal(test.runtime.close(), closing);
    await closing;
    assert.deepEqual(
      test.events.slice(before),
      [],
      "intentional cancellation must not report a failed edit",
    );
    assert.throws(() => test.tick(), /closed/);
    assert.throws(() => test.runtime.watch(), /closed/);
    assert.throws(() => test.runtime.refresh(), /closed/);
    await assert.rejects(
      () => test.runtime.save(join(test.root, "closed.json")),
      /closed/,
    );
    await assert.rejects(
      () => test.runtime.load(join(test.root, "closed.json")),
      /closed/,
    );
  } finally {
    await test.close();
  }
});

Deno.test("candidate asset readiness retains the latest live world and publishes commands only once", async () => {
  let available = false;
  const test = await fixture({
    ready: (frame) => frame.clear.r !== Math.fround(0.2) || available,
  });
  try {
    test.tick(select);
    test.tick([{ tag: "KeyDown", value: "ArrowRight" }]);
    const runtime = test.runtime.game.runtime;
    const ready = test.next("ready");
    await test.edit(replace(
      test.source,
      "use @render.clear 0.065 0.08 0.105 1.0",
      "use @render.clear 0.2 0.08 0.105 1.0",
    ));
    await ready;
    const before = resource(test.runtime.game, "CameraYaw");
    const pending = test.tick([{ tag: "KeyDown", value: "F6" }]);
    assert.equal(test.runtime.game.runtime, runtime);
    assert.deepEqual(
      saves(pending),
      [{ kind: "save" }],
    );
    for (let frame = 0; frame < 3; frame++) {
      const rendered = test.tick([{ tag: "KeyDown", value: "F6" }]);
      assert.equal(
        saves(rendered).length,
        0,
      );
      assert.equal(test.runtime.game.runtime, runtime);
    }
    assert.ok(
      resource(test.runtime.game, "CameraYaw") > before,
      "old code keeps advancing while candidate assets load",
    );
    const latest = test.runtime.game;
    available = true;
    const published = test.next("published");
    const rendered = test.tick([{ tag: "FocusLost" }]);
    await published;
    assert.notEqual(test.runtime.game.runtime, runtime);
    assert.equal(rendered.clear.r, Math.fround(0.2));
    assert.equal(
      saves(rendered).length,
      0,
    );
    assert.equal(
      resource(test.runtime.game, "CameraYaw"),
      resource(latest, "CameraYaw"),
    );
    assert.equal(resource(test.runtime.game, "Selected"), 0);
    assert.equal(
      test.runtime.game.world.entityCount,
      2,
      "candidate startup must not run again",
    );
    assert.equal(resource(test.runtime.game, "HeldRight"), 0);
  } finally {
    await test.close();
  }
});

Deno.test("active frame asset gating holds world, input and platform commands until the frame commits", async () => {
  let available = false;
  const test = await fixture({
    ready: (frame) =>
      available ||
      !frame.draws.some((draw) =>
        draw.entity === 0 && draw.material === "blue.material.json"
      ),
  });
  try {
    test.tick(select);
    const before = test.runtime.game;
    test.tick([...key("m"), ...key("F6")], 0);
    for (let frame = 0; frame < 3; frame++) {
      const held = test.tick();
      assert.equal(test.runtime.game.world, before.world);
      assert.equal(component(test.runtime.game, "Material"), 0);
      assert.deepEqual(held.commands, []);
      assert.equal(
        held.draws.find((draw) => draw.entity === 0)?.material,
        "brass.material.json",
      );
    }
    available = true;
    let committed = test.tick();
    if (component(test.runtime.game, "Material") === 0) {
      assert.deepEqual(saves(committed), []);
      committed = test.tick();
    }
    assert.equal(
      component(test.runtime.game, "Material"),
      1,
      "the queued material action is applied once",
    );
    assert.deepEqual(
      saves(committed),
      [{ kind: "save" }],
    );
    const next = test.tick();
    assert.equal(component(test.runtime.game, "Material"), 1);
    assert.equal(
      saves(next).length,
      0,
    );
    assert.equal(component(before, "Material"), 0);
  } finally {
    await test.close();
  }
});
