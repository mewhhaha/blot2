// Independent native-assets-v1 host: no production compiler/client imports.
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const executable = resolve(
  Deno.args[0] ??
    fileURLToPath(new URL("../zig-out/bin/blotc", import.meta.url)),
);
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
type Metadata = Record<string, any>;
type Frame = { metadata: Metadata; payload: Uint8Array<ArrayBuffer> };
type Input = readonly [string, string | Uint8Array<ArrayBuffer> | null];
function fields(value: Metadata, names: string[]) {
  equal(Object.keys(value).sort(), [...names].sort());
}
function natural(value: unknown) {
  ok(Number.isSafeInteger(value) && (value as number) >= 0);
}
function wire(metadata: Metadata | string, payload = new Uint8Array()) {
  let text = metadata;
  if (typeof text !== "string") text = JSON.stringify(text);
  const json = encoder.encode(text);
  const frame = new Uint8Array(8 + json.length + payload.length);
  const header = new DataView(frame.buffer);
  header.setUint32(0, json.length, true);
  header.setUint32(4, payload.length, true);
  frame.set(json, 8);
  frame.set(payload, 8 + json.length);
  return frame;
}
function partition(
  sources: readonly Input[] = [],
  assets: readonly Input[] = [],
) {
  const chunks: Uint8Array<ArrayBuffer>[] = [];
  let size = 0;
  function ranges(inputs: readonly Input[]) {
    return inputs.map(([path, contents]) => {
      let bytes = contents;
      if (typeof bytes === "string") bytes = encoder.encode(bytes);
      const range: Metadata = { path, start: size, length: bytes?.length ?? 0 };
      if (bytes === null) range.deleted = true;
      if (bytes) chunks.push(bytes);
      size += range.length;
      return range;
    });
  }
  const sourceRanges = ranges(sources), assetRanges = ranges(assets);
  const payload = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    payload.set(chunk, at);
    at += chunk.length;
  }
  return { sources: sourceRanges, assetSources: assetRanges, payload };
}
async function hash(bytes: Uint8Array<ArrayBuffer>) {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
async function host() {
  const directory = await Deno.makeTempDir({
    prefix: "blot-native-assets-wire-",
  });
  const entry = directory + "/main.blot";
  await Deno.writeTextFile(entry, "entry const answer = 42\n");
  const child = new Deno.Command(executable, {
    args: ["serve-project"],
    clearEnv: true,
    env: { BLOT_CACHE_DIR: "" },
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const reader = child.stdout.getReader(), writer = child.stdin.getWriter();
  const stderr = new Response(child.stderr).text();
  let pending: Uint8Array<ArrayBufferLike> = new Uint8Array();
  let id = 0, revision = 0;
  async function exact(length: number) {
    const bytes = new Uint8Array(length);
    let at = 0;
    while (at < length) {
      if (!pending.length) {
        const next = await reader.read();
        ok(!next.done, "Unexpected frame EOF");
        pending = next.value;
      }
      const count = Math.min(length - at, pending.length);
      bytes.set(pending.subarray(0, count), at);
      pending = pending.subarray(count);
      at += count;
    }
    return bytes;
  }
  async function frame(): Promise<Frame> {
    const header = new DataView((await exact(8)).buffer);
    const metadataLength = header.getUint32(0, true),
      payloadLength = header.getUint32(4, true);
    ok(metadataLength > 0 && metadataLength <= 1048576);
    ok(8 + metadataLength + payloadLength <= 67108864);
    const metadata = JSON.parse(decoder.decode(await exact(metadataLength)));
    ok(metadata && typeof metadata === "object" && !Array.isArray(metadata));
    return { metadata, payload: await exact(payloadLength) };
  }
  async function send(
    metadata: Metadata | string,
    payload?: Uint8Array<ArrayBuffer>,
  ) {
    await writer.write(wire(metadata, payload));
    return await frame();
  }
  const hello = await frame();
  equal([
    hello.metadata.kind,
    hello.metadata.protocol,
    hello.metadata.version,
    hello.metadata.maxFrameBytes,
  ], ["hello", "blot-zig-project", 1, 67108864]);
  ok(hello.metadata.capabilities.includes("native-assets-v1"));
  equal(hello.payload.length, 0);
  return {
    directory,
    entry,
    writer,
    send,
    async write(path: string, bytes: string | Uint8Array<ArrayBuffer>) {
      if (typeof bytes === "string") {
        await Deno.writeTextFile(directory + "/" + path, bytes);
      } else await Deno.writeFile(directory + "/" + path, bytes);
      return directory + "/" + path;
    },
    async open(nativeAssets?: Metadata) {
      const request: Metadata = {
        kind: "open",
        id: ++id,
        version: 1,
        entry,
        prelude: null,
      };
      if (nativeAssets !== undefined) request.nativeAssets = nativeAssets;
      const reply = await send(request);
      equal(reply.metadata, { kind: "open", id, epoch: "1", revision: 0 });
      equal(reply.payload.length, 0);
    },
    async build(sources: readonly Input[] = [], assets: readonly Input[] = []) {
      const parts = partition(sources, assets);
      const reply = await send({
        kind: "build",
        id: ++id,
        epoch: "1",
        revision,
        sources: parts.sources,
        assetSources: parts.assetSources,
      }, parts.payload);
      equal([reply.metadata.kind, reply.metadata.id, reply.metadata.epoch], [
        "build",
        id,
        "1",
      ]);
      if (reply.metadata.success) {
        equal(reply.metadata.revision, revision + 1);
        revision++;
      } else equal(reply.metadata.revision, revision);
      return reply;
    },
    async close() {
      const reply = await send({
        kind: "close",
        id: ++id,
        epoch: "1",
        revision,
      });
      equal(reply.metadata, { kind: "close", id, epoch: "1", revision });
      equal(reply.payload.length, 0);
      equal((await child.status).code, 0);
      equal(await stderr, "");
    },
    async terminal(
      metadata: Metadata | string,
      payload?: Uint8Array<ArrayBuffer>,
      error?: string,
    ) {
      await writer.write(wire(metadata, payload));
      equal(pending.length, 0);
      equal((await reader.read()).done, true);
      equal((await child.status).code, 1);
      const text = await stderr;
      if (error) ok(text.endsWith(`blotc: ${error}\n`), text);
    },
    async cleanup() {
      try {
        child.kill("SIGKILL");
      } catch (error) {
        if (
          !(error instanceof Deno.errors.NotFound) &&
          !(error instanceof TypeError)
        ) throw error;
      }
      await child.status;
      await stderr;
      await reader.cancel();
      try {
        await writer.close();
      } catch { /* Terminal child. */ }
      await Deno.remove(directory, { recursive: true });
    },
  };
}
async function success(frame: Frame, answers: Metadata = {}) {
  const meta = frame.metadata;
  equal(meta.success, true, JSON.stringify(meta));
  fields(meta, [
    "kind",
    "id",
    "epoch",
    "revision",
    "success",
    "stats",
    "wasmBytes",
    "assets",
    "assetDependencies",
    "assetStats",
  ]);
  natural(meta.wasmBytes);
  ok(meta.wasmBytes > 0 && meta.wasmBytes <= frame.payload.length);
  fields(meta.assetStats, ["parsed", "reused", "inputBytes", "generatedBytes"]);
  for (const value of Object.values(meta.assetStats)) natural(value);
  let end = meta.wasmBytes;
  for (const [index, item] of meta.assets.entries()) {
    fields(item, ["id", "path", "mediaType", "sha256", "start", "length"]);
    equal(item.id, index + 1);
    equal(item.start, end);
    natural(item.length);
    ok(item.length <= frame.payload.length - end);
    ok(item.path.startsWith("/") && item.mediaType.length > 0);
    equal(
      item.sha256,
      await hash(frame.payload.slice(item.start, item.start + item.length)),
    );
    end += item.length;
  }
  equal(end, frame.payload.length);
  for (const item of meta.assetDependencies) {
    fields(item, ["path", "sha256"]);
    ok(item.path.startsWith("/"));
    ok(item.sha256 === null || /^[0-9a-f]{64}$/.test(item.sha256));
  }
  equal(
    meta.assetDependencies.map((item: Metadata) => item.path),
    meta.assetDependencies.map((item: Metadata) => item.path).sort(),
  );
  const wasm = frame.payload.slice(0, meta.wasmBytes);
  ok(WebAssembly.validate(wasm));
  const instantiated = await WebAssembly.instantiate(wasm);
  for (const [name, value] of Object.entries(answers)) {
    equal(
      (instantiated.instance.exports[name] as WebAssembly.Global).value,
      value,
    );
  }
  return wasm;
}
function rejection(frame: Frame, code: string, stage = "asset") {
  const meta = frame.metadata;
  fields(meta, [
    "kind",
    "id",
    "epoch",
    "revision",
    "success",
    "diagnostics",
    "attemptStats",
  ]);
  equal(meta.success, false);
  equal(frame.payload.length, 0);
  equal(meta.diagnostics.length, 1);
  const diagnostic = meta.diagnostics[0];
  fields(diagnostic, [
    "filename",
    "stage",
    "code",
    "start",
    "end",
    "message",
    "offset_encoding",
    "utf16",
    "details",
  ]);
  equal(diagnostic.stage, stage, JSON.stringify(meta));
  equal(diagnostic.code, code);
  equal(diagnostic.offset_encoding, "utf8_bytes");
  natural(diagnostic.start);
  natural(diagnostic.end);
  ok(diagnostic.start <= diagnostic.end);
  equal(diagnostic.utf16, null);
  equal(diagnostic.details, null);
  if (stage === "asset") equal(meta.attemptStats, null);
  return diagnostic;
}
function definition(
  peer: Awaited<ReturnType<typeof host>>,
  name: string,
  kind: string,
  extra: Metadata = {},
) {
  return {
    module: peer.directory + "/" + name + ".blot",
    path: peer.directory + "/" + name,
    kind,
    ...extra,
  };
}

Deno.test("native asset wire: all readers and real executed Wasm", async () => {
  const peer = await host();
  try {
    const inputs = [
      ["data.json", "json", '{"answer":20}'],
      [
        "catalog.json",
        "catalog",
        '{"meshes":["first.mesh.json","second.mesh.json"],"materials":[],"sounds":[]}',
      ],
      ["text.json", "text", '{"greeting":"å…","lines":["a",""]}'],
      [
        "tunables.json",
        "tunables",
        '{"tunables":[{"name":"camera.zoom","default":0.1,"min":0,"max":1,"doc":"😀"}]}',
      ],
      [
        "shader.wgsl",
        "wgsl",
        "alias Scalar=f32; struct Parameters { gain:Scalar } const count=1u+21u; const skipped:u32=2;",
      ],
    ];
    for (const [path, , input] of inputs) await peer.write(path, input);
    await peer.write(
      "main.blot",
      'import * as config from "./data.json"\nimport * as catalog from "./catalog.json"\nimport * as words from "./text.json"\nimport * as knobs from "./tunables.json"\nimport * as shader from "./shader.wgsl"\nentry const answer = @u32.add (config.value).answer shader.count\nentry const mesh = (catalog.meshes).second\nentry const letter = @array.get (words.text).greeting 0\nentry const tune = @product.get (knobs.tunables).camera_zoom 0\n',
    );
    await peer.open({
      imports: inputs.map(([path, kind]) => definition(peer, path, kind)),
      roots: [],
    });
    const built = await peer.build();
    await success(built, { answer: 42, mesh: 1, letter: 229, tune: 16562854 });
    equal(built.metadata.assets, []);
    equal(built.metadata.assetStats.parsed, 5);
    equal(built.metadata.assetDependencies.length, 5);
    for (const [path, , input] of inputs) {
      equal(
        built.metadata.assetDependencies.find((item: Metadata) =>
          item.path === peer.directory + "/" + path
        )?.sha256,
        await hash(encoder.encode(input)),
      );
    }
    const retained = await peer.build();
    await success(retained, { answer: 42 });
    equal(retained.metadata.assetStats.reused, 5);
    equal(retained.metadata.assetStats.parsed, 0);
    equal(retained.payload, built.payload);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: mixed source/asset partitions, rejected edits, deletion and recovery", async () => {
  const peer = await host();
  try {
    const path = await peer.write("data.json", '{"answer":42}');
    const source =
      'import * as config from "./data.json"\nentry const answer = (config.value).answer\n';
    await peer.open({ imports: [definition(peer, "data.json", "json")] });
    const original = await peer.build([[peer.entry, source]]);
    const wasm = await success(original, { answer: 42 });
    const edited = await peer.build([[peer.entry, source]], [[
      path,
      '{"answer":43}',
    ]]);
    await success(edited, { answer: 43 });
    equal(edited.metadata.assetStats.parsed, 1);
    equal(await Deno.readTextFile(path), '{"answer":42}');
    rejection(
      await peer.build([[peer.entry, source]], [[path, "{"]]),
      "asset_json",
    );
    rejection(
      await peer.build([[peer.entry, source]], [[path, null]]),
      "asset_missing",
    );
    const compilerFailure = await peer.build([[
      peer.entry,
      "entry const answer: U32 = true\n",
    ]], [[path, '{"answer":44}']]);
    equal(compilerFailure.metadata.success, false);
    ok(compilerFailure.metadata.diagnostics[0].stage !== "asset");
    const unchanged = await peer.build([[peer.entry, source]], [[
      path,
      '{"answer":43}',
    ]]);
    await success(unchanged, { answer: 43 });
    equal(unchanged.metadata.assetStats.reused, 1);
    await Deno.remove(path);
    rejection(await peer.build([[peer.entry, source]]), "asset_input");
    const recovered = await peer.build([[peer.entry, source]], [[
      path,
      '{"answer":42}',
    ]]);
    equal(await success(recovered, { answer: 42 }), wasm);
    equal(original.payload.slice(0, original.metadata.wasmBytes), wasm);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: deterministic content handles, binary frames and owned snapshots", async () => {
  const peer = await host();
  try {
    const a = Uint8Array.of(0, 255, 254), b = new Uint8Array();
    const aPath = await peer.write("a.bin", a),
      bPath = await peer.write("b.bin", b);
    const reference = {
      type: "Content",
      export: "content",
      mediaType: "application/octet-stream",
    };
    await peer.open({
      imports: [
        definition(peer, "b.bin", "reference", reference),
        definition(peer, "a.bin", "reference", reference),
        {
          ...definition(peer, "a.bin", "reference", reference),
          module: peer.directory + "/alias.blot",
        },
      ],
    });
    const source =
      'import * as a from "./a.bin"\nimport * as alias from "./alias"\nentry const answer = case a.content of\n  $a.Content id => id\nentry const same = case alias.content of\n  $alias.Content id => id\n';
    const first = await peer.build([[peer.entry, source]], [[aPath, a], [
      bPath,
      b,
    ]]);
    await success(first, { answer: 1, same: 1 });
    equal(first.metadata.assets.length, 2);
    equal(first.metadata.assets.map((item: Metadata) => item.path), [
      aPath,
      bPath,
    ]);
    const owned = first.payload.slice();
    const changedBytes = Uint8Array.of(9, 8, 7);
    const second = await peer.build([[peer.entry, source]], [[
      aPath,
      changedBytes,
    ]]);
    await success(second, { answer: 1 });
    equal(first.payload, owned);
    const range = second.metadata.assets[0];
    equal(
      second.payload.slice(range.start, range.start + range.length),
      changedBytes,
    );
    second.payload.fill(17);
    const third = await peer.build([[peer.entry, source]]);
    await success(third, { answer: 1 });
    equal(first.payload, owned);
    equal(third.payload, first.payload);
    equal(third.metadata.assetDependencies.length, 2);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: root discovery reacquires additions removals and virtual overrides", async () => {
  const peer = await host();
  try {
    await Deno.mkdir(peer.directory + "/assets");
    await peer.open({ roots: [peer.directory] });
    const empty = await peer.build();
    await success(empty, { answer: 42 });
    equal(empty.metadata.assetStats.parsed, 0);
    const shader = await peer.write("assets/new.wgsl", "const count=7u;");
    const source =
      'import * as shader from "./assets/new.wgsl"\nentry const answer = shader.count\n';
    const added = await peer.build([[peer.entry, source]]);
    await success(added, { answer: 7 });
    equal(added.metadata.assetStats.parsed, 1);
    await Deno.remove(shader);
    const removed = await peer.build();
    await success(removed, { answer: 42 });
    equal(removed.metadata.assetDependencies, []);
    const virtual = await peer.build([[peer.entry, source]], [[
      shader,
      "const count=8u;",
    ]]);
    await success(virtual, { answer: 8 });
    const hidden = await peer.build([], [[shader, null]]);
    await success(hidden, { answer: 42 });
    equal(hidden.metadata.assetDependencies, []);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: symlink retargeting changes captured inputs and duplicate identity rejects", async () => {
  const peer = await host();
  try {
    const firstPath = await peer.write("first.json", '{"answer":1}');
    const secondPath = await peer.write("second.json", '{"answer":2}');
    const link = peer.directory + "/linked.json";
    await Deno.symlink(firstPath, link);
    await peer.write(
      "main.blot",
      'import * as config from "./linked.json"\nentry const answer=(config.value).answer\n',
    );
    await peer.open({ imports: [definition(peer, "linked.json", "json")] });
    await success(await peer.build(), { answer: 1 });
    await Deno.remove(link);
    await Deno.symlink(secondPath, link);
    const retargeted = await peer.build();
    await success(retargeted, { answer: 2 });
    equal(retargeted.metadata.assetStats.parsed, 1);
    equal(retargeted.metadata.assetDependencies[0].path, link);
    rejection(
      await peer.build([], [[link, '{"answer":3}'], [
        secondPath,
        '{"answer":4}',
      ]]),
      "DuplicateSourcePath",
      "build-project",
    );
    const recovered = await peer.build();
    await success(recovered, { answer: 2 });
    equal(recovered.metadata.assetStats.reused, 1);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: generated/source collision rejects without committing either owner", async () => {
  const peer = await host();
  try {
    await peer.write("data.json", '{"answer":42}');
    await peer.open({ imports: [definition(peer, "data.json", "json")] });
    const good = await peer.build();
    await success(good, { answer: 42 });
    rejection(
      await peer.build([[
        peer.directory + "/data.json.blot",
        "const answer=0\n",
      ]]),
      "DuplicateAssetModule",
      "build-project",
    );
    const recovered = await peer.build();
    await success(recovered, { answer: 42 });
    equal(recovered.metadata.assetStats.reused, 1);
    equal(recovered.payload, good.payload);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: oversized combined reply preserves revision and asset reuse", async () => {
  const peer = await host();
  try {
    const imports = [];
    for (let index = 0; index < 4; index++) {
      const name = `blob${index}.bin`;
      await peer.write(name, Uint8Array.of(index));
      imports.push(
        definition(peer, name, "reference", {
          type: "Content",
          export: "content",
          mediaType: "application/octet-stream",
        }),
      );
    }
    await peer.open({ imports });
    const first = await peer.build();
    await success(first, { answer: 42 });
    const large = new Uint8Array(16 * 1024 * 1024);
    for (let index = 0; index < 4; index++) {
      await peer.write(`blob${index}.bin`, large);
    }
    rejection(await peer.build(), "response_limit", "build-project");
    for (let index = 0; index < 4; index++) {
      await peer.write(`blob${index}.bin`, Uint8Array.of(index));
    }
    const recovered = await peer.build();
    await success(recovered, { answer: 42 });
    equal(recovered.metadata.assetStats.reused, 4);
    equal(recovered.payload, first.payload);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

for (
  const [kind, bytes, code] of [
    ["json", "{", "asset_json"],
    ["json", Uint8Array.of(255), "asset_unicode"],
    ["catalog", '{"meshes":["a.mesh.json","a.json"]}', "asset_catalog"],
    ["text", '{"greeting":"😀😀\\n"}', "asset_font"],
    [
      "tunables",
      '{"tunables":[{"name":"x","default":2,"min":0,"max":1}]}',
      "asset_tunables",
    ],
    ["wgsl", "struct Parameters { x:u32 }", "asset_wgsl_parameters"],
    [
      "wgsl",
      "const packed=pack2x16float(vec2f(1.0));",
      "asset_wgsl_evaluation",
    ],
  ] as const
) {
  Deno.test(`native asset wire: positioned ${kind} rejection ${code}`, async () => {
    const peer = await host();
    try {
      const path = peer.directory + "/input";
      await peer.open({ imports: [definition(peer, "input", kind)] });
      const failed = await peer.build([], [[path, bytes]]);
      const diagnostic = rejection(failed, code);
      equal(diagnostic.filename, path);
      let length = bytes.length;
      if (typeof bytes === "string") length = encoder.encode(bytes).length;
      ok(diagnostic.end <= length);
      ok(diagnostic.message.length > 0);
      if (kind === "text") {
        equal(diagnostic.message, "text greeting: the font has no 😀\n");
      }
      await peer.close();
    } finally {
      await peer.cleanup();
    }
  });
}

for (
  const [label, config, error] of [
    ["relative root", { roots: ["relative"] }, "InvalidNativeAssets"],
    ["relative module", {
      imports: [{ module: "relative.blot", path: "/input", kind: "json" }],
    }, "InvalidNativeAssets"],
    ["module suffix", {
      imports: [{ module: "/data.json", path: "/input", kind: "json" }],
    }, "InvalidNativeAssets"],
    ["missing reference metadata", {
      imports: [{
        module: "/asset.blot",
        path: "/input",
        kind: "reference",
        type: "Content",
        export: "content",
      }],
    }, "InvalidNativeAssets"],
    ["extra parser metadata", {
      imports: [{
        module: "/asset.blot",
        path: "/input",
        kind: "json",
        type: "Content",
      }],
    }, "InvalidNativeAssets"],
    ["unknown nested field", { roots: [], unknown: true }, "UnknownField"],
  ] as const
) {
  Deno.test(`native asset wire: terminal open rejects ${label}`, async () => {
    const peer = await host();
    try {
      await peer.terminal(
        {
          kind: "open",
          id: 1,
          version: 1,
          entry: peer.entry,
          nativeAssets: config,
        },
        undefined,
        error,
      );
    } finally {
      await peer.cleanup();
    }
  });
}

for (
  const mode of [
    "gap",
    "deleted bytes",
    "unused tail",
    "asset without native session",
    "build options",
    "close assets",
  ]
) {
  Deno.test(`native asset wire: terminal request rejects ${mode}`, async () => {
    const peer = await host();
    try {
      let nativeAssets: Metadata | undefined = {};
      if (mode === "asset without native session") nativeAssets = undefined;
      await peer.open(nativeAssets);
      const request: Metadata = {
        kind: "build",
        id: 2,
        epoch: "1",
        revision: 0,
      };
      let payload = Uint8Array.of(255), code = "InvalidSources";
      request.assetSources = [{
        path: peer.directory + "/input",
        start: 0,
        length: 1,
      }];
      if (mode === "gap") request.assetSources[0].start = 1;
      if (mode === "deleted bytes") request.assetSources[0].deleted = true;
      if (mode === "unused tail") request.assetSources[0].length = 0;
      if (mode === "asset without native session") code = "InvalidRequest";
      if (mode === "build options") {
        request.nativeAssets = {};
        code = "InvalidRequest";
      }
      if (mode === "close assets") {
        request.kind = "close";
        payload = new Uint8Array();
        request.assetSources[0].length = 0;
        code = "InvalidRequest";
      }
      await peer.terminal(request, payload, code);
    } finally {
      await peer.cleanup();
    }
  });
}

Deno.test("native asset wire: opt-in empty sessions and source-only replies retain distinct schemas", async () => {
  for (const native of [false, true]) {
    const peer = await host();
    try {
      if (native) await peer.open({ imports: [], roots: [] });
      else await peer.open();
      const built = await peer.build();
      if (native) {
        await success(built, { answer: 42 });
        equal(built.metadata.assets, []);
        equal(built.metadata.assetDependencies, []);
        equal(built.metadata.assetStats, {
          parsed: 0,
          reused: 0,
          inputBytes: 0,
          generatedBytes: 0,
        });
      } else {
        fields(built.metadata, [
          "kind",
          "id",
          "epoch",
          "revision",
          "success",
          "stats",
        ]);
        equal(built.metadata.success, true);
        ok(WebAssembly.validate(built.payload));
      }
      await peer.close();
    } finally {
      await peer.cleanup();
    }
  }
});

Deno.test("native asset wire: duplicate generated mappings reject as a recoverable build operation", async () => {
  const peer = await host();
  try {
    await peer.write("data.json", '{"answer":42}');
    const mapping = definition(peer, "data.json", "json");
    await peer.open({ imports: [mapping, mapping] });
    rejection(await peer.build(), "DuplicateAssetModule", "build-project");
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

for (
  const [label, mediaType] of [
    ["empty", ""],
    ["newline", "text/plain\n"],
    ["return", "text/plain\r"],
    ["NUL", "text/plain\0"],
    ["too many units", "a".repeat(257)],
    ["astral units", "😀".repeat(129)],
  ]
) {
  Deno.test(`native asset wire: terminal reference mediaType rejects ${label}`, async () => {
    const peer = await host();
    try {
      await peer.terminal(
        {
          kind: "open",
          id: 1,
          version: 1,
          entry: peer.entry,
          nativeAssets: {
            imports: [
              definition(peer, "input", "reference", {
                type: "Content",
                export: "content",
                mediaType,
              }),
            ],
          },
        },
        undefined,
        "InvalidNativeAssets",
      );
    } finally {
      await peer.cleanup();
    }
  });
}

Deno.test("native asset wire: explicit aliases share input acquisition with normal root discovery", async () => {
  const peer = await host();
  try {
    const input = '{"greeting":"å"}';
    const path = await peer.write("text.json", input);
    const alias = {
      module: peer.directory + "/alias.blot",
      path,
      kind: "text",
    };
    await peer.open({
      imports: [alias],
      roots: [peer.directory, peer.directory],
    });
    const source =
      'import * as normal from "./text.json"\nimport * as alias from "./alias"\nentry const answer = @u32.add (@array.get (normal.text).greeting 0) (@array.get (alias.text).greeting 0)\n';
    const built = await peer.build([[peer.entry, source]]);
    await success(built, { answer: 458 });
    equal(built.metadata.assetStats.parsed, 2);
    equal(built.metadata.assetStats.inputBytes, encoder.encode(input).length);
    equal(built.metadata.assetDependencies, [{
      path,
      sha256: await hash(encoder.encode(input)),
    }]);
    const retained = await peer.build([[peer.entry, source]]);
    await success(retained, { answer: 458 });
    equal(retained.metadata.assetStats.reused, 2);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: explicit mapping colliding with a discovered module rejects", async () => {
  const peer = await host();
  try {
    await peer.write("text.json", '{"greeting":"a"}');
    await peer.open({
      imports: [definition(peer, "text.json", "text")],
      roots: [peer.directory],
    });
    rejection(await peer.build(), "DuplicateAssetModule", "build-project");
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});

Deno.test("native asset wire: long Unicode JSON names reject with bounded UTF8 and recover", async () => {
  const peer = await host();
  try {
    const path = await peer.write("data.json", '{"answer":42}');
    await peer.write(
      "main.blot",
      'import * as config from "./data.json"\nentry const answer = (config.value).answer\n',
    );
    await peer.open({ imports: [definition(peer, "data.json", "json")] });
    const before = await peer.build();
    await success(before, { answer: 42 });
    const name = "a".repeat(255) + "å";
    const input = JSON.stringify({ [name]: true });
    const failed = await peer.build([], [[path, input]]);
    const diagnostic = rejection(failed, "asset_identifier");
    equal(diagnostic.filename, path);
    equal(
      diagnostic.message,
      "Invalid Blot value/field name: " + "a".repeat(255),
    );
    ok(diagnostic.message.isWellFormed());
    ok(encoder.encode(diagnostic.message).length <= 1024);
    equal(
      decoder.decode(encoder.encode(diagnostic.message)),
      diagnostic.message,
    );
    equal(
      diagnostic.start,
      encoder.encode(input.slice(0, input.lastIndexOf("true"))).length,
    );
    equal(diagnostic.end, diagnostic.start + 4);
    const recovered = await peer.build();
    await success(recovered, { answer: 42 });
    equal(recovered.metadata.assetStats.reused, 1);
    equal(recovered.payload, before.payload);
    await peer.close();
  } finally {
    await peer.cleanup();
  }
});
