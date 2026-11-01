// Tiny nominal DAG acceptance matrix; each compiler startup/build is bounded.
// deno run -A scripts/bench/source_proof.ts --blotc PATH [--output FILE]
import { resolve } from "node:path";

const options = new Map<string, string>();
for (let at = 0; at < Deno.args.length; at++) {
  const key = Deno.args[at];
  if (!["--blotc", "--timeout-ms", "--output"].includes(key)) {
    throw new Error(`Unexpected argument: ${key}`);
  }
  const value = Deno.args[++at];
  if (!value || value.startsWith("--")) throw new Error(`${key} needs a value`);
  options.set(key, value);
}
const timeoutMs = Number(options.get("--timeout-ms") ?? "5000");
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 5000) {
  throw new Error("--timeout-ms must be from 100 to 5000");
}
const repo = resolve(new URL("../..", import.meta.url).pathname);
const compiler = resolve(
  options.get("--blotc") ?? `${repo}/zig-native/zig-out-native-dev/bin/blotc`,
);
const runner = `${repo}/scripts/bench/scoped_calls.ts`;
const decoder = new TextDecoder();
const matrix: Record<string, unknown>[] = [];
// GNU timeout owns a process group, so this last-resort deadline also kills a
// stuck runner's compiler descendants. Individual startup/build limits stay 5s.
const watchdogMs = 2 * timeoutMs + 2_000;
for (const depth of [6, 8, 10]) {
  for (const width of [1, 8]) {
    const child = await new Deno.Command("timeout", {
      args: [
        "--signal=KILL",
        `${watchdogMs / 1_000}s`,
        Deno.execPath(),
        "run",
        "--no-config",
        "--no-lock",
        "-A",
        runner,
        "--blotc",
        compiler,
        "--nominal",
        "--fields",
        "3",
        "--depth",
        String(depth),
        "--sizes",
        String(width),
        "--timeout-ms",
        String(timeoutMs),
        "--profile",
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const lines = decoder.decode(child.stdout).trim().split("\n").filter(
      Boolean,
    );
    let report: Record<string, unknown>;
    try {
      if (lines.length !== 1) {
        throw new Error("Expected exactly one bounded build report");
      }
      report = JSON.parse(lines[0]);
      if (
        report.depth !== depth || report.width !== width ||
        report.fields !== 3 ||
        report.workload !== "nominal_field_refinement"
      ) {
        throw new Error(
          "Build report does not match its acceptance-matrix cell",
        );
      }
      if (!child.success && report.status === "complete") {
        throw new Error("Child failed after reporting completion");
      }
    } catch (error) {
      let status = "failed";
      if (child.code === 124 || child.code === 137) {
        status = "timeout_incomplete";
      }
      report = {
        status,
        depth,
        width,
        error: String(error),
        stderr: decoder.decode(child.stderr),
        stdout: decoder.decode(child.stdout),
      };
    }
    matrix.push(report);
    console.log(JSON.stringify(report));
    if (report.status !== "complete") Deno.exitCode = 1;
  }
}
if (options.has("--output")) {
  await Deno.writeTextFile(
    resolve(options.get("--output")!),
    `${
      JSON.stringify(
        {
          workload: "nominal_source_proof_matrix",
          timeout_ms: timeoutMs,
          watchdog_ms: watchdogMs,
          matrix,
        },
        null,
        2,
      )
    }\n`,
  );
}
