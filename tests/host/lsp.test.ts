import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { fileURLToPath, pathToFileURL } from "node:url";
import { CompletionBridge } from "../../host/lsp.ts";
import { completionPeerExecutable } from "../guest/fixtures/project_peer_executable.ts";
import {
  byteOffset,
  LspReader,
  LspWriter,
  utf16Position,
} from "../../host/lsp_protocol.ts";

const encoder = new TextEncoder();
const executable = Deno.args[0] ??
  fileURLToPath(
    new URL("../../compiler-goose/build/blotc-goose", import.meta.url),
  );
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

async function setup(
  compiler = executable,
  prepare?: (directory: string) => Promise<void>,
) {
  const directory = await Deno.makeTempDir(), output = new Bytes();
  await prepare?.(directory);
  const bridge = new CompletionBridge(new LspWriter(output), {
    executable: compiler,
    prelude: null,
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
    const text = "// 雪😀\r\nconst work = func (value: U32) : U32 => return va";
    await item.open(text, 10);
    await item.complete(1, 49);
    let rows = await item.output.messages();
    ok(rows[0].result, JSON.stringify(rows));
    equal(rows[0].result.items[0].textEdit, {
      range: {
        start: { line: 1, character: 47 },
        end: { line: 1, character: 49 },
      },
      newText: "value",
    });
    await item.change("invalid", 9);
    await item.complete(1, 49, 3);
    rows = await item.output.messages();
    equal(rows[0].result.items[0].label, "value");
    await item.change(
      "const work = func (value: U32) : U32 => return @hole",
      11,
    );
    await item.complete(0, 52, 7);
    rows = await item.output.messages();
    equal(rows[0].result.items[0].textEdit.newText, "value");
    equal(rows[0].result.items[0].filterText, "holevalue");
    const library = pathToFileURL(item.directory + "/library.blot").href;
    await item.open("const visible = 1.0\n", 1, library);
    const imported =
      'import {visible as renamed} from "./library"\nconst work = func () : F32 => return ren';
    await item.change(imported, 12);
    await item.complete(1, 40, 4);
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
    await item.complete(1, 40, 5);
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
  // The peer is a fresh process; half a second can pass before its first
  // write when the whole suite runs in parallel.
  for (let attempt = 0; attempt < 2000; attempt++) {
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
      fileURLToPath(new URL("../../host/lsp.ts", import.meta.url)),
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

Deno.test("LSP pull diagnostics emit Solid-2 blame relatedInformation and quick-fix codeActions", async () => {
  const directory = await Deno.makeTempDir();
  const output = new Bytes();
  const stdRoot = fileURLToPath(new URL("../../std", import.meta.url));
  const prelude = fileURLToPath(
    new URL("../../std/prelude.blot", import.meta.url),
  );
  const bridge = new CompletionBridge(new LspWriter(output), {
    executable,
    prelude,
    stdRoot,
  });
  const entry = directory + "/main.blot";
  const uri = pathToFileURL(entry).href;
  const send = (method: string, params: unknown = {}, id?: number) => {
    const message: Record<string, unknown> = { jsonrpc: "2.0", method, params };
    if (id !== undefined) message.id = id;
    return bridge.handle(message);
  };
  try {
    await send("initialize", { rootUri: pathToFileURL(directory).href }, 1);
    const initReply = (await output.messages())[0];
    ok(initReply.result.capabilities.diagnosticProvider);
    ok(initReply.result.capabilities.codeActionProvider);
    await send("initialized");

    // 1. SPENT_VALUE with secondary relatedInformation pointing to move line + `.copy` quick-fix
    const spentSource = [
      "func consume (xs: own #[U32]): U32 => return xs.length",
      "io main (): U32 =>",
      "  let a = #[1, 2, 3]",
      "  let n = consume a",
      "  return n + a.length",
      "",
    ].join("\n");
    await send("textDocument/didOpen", {
      textDocument: { uri, languageId: "blot", text: spentSource, version: 1 },
    });
    await send("textDocument/diagnostic", { textDocument: { uri } }, 10);
    let rows = await output.messages();
    equal(rows[0].result.kind, "full");
    equal(rows[0].result.items.length, 1);
    const spentDiag = rows[0].result.items[0];
    equal(spentDiag.code, "SPENT_VALUE");
    equal(spentDiag.source, "blot");
    ok(spentDiag.message.includes("already moved at line 4"));
    ok(spentDiag.message.includes("fix: Pass `a.copy` at line 4"));
    equal(spentDiag.relatedInformation.length, 1);
    equal(spentDiag.relatedInformation[0].location.uri, uri);
    equal(spentDiag.relatedInformation[0].location.range.start.line, 3);
    ok(spentDiag.relatedInformation[0].message.includes("`a` moved here"));

    // Request quick-fix codeAction for SPENT_VALUE
    await send("textDocument/codeAction", {
      textDocument: { uri },
      range: spentDiag.range,
      context: { diagnostics: [spentDiag] },
    }, 11);
    rows = await output.messages();
    equal(rows[0].result.length, 1);
    equal(rows[0].result[0].kind, "quickfix");
    equal(rows[0].result[0].title, "Pass `a.copy` at move site");
    const edit = rows[0].result[0].edit.changes[uri][0];
    equal(edit.newText, ".copy");
    equal(edit.range.start.line, 3);

    // 2. Missing `$` constructor hint -> quick-fix `$Some`
    const ctorSource = [
      "type Opt is data = $Some U32 | $Nothing",
      "io main (): Opt => return Some 1",
      "",
    ].join("\n");
    await send("textDocument/didChange", {
      textDocument: { uri, version: 2 },
      contentChanges: [{ text: ctorSource }],
    });
    // Also verify push-on-save (`textDocument/didSave` -> `publishDiagnostics`)
    await send("textDocument/didSave", { textDocument: { uri } });
    rows = await output.messages();
    equal(rows[0].method, "textDocument/publishDiagnostics");
    equal(rows[0].params.diagnostics.length, 1);
    const ctorDiag = rows[0].params.diagnostics[0];
    equal(ctorDiag.code, "UNKNOWN_VALUE");
    ok(ctorDiag.message.includes("$Some"));
    await send("textDocument/codeAction", {
      textDocument: { uri },
      range: ctorDiag.range,
      context: { diagnostics: [] },
    }, 12);
    rows = await output.messages();
    equal(rows[0].result[0].title, "Replace with constructor `$Some`");
    equal(rows[0].result[0].edit.changes[uri][0].newText, "$Some");
  } finally {
    await bridge.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("LSP resolves manifest generators and completes fields from a live asset buffer", async () => {
  const item = await setup(executable, async (directory) => {
    await Promise.all([
      Deno.writeTextFile(
        directory + "/blot.json",
        JSON.stringify({
          generators: [{
            module: "shape",
            input: "shape.txt",
            generator: "generator.blot",
          }],
        }),
      ),
      Deno.writeTextFile(
        directory + "/generator.blot",
        "io generate (bytes: #[U32]): #[U32] => return bytes\n",
      ),
      Deno.writeTextFile(
        directory + "/shape.txt",
        "type Shape is data = $Shape { width: U32 }\n",
      ),
    ]);
  });
  try {
    const asset = item.directory + "/shape.txt";
    const line = "func size (shape: Shape) => return shape.";
    await item.open('import { Shape } from "./shape"\n' + line);
    await item.complete(1, line.length);
    let messages = await item.output.messages();
    ok(messages[0].result, JSON.stringify(messages));
    equal(
      messages[0].result.items.map(({ label }: { label: string }) => label),
      ["width"],
    );

    await item.open(
      "type Shape is data = $Shape { height: U32 }\n",
      1,
      pathToFileURL(asset).href,
    );
    await item.complete(1, line.length, 3);
    messages = await item.output.messages();
    ok(messages[0].result, JSON.stringify(messages));
    equal(
      messages[0].result.items.map(({ label }: { label: string }) => label),
      ["height"],
    );
  } finally {
    await item.cleanup();
  }
});

Deno.test("LSP suppresses spurious no_entry on library modules while reporting real errors and quick-fixes", async () => {
  const directory = await Deno.makeTempDir();
  const output = new Bytes();
  const stdRoot = fileURLToPath(new URL("../../std", import.meta.url));
  const prelude = fileURLToPath(
    new URL("../../std/prelude.blot", import.meta.url),
  );
  const bridge = new CompletionBridge(new LspWriter(output), {
    executable,
    prelude,
    stdRoot,
  });
  const entry = directory + "/lib.blot";
  const uri = pathToFileURL(entry).href;
  const send = (method: string, params: unknown = {}, id?: number) => {
    const message: Record<string, unknown> = { jsonrpc: "2.0", method, params };
    if (id !== undefined) message.id = id;
    return bridge.handle(message);
  };
  try {
    await send("initialize", { rootUri: pathToFileURL(directory).href }, 1);
    await output.messages();
    await send("initialized");

    // Valid library file without io entries must produce 0 diagnostics
    await send("textDocument/didOpen", {
      textDocument: {
        uri,
        languageId: "blot",
        text: "func double (x: U32): U32 => return x + x\n",
        version: 1,
      },
    });
    await send("textDocument/diagnostic", { textDocument: { uri } }, 20);
    let rows = await output.messages();
    equal(rows[0].result.kind, "full");
    equal(rows[0].result.items, []);

    // Real uniqueness error in library file still produces diagnostic + quick-fix
    const badLib = [
      "func mutator (xs: #[(U32, U32)]): #[(U32, U32)] =>",
      "  xs[0] := (1, 2)",
      "  return xs",
      "",
    ].join("\n");
    await send("textDocument/didChange", {
      textDocument: { uri, version: 2 },
      contentChanges: [{ text: badLib }],
    });
    await send("textDocument/diagnostic", { textDocument: { uri } }, 21);
    rows = await output.messages();
    equal(rows[0].result.kind, "full");
    ok(rows[0].result.items.length >= 1);
    const aliased = rows[0].result.items.find((d: { code: string }) =>
      d.code === "ALIASED_UPDATE"
    );
    ok(aliased, JSON.stringify(rows[0].result.items));
    await send("textDocument/codeAction", {
      textDocument: { uri },
      range: aliased.range,
      context: { diagnostics: [aliased] },
    }, 22);
    rows = await output.messages();
    equal(rows[0].result.length, 1);
    equal(rows[0].result[0].title, "Mark parameter `xs` as `own`");
    equal(rows[0].result[0].edit.changes[uri][0].newText, "own ");
  } finally {
    await bridge.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
