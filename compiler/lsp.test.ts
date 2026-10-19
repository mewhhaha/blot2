import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { fileURLToPath, pathToFileURL } from "node:url";
import { CompletionBridge } from "./lsp.ts";
import { completionPeerExecutable } from "../zig-native/tests/fixtures/project_peer_executable.ts";
import {
  byteOffset,
  LspReader,
  LspWriter,
  utf16Position,
} from "./lsp_protocol.ts";

const encoder = new TextEncoder();
const executable = Deno.args[0] ??
  fileURLToPath(new URL("../zig-native/zig-out/bin/blotc", import.meta.url));
class Bytes {
  data: Uint8Array[] = [];
  async write(bytes: Uint8Array) {
    this.data.push(bytes.slice());
    return bytes.length;
  }
  async read(bytes: Uint8Array) {
    if (this.data.length === 0) return null;
    const first = this.data[0], count = Math.min(bytes.length, first.length);
    bytes.set(first.subarray(0, count));
    if (count === first.length) this.data.shift();
    else this.data[0] = first.subarray(count);
    return count;
  }
  async messages() {
    const reader = new LspReader(this), messages = [];
    while (true) {
      const body = await reader.next();
      if (body === null) return messages;
      messages.push(JSON.parse(new TextDecoder().decode(body)));
    }
  }
}
Deno.test("LSP framing handles fragmented and coalesced messages and rejects invalid lengths before allocation", async () => {
  const bytes = new Bytes(), writer = new LspWriter(bytes);
  await Promise.all([writer.send({ text: "雪😀" }), writer.send({ id: 2 })]);
  bytes.data = bytes.data.flatMap((part) =>
    [...part].map((byte) => Uint8Array.of(byte))
  );
  equal(await bytes.messages(), [{ text: "雪😀" }, { id: 2 }]);
  for (
    const text of [
      "Content-Length: 67108865\r\n\r\n",
      "Content-Length: 0\r\nContent-Length: 0\r\n\r\n",
      "Content-Length: -1\r\n\r\n",
      "x".repeat(8193),
      "Content-Length: 2\r\n\r\n{",
      "Content-Length: 2\r\n",
    ]
  ) {
    const input = new Bytes();
    input.data.push(encoder.encode(text));
    await rejects(new LspReader(input).next());
  }
});
Deno.test("LSP positions preserve CRLF and supplementary Unicode boundaries", () => {
  const text = "// 雪😀\r\nvalue\n";
  for (
    const position of [
      { line: 0, character: 0 },
      { line: 0, character: 4 },
      { line: 0, character: 6 },
      { line: 1, character: 3 },
      { line: 2, character: 0 },
    ]
  ) {
    equal(utf16Position(text, byteOffset(text, position)), position);
  }
  throws(() => byteOffset(text, { line: 0, character: 5 }));
  throws(() => byteOffset(text, { line: 3, character: 0 }));
  throws(() => utf16Position(text, 4));
});

async function setup(compiler = executable) {
  const directory = await Deno.makeTempDir(), output = new Bytes();
  const bridge = new CompletionBridge(new LspWriter(output), {
    executable: compiler,
    prelude: null,
    cacheDirectory: false,
  });
  const entry = directory + "/main.blot", uri = pathToFileURL(entry).href;
  const send = (method: string, params: unknown = {}, id?: number) => {
    const message: Record<string, unknown> = { jsonrpc: "2.0", method, params };
    if (id !== undefined) message.id = id;
    return bridge.handle(message);
  };
  await send("initialize", { rootUri: pathToFileURL(directory).href }, 1);
  await send("initialized");
  await output.messages();
  const open = (text: string, version = 1, target = uri) =>
    send("textDocument/didOpen", {
      textDocument: { uri: target, languageId: "blot", text, version },
    });
  const change = (text: string, version: number) =>
    send("textDocument/didChange", {
      textDocument: { uri, version },
      contentChanges: [{ text }],
    });
  const complete = (line: number, character: number, id = 2) =>
    send("textDocument/completion", {
      textDocument: { uri },
      position: { line, character },
    }, id);
  return {
    directory,
    output,
    bridge,
    entry,
    uri,
    send,
    open,
    change,
    complete,
    async cleanup() {
      await bridge.dispose();
      await Deno.remove(directory, { recursive: true });
    },
  };
}
Deno.test("LSP completes unsaved UTF-16 buffers and imports without an entry and ignores old changes", async () => {
  const item = await setup();
  try {
    const text = "// 雪😀\r\nconst work = fn (value: U32) -> U32 => va";
    await item.open(text, 10);
    await item.complete(1, 41);
    let rows = await item.output.messages();
    ok(rows[0].result, JSON.stringify(rows));
    equal(rows[0].result.items[0].textEdit, {
      range: {
        start: { line: 1, character: 39 },
        end: { line: 1, character: 41 },
      },
      newText: "value",
    });
    await item.change("invalid", 9);
    await item.complete(1, 41, 3);
    rows = await item.output.messages();
    equal(rows[0].result.items[0].label, "value");
    await item.change("const work = fn (value: U32) -> U32 => @hole", 11);
    await item.complete(0, 44, 7);
    rows = await item.output.messages();
    equal(rows[0].result.items[0].textEdit.newText, "value");
    equal(rows[0].result.items[0].filterText, "holevalue");
    const library = pathToFileURL(item.directory + "/library.blot").href;
    await item.open("const visible = 1.0\n", 1, library);
    const imported =
      'import {visible as renamed} from "./library"\nconst work = fn () -> F32 => ren';
    await item.change(imported, 12);
    await item.complete(1, 32, 4);
    rows = await item.output.messages();
    ok(rows[0].result, JSON.stringify(rows));
    equal(
      rows[0].result.items.map((candidate: { label: string }) =>
        candidate.label
      ),
      ["renamed"],
    );
    await item.send("textDocument/didClose", {
      textDocument: { uri: library },
    });
    await item.complete(1, 32, 5);
    rows = await item.output.messages();
    ok(rows[0].result, JSON.stringify(rows));
    equal(rows[0].result.items, []);
    await item.send("shutdown", {}, 6);
    equal((await item.output.messages())[0].result, null);
  } finally {
    await item.cleanup();
  }
});

async function peer(mode: string) {
  const executable = await completionPeerExecutable();
  const directory = await Deno.makeTempDir(),
    compiler = directory + "/compiler",
    log = directory + "/log";
  const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'";
  await Deno.writeTextFile(
    compiler,
    `#!/bin/sh\nexec ${quote(executable)} ${quote(mode)} ${quote(log)} "$@"\n`,
  );
  await Deno.chmod(compiler, 0o755);
  return { directory, compiler, log };
}
async function waiting(path: string) {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      if ((await Deno.readTextFile(path)).includes('"kind":"complete"')) return;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw new Error("Completion was never sent");
}
function reaped(pid: number) {
  throws(() => Deno.kill(pid, 0), Deno.errors.NotFound);
}
Deno.test("LSP invalidates held replies, cancels active queries and reopens a new child generation", async () => {
  // Hold the original child until cancellation; its replacement answers
  // immediately, without a sleep competing with the production deadline.
  const fixture = await peer("completion-restart"),
    item = await setup(fixture.compiler);
  try {
    await item.open("val", 10);
    const first = item.complete(0, 3);
    await waiting(fixture.log);
    await item.change("new", 11);
    await first;
    equal((await item.output.messages())[0].error.code, -32801);
    const firstPid =
      JSON.parse((await Deno.readTextFile(fixture.log)).split("\n")[0]).pid;
    await item.complete(0, 3, 3);
    const second = (await item.output.messages())[0];
    ok(second.result, JSON.stringify(second));
    reaped(firstPid);
    const secondPid =
      JSON.parse((await Deno.readTextFile(fixture.log)).split("\n")[0]).pid;
    ok(secondPid !== firstPid);
    await item.send("textDocument/didClose", {
      textDocument: { uri: item.uri },
    });
    reaped(secondPid);
  } finally {
    await item.cleanup();
    await Deno.remove(fixture.directory, { recursive: true });
  }
});

Deno.test("LSP invalidates a held reply when a watched source changes", async () => {
  const fixture = await peer("completion-hold"),
    item = await setup(fixture.compiler);
  try {
    await item.open("val");
    const pending = item.complete(0, 3);
    await waiting(fixture.log);
    await Deno.writeTextFile(
      item.directory + "/changed.blot",
      "const changed = 1\n",
    );
    await pending;
    equal((await item.output.messages())[0].error.code, -32801);
    await item.bridge.dispose();
    const pid =
      JSON.parse((await Deno.readTextFile(fixture.log)).split("\n")[0]).pid;
    reaped(pid);
  } finally {
    await item.cleanup();
    await Deno.remove(fixture.directory, { recursive: true });
  }
});

Deno.test("LSP stdio recovers invalid JSON and reaps an active child on invalid framing", async () => {
  const fixture = await peer("completion-stall");
  const child = new Deno.Command(Deno.execPath(), {
    args: [
      "run",
      "--allow-read",
      "--allow-run",
      fileURLToPath(new URL("./lsp.ts", import.meta.url)),
      "--compiler",
      fixture.compiler,
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const input = child.stdin.getWriter(), output = child.stdout.getReader();
  const errors = new Response(child.stderr).text();
  let bytes = new Uint8Array();
  const reader = new LspReader({
    async read(target) {
      if (bytes.length === 0) {
        const chunk = await output.read();
        if (chunk.done) return null;
        bytes = chunk.value;
      }
      const count = Math.min(bytes.length, target.length);
      target.set(bytes.subarray(0, count));
      bytes = bytes.subarray(count);
      return count;
    },
  });
  const writer = new LspWriter({
    async write(bytes) {
      await input.write(bytes);
      return bytes.length;
    },
  });
  const message = async () =>
    JSON.parse(new TextDecoder().decode((await reader.next())!));
  let ended = false;
  try {
    await input.write(encoder.encode("Content-Length: 1\r\n\r\n{"));
    equal((await message()).error.code, -32700);
    await writer.send({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {},
    });
    ok((await message()).result.capabilities.completionProvider);
    const uri = pathToFileURL(fixture.directory + "/main.blot").href;
    await writer.send({
      jsonrpc: "2.0",
      method: "textDocument/didOpen",
      params: {
        textDocument: { uri, languageId: "blot", version: 1, text: "val" },
      },
    });
    await writer.send({
      jsonrpc: "2.0",
      id: 2,
      method: "textDocument/completion",
      params: { textDocument: { uri }, position: { line: 0, character: 3 } },
    });
    await waiting(fixture.log);
    const pid =
      JSON.parse((await Deno.readTextFile(fixture.log)).split("\n")[0]).pid;
    await input.write(encoder.encode("Content-Length: 67108865\r\n\r\n"));
    const status = await child.status;
    ended = true;
    equal(status.code, 1);
    reaped(pid);
    ok((await errors).includes("framing limit"));
  } finally {
    if (!ended) {
      child.kill("SIGKILL");
      await child.status;
    }
    await input.close().catch(() => {});
    await output.cancel();
    await errors;
    await Deno.remove(fixture.directory, { recursive: true });
  }
});
for (const mode of ["cancel", "deadline"]) {
  Deno.test(`LSP ${mode} reaps the completion child`, async () => {
    const fixture = await peer("completion-stall"),
      item = await setup(fixture.compiler);
    try {
      await item.open("value");
      const started = performance.now(), pending = item.complete(0, 5);
      await waiting(fixture.log);
      if (mode === "cancel") await item.send("$/cancelRequest", { id: 2 });
      await pending;
      equal((await item.output.messages())[0].error.code, -32800);
      if (mode === "deadline") ok(performance.now() - started < 500);
      await item.bridge.dispose();
      const pid =
        JSON.parse((await Deno.readTextFile(fixture.log)).split("\n")[0]).pid;
      reaped(pid);
    } finally {
      await item.cleanup();
      await Deno.remove(fixture.directory, { recursive: true });
    }
  });
}
