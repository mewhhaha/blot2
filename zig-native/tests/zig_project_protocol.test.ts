// Independent host implementation of PROJECT_PROTOCOL.md: no project client imports.
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const executable = resolve(
  Deno.args[0] ??
    fileURLToPath(new URL("../zig-out/bin/blotc", import.meta.url)),
);
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const statObjects = [
  "sourceValidation",
  "frontend",
  "backend",
  "optimization",
  "runtimeOptimization",
  "backendTiming",
  "phaseProfile",
  "workCounters",
  "principals",
  "refinements",
  "selectedQueries",
  "constantReceipts",
  "attemptStats",
];
type Metadata = Record<string, any>;
function wire(
  metadata: string | Metadata,
  payload: Uint8Array = new Uint8Array(),
): Uint8Array {
  let text = metadata;
  if (typeof text !== "string") text = JSON.stringify(text);
  const json = encoder.encode(text);
  const bytes = new Uint8Array(8 + json.length + payload.length);
  const header = new DataView(bytes.buffer);
  header.setUint32(0, json.length, true);
  header.setUint32(4, payload.length, true);
  bytes.set(json, 8);
  bytes.set(payload, 8 + json.length);
  return bytes;
}
function header(metadata: number, payload = 0) {
  const bytes = new Uint8Array(8);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, metadata, true);
  view.setUint32(4, payload, true);
  return bytes;
}
function object(value: unknown) {
  ok(value && typeof value === "object" && !Array.isArray(value));
}
function natural(value: unknown) {
  ok(Number.isSafeInteger(value) && (value as number) >= 0);
}
function fields(value: Metadata, names: string[]) {
  equal(Object.keys(value).sort(), names.sort());
}
async function host() {
  const directory = await Deno.makeTempDir({ prefix: "blot-protocol-" });
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
  const reader = child.stdout.getReader();
  const writer = child.stdin.getWriter();
  const stderr = new Response(child.stderr).text();
  let pending = new Uint8Array();
  async function exact(length: number) {
    const output = new Uint8Array(length);
    let offset = 0;
    while (offset < length) {
      if (!pending.length) {
        const read = await reader.read();
        ok(!read.done, "Unexpected frame EOF");
        pending = read.value;
      }
      const count = Math.min(length - offset, pending.length);
      output.set(pending.subarray(0, count), offset);
      pending = pending.subarray(count);
      offset += count;
    }
    return output;
  }
  async function frame() {
    const bytes = await exact(8);
    const view = new DataView(bytes.buffer);
    const metadataLength = view.getUint32(0, true);
    const payloadLength = view.getUint32(4, true);
    ok(metadataLength > 0 && metadataLength <= 16777216);
    ok(8 + metadataLength + payloadLength <= 67108864);
    const metadata = JSON.parse(decoder.decode(await exact(metadataLength)));
    object(metadata);
    return {
      metadata: metadata as Metadata,
      payload: await exact(payloadLength),
    };
  }
  async function send(metadata: string | Metadata, payload?: Uint8Array) {
    await writer.write(wire(metadata, payload));
    return await frame();
  }
  const hello = await frame();
  fields(hello.metadata, [
    "kind",
    "protocol",
    "version",
    "compilerIdentity",
    "capabilities",
    "maxFrameBytes",
  ]);
  equal(hello.payload.length, 0);
  equal(hello.metadata.kind, "hello");
  equal(hello.metadata.protocol, "blot-zig-project");
  equal(hello.metadata.version, 1);
  ok(/^[0-9a-f]{64}$/.test(hello.metadata.compilerIdentity));
  equal(hello.metadata.maxFrameBytes, 67108864);
  equal(hello.metadata.capabilities, [
    "project-build",
    "utf8_bytes",
    "abort-disposes-process",
    "source-overlays",
    "backend-checkpoints",
    "native-assets-v1",
    "editor-completion-v1",
    "allocation-explanations-v1",
  ]);
  return {
    entry,
    child,
    writer,
    send,
    frame,
    async open(extra: Metadata = {}, payload?: Uint8Array) {
      const reply = await send({
        kind: "open",
        id: 1,
        version: 1,
        entry,
        ...extra,
      }, payload);
      equal(reply.metadata, { kind: "open", id: 1, epoch: "1", revision: 0 });
      equal(reply.payload.length, 0);
    },
    async ended(code: number, error?: string) {
      equal(pending.length, 0);
      equal(
        (await reader.read()).done,
        true,
        "Terminal errors must not send replies",
      );
      equal((await child.status).code, code);
      const text = await stderr;
      if (error) ok(text.endsWith(`blotc: ${error}\n`), text);
      else equal(text, "");
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
      } catch { /* Child may already be terminal. */ }
      await Deno.remove(directory, { recursive: true });
    },
  };
}
function rejected(
  reply: { metadata: Metadata; payload: Uint8Array },
  id: number,
  revision: number,
) {
  fields(reply.metadata, [
    "kind",
    "id",
    "epoch",
    "revision",
    "success",
    "diagnostics",
    "attemptStats",
  ]);
  const meta = reply.metadata;
  equal([meta.kind, meta.id, meta.epoch, meta.revision, meta.success], [
    "build",
    id,
    "1",
    revision,
    false,
  ]);
  equal(reply.payload.length, 0);
  equal(meta.diagnostics.length, 1);
  if (meta.attemptStats !== null) object(meta.attemptStats);
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
  for (const name of ["filename", "stage", "code", "message"]) {
    equal(typeof diagnostic[name], "string");
  }
  natural(diagnostic.start);
  natural(diagnostic.end);
  ok(diagnostic.start <= diagnostic.end);
  equal(diagnostic.offset_encoding, "utf8_bytes");
  return diagnostic;
}
Deno.test("wire contract: build, rejection details, revisions, checkpoint and close", async () => {
  const peer = await host();
  try {
    // Explicit null/default fields have the same meaning as omission.
    await peer.open({
      epoch: null,
      revision: null,
      sources: [],
      imports: [],
      prelude: null,
      stdRoot: null,
      dependencies: null,
      profileBackend: false,
      codegenTier: "development",
      shareMachineCode: false,
      codegenWorkers: 1,
      checkpoint: false,
    });
    const built = await peer.send({
      kind: "build",
      id: 2,
      epoch: "1",
      revision: 0,
    });
    fields(built.metadata, [
      "kind",
      "id",
      "epoch",
      "revision",
      "success",
      "stats",
    ]);
    equal([
      built.metadata.kind,
      built.metadata.id,
      built.metadata.epoch,
      built.metadata.revision,
      built.metadata.success,
    ], ["build", 2, "1", 1, true]);
    ok(WebAssembly.validate(built.payload));
    const wasm = await WebAssembly.instantiate(built.payload);
    equal((wasm.instance.exports.answer as WebAssembly.Global).value, 42);
    fields(built.metadata.stats, [
      "nativeWorkSteps",
      "demandLowering",
      "allocationSites",
      "arrayCosts",
      "sourceBytes",
      "freshModules",
      "cachedModules",
      "restartCacheLoaded",
      "restartCacheWrite",
      "sessionHeap",
      ...statObjects,
    ]);
    for (
      const key of [
        "nativeWorkSteps",
        "sourceBytes",
        "freshModules",
        "cachedModules",
      ]
    ) natural(built.metadata.stats[key]);
    for (const key of statObjects) object(built.metadata.stats[key]);
    equal(built.metadata.stats.restartCacheLoaded, false);
    equal(built.metadata.stats.demandLowering, null);
    equal(built.metadata.stats.sessionHeap, null);
    let id = 3;
    for (
      const source of [
        "// 雪\nconst incomplete = fn (value: U32) -> U32 => @hole\nentry const answer = 42\n",
        'entry const answer = @type.call "add" #True #True\n',
      ]
    ) {
      const payload = encoder.encode(source);
      const reply = await peer.send({
        kind: "build",
        id,
        epoch: "1",
        revision: 1,
        sources: [{ path: peer.entry, start: 0, length: payload.length }],
      }, payload);
      const diagnostic = rejected(reply, id++, 1);
      if (diagnostic.code === "typed_hole") {
        const start = source.indexOf("@hole");
        equal(diagnostic.start, encoder.encode(source.slice(0, start)).length);
        equal(diagnostic.utf16, { start, end: start + 5 });
        object(diagnostic.details.hole);
        const hole = diagnostic.details.hole;
        fields(hole, [
          "expected",
          "nodes",
          "edges",
          "scope",
          "requirements",
          "enclosing",
          "truncated",
        ]);
        natural(hole.expected);
        ok(hole.expected < hole.nodes.length);
        for (const key of ["nodes", "edges", "scope", "requirements"]) {
          ok(Array.isArray(hole[key]));
        }
        equal(typeof hole.truncated, "boolean");
        equal(hole.nodes[hole.expected].kind, "u32");
        const binding = hole.scope.find((item: Metadata) =>
          item.name === "value"
        );
        ok(binding);
        equal(hole.nodes[binding.type].kind, "u32");
        const reference = (value: unknown) => {
          if (value === null) return;
          natural(value);
          ok((value as number) < hole.nodes.length);
        };
        const span = (value: Metadata, bound: number) => {
          fields(value, ["start", "len"]);
          natural(value.start);
          natural(value.len);
          ok(value.start + value.len <= bound);
        };
        span(hole.enclosing, hole.requirements.length);
        for (const node of hole.nodes) {
          fields(node, [
            "kind",
            "name",
            "identity",
            "variable",
            "children",
            "effects",
          ]);
          equal(typeof node.kind, "string");
          if (node.name !== null) equal(typeof node.name, "string");
          if (node.variable !== null) natural(node.variable);
          if (node.identity !== null) {
            fields(node.identity, ["unit", "decl"]);
            natural(node.identity.unit);
            natural(node.identity.decl);
          }
          reference(node.effects);
          span(node.children, hole.edges.length);
        }
        for (const edge of hole.edges) {
          fields(edge, ["name", "type"]);
          reference(edge.type);
          if (edge.name !== null) equal(typeof edge.name, "string");
        }
        for (const item of hole.scope) {
          fields(item, ["name", "type", "requirements"]);
          equal(typeof item.name, "string");
          reference(item.type);
          span(item.requirements, hole.requirements.length);
        }
        for (const requirement of hole.requirements) {
          fields(requirement, [
            "kind",
            "name",
            "subject",
            "argument",
            "result",
            "signature",
            "explicit",
          ]);
          equal(typeof requirement.kind, "string");
          if (requirement.name !== null) {
            equal(typeof requirement.name, "string");
          }
          equal(typeof requirement.explicit, "boolean");
          for (const key of ["subject", "argument", "result", "signature"]) {
            reference(requirement[key]);
          }
        }
      } else {
        const explanation = diagnostic.details.explanation;
        const first = source.indexOf("#True");
        const second = source.indexOf("#True", first + 1);
        equal(explanation.contexts, [
          {
            kind: "left_operand",
            path: peer.entry,
            span: { start: first, end: first + 5 },
          },
          {
            kind: "right_operand",
            path: peer.entry,
            span: { start: second, end: second + 5 },
          },
        ]);
        const { contexts: _contexts, ...withoutContexts } = explanation;
        equal(withoutContexts, {
          operation: "+",
          member: "add",
          candidates: [{
            side: "left",
            operand: "Bool",
            outcome: "no_member",
          }],
          truncated: false,
        });
      }
    }
    const duplicate = await peer.send({
      kind: "build",
      id,
      epoch: "1",
      revision: 1,
      sources: [{ path: peer.entry, start: 0, length: 0 }, {
        path: peer.entry,
        start: 0,
        length: 0,
      }],
    });
    const diagnostic = rejected(duplicate, id++, 1);
    equal([
      diagnostic.stage,
      diagnostic.code,
      diagnostic.start,
      diagnostic.end,
      diagnostic.utf16,
      diagnostic.details,
    ], ["build-project", "DuplicateSourcePath", 0, 0, null, null]);
    equal(duplicate.metadata.attemptStats, null);
    const oversizedSource = new Uint8Array(16 * 1024 * 1024 + 1).fill(32);
    const limited = await peer.send({
      kind: "build",
      id,
      epoch: "1",
      revision: 1,
      sources: [{ path: peer.entry, start: 0, length: oversizedSource.length }],
    }, oversizedSource);
    const sourceLimit = rejected(limited, id++, 1);
    equal([sourceLimit.stage, sourceLimit.code], [
      "build-project",
      "SourceLimit",
    ]);
    equal(limited.metadata.attemptStats, null);
    const recovery = await peer.send({
      kind: "build",
      id: id++,
      epoch: "1",
      revision: 1,
    });
    equal(recovery.metadata.revision, 2);
    equal(recovery.metadata.success, true);
    equal(recovery.payload, built.payload);
    const checkpoint = await peer.send({
      kind: "checkpoint",
      id: id++,
      epoch: "1",
      revision: 2,
    });
    fields(checkpoint.metadata, ["kind", "id", "epoch", "revision", "success"]);
    equal(checkpoint.metadata.revision, 2);
    equal(checkpoint.metadata.success, true);
    ok(checkpoint.payload.length > 0);
    const close = await peer.send({
      kind: "close",
      id,
      epoch: "1",
      revision: 2,
    });
    equal(close.metadata, { kind: "close", id, epoch: "1", revision: 2 });
    equal(close.payload.length, 0);
    await peer.ended(0);
    const restored = await host();
    try {
      await restored.open({ checkpoint: true }, checkpoint.payload);
      const result = await restored.send({
        kind: "build",
        id: 2,
        epoch: "1",
        revision: 0,
      });
      equal(result.metadata.revision, 1);
      equal(result.metadata.success, true);
      await restored.send({ kind: "close", id: 3, epoch: "1", revision: 1 });
      await restored.ended(0);
    } finally {
      await restored.cleanup();
    }
  } finally {
    await peer.cleanup();
  }
});

Deno.test("wire contract demand reports are opt in and preserve executable bytes", async () => {
  const source =
    `const choose = fn (left: Bool) => fn ~(right: Bool) => if left then @demand right else #False
entry const run = fn (value: Bool) => choose value #True
`;
  const payload = encoder.encode(source);
  let plain: Uint8Array | undefined;
  for (const explainDemands of [false, true]) {
    const peer = await host();
    try {
      await Deno.writeTextFile(peer.entry, source);
      await peer.open({ explainDemands });
      const built = await peer.send({
        kind: "build",
        id: 2,
        epoch: "1",
        revision: 0,
      });
      equal(built.metadata.success, true);
      const report = built.metadata.stats.demandLowering;
      if (!explainDemands) {
        equal(report, null);
        plain = built.payload;
      } else {
        equal(built.payload, plain);
        fields(report, ["sites", "omitted"]);
        natural(report.omitted);
        ok(
          Array.isArray(report.sites) && report.sites.length > 0 &&
            report.sites.length <= 256,
        );
        for (const site of report.sites) {
          fields(site, [
            "filename",
            "filename_truncated",
            "unit",
            "start",
            "end",
            "offset_encoding",
            "lowering",
            "reason",
          ]);
          equal(site.filename, peer.entry);
          equal(site.filename_truncated, false);
          natural(site.unit);
          natural(site.start);
          natural(site.end);
          ok(site.start <= site.end && site.end <= payload.length);
          equal(site.offset_encoding, "utf8_bytes");
          ok(
            ["eliminated", "direct", "local_memo", "stored"].includes(
              site.lowering,
            ),
          );
          ok(
            [
              "unused",
              "proved_local",
              "repeated_local",
              "unknown_callee",
              "escaping_use",
              "unresolved_control",
              "inlining_limit",
              "unavailable_body",
              "unresolved_shape",
            ].includes(site.reason),
          );
        }
      }
      const wasm = await WebAssembly.instantiate(built.payload);
      equal((wasm.instance.exports.run as CallableFunction)(0), 0);
      equal((wasm.instance.exports.run as CallableFunction)(1), 1);
    } finally {
      await peer.cleanup();
    }
  }
});

Deno.test("wire completion is source-only bounded recoverable and leaves retained builds untouched", async () => {
  const peer = await host();
  try {
    await peer.open({ prelude: null });
    const original = await peer.send({
      kind: "build",
      id: 2,
      epoch: "1",
      revision: 0,
    });
    equal(original.metadata.success, true);
    let id = 2;
    const query = async (marked: string) => {
      const cursor = marked.indexOf("<cursor>");
      ok(cursor >= 0);
      const payload = encoder.encode(marked.replace("<cursor>", ""));
      const next = ++id;
      const reply = await peer.send({
        kind: "complete",
        id: next,
        epoch: "1",
        revision: 1,
        snapshot: next,
        filename: peer.entry,
        position: encoder.encode(marked.slice(0, cursor)).length,
        sources: [{ path: peer.entry, start: 0, length: payload.length }],
      }, payload);
      fields(reply.metadata, [
        "kind",
        "id",
        "epoch",
        "revision",
        "snapshot",
        "filename",
        "position",
        "success",
        "replace",
        "context",
        "items",
        "truncated",
        "diagnostics",
      ]);
      equal(reply.metadata.revision, 1);
      equal(reply.metadata.snapshot, next);
      equal(reply.metadata.filename, peer.entry);
      equal(reply.payload.length, 0);
      ok(encoder.encode(JSON.stringify(reply.metadata)).length <= 256 * 1024);
      return reply.metadata;
    };
    const source = "// 雪\nconst work = fn (value: U32) -> U32 => va<cursor>";
    const first = await query(source);
    equal(
      first.items.map((
        item: Metadata,
      ) => [item.insertText, item.kind, item.match]),
      [["value", "value", "exact"]],
    );
    equal(first.context.nodes[first.context.expected].kind, "u32");
    fields(first.items[0], ["label", "insertText", "kind", "detail", "match"]);
    const scope = await query(
      "const work = fn (value: U32) -> U32 => do:\n  let original = value\n  value := #True\n  break @ho<cursor>le",
    );
    equal(
      scope.items.filter((item: Metadata) =>
        ["value", "original"].includes(item.insertText)
      ).map((item: Metadata) => [item.insertText, item.match]),
      [["original", "exact"], ["value", "incompatible"]],
    );
    equal(scope.replace.end - scope.replace.start, 5);
    const broken = await query(
      "const good = 42\nconst bad = (\nconst invented = 3\nconst work = goo<cursor>",
    );
    equal(broken.context, null);
    equal(broken.items.map((item: Metadata) => [item.insertText, item.match]), [
      ["good", "unknown"],
    ]);
    ok(broken.diagnostics.length > 0);
    const comment = await query("const bad = (\n// goo<cursor>");
    equal(comment.items, []);
    equal(comment.context, null);
    equal(comment.diagnostics, []);
    const text = encoder.encode("雪");
    const invalid = await peer.send({
      kind: "complete",
      id: ++id,
      epoch: "1",
      revision: 1,
      snapshot: id,
      filename: peer.entry,
      position: 1,
      sources: [{ path: peer.entry, start: 0, length: text.length }],
    }, text);
    equal(invalid.metadata.success, false);
    equal(invalid.metadata.diagnostics[0].code, "invalid_position");
    equal(invalid.metadata.diagnostics[0].start, 0);
    const missing = await peer.send({
      kind: "complete",
      id: ++id,
      epoch: "1",
      revision: 1,
      snapshot: id,
      filename: peer.entry + ".missing",
      position: 0,
    });
    equal(missing.metadata.success, false);
    equal(missing.metadata.diagnostics[0].code, "missing_source");
    const final = await peer.send({
      kind: "build",
      id: ++id,
      epoch: "1",
      revision: 1,
    });
    equal(final.metadata.success, true);
    equal(final.metadata.revision, 2);
    equal(final.payload, original.payload);
    await peer.send({ kind: "close", id: ++id, epoch: "1", revision: 2 });
    await peer.ended(0);
  } finally {
    await peer.cleanup();
  }
});
Deno.test("wire completion rejects over-limit UTF-8 filename echoes before querying", async () => {
  const peer = await host();
  try {
    await peer.open();
    await peer.writer.write(wire({
      kind: "complete",
      id: 2,
      epoch: "1",
      revision: 0,
      snapshot: 1,
      filename: "/" + "雪".repeat(1366),
      position: 0,
    }));
    await peer.ended(1, "InvalidCompletionRequest");
  } finally {
    await peer.cleanup();
  }
});

for (const field of ["snapshot", "filename", "position"]) {
  Deno.test(`wire completion fields are forbidden on build when ${field} is non-null`, async () => {
    const peer = await host();
    try {
      await peer.open();
      let value: string | number = 0;
      if (field === "filename") value = peer.entry;
      await peer.writer.write(
        wire({ kind: "build", id: 2, epoch: "1", revision: 0, [field]: value }),
      );
      await peer.ended(1, "InvalidRequest");
    } finally {
      await peer.cleanup();
    }
  });
}

Deno.test("wire accepts null completion defaults on ordinary requests", async () => {
  const peer = await host();
  try {
    await peer.open({ snapshot: null, filename: null, position: null });
    const built = await peer.send({
      kind: "build",
      id: 2,
      epoch: "1",
      revision: 0,
      snapshot: null,
      filename: null,
      position: null,
    });
    equal(built.metadata.success, true);
    await peer.send({
      kind: "close",
      id: 3,
      epoch: "1",
      revision: 1,
      snapshot: null,
      filename: null,
      position: null,
    });
    await peer.ended(0);
  } finally {
    await peer.cleanup();
  }
});

const invalid: {
  name: string;
  error: string;
  opened?: boolean;
  bytes: (entry: string) => Uint8Array;
}[] = [
  {
    name: "missing version",
    error: "VersionMismatch",
    bytes: (entry) => wire({ kind: "open", id: 1, entry }),
  },
  {
    name: "wrong version",
    error: "VersionMismatch",
    bytes: (entry) => wire({ kind: "open", id: 1, version: 2, entry }),
  },
  {
    name: "wrong numeric-string version",
    error: "VersionMismatch",
    bytes: (entry) => wire({ kind: "open", id: 1, version: "2", entry }),
  },
  {
    name: "null version",
    error: "VersionMismatch",
    bytes: (entry) => wire({ kind: "open", id: 1, version: null, entry }),
  },
  {
    name: "duplicate JSON field",
    error: "DuplicateField",
    bytes: () => wire('{"kind":"open","id":1,"id":2}'),
  },
  {
    name: "unknown JSON field",
    error: "UnknownField",
    bytes: () => wire({ kind: "open", id: 1, unknown: 0 }),
  },
  { name: "invalid JSON", error: "SyntaxError", bytes: () => wire("?") },
  {
    name: "invalid metadata UTF-8",
    error: "SyntaxError",
    bytes: () => {
      const bytes = wire("?");
      bytes[8] = 255;
      return bytes;
    },
  },
  {
    name: "mistyped request field",
    error: "UnexpectedToken",
    bytes: () => wire({ kind: "open", id: true, version: 1 }),
  },
  {
    name: "duplicate nested field",
    error: "DuplicateField",
    opened: true,
    bytes: (entry) =>
      wire(
        `{"kind":"build","id":2,"epoch":"1","revision":0,"sources":[{"path":${
          JSON.stringify(entry)
        },"start":0,"length":0,"length":0}]}`,
      ),
  },
  {
    name: "truncated header",
    error: "TruncatedFrame",
    bytes: () => Uint8Array.of(1, 2),
  },
  {
    name: "truncated metadata",
    error: "TruncatedFrame",
    bytes: () => header(2),
  },
  {
    name: "truncated payload",
    error: "TruncatedFrame",
    bytes: () => {
      const bytes = wire("{}");
      new DataView(bytes.buffer).setUint32(4, 1, true);
      return bytes;
    },
  },
  { name: "empty metadata", error: "FrameTooLarge", bytes: () => header(0) },
  {
    name: "oversized metadata",
    error: "FrameTooLarge",
    bytes: () => header(16777217),
  },
  {
    name: "oversized frame",
    error: "FrameTooLarge",
    bytes: () => header(1, 67108864),
  },
  {
    name: "before open",
    error: "NotOpen",
    bytes: () => wire({ kind: "build", id: 1 }),
  },
  {
    name: "invalid open",
    error: "InvalidOpen",
    bytes: () => wire({ kind: "open", id: 1, version: 1, entry: "relative" }),
  },
  {
    name: "second open",
    error: "AlreadyOpen",
    opened: true,
    bytes: (entry) => wire({ kind: "open", id: 2, version: 1, entry }),
  },
  {
    name: "repeated ID",
    error: "RequestOrder",
    opened: true,
    bytes: () => wire({ kind: "build", id: 1, epoch: "1", revision: 0 }),
  },
  {
    name: "zero ID",
    error: "RequestOrder",
    bytes: (entry) => wire({ kind: "open", id: 0, version: 1, entry }),
  },
  {
    name: "wrong revision",
    error: "RevisionMismatch",
    opened: true,
    bytes: () => wire({ kind: "build", id: 2, epoch: "1", revision: 1 }),
  },
  {
    name: "wrong epoch",
    error: "RevisionMismatch",
    opened: true,
    bytes: () => wire({ kind: "build", id: 2, epoch: "2", revision: 0 }),
  },
  {
    name: "missing epoch",
    error: "RevisionMismatch",
    opened: true,
    bytes: () => wire({ kind: "build", id: 2, revision: 0 }),
  },
  {
    name: "late version",
    error: "InvalidRequest",
    opened: true,
    bytes: () =>
      wire({ kind: "build", id: 2, version: 1, epoch: "1", revision: 0 }),
  },
  {
    name: "close payload",
    error: "InvalidRequest",
    opened: true,
    bytes: () =>
      wire({ kind: "close", id: 2, epoch: "1", revision: 0 }, Uint8Array.of(1)),
  },
  {
    name: "checkpoint sources",
    error: "InvalidRequest",
    opened: true,
    bytes: (entry) =>
      wire({
        kind: "checkpoint",
        id: 2,
        epoch: "1",
        revision: 0,
        sources: [{ path: entry, start: 0, length: 0 }],
      }),
  },
  {
    name: "gap in sources",
    error: "InvalidSources",
    opened: true,
    bytes: (entry) =>
      wire({
        kind: "build",
        id: 2,
        epoch: "1",
        revision: 0,
        sources: [{ path: entry, start: 1, length: 0 }],
      }),
  },
  {
    name: "deleted source bytes",
    error: "InvalidSources",
    opened: true,
    bytes: (entry) =>
      wire({
        kind: "build",
        id: 2,
        epoch: "1",
        revision: 0,
        sources: [{ path: entry, start: 0, length: 1, deleted: true }],
      }, Uint8Array.of(97)),
  },
  {
    name: "invalid source UTF-8",
    error: "InvalidSources",
    opened: true,
    bytes: (entry) =>
      wire({
        kind: "build",
        id: 2,
        epoch: "1",
        revision: 0,
        sources: [{ path: entry, start: 0, length: 1 }],
      }, Uint8Array.of(255)),
  },
  {
    name: "too many sources",
    error: "SourceLimit",
    opened: true,
    bytes: (entry) =>
      wire({
        kind: "build",
        id: 2,
        epoch: "1",
        revision: 0,
        sources: Array.from(
          { length: 4097 },
          () => ({ path: entry, start: 0, length: 0 }),
        ),
      }),
  },
];
for (const item of invalid) {
  Deno.test(`wire contract terminal error: ${item.name}`, async () => {
    const peer = await host();
    try {
      if (item.opened) await peer.open();
      await peer.writer.write(item.bytes(peer.entry));
      await peer.writer.close();
      await peer.ended(1, item.error);
    } finally {
      await peer.cleanup();
    }
  });
}
Deno.test("wire contract boundary EOF and cancellation dispose the process", async () => {
  const eof = await host();
  try {
    await eof.open();
    await eof.writer.close();
    await eof.ended(0);
  } finally {
    await eof.cleanup();
  }
  const cancelled = await host();
  try {
    await cancelled.open();
    // There is no cancel frame or acknowledgement; process death discards the session.
    await cancelled.writer.write(
      wire({ kind: "build", id: 2, epoch: "1", revision: 0 }),
    );
    cancelled.child.kill("SIGKILL");
    const status = await cancelled.child.status;
    equal(status.success, false);
    equal(status.signal, "SIGKILL");
  } finally {
    await cancelled.cleanup();
  }
});

Deno.test("wire contract checkpoints reject before success and invalid candidates are optional", async () => {
  const peer = await host();
  try {
    await peer.open({ checkpoint: true }, Uint8Array.of(1, 2, 3));
    const checkpoint = await peer.send({
      kind: "checkpoint",
      id: 2,
      epoch: "1",
      revision: 0,
    });
    equal(checkpoint.metadata, {
      kind: "checkpoint",
      id: 2,
      epoch: "1",
      revision: 0,
      success: false,
      code: "NoSuccessfulRevision",
    });
    equal(checkpoint.payload.length, 0);
    const result = await peer.send({
      kind: "build",
      id: 3,
      epoch: "1",
      revision: 0,
    });
    equal(result.metadata.success, true);
    equal(result.metadata.revision, 1);
    await peer.send({ kind: "close", id: 4, epoch: "1", revision: 1 });
    await peer.ended(0);
  } finally {
    await peer.cleanup();
  }
});

Deno.test("wire contract preserves Zig numeric-string and enum-tag allowances", async () => {
  const peer = await host();
  try {
    const opened = await peer.send({
      kind: 0,
      id: "1",
      version: "1e0",
      entry: peer.entry,
      codegenWorkers: "1.0",
      codegenTier: "1",
    });
    equal(opened.metadata, { kind: "open", id: 1, epoch: "1", revision: 0 });
    const payload = encoder.encode("entry const answer = 7\n");
    const built = await peer.send({
      kind: "1",
      id: 2.0,
      epoch: "1",
      revision: "0.0",
      sources: [{
        path: peer.entry,
        start: "0e0",
        length: String(payload.length),
      }],
    }, payload);
    equal([
      built.metadata.kind,
      built.metadata.id,
      built.metadata.revision,
      built.metadata.success,
    ], ["build", 2, 1, true]);
    ok(WebAssembly.validate(built.payload));
    const close = await peer.send({
      kind: 2,
      id: "3",
      epoch: "1",
      revision: "1",
    });
    equal(close.metadata, { kind: "close", id: 3, epoch: "1", revision: 1 });
    await peer.ended(0);
  } finally {
    await peer.cleanup();
  }
});
