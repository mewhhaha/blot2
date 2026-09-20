import assert from "node:assert/strict";
import { join } from "node:path";
import {
  createAssetStore,
  parseMaterial,
  parseMesh,
  resolveAssetPath,
} from "./asset_store.ts";
import { createRenderer, validateFrame } from "./renderer.ts";
import { createEventPump } from "./event_pump.ts";
import { decodeTexture } from "./texture.ts";
import type { GameEvent, RenderFrame } from "./protocol.ts";

const encode = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const model = (
  x: number,
  z: number,
) => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, 0, z, 1];
const scene = (): RenderFrame => ({
  view: identity,
  projection: [
    1.154700538,
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
  draws: [
    {
      mesh: "cube.mesh.json",
      material: "checker.material.json",
      transform: model(-1.3, -5),
      entity: 1,
    },
    {
      mesh: "cube.mesh.json",
      material: "blue.material.json",
      transform: model(1.3, -5),
      entity: 2,
    },
  ],
});

Deno.test("mesh and material boundaries reject malformed assets", () => {
  const mesh = {
    positions: [0, 0, 0, 1, 0, 0, 0, 1, 0],
    normals: [0, 0, 1, 0, 0, 1, 0, 0, 1],
    uvs: [0, 0, 1, 0, 0, 1],
    indices: [0, 1, 2],
  };
  assert.equal(parseMesh(encode(mesh)).vertices.length, 24);
  assert.throws(
    () => parseMesh(encode({ ...mesh, indices: [0, 1, 3] })),
    /index/,
  );
  assert.throws(() => parseMesh(encode({ ...mesh, normals: [] })), /matching/);
  assert.throws(
    () =>
      parseMaterial(
        encode({
          shader: "scene.wgsl",
          color: [1, 1, 1, 0.5],
          lighting: "lit",
        }),
      ),
    /opaque/,
  );
  assert.throws(() => resolveAssetPath("/tmp/assets", "../escape"), /inside/);
  assert.throws(() => validateFrame({ ...scene(), view: [] }), /16/);
  assert.throws(() => validateFrame({ ...scene(), view: Array(16) }), /finite/);
  assert.throws(
    () => validateFrame({ ...scene(), ambient: { x: 1e100, y: 0, z: 0 } }),
    /float32/,
  );
  assert.throws(
    () =>
      validateFrame({
        ...scene(),
        draws: [{ ...scene().draws[0], transform: Array(16).fill(0) }],
      }),
    /invertible/,
  );
  assert.throws(
    () =>
      validateFrame({
        ...scene(),
        draws: [{ ...scene().draws[0], entity: -1 }],
      }),
    /U32/,
  );
  const projective = identity.slice();
  projective[3] = 1;
  assert.throws(
    () =>
      validateFrame({
        ...scene(),
        draws: [{ ...scene().draws[0], transform: projective }],
      }),
    /affine/,
  );
});

Deno.test("event pump snapshots and drains input, then detaches on close", () => {
  const window = new EventTarget();
  const pump = createEventPump(window);
  const dispatch = (type: string, properties: Record<string, unknown>) =>
    window.dispatchEvent(Object.assign(new Event(type), properties));
  dispatch("keydown", { key: "ArrowLeft", repeat: false });
  dispatch("keydown", { key: "ArrowLeft", repeat: true });
  dispatch("mousemove", { clientX: 4, clientY: 6 });
  dispatch("mousedown", { clientX: 4, clientY: 6, button: 0 });
  dispatch("wheel", { clientX: 8, clientY: 9, deltaY: -3 });
  dispatch("blur", {});
  const viewport = { width: 96, height: 64 };
  const frame = pump.nextFrame(100, viewport);
  viewport.width = 128;
  assert.deepEqual(frame.viewport, { width: 96, height: 64 });
  assert.deepEqual(frame.events, [
    { tag: "KeyDown", value: "ArrowLeft" },
    { tag: "PointerMove", value: { x: 4, y: 6 } },
    { tag: "PointerDown", value: { x: 4, y: 6, button: 0 } },
    { tag: "Wheel", value: { x: 8, y: 9, delta: -3 } },
    { tag: "FocusLost" },
  ]);
  assert.deepEqual(pump.nextFrame(101, viewport).events, []);
  assert.throws(() => pump.nextFrame(NaN, viewport), /clock/);
  assert.throws(
    () => pump.nextFrame(102, { width: 0, height: 64 }),
    /viewport/,
  );
  pump.close();
  pump.close();
  // A still-attached pointer listener would reject this malformed event.
  dispatch("mousemove", {});
  assert.throws(() => pump.nextFrame(103, viewport), /closed/);
});

Deno.test("PNG texture decoder produces independent RGBA pixels", async () => {
  const bytes = await Deno.readFile(
    new URL("./assets/checker.png", import.meta.url),
  );
  const first = await decodeTexture(bytes);
  const second = await decodeTexture(bytes);
  assert.equal(first.pixels.length, first.width * first.height * 4);
  assert.ok(first.width > 1 && first.height > 1);
  const original = second.pixels[0];
  first.pixels[0] ^= 255;
  assert.equal(second.pixels[0], original);
  await assert.rejects(
    () => decodeTexture(new Uint8Array([1, 2, 3])),
    /PNG or JPEG/,
  );
});

Deno.test("asset loads deduplicate and retain the usable revision after failure", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-assets-" });
  const path = join(root, "shader.wgsl");
  await Deno.writeTextFile(path, "first");
  const events: GameEvent[] = [];
  const destroyed: string[] = [];
  let reads = 0;
  const assets = createAssetStore({
    rootDirectory: root,
    event: (event) => events.push(event),
    prepare(kind, _key, bytes) {
      reads++;
      const source = new TextDecoder().decode(bytes);
      if (source === "broken") {
        return Promise.reject(new Error("invalid shader"));
      }
      return Promise.resolve({
        kind,
        source,
        destroy() {
          destroyed.push(source);
        },
      });
    },
  });
  try {
    for (let count = 0; count < 10; count++) {
      assert.equal(assets.get("shader", "shader.wgsl"), undefined);
    }
    await assets.idle();
    assert.equal(reads, 1);
    assert.equal(assets.get("shader", "shader.wgsl")?.source, "first");
    await Deno.writeTextFile(path, "broken");
    assets.reload([path]);
    await assets.idle();
    assert.equal(assets.get("shader", "shader.wgsl")?.source, "first");
    assert.deepEqual(events.map((event) => event.tag), [
      "AssetReady",
      "AssetFailed",
    ]);
    for (let count = 0; count < 10; count++) {
      assets.get("shader", "shader.wgsl");
    }
    await assets.idle();
    assert.equal(reads, 2);
    await Deno.writeTextFile(path, "second");
    assets.reload([path]);
    await assets.idle();
    assert.equal(assets.get("shader", "shader.wgsl")?.source, "second");
    assert.deepEqual(destroyed, ["first"]);
  } finally {
    await assets.close();
    await Deno.remove(root, { recursive: true });
  }
  assert.deepEqual(destroyed, ["first", "second"]);
  assert.deepEqual(assets.stats(), { resident: 0, pending: 0 });
});

Deno.test("closing drains an in-flight asset and disposes its late result", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-asset-close-" });
  await Deno.writeTextFile(join(root, "shader"), "source");
  const started = Promise.withResolvers<void>();
  const release = Promise.withResolvers<void>();
  let destroyed = 0;
  const events: GameEvent[] = [];
  const assets = createAssetStore({
    rootDirectory: root,
    event: (event) => events.push(event),
    async prepare(kind) {
      started.resolve();
      await release.promise;
      return {
        kind,
        destroy() {
          destroyed++;
        },
      };
    },
  });
  try {
    assets.get("shader", "shader");
    await started.promise;
    const closed = assets.close();
    release.resolve();
    await closed;
    assert.equal(destroyed, 1);
    assert.deepEqual(events, []);
  } finally {
    release.resolve();
    await assets.close();
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("asset reload discards stale candidates and accepts directory notifications", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-asset-race-" });
  const path = join(root, "shader");
  await Deno.writeTextFile(path, "first");
  const firstStarted = Promise.withResolvers<void>();
  const releaseFirst = Promise.withResolvers<void>();
  const replacementReady = Promise.withResolvers<void>();
  const destroyed: string[] = [];
  const events: GameEvent[] = [];
  const assets = createAssetStore({
    rootDirectory: root,
    event(event) {
      events.push(event);
      if (event.tag === "AssetReady" && event.value.revision === 2) {
        replacementReady.resolve();
      }
    },
    async prepare(kind, _key, bytes) {
      const source = new TextDecoder().decode(bytes);
      if (source === "first") {
        firstStarted.resolve();
        await releaseFirst.promise;
      }
      return {
        kind,
        source,
        destroy: () => {
          destroyed.push(source);
        },
      };
    },
  });
  try {
    assets.get("shader", "shader");
    await firstStarted.promise;
    await Deno.writeTextFile(path, "second");
    assets.reload([root]);
    await replacementReady.promise;
    assert.equal(assets.get("shader", "shader")?.source, "second");
    releaseFirst.resolve();
    await assets.idle();
    assert.deepEqual(events.map((event) => event.tag), ["AssetReady"]);
    assert.deepEqual(destroyed, ["first"]);
  } finally {
    releaseFirst.resolve();
    await assets.close();
    await Deno.remove(root, { recursive: true });
  }
  assert.deepEqual(destroyed, ["first", "second"]);
});

Deno.test("asset boundary rejects symlink escapes without preparing outside bytes", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-asset-links-" });
  const inside = join(root, "assets");
  await Deno.mkdir(inside);
  await Deno.writeTextFile(join(root, "outside"), "private");
  await Deno.symlink(join(root, "outside"), join(inside, "escape"));
  const events: GameEvent[] = [];
  let prepared = false;
  const assets = createAssetStore({
    rootDirectory: inside,
    event: (event) => events.push(event),
    prepare(kind) {
      prepared = true;
      return { kind, destroy() {} };
    },
  });
  try {
    assets.get("shader", "escape");
    await assets.idle();
    assert.equal(prepared, false);
    assert.equal(events.length, 1);
    const failure = events[0];
    assert.equal(failure.tag, "AssetFailed");
    if (failure.tag === "AssetFailed") {
      assert.match(failure.value.message, /symlink/);
    }
  } finally {
    await assets.close();
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("asset invariant failures are observed, reported, and still dispose resources", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-asset-failure-" });
  await Deno.writeTextFile(join(root, "shader"), "source");
  let destroyed = 0;
  const assets = createAssetStore({
    rootDirectory: root,
    event() {},
    prepare() {
      return {
        kind: "texture" as const,
        destroy() {
          destroyed++;
        },
      };
    },
  });
  try {
    assets.get("shader", "shader");
    await assert.rejects(() => assets.idle(), /returned texture for shader/);
    assert.throws(
      () => assets.get("shader", "shader"),
      /returned texture for shader/,
    );
    await assert.rejects(() => assets.close(), AggregateError);
    assert.equal(destroyed, 1);
    assert.deepEqual(assets.stats(), { resident: 0, pending: 0 });
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("asset watcher publishes a file edit and stops cleanly", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-asset-watch-" });
  const path = join(root, "shader");
  await Deno.writeTextFile(path, "first");
  const replacement = Promise.withResolvers<void>();
  const assets = createAssetStore({
    rootDirectory: root,
    event(event) {
      if (event.tag === "AssetReady" && event.value.revision > 1) {
        replacement.resolve();
      }
    },
    prepare(kind, _key, bytes) {
      return { kind, source: new TextDecoder().decode(bytes), destroy() {} };
    },
  });
  let watching: Promise<void> | undefined;
  const timeout = setTimeout(
    () => replacement.reject(new Error("asset watcher missed edit")),
    3000,
  );
  try {
    assets.get("shader", "shader");
    await assets.idle();
    watching = assets.watch();
    void watching.catch(replacement.reject);
    await Deno.writeTextFile(path, "second");
    await replacement.promise;
    await assets.idle();
    assert.equal(assets.get("shader", "shader")?.source, "second");
  } finally {
    clearTimeout(timeout);
    await assets.close();
    await watching;
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("cyclic asset dependencies fail instead of deadlocking", async () => {
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-asset-cycle-" });
  await Deno.writeTextFile(join(root, "a"), "a");
  await Deno.writeTextFile(join(root, "b"), "b");
  const events: GameEvent[] = [];
  const assets = createAssetStore({
    rootDirectory: root,
    event: (event) => events.push(event),
    async prepare(kind, key, _bytes, requireAsset) {
      await requireAsset("shader", key === "a" ? "b" : "a");
      return { kind, destroy() {} };
    },
  });
  try {
    assets.get("shader", "a");
    await assets.idle();
    assert.equal(assets.stats().resident, 0);
    assert.ok(
      events.some((event) =>
        event.tag === "AssetFailed" && /cyclic/.test(event.value.message)
      ),
    );
  } finally {
    await assets.close();
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("WebGPU renders and picks transformed depth-tested meshes through reload and resize", async () => {
  const adapter = await navigator.gpu.requestAdapter();
  assert.ok(adapter, "WebGPU adapter required for renderer verification");
  const device = await adapter.requestDevice();
  const failures: GPUError[] = [];
  device.addEventListener(
    "uncapturederror",
    (event) => failures.push((event as GPUUncapturedErrorEvent).error),
  );
  const root = await Deno.makeTempDir({ prefix: "blot-ecs-gpu-" });
  for await (
    const file of Deno.readDir(new URL("./assets", import.meta.url))
  ) {
    if (file.isFile) {
      await Deno.copyFile(
        new URL(`./assets/${file.name}`, import.meta.url),
        join(root, file.name),
      );
    }
  }
  let width = 96;
  let height = 64;
  const colorTarget = () =>
    device.createTexture({
      size: [width, height],
      format: "rgba8unorm",
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
    });
  let color = colorTarget();
  const events: GameEvent[] = [];
  // Exercise allocation recovery without allocating the real multi-GB limit.
  const boundedLimits = new Proxy(device.limits, {
    get(target, key) {
      return key === "maxBufferSize" ? 4096 : Reflect.get(target, key, target);
    },
  });
  const boundedDevice = new Proxy(device, {
    get(target, key) {
      if (key === "limits") return boundedLimits;
      const value = Reflect.get(target, key, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const renderer = createRenderer({
    device: boundedDevice,
    format: "rgba8unorm",
    rootDirectory: root,
    event: (event) => events.push(event),
    target: {
      size: () => [width, height],
      view: () => color.createView(),
      present() {},
    },
  });
  const read = async () => {
    const rowBytes = Math.ceil(width * 4 / 256) * 256;
    const pixels = device.createBuffer({
      size: rowBytes * height,
      usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
    });
    try {
      const commands = device.createCommandEncoder();
      commands.copyTextureToBuffer({ texture: color }, {
        buffer: pixels,
        bytesPerRow: rowBytes,
        rowsPerImage: height,
      }, [width, height]);
      device.queue.submit([commands.finish()]);
      await pixels.mapAsync(GPUMapMode.READ);
      const bytes = new Uint8Array(pixels.getMappedRange()).slice();
      pixels.unmap();
      return (x: number, y: number) =>
        Array.from(bytes.slice(y * rowBytes + x * 4, y * rowBytes + x * 4 + 4));
    } finally {
      pixels.destroy();
    }
  };
  const settle = async (frame: RenderFrame) => {
    for (let pass = 0; pass < 3; pass++) {
      renderer.submit(frame);
      await renderer.assets.idle();
    }
    renderer.submit(frame);
  };
  try {
    const frame = scene();
    const snapshot = structuredClone(frame);
    await settle(frame);
    assert.deepEqual(events.filter((event) => event.tag === "AssetFailed"), []);
    let pixel = await read();
    const left = pixel(28, 32);
    const right = pixel(68, 32);
    assert.ok(
      left[0] > right[0] * 3,
      `separate material colors ${left} / ${right}`,
    );
    const checks = Array.from(
      { length: 20 },
      (_, index) => pixel(20 + index, 28),
    );
    assert.ok(
      checks.some((sample) => sample[0] > sample[2] + 75),
      "texture must contain gold checks",
    );
    assert.ok(
      Math.max(...checks.map((sample) => sample[2])) -
          Math.min(...checks.map((sample) => sample[2])) > 20,
      "texture must vary across the face",
    );
    assert.ok(right[2] > right[0] * 3, `blue material ${right}`);
    assert.equal(renderer.pick(frame, { x: 28, y: 32 })?.entity, 1);
    assert.equal(renderer.pick(frame, { x: 68, y: 32 })?.entity, 2);
    assert.equal(renderer.pick(frame, { x: 48, y: 32 }), undefined);
    assert.equal(renderer.pick(frame, { x: -1, y: 32 }), undefined);
    const tooMany = Array.from({ length: 65 }, () => frame.draws[0]);
    assert.throws(
      () => renderer.submit({ ...frame, draws: tooMany }),
      /draw list/,
    );
    renderer.submit({ ...frame, draws: tooMany.slice(0, 8) });
    const near = { ...frame.draws[0], transform: model(0, -4) };
    const far = { ...frame.draws[1], transform: model(0, -7) };
    await settle({ ...frame, draws: [near] });
    const nearColor = (await read())(48, 32);
    await settle({ ...frame, draws: [near, far] });
    pixel = await read();
    assert.deepEqual(
      pixel(48, 32),
      nearColor,
      "later distant blue draw must be occluded",
    );
    const nearest = renderer.pick({ ...frame, draws: [far, near] }, {
      x: 48,
      y: 32,
    });
    assert.equal(nearest?.entity, 1);
    assert.equal(nearest?.draw_index, 1);
    assert.ok(Math.abs(nearest!.position.z + 3) < 1e-8);
    assert.ok(Math.abs(nearest!.distance - 2.9) < 1e-8);
    const occluded = renderer.pick({
      ...frame,
      draws: [far, { ...near, entity: undefined }],
    }, { x: 48, y: 32 });
    assert.equal(occluded?.draw_index, 1);
    assert.equal(
      occluded?.entity,
      undefined,
      "noneditable geometry still occludes",
    );
    const c = Math.SQRT1_2;
    const rotated = {
      ...near,
      entity: 3,
      transform: [2 * c, 0, -2 * c, 0, 0, 0.5, 0, 0, c, 0, c, 0, 0, 0, -5, 1],
    };
    await settle({ ...frame, draws: [rotated] });
    const transformed = renderer.pick({ ...frame, draws: [rotated] }, {
      x: 48,
      y: 32,
    });
    assert.equal(transformed?.entity, 3);
    assert.ok(Math.abs(transformed!.position.z - (-5 + Math.SQRT2)) < 1e-8);
    const translatedCamera = {
      ...frame,
      view: model(-1, 0),
      draws: [{ ...near, transform: model(1, -5) }],
    };
    assert.ok(
      Math.abs(
        renderer.pick(translatedCamera, { x: 48, y: 32 })!.position.x - 1,
      ) < 1e-8,
    );
    assert.equal(
      renderer.pick({
        ...frame,
        draws: [{ ...near, transform: model(0, -200) }],
      }, { x: 48, y: 32 }),
      undefined,
      "far-plane clipping applies to picks",
    );
    const onFarPlane = {
      ...frame,
      projection: identity,
      draws: [{ ...near, transform: model(0, 2) }],
    };
    renderer.submit(onFarPlane);
    const farPlanePixels = await read();
    assert.deepEqual(farPlanePixels(48, 32), farPlanePixels(0, 0));
    assert.equal(
      renderer.pick(onFarPlane, { x: 48, y: 32 }),
      undefined,
      "depth equal to the clear value fails the pipeline's less test",
    );
    const texturePath = join(root, "checker.png");
    await Deno.copyFile(
      new URL("./assets/brass.png", import.meta.url),
      texturePath,
    );
    renderer.assets.reload([texturePath]);
    await renderer.assets.idle();
    renderer.submit(frame);
    const replacementColor = (await read())(28, 32);
    assert.notDeepEqual(
      replacementColor,
      left,
      "texture replacement changes pixels",
    );
    await Deno.writeTextFile(texturePath, "broken texture");
    renderer.assets.reload([texturePath]);
    await renderer.assets.idle();
    renderer.submit(frame);
    assert.deepEqual(
      (await read())(28, 32),
      replacementColor,
      "invalid texture retains last good GPU image",
    );
    const bluePath = join(root, "blue.material.json");
    await Deno.writeTextFile(
      bluePath,
      JSON.stringify({
        shader: "scene.wgsl",
        color: [0.9, 0.1, 0.1, 1],
        lighting: "unlit",
      }),
    );
    renderer.assets.reload([bluePath]);
    await renderer.assets.idle();
    renderer.submit(frame);
    pixel = await read();
    assert.ok(
      pixel(68, 32)[0] > pixel(68, 32)[2] * 3,
      "material replacement must change pixels",
    );
    const lastGoodMaterial = renderer.assets.get(
      "material",
      "blue.material.json",
    );
    const beforeDependencyChange = pixel(68, 32);
    const candidateMaterial = {
      shader: "new.wgsl",
      texture: "new.png",
      color: [0.1, 0.9, 0.1, 1],
      lighting: "unlit",
    };
    await Deno.writeTextFile(bluePath, JSON.stringify(candidateMaterial));
    renderer.assets.reload([bluePath]);
    await renderer.assets.idle();
    assert.equal(
      renderer.assets.get("material", "blue.material.json"),
      lastGoodMaterial,
    );
    renderer.submit(frame);
    assert.deepEqual(
      (await read())(68, 32),
      beforeDependencyChange,
      "missing new dependencies retain the old material and draw",
    );
    const newShaderPath = join(root, "new.wgsl");
    const newTexturePath = join(root, "new.png");
    await Deno.writeTextFile(newShaderPath, "broken shader");
    await Deno.writeTextFile(newTexturePath, "broken texture");
    renderer.assets.reload([newShaderPath, newTexturePath]);
    await renderer.assets.idle();
    assert.equal(
      renderer.assets.get("material", "blue.material.json"),
      lastGoodMaterial,
      "invalid new dependencies keep the old material",
    );
    await Deno.copyFile(
      new URL("./assets/scene.wgsl", import.meta.url),
      newShaderPath,
    );
    renderer.assets.reload([newShaderPath]);
    await renderer.assets.idle();
    assert.equal(
      renderer.assets.get("material", "blue.material.json"),
      lastGoodMaterial,
      "shader alone cannot publish while the new texture is invalid",
    );
    await Deno.copyFile(
      new URL("./assets/brass.png", import.meta.url),
      newTexturePath,
    );
    renderer.assets.reload([newTexturePath]);
    await renderer.assets.idle();
    assert.notEqual(
      renderer.assets.get("material", "blue.material.json"),
      lastGoodMaterial,
      "dependency edit retries and publishes the waiting material",
    );
    renderer.submit(frame);
    const afterDependenciesReady = (await read())(68, 32);
    assert.ok(
      afterDependenciesReady[1] > afterDependenciesReady[0] * 2,
      `published material is green: ${afterDependenciesReady}`,
    );
    await Deno.writeTextFile(
      bluePath,
      JSON.stringify({
        shader: "scene.wgsl",
        color: [0.9, 0.1, 0.1, 1],
        lighting: "unlit",
      }),
    );
    renderer.assets.reload([bluePath]);
    await renderer.assets.idle();
    const shaderPath = join(root, "scene.wgsl");
    await Deno.writeTextFile(shaderPath, "invalid shader");
    renderer.assets.reload([shaderPath]);
    await renderer.assets.idle();
    renderer.submit(frame);
    assert.ok(
      events.some((event) =>
        event.tag === "AssetFailed" && event.value.key === "scene.wgsl"
      ),
    );
    assert.ok(
      (await read())(68, 32)[0] > 200,
      "invalid shader must retain the usable pipeline",
    );
    const meshPath = join(root, "cube.mesh.json");
    const originalMesh = await Deno.readTextFile(meshPath);
    const smallerMesh = JSON.parse(originalMesh);
    smallerMesh.positions = smallerMesh.positions.map((value: number) =>
      value * 0.5
    );
    const oldMesh = renderer.assets.get("mesh", "cube.mesh.json");
    assert.equal(oldMesh?.kind, "mesh");
    await Deno.writeTextFile(meshPath, JSON.stringify(smallerMesh));
    renderer.assets.reload([meshPath]);
    await renderer.assets.idle();
    const smallerHit = renderer.pick({ ...frame, draws: [near] }, {
      x: 48,
      y: 32,
    });
    assert.ok(
      Math.abs(smallerHit!.position.z + 3.5) < 1e-8,
      "mesh reload updates picking geometry",
    );
    if (oldMesh?.kind === "mesh") {
      device.pushErrorScope("validation");
      device.queue.writeBuffer(oldMesh.vertices, 0, new Float32Array(8));
      const disposed = await device.popErrorScope();
      assert.match(
        disposed?.message ?? "",
        /destroyed/i,
        "superseded mesh GPU buffer is freed",
      );
    }
    await Deno.writeTextFile(meshPath, "{}");
    renderer.assets.reload([meshPath]);
    await renderer.assets.idle();
    assert.deepEqual(
      renderer.pick({ ...frame, draws: [near] }, { x: 48, y: 32 }),
      smallerHit,
      "invalid mesh retains last good geometry",
    );
    await Deno.writeTextFile(meshPath, originalMesh);
    renderer.assets.reload([meshPath]);
    await renderer.assets.idle();
    width = 128;
    height = 80;
    color.destroy();
    color = colorTarget();
    renderer.submit(frame);
    assert.equal((await read())(0, 0)[3], 255);
    assert.equal(renderer.pick(frame, { x: 37, y: 40 })?.entity, 1);
    assert.equal(renderer.pick(frame, { x: 91, y: 40 })?.entity, 2);
    const beforeWidth = width;
    width = -1;
    assert.throws(() => renderer.submit(frame), /dimensions/);
    width = beforeWidth;
    for (let iteration = 0; iteration < 100; iteration++) {
      renderer.submit(frame);
    }
    await device.queue.onSubmittedWorkDone();
    assert.equal(renderer.assets.stats().resident, 7);
    assert.deepEqual(failures, []);
    assert.deepEqual(
      frame,
      snapshot,
      "rendering and picking do not mutate a frame",
    );
  } finally {
    await renderer.close();
    color.destroy();
    device.destroy();
    await Deno.remove(root, { recursive: true });
  }
  assert.deepEqual(renderer.assets.stats(), { resident: 0, pending: 0 });
  assert.throws(() => renderer.submit(scene()), /closed/);
  assert.throws(() => renderer.pick(scene(), { x: 1, y: 1 }), /closed/);
});
