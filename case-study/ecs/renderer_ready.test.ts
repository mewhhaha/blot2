import assert from "node:assert/strict";
import { join } from "node:path";
import type { GameEvent, RenderFrame } from "./protocol.ts";
import { createRenderer } from "./renderer.ts";

const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const scene = (): RenderFrame => ({
  view: identity,
  projection: [
    1.732050808,
    0,
    0,
    0,
    0,
    1.732050808,
    0,
    0,
    0,
    0,
    -100 / 99.9,
    -1,
    0,
    0,
    -10 / 99.9,
    0,
  ],
  clear: { r: 0.02, g: 0.03, b: 0.04, a: 1 },
  ambient: { x: 1, y: 1, z: 1 },
  light_direction: { x: 0, y: -1, z: 0 },
  light_color: { x: 0, y: 0, z: 0 },
  draws: [{
    mesh: "cube.mesh.json",
    material: "blue.material.json",
    transform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, -5, 1],
    entity: 7,
  }],
});

Deno.test("renderer readiness gates new references, keeps the visible frame and recovers through dependencies", async () => {
  const adapter = await navigator.gpu.requestAdapter();
  assert.ok(adapter, "WebGPU adapter required for readiness verification");
  const device = await adapter.requestDevice();
  const failures: GPUError[] = [];
  device.addEventListener(
    "uncapturederror",
    (event) => failures.push((event as GPUUncapturedErrorEvent).error),
  );
  const root = await Deno.makeTempDir({ prefix: "blot-render-ready-" });
  for await (const file of Deno.readDir(new URL("./assets", import.meta.url))) {
    if (file.isFile) {
      await Deno.copyFile(
        new URL(`./assets/${file.name}`, import.meta.url),
        join(root, file.name),
      );
    }
  }
  const limits = new Proxy(device.limits, {
    get(target, key) {
      return key === "maxBufferSize" ? 4096 : Reflect.get(target, key, target);
    },
  });
  const bounded = new Proxy(device, {
    get(target, key) {
      if (key === "limits") return limits;
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const color = device.createTexture({
    size: [64, 64],
    format: "rgba8unorm",
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
  });
  let presentations = 0;
  let watching: Promise<void> | undefined;
  const watchedReady = Promise.withResolvers<void>();
  const events: GameEvent[] = [];
  const renderer = createRenderer({
    device: bounded,
    format: "rgba8unorm",
    rootDirectory: root,
    target: {
      size: () => [64, 64],
      view: () => color.createView(),
      present() {
        presentations++;
      },
    },
    event(event) {
      events.push(event);
      if (
        event.tag === "AssetReady" &&
        event.value.key === "watched.material.json"
      ) watchedReady.resolve();
    },
  });
  const pixel = async () => {
    const readback = device.createBuffer({
      size: 256,
      usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
    });
    try {
      const commands = device.createCommandEncoder();
      commands.copyTextureToBuffer({ texture: color, origin: [32, 32] }, {
        buffer: readback,
        bytesPerRow: 256,
      }, [1, 1]);
      device.queue.submit([commands.finish()]);
      await readback.mapAsync(GPUMapMode.READ);
      const value = [...new Uint8Array(readback.getMappedRange()).slice(0, 4)];
      readback.unmap();
      return value;
    } finally {
      readback.destroy();
    }
  };
  try {
    const current = scene();
    const snapshot = structuredClone(current);
    assert.equal(renderer.ready(current), false);
    assert.equal(renderer.assets.stats().pending, 2);
    assert.equal(renderer.ready(current), false);
    assert.equal(renderer.assets.stats().pending, 2);
    await renderer.prepare(current);
    assert.equal(renderer.ready(current), true);
    assert.equal(
      presentations,
      0,
      "preparation cannot replace the visible frame",
    );
    renderer.submit(current);
    const previousPixel = await pixel();
    assert.ok(previousPixel[2] > previousPixel[0] * 3);

    const candidate: RenderFrame = {
      ...current,
      draws: [{
        ...current.draws[0],
        mesh: "next.mesh.json",
        material: "next.material.json",
      }],
    };
    assert.equal(renderer.ready(candidate), false);
    await renderer.assets.idle();
    await assert.rejects(
      () => renderer.prepare(candidate),
      /mesh next.mesh.json.*material next.material.json/,
    );
    const failedEvents = events.length;
    for (let frame = 0; frame < 20; frame++) {
      assert.equal(renderer.ready(candidate), false);
    }
    assert.equal(
      events.length,
      failedEvents,
      "retrying a frame does not retry I/O",
    );
    assert.equal(renderer.ready(current), true);
    renderer.submit(current);
    assert.deepEqual(await pixel(), previousPixel);

    const meshPath = join(root, "next.mesh.json");
    const materialPath = join(root, "next.material.json");
    const shaderPath = join(root, "next.wgsl");
    const texturePath = join(root, "next.png");
    const material = {
      shader: "next.wgsl",
      texture: "next.png",
      color: [0.1, 0.9, 0.1, 1],
      lighting: "unlit",
    };
    await Deno.copyFile(join(root, "cube.mesh.json"), meshPath);
    await Deno.writeTextFile(materialPath, JSON.stringify(material));
    renderer.assets.reload([meshPath, materialPath]);
    await renderer.assets.idle();
    assert.equal(renderer.ready(candidate), false);
    assert.equal(renderer.assets.get("mesh", "next.mesh.json")?.kind, "mesh");
    for (const key of ["next.wgsl", "next.png"]) {
      assert.ok(
        events.some((event) =>
          event.tag === "AssetFailed" && event.value.key === key
        ),
      );
    }
    await Deno.writeTextFile(shaderPath, "invalid shader");
    await Deno.writeTextFile(texturePath, "invalid texture");
    renderer.assets.reload([shaderPath, texturePath]);
    await renderer.assets.idle();
    assert.equal(renderer.ready(candidate), false);
    await Deno.copyFile(join(root, "scene.wgsl"), shaderPath);
    renderer.assets.reload([shaderPath]);
    await renderer.assets.idle();
    assert.equal(
      renderer.ready(candidate),
      false,
      "the texture is still invalid",
    );
    renderer.submit(current);
    assert.deepEqual(await pixel(), previousPixel);
    await Deno.copyFile(join(root, "brass.png"), texturePath);
    renderer.assets.reload([texturePath]);
    await renderer.prepare(candidate);
    assert.equal(renderer.ready(candidate), true);
    renderer.submit(candidate);
    const replacementPixel = await pixel();
    assert.ok(replacementPixel[1] > replacementPixel[0] * 2);
    assert.equal(renderer.pick(candidate, { x: 32, y: 32 })?.entity, 7);

    await Deno.writeTextFile(shaderPath, "invalid replacement shader");
    renderer.assets.reload([shaderPath]);
    assert.equal(
      renderer.ready(candidate),
      true,
      "resident assets remain usable",
    );
    await renderer.prepare(candidate);
    await renderer.assets.idle();
    assert.equal(
      renderer.ready(candidate),
      true,
      "failed reload keeps the old shader",
    );
    renderer.submit(candidate);
    assert.deepEqual(await pixel(), replacementPixel);

    const beforeInvalid = renderer.assets.stats();
    assert.throws(() => renderer.ready({ ...current, view: [] }), /16/);
    assert.throws(
      () =>
        renderer.ready({
          ...current,
          draws: Array.from({ length: 65 }, () => current.draws[0]),
        }),
      /draw list/,
    );
    assert.throws(
      () =>
        renderer.ready({
          ...current,
          draws: [
            { ...current.draws[0], mesh: "must-not-load.mesh.json" },
            { ...current.draws[0], material: "../escape.material.json" },
          ],
        }),
      /inside/,
    );
    assert.deepEqual(renderer.assets.stats(), beforeInvalid);
    assert.equal(renderer.ready({ ...current, draws: [] }), true);
    await renderer.prepare({ ...current, draws: [] });

    const watched: RenderFrame = {
      ...current,
      draws: [{ ...current.draws[0], material: "watched.material.json" }],
    };
    assert.equal(renderer.ready(watched), false);
    await renderer.assets.idle();
    watching = renderer.assets.watch();
    void watching.catch(() => {});
    const timeout = setTimeout(
      () => watchedReady.reject(new Error("asset watch timed out")),
      5000,
    );
    void watchedReady.promise.catch(() => {});
    try {
      await Deno.writeTextFile(
        join(root, "watched.material.json"),
        JSON.stringify({ ...material, shader: "scene.wgsl", texture: null }),
      );
      await watchedReady.promise;
    } finally {
      clearTimeout(timeout);
    }
    assert.equal(
      renderer.ready(watched),
      true,
      "a file edit wakes a failed new reference",
    );
    assert.deepEqual(current, snapshot);
    await device.queue.onSubmittedWorkDone();
    assert.deepEqual(failures, []);
  } finally {
    await renderer.close();
    await watching;
    color.destroy();
    device.destroy();
    await Deno.remove(root, { recursive: true });
  }
  assert.equal(renderer.assets.stats().resident, 0);
  assert.throws(() => renderer.ready(scene()), /closed/);
  await assert.rejects(() => renderer.prepare(scene()), /closed/);
});
