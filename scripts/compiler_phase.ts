import { spawn } from "node:child_process";
import { closeSync, openSync } from "node:fs";
import { resolve } from "node:path";

export type Phase = {
  name: string;
  command: string[];
  wall_seconds: number;
  code: number;
  stdout: string;
  stderr: string;
  cache: string;
  stopped?: "budget" | "cancelled";
};

export function cacheStatus(name: string, stderr: string): string {
  let step = "";
  if (name === "native-compile") step = "compile test";
  if (name === "native-run") step = "run test";
  if (!step) return "not-applicable";
  const lines = stderr.split("\n").filter((line) => line.includes(step));
  if (lines.some((line) => /\bsuccess\b|\bpass\b/.test(line))) return "miss";
  if (lines.length && lines.every((line) => /\bcached\b/.test(line))) {
    return "hit";
  }
  return "unknown";
}

type Controls = {
  seconds?: number;
  heartbeat?: number;
  signal?: AbortSignal;
};

export async function runPhase(
  name: string,
  command: string[],
  directory: string,
  cwd = Deno.cwd(),
  env: Record<string, string> = {},
  controls: Controls = {},
): Promise<Phase> {
  await Deno.mkdir(directory, { recursive: true });
  const stdout = resolve(directory, `${name}.stdout.log`);
  const stderr = resolve(directory, `${name}.stderr.log`);
  const out = openSync(stdout, "w");
  const err = openSync(stderr, "w");
  const started = performance.now();
  const result: Phase = {
    name,
    command,
    wall_seconds: 0,
    code: 127,
    stdout,
    stderr,
    cache: "not-applicable",
  };
  console.log(`${name}: starting`);
  // A separate process group lets cancellation reach Zig workers and test guests.
  // Direct file descriptors also preserve partial logs if a descendant stalls.
  const child = spawn(command[0], command.slice(1), {
    cwd,
    env: { ...Deno.env.toObject(), ...env },
    detached: Deno.build.os !== "windows",
    stdio: ["ignore", out, err],
  });
  closeSync(out);
  closeSync(err);
  let cleanup: Promise<void> | undefined;
  const kill = async (force: boolean) => {
    if (!child.pid) return;
    try {
      if (Deno.build.os === "windows") {
        const args = ["/pid", String(child.pid), "/t"];
        if (force) args.push("/f");
        await new Deno.Command("taskkill", {
          args,
          stdout: "null",
          stderr: "null",
        }).output();
      } else {
        let signal: Deno.Signal = "SIGTERM";
        if (force) signal = "SIGKILL";
        Deno.kill(-child.pid, signal);
      }
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  };
  const stop = (reason: "budget" | "cancelled") => {
    if (cleanup) return;
    result.stopped = reason;
    console.error(`${name}: ${reason}; stopping process group`);
    cleanup = (async () => {
      await kill(false);
      await new Promise((done) => setTimeout(done, 250));
      await kill(true);
    })();
  };
  const abort = () => {
    if (controls.signal?.reason === "budget") stop("budget");
    else stop("cancelled");
  };
  controls.signal?.addEventListener("abort", abort, { once: true });
  let timeout: ReturnType<typeof setTimeout> | undefined;
  if (controls.seconds) {
    timeout = setTimeout(() => stop("budget"), controls.seconds * 1000);
  }
  const heartbeat = setInterval(() => {
    console.log(
      `${name}: ${
        ((performance.now() - started) / 1000).toFixed(0)
      }s elapsed; logs: ${directory}`,
    );
  }, (controls.heartbeat ?? 15) * 1000);
  try {
    const status = new Promise<number>((done) => {
      child.once("error", (error) => {
        Deno.writeTextFileSync(stderr, `${error}\n`, { append: true });
        done(127);
      });
      child.once("exit", (code) => done(code ?? 1));
    });
    if (controls.signal?.aborted) abort();
    result.code = await status;
    await cleanup;
    if (result.stopped === "budget") result.code = 124;
    if (result.stopped === "cancelled") result.code = 130;
  } finally {
    clearTimeout(timeout);
    clearInterval(heartbeat);
    controls.signal?.removeEventListener("abort", abort);
  }
  result.wall_seconds = (performance.now() - started) / 1000;
  result.cache = cacheStatus(name, await Deno.readTextFile(stderr));
  console.log(
    `${name}: ${
      result.wall_seconds.toFixed(2)
    }s, exit ${result.code}, cache ${result.cache}`,
  );
  return result;
}

export async function together(
  jobs: (() => Promise<unknown>)[],
  controller: AbortController,
) {
  let failure: unknown;
  const results = await Promise.allSettled(jobs.map(async (job) => {
    try {
      return await job();
    } catch (error) {
      failure ??= error;
      controller.abort();
      throw error;
    }
  }));
  if (failure) throw failure;
  for (const result of results) {
    if (result.status === "rejected") throw result.reason;
  }
}
