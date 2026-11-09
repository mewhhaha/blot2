// Scoped production checks. This runner never builds either compiler.
import {
  deepStrictEqual as same,
  ok,
  strictEqual as equal,
} from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { instantiateGuest } from "../../host/guest.ts";

type ObjectValue = Record<string, unknown>;
type Frame = { metadata: ObjectValue; payload: Uint8Array<ArrayBuffer> };
type Binary = { name: string; path: string; sha256: string; bytes: number };
type Step = { binary: string; name: string; status: string; error?: string };
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const fixtureRoot = fileURLToPath(
  new URL("../tests/qualification/", import.meta.url),
);
const runner = fileURLToPath(import.meta.url);
const maxFrame = 64 * 1024 * 1024;
const maxLog = 8 * 1024 * 1024;

function object(value: unknown): ObjectValue {
  ok(value !== null && typeof value === "object" && !Array.isArray(value));
  return value as ObjectValue;
}
function errorText(error: unknown): string {
  if (error instanceof Error) return error.stack ?? error.message;
  return String(error);
}
async function hash(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}
async function identity(name: string, path: string): Promise<Binary> {
  const bytes = await Deno.readFile(path);
  return { name, path, sha256: await hash(bytes), bytes: bytes.length };
}
function kill(child: Deno.ChildProcess) {
  try {
    child.kill("SIGKILL");
  } catch { /* Already exited. */ }
}
async function bounded<T>(
  operation: Promise<T>,
  milliseconds: number,
  expire: () => void,
  label: string,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          expire();
          reject(new Error(label + " exceeded " + milliseconds + "ms"));
        }, milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
async function readLog(
  stream: ReadableStream<Uint8Array>,
  expire: () => void,
  signal?: AbortSignal,
) {
  const reader = stream.getReader();
  const cancel = () => {
    reader.cancel().catch(() => {});
  };
  signal?.addEventListener("abort", cancel, { once: true });
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      length += next.value.length;
      if (length > maxLog) {
        expire();
        throw new Error("Process output exceeded the evidence limit");
      }
      chunks.push(next.value);
    }
  } finally {
    signal?.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
  const result = new Uint8Array(length);
  let at = 0;
  for (const chunk of chunks) {
    result.set(chunk, at);
    at += chunk.length;
  }
  return result;
}
function wire(metadata: ObjectValue, payload = new Uint8Array()): Uint8Array {
  const json = encoder.encode(JSON.stringify(metadata));
  const result = new Uint8Array(8 + json.length + payload.length);
  const view = new DataView(result.buffer);
  view.setUint32(0, json.length, true);
  view.setUint32(4, payload.length, true);
  result.set(json, 8);
  result.set(payload, 8 + json.length);
  return result;
}
function diagnostics(values: unknown): ObjectValue[] {
  ok(Array.isArray(values), "Missing diagnostic list");
  return values.map((value) => {
    const item = object(value);
    ok(typeof item.code === "string" && typeof item.stage === "string");
    ok(Number.isSafeInteger(item.start) && Number.isSafeInteger(item.end));
    ok(Number(item.start) >= 0 && Number(item.end) >= Number(item.start));
    return {
      filename: item.filename,
      stage: item.stage,
      code: item.code,
      start: item.start,
      end: item.end,
      message: item.message,
      offset_encoding: item.offset_encoding,
      utf16: item.utf16 ?? null,
    };
  });
}
function observable(value: unknown): unknown {
  if (ArrayBuffer.isView(value)) return Array.from(value as Uint32Array);
  return value;
}

// Execute in a separate bounded process: a looping Wasm function cannot block
// the qualification process's timer or prevent the next independent check.
async function executeWasm(path: string, fixture: string) {
  const guest = await instantiateGuest(await Deno.readFile(path));
  try {
    equal(guest.abi.version, 8, "The candidate must emit guest ABI 8");
    const values: unknown[] = [];
    function call(name: string, argument: unknown, expected: unknown) {
      const result = observable(guest.call(name, argument));
      same(result, expected);
      values.push({ name, argument, result });
    }
    if (fixture === "curried") {
      call("answer", null, 42);
      for (const n of [0, 1, 40, 100]) call("apply", n, n + 2);
    } else if (fixture === "recursion") {
      for (const n of [0, 1, 2, 6, 12]) {
        call("forward", n, n * (n + 1) / 2);
        call("parity", n, n % 2 === 0);
      }
    } else if (fixture === "aggregates") {
      for (const n of [0, 7, 40]) {
        call("record", n, n + 2);
        call("array", n, [n, 2, 3]);
      }
    } else if (fixture === "project" || fixture === "project-edited") {
      let extra = 0;
      if (fixture === "project-edited") extra = 1;
      for (const n of [0, 1, 40]) call("answer", n, (n + 2) * 2 + extra);
    } else throw new Error("Unknown execution fixture: " + fixture);
    for (const n of [0, 7, 40]) call("scoped", n, n + 1);
    return { abi: guest.abi.version, values };
  } finally {
    guest.dispose();
  }
}

class Peer {
  readonly child: Deno.ChildProcess;
  readonly reader: ReadableStreamDefaultReader<Uint8Array>;
  readonly writer: WritableStreamDefaultWriter<Uint8Array>;
  readonly stderr: Promise<Uint8Array>;
  readonly trace: unknown[] = [];
  private readonly stderrAbort = new AbortController();
  private pending: Uint8Array = new Uint8Array();
  constructor(
    binary: Binary,
    readonly milliseconds: () => number,
    env: Record<string, string>,
  ) {
    this.child = new Deno.Command(binary.path, {
      args: ["serve-project"],
      clearEnv: true,
      env: { BLOT_CACHE_DIR: "", ...env },
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    this.reader = this.child.stdout.getReader();
    this.writer = this.child.stdin.getWriter();
    this.stderr = readLog(
      this.child.stderr,
      () => kill(this.child),
      this.stderrAbort.signal,
    );
    this.stderr.catch(() => {}); // Cleanup records failures even after a request aborts.
  }
  private async exact(length: number): Promise<Uint8Array<ArrayBuffer>> {
    const bytes = new Uint8Array(length);
    let at = 0;
    while (at < length) {
      if (!this.pending.length) {
        const next = await this.reader.read();
        ok(!next.done, "Unexpected project-server EOF");
        this.pending = next.value;
      }
      const count = Math.min(length - at, this.pending.length);
      bytes.set(this.pending.subarray(0, count), at);
      this.pending = this.pending.subarray(count);
      at += count;
    }
    return bytes;
  }
  private async frame(): Promise<Frame> {
    const view = new DataView((await this.exact(8)).buffer);
    const jsonLength = view.getUint32(0, true);
    const payloadLength = view.getUint32(4, true);
    ok(jsonLength > 0 && jsonLength <= 16 * 1024 * 1024);
    ok(8 + jsonLength + payloadLength <= maxFrame, "Oversized server frame");
    const metadata = object(
      JSON.parse(decoder.decode(await this.exact(jsonLength))),
    );
    const payload = await this.exact(payloadLength);
    this.trace.push({
      direction: "reply",
      metadata,
      bytes: payload.length,
      sha256: await hash(payload),
    });
    return { metadata, payload };
  }
  async hello() {
    const hello = await bounded(
      this.frame(),
      this.milliseconds(),
      () => kill(this.child),
      "hello",
    );
    equal(hello.metadata.kind, "hello");
    equal(hello.metadata.protocol, "blot-zig-project");
    equal(hello.metadata.version, 1);
    equal(hello.payload.length, 0);
    ok(Array.isArray(hello.metadata.capabilities));
    ok(hello.metadata.capabilities.includes("project-build"));
    ok(hello.metadata.capabilities.includes("source-overlays"));
    return hello.metadata;
  }
  async send(metadata: ObjectValue, payload = new Uint8Array()) {
    this.trace.push({
      direction: "request",
      metadata,
      bytes: payload.length,
      sha256: await hash(payload),
    });
    return await bounded(
      (async () => {
        await this.writer.write(wire(metadata, payload));
        return await this.frame();
      })(),
      this.milliseconds(),
      () => kill(this.child),
      String(metadata.kind),
    );
  }
  async close(id: number, revision: number) {
    const reply = await this.send({ kind: "close", id, epoch: "1", revision });
    same(reply.metadata, { kind: "close", id, epoch: "1", revision });
    equal(reply.payload.length, 0);
    await bounded(
      this.writer.close(),
      this.milliseconds(),
      () => kill(this.child),
      "stdin close",
    );
    const status = await bounded(
      this.child.status,
      this.milliseconds(),
      () => kill(this.child),
      "server exit",
    );
    equal(status.code, 0);
    equal(this.pending.length, 0, "Trailing protocol bytes");
    const eof = await bounded(
      this.reader.read(),
      this.milliseconds(),
      () => kill(this.child),
      "server EOF",
    );
    ok(eof.done, "Trailing protocol frame");
  }
  async dispose() {
    kill(this.child);
    this.stderrAbort.abort();
    await bounded(
      Promise.all([
        this.child.status,
        this.reader.cancel().catch(() => {}),
        this.writer.abort().catch(() => {}),
      ]),
      5000,
      () => kill(this.child),
      "server cleanup",
    );
    return await bounded(
      this.stderr,
      5000,
      () => kill(this.child),
      "stderr cleanup",
    );
  }
}

async function qualify() {
  const args = new Map<string, string>();
  let oracleOnly = false;
  for (let index = 0; index < Deno.args.length; index++) {
    const key = Deno.args[index];
    if (key === "--oracle-only") {
      oracleOnly = true;
      continue;
    }
    if (key === "--help") {
      console.log(
        "deno run -A compiler-goose/tools/qualify_compiler.ts --goose-compiler BIN --zig-oracle BIN [--output DIR] [--timeout-ms 30000] [--overall-ms 300000]\n--oracle-only records a fixture baseline and leaves Goose qualification pending.",
      );
      return;
    }
    ok(
      [
        "--goose-compiler",
        "--zig-oracle",
        "--output",
        "--timeout-ms",
        "--overall-ms",
      ].includes(key),
      "Unknown argument " + key,
    );
    ok(
      index + 1 < Deno.args.length && !args.has(key),
      "Missing or duplicate argument " + key,
    );
    args.set(key, Deno.args[++index]);
  }
  ok(args.has("--zig-oracle"), "--zig-oracle is required");
  ok(
    oracleOnly || args.has("--goose-compiler"),
    "--goose-compiler is required",
  );
  const timeout = Number(args.get("--timeout-ms") ?? 30000);
  const overall = Number(args.get("--overall-ms") ?? 300000);
  ok(Number.isSafeInteger(timeout) && timeout > 0 && timeout <= 120000);
  ok(Number.isSafeInteger(overall) && overall > 0);
  const deadline = Date.now() + overall;
  function milliseconds() {
    const remaining = Math.min(timeout, deadline - Date.now());
    ok(remaining > 0, "Overall qualification deadline reached");
    return remaining;
  }
  const binaries = [
    await identity("oracle", await Deno.realPath(args.get("--zig-oracle")!)),
  ];
  if (!oracleOnly) {
    binaries.push(
      await identity(
        "goose",
        await Deno.realPath(args.get("--goose-compiler")!),
      ),
    );
  }
  let output = args.get("--output");
  if (output) {
    output = resolve(output);
    await Deno.mkdir(output, { recursive: true });
    for await (const _entry of Deno.readDir(output)) {
      throw new Error("Evidence directory must be empty");
    }
  } else {
    const parent = fileURLToPath(
      new URL("../../build/goose-port/", import.meta.url),
    );
    await Deno.mkdir(parent, { recursive: true });
    output = await Deno.makeTempDir({
      dir: parent,
      prefix: "compiler-qualification-",
    });
  }
  const destination: string = output;
  const steps: Step[] = [];
  const observations: Record<string, Record<string, unknown>> = {};
  const memory: Record<string, unknown[]> = {};
  const commands: unknown[] = [];
  const fixtureNames = [
    "curried",
    "recursion",
    "aggregates",
    "parse-error",
    "type-error",
    "hole-error",
  ];
  const fixtureHashes: Record<string, string> = {};
  for (
    const name of [
      ...fixtureNames.map((name) => name + ".blot"),
      "project/main.blot",
      "project/library.blot",
    ]
  ) {
    fixtureHashes[name] = await hash(await Deno.readFile(fixtureRoot + name));
  }
  const projectRoot = destination + "/project";
  await Deno.mkdir(projectRoot);
  for (const name of ["main.blot", "library.blot"]) {
    await Deno.copyFile(
      fixtureRoot + "project/" + name,
      projectRoot + "/" + name,
    );
  }
  async function run(
    binary: string,
    label: string,
    executable: string,
    commandArgs: string[],
  ) {
    milliseconds();
    const child = new Deno.Command(executable, {
      args: commandArgs,
      clearEnv: true,
      env: { BLOT_CACHE_DIR: "" },
      stdin: "null",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    const abort = new AbortController();
    const expire = () => {
      abort.abort();
      kill(child);
    };
    const operation = Promise.all([
      child.status,
      readLog(child.stdout, expire, abort.signal),
      readLog(child.stderr, expire, abort.signal),
    ]);
    try {
      const [status, stdout, stderr] = await bounded(
        operation,
        milliseconds(),
        expire,
        label,
      );
      await Deno.writeFile(
        destination + "/" + binary + "/" + label + ".stdout",
        stdout,
      );
      await Deno.writeFile(
        destination + "/" + binary + "/" + label + ".stderr",
        stderr,
      );
      commands.push({
        binary,
        label,
        executable,
        args: commandArgs,
        code: status.code,
        stdout_sha256: await hash(stdout),
        stderr_sha256: await hash(stderr),
      });
      return { ...status, stdout, stderr };
    } finally {
      expire();
      await bounded(child.status, 5000, () => kill(child), "command cleanup");
    }
  }
  async function step(
    binary: string,
    name: string,
    operation: () => Promise<unknown>,
  ) {
    try {
      const value = await operation();
      observations[binary][name] = value;
      let status = "pass";
      if (
        value !== null && typeof value === "object" &&
        object(value).coverage === "unsupported"
      ) status = "unsupported";
      steps.push({ binary, name, status });
    } catch (error) {
      steps.push({ binary, name, status: "fail", error: errorText(error) });
    }
  }
  async function guest(
    binary: string,
    label: string,
    path: string,
    fixture: string,
  ) {
    const execution = await run(binary, label, Deno.execPath(), [
      "run",
      "--quiet",
      "--allow-read",
      runner,
      "--execute-wasm",
      path,
      "--case",
      fixture,
    ]);
    ok(execution.success, decoder.decode(execution.stderr));
    return object(JSON.parse(decoder.decode(execution.stdout)));
  }
  function noteMemory(binary: string, records: ObjectValue[]) {
    for (const item of records) {
      if (item.kind !== "compilation") continue;
      const value = item.memory;
      memory[binary].push(value ?? null);
      if (
        value !== null && typeof value === "object" && "live_bytes" in value
      ) {
        const live = object(value).live_bytes;
        if (typeof live === "number") {
          equal(live, 0, "Reported live compiler bytes must be zero");
        }
      }
    }
  }
  async function session(binary: Binary, injected: boolean) {
    const label = "server";
    let env: Record<string, string> = {};
    if (injected) {
      env = {
        BLOT_GOOSE_FAIL_REQUEST: "2",
        BLOT_GOOSE_FAIL_AT: "1",
        BLOT_GOOSE_FAIL_KIND: "1",
      };
    }
    const peer = new Peer(binary, milliseconds, env);
    const traceName = label + "-" + String(injected);
    try {
      await peer.hello();
      const entry = projectRoot + "/main.blot";
      const opened = await peer.send({
        kind: "open",
        id: 1,
        version: 1,
        entry,
        prelude: null,
      });
      same(opened.metadata, { kind: "open", id: 1, epoch: "1", revision: 0 });
      equal(opened.payload.length, 0);
      let id = 2;
      let revision = 0;
      const results: unknown[] = [];
      async function build(source?: string) {
        let payload = new Uint8Array();
        const request: ObjectValue = {
          kind: "build",
          id: id++,
          epoch: "1",
          revision,
        };
        if (source !== undefined) {
          payload = encoder.encode(source);
          request.sources = [{ path: entry, start: 0, length: payload.length }];
        }
        const reply = await peer.send(request, payload);
        equal(reply.metadata.kind, "build");
        equal(reply.metadata.id, request.id);
        equal(reply.metadata.epoch, "1");
        return reply;
      }
      async function accepted(reply: Frame, edited = false) {
        equal(reply.metadata.success, true, JSON.stringify(reply.metadata));
        equal(reply.metadata.revision, revision + 1);
        revision++;
        ok(WebAssembly.validate(reply.payload));
        const path = destination + "/" + binary.name + "/" + traceName + "-" +
          revision + ".wasm";
        await Deno.writeFile(path, reply.payload);
        const stats = object(reply.metadata.stats);
        memory[binary.name].push({ sessionHeap: stats.sessionHeap ?? null });
        let fixture = "project";
        if (edited) fixture = "project-edited";
        results.push(
          await guest(
            binary.name,
            traceName + "-execute-" + revision,
            path,
            fixture,
          ),
        );
      }
      function rejected(reply: Frame, code: string) {
        equal(reply.metadata.success, false);
        equal(
          reply.metadata.revision,
          revision,
          "A failed request must retain its accepted revision",
        );
        equal(reply.payload.length, 0);
        const issues = diagnostics(reply.metadata.diagnostics);
        ok(issues.some((issue) => issue.code === code), JSON.stringify(issues));
        results.push({ rejected: issues, revision });
      }
      if (injected) {
        rejected(await build(), "out_of_memory");
        await accepted(await build()); // Same open session survives the refused request.
      } else {
        await accepted(await build());
        const original = await Deno.readTextFile(entry);
        const edited = original.replace(
          "@u32.add (renamed value) (library.increment value)",
          "@u32.add (@u32.add (renamed value) (library.increment value)) 1",
        );
        ok(edited !== original);
        await accepted(await build(edited), true);
        rejected(
          await build(
            'import { hidden } from "./library"\nentry func answer () : U32 => return hidden 40\n',
          ),
          "unknown_export",
        );
        await accepted(await build()); // Failed/temporary overlays never replace disk or retained state.
      }
      await peer.close(id, revision);
      return { results, revision, closed: true };
    } finally {
      const stderr = await peer.dispose();
      await Deno.writeFile(
        destination + "/" + binary.name + "/" + traceName + ".stderr",
        stderr,
      );
      await Deno.writeTextFile(
        destination + "/" + binary.name + "/" + traceName + ".frames.json",
        JSON.stringify(peer.trace, null, 2) + "\n",
      );
    }
  }
  for (const binary of binaries) {
    await Deno.mkdir(destination + "/" + binary.name);
    observations[binary.name] = {};
    memory[binary.name] = [];
    for (
      const [label, command, fixture, code] of [
        ["parse", "parse", "curried", ""],
        ["check", "check", "curried", ""],
        ["parse-error", "parse", "parse-error", ""],
        ["type-error", "check", "type-error", "type_mismatch"],
        ["hole-error", "check", "hole-error", "typed_hole"],
      ]
    ) {
      await step(binary.name, "cli:" + label, async () => {
        const path = fixtureRoot + fixture + ".blot";
        const result = await run(binary.name, label, binary.path, [
          command,
          path,
          "--prelude",
          "none",
        ]);
        const records = decoder.decode(result.stdout).trim().split("\n").filter(
          Boolean,
        ).map((line) => object(JSON.parse(line)));
        noteMemory(binary.name, records);
        const issues = diagnostics(
          records.filter((item) => item.kind === "diagnostic"),
        );
        if (label === "parse" || label === "check") {
          ok(result.success, decoder.decode(result.stderr));
          equal(issues.length, 0);
        } else {
          ok(!result.success, "Expected the fixture to reject");
          ok(issues.length > 0);
          if (code) {
            ok(
              issues.some((issue) => issue.code === code),
              JSON.stringify(issues),
            );
          }
          const length = (await Deno.readFile(path)).length;
          for (const issue of issues) ok(Number(issue.end) <= length);
          if (fixture === "hole-error") {
            const source = await Deno.readTextFile(path);
            const start =
              encoder.encode(source.slice(0, source.indexOf("@hole"))).length;
            ok(
              issues.some((issue) =>
                issue.start === start && issue.end === start + 5
              ),
            );
          }
        }
        return { success: result.success, diagnostics: issues };
      });
    }
    for (const fixture of ["curried", "recursion", "aggregates"]) {
      await step(binary.name, "wasm:" + fixture, async () => {
        const path = destination + "/" + binary.name + "/" + fixture + ".wasm";
        const result = await run(binary.name, "build-" + fixture, binary.path, [
          "build",
          fixtureRoot + fixture + ".blot",
          path,
          "--prelude",
          "none",
        ]);
        const records = decoder.decode(result.stdout).trim().split("\n").filter(
          Boolean,
        ).map((line) => object(JSON.parse(line)));
        noteMemory(binary.name, records);
        if (fixture === "recursion" && !result.success) {
          const issues = diagnostics(
            records.filter((item) => item.kind === "diagnostic"),
          );
          ok(
            issues.length > 0 &&
              issues.every((issue) =>
                issue.code === "storage_unsupported" &&
                String(issue.message).includes("Recursive selected calls")
              ),
            JSON.stringify(issues),
          );
          return {
            coverage: "unsupported",
            abi: 8,
            executed: false,
            diagnostics: issues,
          };
        }
        ok(
          result.success,
          decoder.decode(result.stderr) + decoder.decode(result.stdout),
        );
        const compilation = records.find((item) => item.kind === "compilation");
        ok(
          compilation && compilation.success === true,
          "Missing successful compilation record",
        );
        const bytes = await Deno.readFile(path);
        ok(WebAssembly.validate(bytes));
        commands.push({
          binary: binary.name,
          artifact: path,
          sha256: await hash(bytes),
        });
        return await guest(binary.name, "execute-" + fixture, path, fixture);
      });
    }
    await step(binary.name, "project:lifecycle", () => session(binary, false));
    if (binary.name === "goose") {
      await step(
        binary.name,
        "project:request-oom",
        () => session(binary, true),
      );
    }
  }
  if (!oracleOnly) {
    for (const name of Object.keys(observations.oracle)) {
      await step("goose", "parity:" + name, async () => {
        ok(name in observations.goose, "Missing Goose observation");
        same(observations.goose[name], observations.oracle[name]);
        return { matchesOracle: true };
      });
    }
  }
  for (const binary of binaries) {
    const final = await identity(binary.name, binary.path);
    equal(final.sha256, binary.sha256, "Compiler changed during qualification");
  }
  const failed = steps.some((step) => step.status === "fail");
  const memoryStatus: Record<string, unknown> = {};
  for (const binary of binaries) {
    const measurements = memory[binary.name];
    let available = measurements.length > 0;
    for (const value of measurements) {
      if (
        value === null || typeof value !== "object" ||
        object(value).live_bytes === null ||
        object(value).live_bytes === undefined
      ) available = false;
    }
    let status = "unavailable";
    if (available) status = "reported-zero";
    memoryStatus[binary.name] = { status, observations: measurements };
  }
  let gooseStatus = "pending";
  if (!oracleOnly) {
    gooseStatus = "scoped-functional-pass";
    if (failed) gooseStatus = "failed";
  }
  const receipt = {
    schema: 1,
    timestamp: new Date().toISOString(),
    binaries,
    runner_sha256: await hash(await Deno.readFile(runner)),
    guest_host_sha256: await hash(
      await Deno.readFile(new URL("../../host/guest.ts", import.meta.url)),
    ),
    fixture_sha256: fixtureHashes,
    deno: Deno.version,
    platform: { os: Deno.build.os, arch: Deno.build.arch },
    limits: {
      command_and_request_ms: timeout,
      overall_ms: overall,
      max_frame_bytes: maxFrame,
      max_log_bytes: maxLog,
    },
    scope: [
      "CLI parse/check rejection codes and spans",
      "executed ABI 8 named/curried/recursive/record/array fixtures",
      "project open/build/edit/reject/retry/close",
      "Goose request-token-2 injected OOM and retry",
    ],
    oracle_only: oracleOnly,
    scoped_functional_pass: !failed,
    full_runtime_qualification: "pending",
    goose_qualification: gooseStatus,
    memory_qualification: memoryStatus,
    limitations: [
      "These scoped checks do not qualify the entire compiler/runtime.",
      "Null memory counters are unavailable coverage, never zero live bytes.",
    ],
    unsupported_execution: steps.filter((step) => step.status === "unsupported")
      .map((step) => ({
        binary: step.binary,
        fixture: step.name,
        reason:
          "ABI 8 recursive selected calls rejected; execution remains unqualified",
      })),
    steps,
    observations,
    commands,
  };
  if (oracleOnly) {
    receipt.limitations.push(
      "Goose was not run; compiler parity and request OOM remain pending.",
    );
  }
  await Deno.writeTextFile(
    destination + "/receipt.json",
    JSON.stringify(receipt, null, 2) + "\n",
  );
  console.log(
    JSON.stringify({
      receipt: destination + "/receipt.json",
      scoped_functional_pass: !failed,
      full_runtime_qualification: "pending",
    }),
  );
  if (failed) Deno.exitCode = 1;
}

if (Deno.args[0] === "--execute-wasm") {
  equal(Deno.args[2], "--case");
  console.log(JSON.stringify(await executeWasm(Deno.args[1], Deno.args[3])));
} else if (import.meta.main) {
  await qualify();
}
