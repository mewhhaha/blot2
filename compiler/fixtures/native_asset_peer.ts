const [mode, log] = Deno.args;
const encoder = new TextEncoder();
const wasm = Uint8Array.of(0, 97, 115, 109, 1, 0, 0, 0);
const resource = Uint8Array.of(0, 255, 42);
const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", resource));
const sha256 = Array.from(hash, (byte) => byte.toString(16).padStart(2, "0"))
  .join("");
async function write(metadata: unknown, payload = new Uint8Array()) {
  const json = encoder.encode(JSON.stringify(metadata));
  const bytes = new Uint8Array(8 + json.length + payload.length);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, json.length, true);
  view.setUint32(4, payload.length, true);
  bytes.set(json, 8);
  bytes.set(payload, 8 + json.length);
  let offset = 0;
  while (offset < bytes.length) {
    offset += await Deno.stdout.write(bytes.subarray(offset));
  }
}
async function exact(length: number) {
  const result = new Uint8Array(length);
  let offset = 0;
  while (offset < length) {
    const count = await Deno.stdin.read(result.subarray(offset));
    if (count === null) Deno.exit();
    offset += count;
  }
  return result;
}
await Deno.writeTextFile(log, JSON.stringify({ pid: Deno.pid }) + "\n");
await new Promise((resolve) => setTimeout(resolve, 50));
const capabilities = [
  "project-build",
  "utf8_bytes",
  "abort-disposes-process",
  "source-overlays",
];
if (mode !== "no-capability") capabilities.push("native-assets-v1");
await write({
  kind: "hello",
  protocol: "blot-zig-project",
  version: 1,
  maxFrameBytes: 67108864,
  compilerIdentity: "a".repeat(64),
  capabilities,
});
let revision = 0;
while (true) {
  const header = await exact(8);
  const view = new DataView(header.buffer);
  const metadata = JSON.parse(
    new TextDecoder().decode(await exact(view.getUint32(0, true))),
  );
  const input = await exact(view.getUint32(4, true));
  await Deno.writeTextFile(
    log,
    JSON.stringify({ ...metadata, payload: Array.from(input) }) + "\n",
    { append: true },
  );
  if (metadata.kind === "open") {
    await write({
      kind: "open",
      id: metadata.id,
      epoch: "native",
      revision: 0,
    });
    continue;
  }
  if (metadata.kind === "close") {
    await write({ kind: "close", id: metadata.id, epoch: "native", revision });
    break;
  }
  if (revision === 0 && mode === "valid") {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  revision++;
  const payload = new Uint8Array(wasm.length + resource.length);
  payload.set(wasm);
  payload.set(resource, wasm.length);
  const asset: Record<string, unknown> = {
    id: 1,
    path: "/native/resource.bin",
    mediaType: "application/octet-stream",
    sha256,
    start: wasm.length,
    length: resource.length,
  };
  const dependencies: Record<string, unknown>[] = [{
    path: "/native/resource.bin",
    sha256,
  }];
  const assetStats: Record<string, unknown> = {
    parsed: 1,
    reused: 0,
    inputBytes: 3,
    generatedBytes: 64,
  };
  let wasmBytes: unknown = wasm.length;
  if (mode === "wasm-length") wasmBytes = payload.length + 1;
  if (mode === "gap") asset.start = wasm.length + 1;
  if (mode === "trailing") asset.length = resource.length - 1;
  if (mode === "hash-format") asset.sha256 = "A".repeat(64);
  if (mode === "hash-data") asset.sha256 = "0".repeat(64);
  if (mode === "id") asset.id = 0;
  if (mode === "path") asset.path = "relative.bin";
  if (mode === "media") asset.mediaType = "bad\nmedia";
  if (mode === "dependency") dependencies[0].sha256 = 0;
  if (mode === "stats") assetStats.parsed = 0.5;
  const reply: Record<string, unknown> = {
    kind: "build",
    id: metadata.id,
    epoch: "native",
    revision,
    success: true,
    wasmBytes,
    assets: [asset],
    assetDependencies: dependencies,
    assetStats,
    stats: {
      nativeWorkSteps: 0,
      sourceBytes: 0,
      freshModules: 0,
      cachedModules: 0,
      restartCacheLoaded: false,
      frontend: {},
      backend: {},
      optimization: {},
      runtimeOptimization: {},
      backendTiming: {},
      workCounters: {},
      principals: {},
      refinements: {},
      selectedQueries: {},
      attemptStats: {},
    },
  };
  if (mode === "missing") delete reply.assetStats;
  await write(reply, payload);
}
