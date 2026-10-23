import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { type Phase, runPhase } from "./compiler_phase.ts";
import { nativeTestRecords, verifyNativeSelection } from "./dev_check_areas.ts";
import { nativeTestPartitions } from "./native_test_partitions.ts";

type Interval = {
  shard: number;
  shards: number;
  selected: number;
  start_ns: number;
  end_ns: number;
};

export function shardInterval(
  log: string,
  shard: number,
  shards: number,
  selected: number,
): Interval {
  const rows = log.split("\n").filter((line) =>
    line.startsWith("BLOT_NATIVE_SHARD\t")
  );
  if (rows.length !== 1) {
    throw new Error("Missing or repeated native shard completion");
  }
  const row = JSON.parse(rows[0].slice("BLOT_NATIVE_SHARD\t".length));
  if (
    row.shard !== shard || row.shards !== shards || row.selected !== selected ||
    !Number.isFinite(row.start_ns) || row.start_ns < 0 ||
    !Number.isFinite(row.end_ns) || row.end_ns < row.start_ns
  ) {
    throw new Error("Native shard completion does not match its inventory");
  }
  return row;
}

export function peakConcurrency(intervals: Interval[]): number {
  const events = intervals.filter((row) =>
    row.selected > 0 && row.end_ns > row.start_ns
  )
    .flatMap((row) => [[row.start_ns, 1], [row.end_ns, -1]])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  let active = 0;
  let peak = 0;
  for (const [, change] of events) peak = Math.max(peak, active += change);
  return peak;
}

/** Run the installed complete inventory directly; Zig's build scheduler owns no execution slots. */
export async function runNativeTests(options: {
  binary: string;
  directory: string;
  shards: number;
  seconds: number;
  mode?: "full" | "sampled";
  signal?: AbortSignal;
}) {
  const started = performance.now();
  const mode = options.mode ?? "full";
  if (
    !Number.isInteger(options.shards) || options.shards < 1 ||
    options.shards > 4 ||
    !Number.isFinite(options.seconds) || options.seconds <= 0 ||
    !["full", "sampled"].includes(mode)
  ) throw new Error("Invalid native execution options");
  const binary = resolve(options.binary);
  const directory = resolve(options.directory);
  await Deno.mkdir(directory, { recursive: true });
  const costs = new Map<string, number>();
  let timingSource: string | null = null;
  try {
    const previous = JSON.parse(
      await Deno.readTextFile(resolve(directory, "results.json")),
    );
    if (
      previous.success && previous.allocation_failures === mode &&
      Array.isArray(previous.phases)
    ) {
      for (const phase of previous.phases) {
        if (phase.name === "inventory") continue;
        for (
          const record of nativeTestRecords(
            await Deno.readTextFile(phase.stderr),
          )
        ) {
          if (
            record.status === "passed" && record.leaks === 0 &&
            record.logged_errors === 0
          ) {
            costs.set(record.name, record.duration_ns);
          }
        }
      }
      if (costs.size) timingSource = "last-successful-run";
    }
  } catch {
    // Missing, corrupt or moved history is only a lost scheduling hint.
    costs.clear();
  }
  if (costs.size === 0 && mode === "full") {
    try {
      const baseline = JSON.parse(
        await Deno.readTextFile(
          new URL("./native_test_costs.json", import.meta.url),
        ),
      );
      if (baseline.version === 1 && baseline.allocation_failures === "full") {
        for (const [name, cost] of Object.entries(baseline.costs)) {
          if (
            typeof cost === "number" && Number.isSafeInteger(cost) && cost > 0
          ) costs.set(name, cost);
        }
        if (costs.size) timingSource = "recorded-baseline";
      }
    } catch {
      // An absent baseline is harmless; cold runs retain round-robin coverage.
      costs.clear();
    }
  }
  const runDirectory = await Deno.makeTempDir({
    dir: directory,
    prefix: "run-",
  });
  const report = {
    success: false,
    allocation_failures: mode,
    qualifies_release: false,
    started_at: new Date().toISOString(),
    wall_seconds: 0,
    error: null as string | null,
    inventory: [] as string[],
    shards: options.shards,
    intervals: [] as Interval[],
    peak_active_shards: 0,
    phases: [] as Phase[],
    artifacts: [] as string[],
    scheduling: "round-robin",
    partitions: [] as string[][],
    estimated_partition_ns: [] as number[],
    timing_source: timingSource,
  };
  const controller = new AbortController();
  const abort = () => controller.abort(options.signal?.reason ?? "cancelled");
  options.signal?.addEventListener("abort", abort, { once: true });
  if (options.signal?.aborted) abort();
  const timer = setTimeout(
    () => controller.abort("budget"),
    options.seconds * 1000,
  );
  const execute = async (name: string, args: string[]) => {
    if (controller.signal.aborted) {
      throw new Error("Native execution cancelled");
    }
    const result = await runPhase(
      name,
      [binary, ...args],
      runDirectory,
      Deno.cwd(),
      {},
      {
        seconds: Math.max(
          0.001,
          options.seconds - (performance.now() - started) / 1000,
        ),
        signal: controller.signal,
        forceCancel: true,
      },
    );
    report.phases.push(result);
    report.artifacts.push(result.stdout, result.stderr);
    if (result.code !== 0) {
      throw new Error(`${name} failed (${result.code}); logs: ${runDirectory}`);
    }
    return result;
  };
  try {
    const inventory = await execute("inventory", ["--list"]);
    report.inventory = (await Deno.readTextFile(inventory.stdout)).trim().split(
      "\n",
    );
    if (
      !report.inventory[0] ||
      new Set(report.inventory).size !== report.inventory.length
    ) {
      throw new Error("Native inventory is empty or duplicated");
    }
    const plan = nativeTestPartitions(report.inventory, options.shards, costs);
    report.scheduling = plan.weighted ? "prior-timings" : "round-robin";
    report.partitions = plan.groups;
    report.estimated_partition_ns = plan.estimated_ns;
    let failure: unknown;
    await Promise.allSettled(
      Array.from({ length: options.shards }, async (_, shard) => {
        try {
          const expected = plan.groups[shard];
          const physicalShard = plan.weighted ? 0 : shard;
          const physicalShards = plan.weighted ? 1 : options.shards;
          const result = await execute(`shard-${shard}`, [
            `--shard=${physicalShard}`,
            `--shards=${physicalShards}`,
            `--allocation-failures=${mode}`,
            "--fail-fast",
            ...(plan.weighted ? expected.map((name) => `--test=${name}`) : []),
          ]);
          const log = await Deno.readTextFile(result.stderr);
          verifyNativeSelection(nativeTestRecords(log), expected, mode);
          report.intervals.push(
            {
              ...shardInterval(
                log,
                physicalShard,
                physicalShards,
                expected.length,
              ),
              shard,
              shards: options.shards,
            },
          );
        } catch (error) {
          failure ??= error;
          controller.abort("failed sibling");
          throw error;
        }
      }),
    );
    if (failure) throw failure;
    if (controller.signal.aborted) {
      throw new Error("Native execution cancelled or over budget");
    }
    report.success = true;
    return report;
  } catch (error) {
    report.error = String(error);
    throw error;
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener("abort", abort);
    report.wall_seconds = (performance.now() - started) / 1000;
    report.intervals.sort((a, b) => a.shard - b.shard);
    report.phases.sort((a, b) => a.name.localeCompare(b.name));
    report.peak_active_shards = peakConcurrency(report.intervals);
    const text = JSON.stringify(report, null, 2) + "\n";
    await Deno.writeTextFile(resolve(runDirectory, "results.json"), text);
    await Deno.writeTextFile(resolve(directory, "results.json"), text);
    // Preserve the raw records in the outer gate's journal as well as per-shard
    // files. Publish whole files serially so concurrent records cannot interleave.
    for (
      const phase of report.phases.filter((phase) => phase.name !== "inventory")
    ) {
      for (
        const [path, output] of [[phase.stdout, Deno.stdout], [
          phase.stderr,
          Deno.stderr,
        ]] as const
      ) {
        const file = await Deno.open(path);
        await file.readable.pipeTo(output.writable, { preventClose: true });
      }
    }
    console.log(
      `Native execution: ${report.inventory.length} tests, ${report.shards} shards, peak ${report.peak_active_shards}; report: ${
        resolve(directory, "results.json")
      }`,
    );
  }
}

/** Pin raw inventory, shard logs and the report when accepting journal evidence. */
export async function nativeExecutionArtifacts(
  directory: string,
): Promise<string[]> {
  const path = resolve(directory, "results.json");
  const report = JSON.parse(await Deno.readTextFile(path));
  if (
    !report.success || report.allocation_failures !== "full" ||
    !Array.isArray(report.artifacts)
  ) {
    throw new Error(
      "Native execution did not complete exhaustive qualification",
    );
  }
  return [path, ...report.artifacts];
}

if (import.meta.main) {
  const { values } = parseArgs({
    args: Deno.args,
    options: {
      binary: {
        type: "string",
        default: "zig-native/zig-out-native-dev/bin/blot-tests",
      },
      "timings-dir": {
        type: "string",
        default: "build/bench/native-execution",
      },
      shards: { type: "string", default: "2" },
      "budget-seconds": { type: "string", default: "600" },
      "allocation-failures": { type: "string", default: "full" },
    },
  });
  const controller = new AbortController();
  const abort = () => controller.abort("cancelled");
  Deno.addSignalListener("SIGINT", abort);
  if (Deno.build.os !== "windows") Deno.addSignalListener("SIGTERM", abort);
  try {
    await runNativeTests({
      binary: values.binary,
      directory: values["timings-dir"],
      shards: Number(values.shards),
      seconds: Number(values["budget-seconds"]),
      mode: values["allocation-failures"] as "full" | "sampled",
      signal: controller.signal,
    });
  } finally {
    Deno.removeSignalListener("SIGINT", abort);
    if (Deno.build.os !== "windows") {
      Deno.removeSignalListener("SIGTERM", abort);
    }
  }
}
