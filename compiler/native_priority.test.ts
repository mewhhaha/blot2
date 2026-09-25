import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { arithmeticSource } from "./benchmark_workloads.ts";
import {
  decodeNativeResponse,
  encodeNativeRequest,
  nativeProtocolMagic,
  nativeProtocolVersion,
} from "./native_protocol.ts";
import { NativeProcess } from "./native_process.ts";
import { createSourceFrontend } from "./source_frontend.ts";

// blotc resets a demoted launcher's scheduling (SCHED_IDLE, a positive nice
// value, idle IO) on every thread unless started with --inherit-priority.
// Deno reads /proc only with --allow-all, so threads are inspected with ps.
const blotc = fileURLToPath(
  new URL("../generated/compiler/blotc", import.meta.url),
);
const decoder = new TextDecoder();

async function run(command: string, args: string[]) {
  try {
    const result = await new Deno.Command(command, {
      args,
      stdout: "piped",
      stderr: "null",
    }).output();
    return result.success ? decoder.decode(result.stdout).trim() : undefined;
  } catch (error) {
    if (
      error instanceof Deno.errors.NotFound ||
      error instanceof Deno.errors.NotCapable ||
      error instanceof Deno.errors.PermissionDenied
    ) return undefined;
    throw error;
  }
}

const self = String(Deno.pid);
const ps = await run("ps", ["-L", "-o", "lwp=,cls=,ni=", "-p", self]) !==
  undefined;
const detachable = ps &&
  await run("setsid", ["--fork", "true"]) !== undefined;
const chrt = await run("chrt", ["--idle", "0", "true"]) !== undefined;
const nice = await run("nice", ["-n", "16", "true"]) !== undefined;
const ionice = await run("ionice", ["-c", "3", "true"]) !== undefined;
// Leaving SCHED_IDLE or lowering nice to 0 needs RLIMIT_NICE >= 20.
const limit = await run("prlimit", [
  "--pid",
  self,
  "--nice",
  "--raw",
  "--noheadings",
  "--output",
  "SOFT",
]);
const restorable = limit === "unlimited" ||
  (limit !== undefined && Number(limit) >= 20);

interface Task {
  readonly id: string;
  readonly policy: string;
  readonly nice: string;
}

async function tasks(pid: number): Promise<Task[]> {
  const listing = await run("ps", [
    "-L",
    "-o",
    "lwp=,cls=,ni=",
    "-p",
    String(pid),
  ]);
  ok(listing, "ps lists the native compiler's threads");
  return listing.split("\n").map((line) => {
    const [id, policy, nice] = line.trim().split(/\s+/);
    return { id, policy, nice };
  });
}

// Some harnesses keep rewriting the scheduling of every thread they reach
// through /proc/<pid>/task/<tid>/children. For example,
// build/perf-overhaul/run_normal_priority.py forces SCHED_BATCH nice 0 every
// 100 ms, which would hide blotc's own choice. Every blotc here therefore runs
// outside this test's process tree. `setsid --fork` orphans a shell that starts
// `launcher... blotc` on this test's stdin and stdout. The shell reports the
// compiler's pid on stderr, waits for it, then reports its exit status.
const detach =
  'exec 3<&0; "$@" <&3 3<&- 2>/dev/null & echo "$!" >&2; wait "$!"; echo "$?" >&2';

// A harness can still reach the compiler if it walks the short-lived setsid
// parent between that parent's fork and its exit. The launch then shows the
// harness's SCHED_BATCH nice 0. No launcher below produces that, so the launch
// is retried.
class Rewritten extends Error {}

function unrewritten(running: Task[]) {
  if (running.some((task) => task.policy === "B" && task.nice === "0")) {
    throw new Rewritten(
      "a harness kept rewriting the detached compiler to SCHED_BATCH nice 0",
    );
  }
}

class Frames {
  readonly #reader: ReadableStreamDefaultReader<Uint8Array<ArrayBuffer>>;
  #buffer = new Uint8Array(0);

  constructor(stream: ReadableStream<Uint8Array<ArrayBuffer>>) {
    this.#reader = stream.getReader();
  }

  async #exact(length: number) {
    while (this.#buffer.length < length) {
      const next = await this.#reader.read();
      if (next.done) throw new Error("native compiler closed stdout");
      const joined = new Uint8Array(this.#buffer.length + next.value.length);
      joined.set(this.#buffer);
      joined.set(next.value, this.#buffer.length);
      this.#buffer = joined;
    }
    const bytes = this.#buffer.slice(0, length);
    this.#buffer = this.#buffer.slice(length);
    return bytes;
  }

  async read() {
    const words = new DataView((await this.#exact(4)).buffer).getUint32(
      0,
      true,
    );
    return await this.#exact(words * 4);
  }

  async close() {
    await this.#reader.cancel();
    this.#reader.releaseLock();
  }
}

class Lines {
  readonly #reader: ReadableStreamDefaultReader<string>;
  #text = "";

  constructor(stream: ReadableStream<Uint8Array<ArrayBuffer>>) {
    this.#reader = stream.pipeThrough(new TextDecoderStream()).getReader();
  }

  async read() {
    let end = this.#text.indexOf("\n");
    while (end < 0) {
      const next = await this.#reader.read();
      if (next.done) throw new Error("the detached launcher closed stderr");
      this.#text += next.value;
      end = this.#text.indexOf("\n");
    }
    const line = this.#text.slice(0, end);
    this.#text = this.#text.slice(end + 1);
    return line;
  }

  async close() {
    await this.#reader.cancel();
    this.#reader.releaseLock();
  }
}

// Starts blotc through `launcher` outside this process tree, checks the threads
// after the handshake and again after a compile has started the worker pool.
async function session(
  launcher: readonly string[],
  extra: readonly string[],
  check: (tasks: Task[]) => Promise<void>,
) {
  const child = new Deno.Command("setsid", {
    args: [
      "--fork",
      "sh",
      "-c",
      detach,
      "sh",
      ...launcher,
      blotc,
      "--threads",
      "4",
      ...extra,
    ],
    clearEnv: true,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const reports = new Lines(child.stderr);
  const frames = new Frames(child.stdout);
  const writer = child.stdin.getWriter();
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    const pid = Number(await reports.read());
    ok(Number.isInteger(pid) && pid > 0, "the launcher reports blotc's pid");
    const handshake = new DataView((await frames.read()).buffer);
    equal(
      [handshake.getUint32(0, true), handshake.getUint32(4, true)],
      [nativeProtocolMagic, nativeProtocolVersion],
    );
    await check(await tasks(pid));
    const prepared = frontend.prepare(arithmeticSource("balanced", false));
    const payload = encodeNativeRequest({
      operation: "emit",
      root: prepared.root,
      prelude: prepared.prelude,
      fuel: prepared.nodeCount,
      const_steps: 100n,
    });
    const header = new Uint8Array(4);
    new DataView(header.buffer).setUint32(0, payload.length / 4, true);
    await writer.write(header);
    await writer.write(payload);
    equal(decodeNativeResponse(await frames.read()).operation, "emit");
    const running = await tasks(pid);
    ok(running.length > 1, "a compile starts the worker threads");
    await check(running);
    await writer.close();
    equal(await reports.read(), "0", "blotc exits with status 0");
    equal((await child.status).code, 0);
  } finally {
    frontend.dispose();
    // Closing stdin ends a detached blotc that is still running.
    await Promise.allSettled([
      writer.abort(),
      frames.close(),
      reports.close(),
      child.status,
    ]);
    writer.releaseLock();
  }
}

async function launch(
  launcher: readonly string[],
  extra: readonly string[],
  check: (tasks: Task[]) => Promise<void>,
) {
  for (let attempt = 1;; attempt += 1) {
    try {
      return await session(launcher, extra, check);
    } catch (error) {
      if (!(error instanceof Rewritten) || attempt === 3) throw error;
    }
  }
}

async function normal(running: Task[]) {
  unrewritten(running);
  for (const task of running) {
    equal([task.policy, task.nice], ["TS", "0"], `thread ${task.id}`);
  }
}

Deno.test({
  name: "blotc restores SCHED_OTHER nice 0 on every thread under chrt --idle",
  ignore: !detachable || !chrt || !restorable,
  fn: () => launch(["chrt", "--idle", "0"], [], normal),
});

Deno.test({
  name: "blotc restores SCHED_OTHER nice 0 on every thread under nice 16",
  ignore: !detachable || !nice || !restorable,
  fn: () => launch(["nice", "-n", "16"], [], normal),
});

Deno.test({
  name: "blotc restores best-effort IO on every thread under ionice idle",
  ignore: !detachable || !ionice,
  fn: () =>
    launch(["ionice", "-c", "3"], [], async (running) => {
      for (const task of running) {
        equal(await run("ionice", ["-p", task.id]), "best-effort: prio 4");
      }
    }),
});

Deno.test({
  name: "blotc --inherit-priority keeps the launcher's scheduling",
  ignore: !detachable || !chrt || !nice,
  async fn() {
    await launch(
      ["chrt", "--idle", "0"],
      ["--inherit-priority"],
      async (running) => {
        unrewritten(running);
        for (const task of running) {
          equal(task.policy, "IDL", `thread ${task.id}`);
        }
      },
    );
    // nice adds 16 to this process's own nice value (ps prints "-" for the
    // nice value of SCHED_IDLE tasks). The detached launcher inherits it.
    const [parent] = await tasks(Deno.pid);
    const expected = parent.policy === "IDL"
      ? ["IDL", "-"]
      : [parent.policy, String(Math.min(19, Number(parent.nice) + 16))];
    await launch(
      ["nice", "-n", "16"],
      ["--inherit-priority"],
      async (running) => {
        unrewritten(running);
        for (const task of running) {
          equal([task.policy, task.nice], expected, `thread ${task.id}`);
        }
      },
    );
  },
});

Deno.test({
  name: "NativeProcess passes --inherit-priority only for priority inherit",
  ignore: !ps,
  async fn() {
    await rejects(
      () => NativeProcess.start({ priority: "low" as "normal" }),
      RangeError,
    );
    for (
      const [priority, flagged] of [
        [undefined, false],
        ["normal", false],
        ["inherit", true],
      ] as const
    ) {
      const process = await NativeProcess.start({ priority });
      try {
        const args = await run("ps", [
          "-o",
          "args=",
          "-p",
          String(process.pid),
        ]);
        ok(args, "ps prints the native compiler's arguments");
        equal(args.split(/\s+/).includes("--inherit-priority"), flagged);
      } finally {
        await process.dispose();
      }
    }
  },
});
