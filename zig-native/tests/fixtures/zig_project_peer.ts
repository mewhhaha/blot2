const [mode, log, command] = Deno.args;
await Deno.writeTextFile(
  log,
  JSON.stringify({
    pid: Deno.pid,
    command,
    ambient: Deno.env.get("BLOT_CLIENT_TEST_AMBIENT") ?? null,
  }) + "\n",
);
const encoder = new TextEncoder();
const identity = "a".repeat(64);
const wasm = Uint8Array.of(0, 97, 115, 109, 1, 0, 0, 0);
function frame(metadata: unknown, payload = new Uint8Array()): Uint8Array {
  const bytes = encoder.encode(JSON.stringify(metadata));
  const output = new Uint8Array(8 + bytes.length + payload.length);
  const view = new DataView(output.buffer);
  view.setUint32(0, bytes.length, true);
  view.setUint32(4, payload.length, true);
  output.set(bytes, 8);
  output.set(payload, 8 + bytes.length);
  return output;
}
async function write(bytes: Uint8Array) {
  if (mode === "fragmented") {
    for (let offset = 0; offset < bytes.length; offset += 3) {
      await Deno.stdout.write(bytes.subarray(offset, offset + 3));
    }
  } else {
    let offset = 0;
    while (offset < bytes.length) {
      offset += await Deno.stdout.write(bytes.subarray(offset));
    }
  }
}
const hello = {
  kind: "hello",
  protocol: "blot-zig-project",
  version: mode === "wrong-version" ? 2 : 1,
  compilerIdentity: identity,
  capabilities: ["project-build", "utf8_bytes", "abort-disposes-process"],
  maxFrameBytes: 67108864,
};
if (mode === "startup-stall") {
  await Deno.stdin.read(new Uint8Array(1));
  Deno.exit();
}
if (mode === "delayed") {
  await new Promise((resolve) => setTimeout(resolve, 100));
}
if (mode === "coalesced") {
  const first = frame(hello),
    second = frame({ kind: "open", id: 1, epoch: "epoch", revision: 0 });
  const bytes = new Uint8Array(first.length + second.length);
  bytes.set(first);
  bytes.set(second, first.length);
  await write(bytes);
} else {await write(
    frame(hello, mode === "hello-payload" ? Uint8Array.of(1) : undefined),
  );}
async function exact(length: number) {
  const output = new Uint8Array(length);
  let offset = 0;
  while (offset < length) {
    const count = await Deno.stdin.read(output.subarray(offset));
    if (count === null) Deno.exit();
    offset += count;
  }
  return output;
}
let revision = 0, builds = 0;
while (true) {
  const header = await exact(8),
    view = new DataView(header.buffer),
    length = view.getUint32(0, true);
  if (view.getUint32(4, true) !== 0) {
    throw new Error("Unexpected request payload");
  }
  const request = JSON.parse(new TextDecoder().decode(await exact(length)));
  await Deno.writeTextFile(log, JSON.stringify(request) + "\n", {
    append: true,
  });
  if (request.kind === "open") {
    if (mode !== "coalesced") {
      await write(
        frame({ kind: "open", id: request.id, epoch: "epoch", revision: 0 }),
      );
    }
    continue;
  }
  if (request.kind === "close") {
    await write(
      frame({
        kind: "close",
        id: mode === "close-id" ? request.id + 1 : request.id,
        epoch: "epoch",
        revision,
      }),
    );
    break;
  }
  builds++;
  if (mode === "hold" && builds === 1) {
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  if (mode === "active-stall") {
    await new Promise((resolve) => setTimeout(resolve, 60_000));
  }
  if (
    [
      "truncated-header",
      "truncated-metadata",
      "truncated-payload",
      "oversized",
      "oversized-metadata",
      "invalid-json",
      "invalid-utf8",
      "stderr",
    ].includes(mode)
  ) {
    if (mode === "stderr") {
      await Deno.stderr.write(
        encoder.encode("X".repeat(100_000) + "STDERR-TAIL\n"),
      );
    }
    if (mode === "truncated-header") await write(Uint8Array.of(1, 2));
    else {
      const bytes = new Uint8Array(10), data = new DataView(bytes.buffer);
      data.setUint32(
        0,
        mode === "oversized-metadata"
          ? 1048577
          : mode === "truncated-metadata"
          ? 99
          : mode === "invalid-utf8"
          ? 1
          : 2,
        true,
      );
      data.setUint32(
        4,
        mode === "oversized" ? 67108864 : mode === "truncated-payload" ? 99 : 0,
        true,
      );
      bytes.set(
        mode === "invalid-utf8" ? Uint8Array.of(255) : encoder.encode(
          mode === "invalid-json" || mode === "stderr" ? "??" : "{}",
        ),
        8,
      );
      await write(bytes.subarray(0, mode === "invalid-utf8" ? 9 : 10));
    }
    break;
  }
  const failure = mode === "invalid-hole" ||
    mode === "reject-first" && builds === 1 ||
    mode === "failed-revision" || mode === "reject-payload" ||
    mode === "missing-offset";
  const next = failure ? revision : revision + 1;
  const common = {
    kind: mode === "wrong-kind" ? "open" : "build",
    id: mode === "cross-id" ? request.id + 1 : request.id,
    epoch: mode === "wrong-epoch" ? "another" : "epoch",
    revision: mode === "same-revision"
      ? revision
      : mode === "failed-revision"
      ? next + 1
      : next,
  };
  if (failure) {
    await write(frame({
      ...common,
      success: false,
      diagnostics: [{
        filename: "/fixture.blot",
        stage: "check",
        code: mode === "invalid-hole" ? "typed_hole" : "type_mismatch",
        start: 1,
        end: 2,
        message: "fixture rejection",
        offset_encoding: mode === "missing-offset" ? "utf16" : "utf8_bytes",
        utf16: { start: 1, end: 2 },
        ...(mode === "invalid-hole"
          ? {
            details: {
              hole: {
                expected: 0,
                nodes: [{
                  kind: "function",
                  name: null,
                  identity: null,
                  variable: null,
                  effects: 0,
                  children: { start: 0, len: 0 },
                }],
                edges: [],
                scope: [],
                requirements: [],
                enclosing: { start: 0, len: 0 },
                truncated: false,
              },
            },
          }
          : {}),
      }],
      attemptStats: mode === "reject-first" ? null : {},
    }, mode === "reject-payload" ? wasm : undefined));
  } else {await write(
      frame({
        ...common,
        success: true,
        stats: mode === "source-fuel" ? { const_steps: 1 } : {
          ...(mode === "missing-work"
            ? {}
            : { nativeWorkSteps: mode === "fractional-work" ? 0.5 : builds }),
          frontend: {},
          sourceBytes: 0,
          freshModules: 0,
          cachedModules: 0,
          attemptStats: {},
          nested: { marker: builds },
        },
      }, mode === "invalid-wasm" ? Uint8Array.of(1, 2, 3) : wasm),
    );}
  revision = next;
}
