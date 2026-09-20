import { resolve } from "node:path";
import { captureSurface } from "./capture.ts";
import { createEventPump } from "./event_pump.ts";
import { createRenderer, validateFrame } from "./renderer.ts";
import { createGameRuntime } from "./runtime.ts";

function argument(name: string, fallback: string): string {
  const prefix = `--${name}=`;
  return Deno.args.find((value) => value.startsWith(prefix))?.slice(
    prefix.length,
  ) ?? Deno.env.get(`BLOT_ECS_${name.toUpperCase()}`) ?? fallback;
}
const frameLimit = Number(argument("frames", "0"));
if (!Number.isSafeInteger(frameLimit) || frameLimit < 0) {
  throw new Error("--frames must be a nonnegative integer");
}
const sourcePath = resolve(argument("source", "case-study/ecs/game.blot"));
const savePath = resolve(argument("save", "build/ecs-quicksave.json"));
const assetPath = resolve("case-study/ecs/assets");
const capturePath = argument("capture", "");
let capturing: Promise<void> | undefined;
let texture: GPUTexture | undefined;

const adapter = await navigator.gpu.requestAdapter({
  powerPreference: "high-performance",
});
if (!adapter) throw new Error("No WebGPU adapter available");
const device = await adapter.requestDevice();
const win = new Deno.BrowserWindow({
  title: "Blot",
  width: 1100,
  height: 720,
});
const surface = win.getNativeWindow();
const context = surface.getContext("webgpu");
if (!context) throw new Error("Window did not provide a WebGPU surface");
const format = navigator.gpu.getPreferredCanvasFormat();
device.pushErrorScope("validation");
context.configure({
  device,
  format,
  alphaMode: "opaque",
  usage: GPUTextureUsage.RENDER_ATTACHMENT |
    (capturePath ? GPUTextureUsage.COPY_SRC : 0),
});
const resize = () => {
  const [width, height] = win.getSize();
  surface.width = Math.max(1, width);
  surface.height = Math.max(1, height);
};
resize();
const surfaceError = await device.popErrorScope();
if (surfaceError) throw new Error(`Window surface: ${surfaceError.message}`);
win.addEventListener("resize", resize);
const viewport = () => ({ width: surface.width, height: surface.height });
const input = createEventPump(win);
let status = "compiling";
let guestTitle = "Blot";
const renderer = createRenderer({
  device,
  format,
  rootDirectory: assetPath,
  target: {
    size: () => [surface.width, surface.height],
    view: () => {
      const current = context.getCurrentTexture();
      texture = current;
      return current.createView();
    },
    present: () => {
      if (
        capturePath && !capturing && frames >= 60 &&
        renderer.assets.stats().pending === 0
      ) {
        if (!texture) throw new Error("Capture preceded a frame texture");
        capturing = captureSurface(device, texture, resolve(capturePath));
        void capturing.then(
          () => console.log(`Captured native surface to ${capturePath}`),
          fail,
        );
      }
      surface.present();
    },
  },
  event: (event) => {
    if (event.tag === "AssetFailed") {
      console.error(`${event.value.key}: ${event.value.message}`);
    }
    input.enqueue(event);
  },
});

let runtime: Awaited<ReturnType<typeof createGameRuntime>> | undefined;
let starting:
  | Promise<Awaited<ReturnType<typeof createGameRuntime>>>
  | undefined;
let timer: ReturnType<typeof setTimeout> | undefined;
let closing: Promise<void> | undefined;
let snapshotting: Promise<void> | undefined;
const close = (): Promise<void> => {
  if (closing) return closing;
  clearTimeout(timer);
  input.close();
  win.removeEventListener("resize", resize);
  closing = (async () => {
    try {
      const active = runtime ?? await starting;
      await snapshotting;
      await capturing;
      await active?.close();
    } finally {
      try {
        await renderer.close();
        await device.queue.onSubmittedWorkDone();
      } finally {
        device.destroy();
      }
    }
  })();
  return closing;
};
const fail = (error: unknown) => {
  console.error(error);
  void close().then(() => Deno.exit(1), (shutdownError) => {
    console.error(shutdownError);
    Deno.exit(1);
  });
};
win.addEventListener("close", () => {
  void close().then(() => Deno.exit(0), fail);
});
device.addEventListener(
  "uncapturederror",
  (event) => fail((event as GPUUncapturedErrorEvent).error),
);
void device.lost.then((lost) => {
  if (!closing) fail(new Error(`GPU device lost: ${lost.message}`));
});

try {
  starting = createGameRuntime({
    sourcePath,
    compilerExecutable: resolve("generated/compiler/blotc"),
    viewport,
    validate: validateFrame,
    ready: renderer.ready,
    prepare: renderer.prepare,
    pick: (frame, point) => renderer.pick(frame, point),
    report: (event) => {
      if (event.kind === "compiling") status = `compiling #${event.revision}`;
      if (event.kind === "ready") status = `ready #${event.revision}`;
      if (event.kind === "published") {
        status = `live #${event.revision} · ${event.latency_ms.toFixed(0)} ms`;
        console.log(
          `${status}; compile ${
            event.compiled.stats.total_ms.toFixed(1)
          } ms; ${event.compiled.stats.groups_checked} groups checked, ${event.compiled.stats.entries_compiled} code entries generated`,
        );
      }
      if (event.kind === "failed") {
        status = `edit #${event.revision} rejected · previous build running`;
        console.error(event.error);
      }
    },
  });
  runtime = await starting;
  if (closing || win.isClosed()) {
    await close();
    Deno.exit(0);
  }
  status = "live";
  void runtime.watch().catch(fail);
  void renderer.assets.watch().catch(fail);
} catch (error) {
  console.error(error);
  try {
    await close();
  } finally {
    Deno.exit(1);
  }
}

if (!runtime) throw new Error("Game did not start");
const active = runtime;
let frames = 0;
let deadline = performance.now();
let titleAt = 0;
function present() {
  if (closing) return;
  if (win.isClosed()) {
    void close().then(() => Deno.exit(0), fail);
    return;
  }
  try {
    const frame = input.nextFrame(performance.now() / 1000, viewport());
    const rendered = active.frame(frame);
    renderer.submit(rendered);
    for (const command of rendered.commands ?? []) {
      if (command.kind === "title") {
        guestTitle = command.title;
        continue;
      }
      const pending = (snapshotting ?? Promise.resolve()).then(async () => {
        if (command.kind === "save") await active.save(savePath);
        else await active.load(savePath);
        console.log(
          `${command.kind === "save" ? "Saved" : "Loaded"} ${savePath}`,
        );
      }).catch((error) => console.error(error));
      snapshotting = pending;
      void pending.finally(() => {
        if (snapshotting === pending) snapshotting = undefined;
      });
    }
    frames++;
    if (performance.now() >= titleAt) {
      win.setTitle(`${guestTitle} · ${status}`);
      titleAt = performance.now() + 250;
    }
    if (frameLimit && frames >= frameLimit) {
      console.log(`Presented ${frames} native frames successfully`);
      void close().then(() => Deno.exit(0), fail);
      return;
    }
    deadline = Math.max(deadline + 1000 / 60, performance.now());
    timer = setTimeout(present, Math.max(0, deadline - performance.now()));
  } catch (error) {
    fail(error);
  }
}
console.log(`Watching ${sourcePath} and ${assetPath}`);
present();
