// Bounded driver for the existing CPU-weighted gdb sampling protocol.
import {
  createZigProjectCompiler,
  type ZigProjectBuildOptions,
  type ZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "../../host/zig_project_client.ts";

async function waitFor(path: string, child: Deno.ChildProcess) {
  let exited = false;
  child.status.then(() => exited = true);
  const deadline = performance.now() + 5000;
  while (performance.now() < deadline) {
    try {
      await Deno.stat(path);
      return;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    if (exited) throw new Error(`gdb exited before ${path}; see gdb.log`);
    await new Promise((done) => setTimeout(done, 10));
  }
  throw new Error(`gdb handshake exceeded 5000 ms: ${path}`);
}

export async function createSampledCompiler(
  options: ZigProjectCompilerOptions,
  output: string,
  repo: string,
  focus?: string,
  emissionDelayMs = 0,
) {
  if (
    !Number.isInteger(emissionDelayMs) || emissionDelayMs < 0 ||
    emissionDelayMs > 15000
  ) {
    throw new Error("Emission sampling delay must be 0..15000 ms");
  }
  const binary = String(options.executable);
  const control = `${output}/control-0`;
  await Deno.mkdir(control, { recursive: true });
  for (const name of ["pid", "attached", "start", "stop", "detached"]) {
    await Deno.remove(`${control}/${name}`).catch((error) => {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    });
  }
  await Deno.writeTextFile(`${output}/samples.jsonl`, "");
  await Deno.writeTextFile(`${output}/builds.jsonl`, "");
  await Deno.writeTextFile(`${output}/gdb.log`, "");
  await Deno.remove(`${output}/sampling-window.json`).catch((error) => {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  });
  const wrapper = `${output}/blotc-ptracer`;
  await Deno.writeTextFile(
    wrapper,
    `#!/usr/bin/env python3
import ctypes, os, sys
ctypes.CDLL(None).prctl(0x59616D61, ctypes.c_ulong(-1).value, 0, 0, 0)
os.execv(${JSON.stringify(binary)}, [${JSON.stringify(binary)}] + sys.argv[1:])
`,
  );
  await Deno.chmod(wrapper, 0o755);
  const clock = await new Deno.Command("getconf", {
    args: ["CLK_TCK"],
    signal: AbortSignal.timeout(5000),
    stdout: "piped",
    stderr: "piped",
  }).output();
  const hz = Number(new TextDecoder().decode(clock.stdout).trim());
  if (!clock.success || !Number.isFinite(hz) || hz <= 0) {
    throw new Error(
      "getconf CLK_TCK failed; process CPU accounting unavailable",
    );
  }
  let compiler: ZigProjectCompiler | undefined;
  let gdb: Deno.ChildProcess | undefined;
  let log: Promise<void> | undefined;
  const detach = async () => {
    if (gdb) {
      try {
        await Deno.writeTextFile(`${control}/stop`, "1");
        await waitFor(`${control}/detached`, gdb);
      } catch {
        try {
          gdb.kill("SIGKILL");
        } catch { /* Already exited. */ }
      }
    }
  };
  const dispose = async () => {
    await detach();
    const timer = setTimeout(() => {
      try {
        gdb?.kill("SIGKILL");
      } catch { /* Already exited. */ }
    }, 5000);
    try {
      await compiler?.dispose();
    } finally {
      try {
        await log;
      } finally {
        clearTimeout(timer);
      }
    }
  };
  try {
    compiler = await createZigProjectCompiler({
      ...options,
      executable: wrapper,
      startupTimeoutMs: Math.min(options.startupTimeoutMs ?? 5000, 5000),
    });
    const project = compiler;
    gdb = new Deno.Command("gdb", {
      args: ["-batch", "-q", "-x", `${repo}/benchmarks/tools/gdb_sampler.py`],
      env: {
        SAMPLE_CONTROL: control,
        SAMPLE_RUN: "0",
        SAMPLE_BINARY: binary,
        SAMPLE_OUT: `${output}/samples.jsonl`,
        SAMPLE_MIN_MS: "50",
        SAMPLE_MAX_MS: "100",
        SAMPLE_LIMIT: "80",
        SAMPLE_FOCUS: focus ?? "",
        SAMPLE_EMISSION_DELAY_MS: String(emissionDelayMs),
      },
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    log = gdb.output().then(async ({ stdout, stderr }) => {
      await Deno.writeFile(
        `${output}/gdb.log`,
        new Uint8Array([...stdout, ...stderr]),
      );
    });
    await Deno.writeTextFile(`${control}/pid`, String(project.pid));
    await waitFor(`${control}/attached`, gdb);
    const ticks = async () => {
      const stat = await Deno.readTextFile(`/proc/${project.pid}/stat`);
      const fields = stat.slice(stat.lastIndexOf(") ") + 2).trim().split(/\s+/);
      return Number(fields[11]) + Number(fields[12]);
    };
    return {
      compiler: project,
      dispose,
      async build(buildOptions: ZigProjectBuildOptions) {
        const before = await ticks();
        const started = Date.now();
        let success = false;
        try {
          await Deno.writeTextFile(`${control}/start`, "1");
          const result = await project.build(buildOptions);
          success = result.success;
          return result;
        } finally {
          const finished = Date.now();
          const after = await ticks().catch(() => null);
          let cpuMs: number | null = null;
          if (after !== null) cpuMs = (after - before) * 1000 / hz;
          let label = "world-producer";
          if (focus === "emission") label = "gdev-main";
          await Deno.writeTextFile(
            `${output}/builds.jsonl`,
            JSON.stringify({
              run: 0,
              label,
              sampled: true,
              diagnostic: "sampling is diagnostic, not release timing",
              started_ms: started,
              finished_ms: finished,
              success,
              cpu_ms: cpuMs,
              processcpu_delta: cpuMs,
              user_hz: hz,
              cpu_accounting_missing: after === null,
              cpu_accounting:
                `Linux USER_HZ=${hz}; child user plus system ticks; milliseconds`,
            }) + "\n",
          );
          await detach();
        }
      },
    };
  } catch (error) {
    await dispose();
    throw error;
  }
}
