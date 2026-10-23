import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import process from "node:process";
import {
  nativeExecutionArtifacts,
  peakConcurrency,
  runNativeTests,
  shardInterval,
} from "./run_native_tests.ts";
import { NativeJournal } from "./compiler_gate_state.ts";
import { nativeTestPartitions } from "./native_test_partitions.ts";

async function fixture(kind = "pass") {
  const directory = await Deno.makeTempDir({ prefix: "blot-native-schedule-" });
  const binary = resolve(directory, "native");
  const script = resolve(directory, "native.ts");
  await Deno.writeTextFile(
    script,
    `
const root = ${JSON.stringify(directory)};
const kind = ${JSON.stringify(kind)};
const names = Array.from({ length: 7 }, (_, n) => "law" + n);
if (Deno.args.includes("--list")) {
  console.log(names.join("\\n"));
} else {
  if (!Deno.args.includes("--fail-fast")) throw new Error("scheduler omitted fail-fast");
  const args = Object.fromEntries(Deno.args.map(arg => arg.split("=")));
  const shard = Number(args["--shard"]), shards = Number(args["--shards"]);
  const mode = args["--allocation-failures"];
  const start = Date.now() * 1e6;
  await Deno.writeTextFile(root + "/started-" + shard, "started");
  const exists = async path => { try { await Deno.stat(path); return true; } catch { return false; } };
  const until = Date.now() + 10000;
  while (["pass", "fail-with-descendant", "cancel"].includes(kind) && !(await Promise.all(Array.from({length: shards}, (_, n) => exists(root + "/started-" + n)))).every(Boolean)) {
    if (Date.now() > until) throw new Error("shards were serialized");
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  if (kind === "fail-with-descendant" || kind === "cancel") {
    if (shard === 1) {
      const child = new Deno.Command(Deno.execPath(), { args: ["eval", "Deno.addSignalListener('SIGTERM',()=>{}); setInterval(()=>{},1000)"], stdout: "null", stderr: "null" }).spawn();
      await Deno.writeTextFile(root + "/descendant", String(child.pid));
    }
    if (shard === 0 && kind === "fail-with-descendant") {
      while (!await exists(root + "/descendant")) await new Promise(resolve => setTimeout(resolve, 10));
      Deno.exit(23);
    }
    Deno.addSignalListener("SIGTERM", () => {});
    await new Promise(resolve => setTimeout(resolve, 60_000));
  }
  await new Promise(resolve => setTimeout(resolve, 40));
  const requested = Deno.args.filter(arg => arg.startsWith("--test=")).map(arg => arg.slice(7));
  const selected = names.filter((name, n) => n % shards === shard && (!requested.length || requested.includes(name)));
  for (const name of selected) {
    if (kind === "omitted" && name === "law0") continue;
    const row = {name, duration_ns: 1, status: kind === "skipped" ? "skipped" : "passed", leaks: kind === "leak" ? 1 : 0,
      logged_errors: 0, allocation_failures: kind === "wrong-mode" ? "sampled" : mode,
      sweeps: {full_sweeps: 0, sampled_sweeps: 0, discovered_allocations: 0, fault_runs: 0}};
    console.error("BLOT_NATIVE_TEST\\t" + JSON.stringify(row));
    if (kind === "duplicate" && name === "law0") console.error("BLOT_NATIVE_TEST\\t" + JSON.stringify(row));
  }
  if (kind !== "incomplete") console.error("BLOT_NATIVE_SHARD\\t" + JSON.stringify({shard, shards, selected: selected.length, start_ns: start, end_ns: Date.now() * 1e6}));
}
`,
  );
  const quote = (s: string) => "'" + s.replaceAll("'", "'\\''") + "'";
  await Deno.writeTextFile(
    binary,
    `#!/bin/sh\nexec ${quote(Deno.execPath())} run -A ${quote(script)} "$@"\n`,
  );
  await Deno.chmod(binary, 0o755);
  return {
    binary,
    directory,
    seconds: 30,
    async [Symbol.asyncDispose]() {
      await Deno.remove(directory, { recursive: true });
    },
  };
}

Deno.test("native scheduling overlaps 1, 2 and 4 workers with exact complete inventory coverage", async () => {
  for (const shards of [1, 2, 4]) {
    await using input = await fixture();
    const result = await runNativeTests({ ...input, shards });
    assert.equal(result.success, true);
    assert.equal(result.allocation_failures, "full");
    assert.equal(result.inventory.length, 7);
    assert.equal(result.peak_active_shards, shards);
    assert.equal(result.intervals.reduce((n, row) => n + row.selected, 0), 7);
    assert.equal(
      (await nativeExecutionArtifacts(input.directory)).length,
      1 + 2 * (shards + 1),
    );
  }
});

Deno.test("native scheduling refuses omissions duplicates skipped leaks wrong modes and unfinished shards", async () => {
  for (
    const kind of [
      "omitted",
      "duplicate",
      "skipped",
      "leak",
      "wrong-mode",
      "incomplete",
    ]
  ) {
    await using input = await fixture(kind);
    await assert.rejects(
      runNativeTests({ ...input, shards: 2 }),
      /Native results do not match|Native test did not pass|Missing or repeated native shard/,
    );
    const report = JSON.parse(
      await Deno.readTextFile(resolve(input.directory, "results.json")),
    );
    assert.equal(report.success, false, kind);
    await assert.rejects(nativeExecutionArtifacts(input.directory));
  }
});

async function stoppedDescendant(directory: string) {
  const pid = Number(await Deno.readTextFile(resolve(directory, "descendant")));
  try {
    process.kill(pid, 0);
    // Linux can retain killed children as zombies until the host reaps them.
    const status = await new Deno.Command("ps", {
      args: ["-o", "stat=", "-p", String(pid)],
    }).output();
    assert.match(new TextDecoder().decode(status.stdout).trim(), /^(?:Z.*)?$/);
  } catch (error) {
    if (
      !(error instanceof Deno.errors.NotFound) &&
      (error as NodeJS.ErrnoException).code !== "ESRCH"
    ) throw error;
  }
}

Deno.test("native failure and cancellation reap sibling process groups and their descendants", async () => {
  for (const kind of ["fail-with-descendant", "cancel"]) {
    await using input = await fixture(kind);
    const controller = new AbortController();
    const running = runNativeTests({
      ...input,
      shards: 2,
      signal: controller.signal,
    });
    const rejected = assert.rejects(running);
    if (kind === "cancel") {
      const until = performance.now() + 10_000;
      while (true) {
        try {
          await Deno.stat(resolve(input.directory, "descendant"));
          break;
        } catch (error) {
          if (!(error instanceof Deno.errors.NotFound)) throw error;
        }
        if (performance.now() > until) {
          throw new Error("native descendants did not start");
        }
        await new Promise((done) => setTimeout(done, 10));
      }
      controller.abort("cancelled");
    }
    await rejected;
    await stoppedDescendant(input.directory);
  }
});

Deno.test("native journal observes raw shard evidence and never accepts sampled results", async () => {
  await using input = await fixture();
  const report = await runNativeTests({ ...input, shards: 2 });
  const artifacts = await nativeExecutionArtifacts(input.directory);
  const journal = new NativeJournal(resolve(input.directory, "journal.json"));
  const phase = { ...report.phases[1], name: "native-run" };
  await journal.record("key", phase, artifacts);
  assert(await journal.reuse("native-run", "key"));
  await Deno.writeTextFile(report.phases[2].stderr, "truncated evidence");
  assert.equal(await journal.reuse("native-run", "key"), undefined);
  await using sampled = await fixture();
  await runNativeTests({ ...sampled, shards: 2, mode: "sampled" });
  await assert.rejects(nativeExecutionArtifacts(sampled.directory));
});

Deno.test("native interval accounting distinguishes serialization from overlapping work", () => {
  const a = { shard: 0, shards: 2, selected: 1, start_ns: 1, end_ns: 3 };
  const b = { ...a, shard: 1, start_ns: 3, end_ns: 5 };
  assert.equal(peakConcurrency([a, b]), 1);
  assert.equal(peakConcurrency([a, { ...b, start_ns: 2 }]), 2);
  assert.throws(() =>
    shardInterval("BLOT_NATIVE_SHARD\t" + JSON.stringify(a), 1, 2, 1)
  );
  assert.throws(() =>
    shardInterval(
      "BLOT_NATIVE_SHARD\t" + JSON.stringify({ ...a, end_ns: 0 }),
      0,
      2,
      1,
    )
  );
});

Deno.test("timing hints preserve every current test and decline unhelpful or invalid costs", () => {
  const names = ["slow0", "new1", "slow2", "new3", "slow4", "new5"];
  const costs = new Map([
    ["slow0", 100],
    ["slow2", 99],
    ["slow4", 98],
    ["new1", 1],
    ["new3", 1],
    ["new5", 1],
    ["deleted", 1e20],
  ]);
  const plan = nativeTestPartitions(names, 2, costs);
  assert(plan.weighted);
  assert.deepEqual(plan.groups.flat().sort(), [...names].sort());
  assert(Math.max(...plan.estimated_ns) < 297);
  const unknown = nativeTestPartitions([...names, "new6"], 2, costs);
  assert.deepEqual(unknown.groups.flat().sort(), [...names, "new6"].sort());
  const invalid = nativeTestPartitions(
    names,
    2,
    new Map([["slow0", NaN], ["slow2", -1], ["slow4", Infinity]]),
  );
  assert.equal(invalid.weighted, false);
  assert.deepEqual(invalid.groups.flat().sort(), [...names].sort());
  assert.equal(
    nativeTestPartitions(["only"], 4, new Map([["only", 100]])).weighted,
    false,
  );
});

Deno.test("native scheduling uses history only for placement and validates exact selected execution", async () => {
  await using input = await fixture();
  const prior = await runNativeTests({ ...input, shards: 2 });
  for (const phase of prior.phases) {
    if (phase.name === "inventory") continue;
    const text = await Deno.readTextFile(phase.stderr);
    await Deno.writeTextFile(
      phase.stderr,
      text.replace(/("name":"law[024]","duration_ns":)1/g, "$1100"),
    );
  }
  const measured = await runNativeTests({ ...input, shards: 2 });
  assert.equal(measured.scheduling, "prior-timings");
  assert.deepEqual(
    measured.partitions.flat().sort(),
    prior.inventory.slice().sort(),
  );
  assert.equal(
    measured.intervals.reduce(
      (total, interval) => total + interval.selected,
      0,
    ),
    7,
  );
  assert.equal(measured.peak_active_shards, 2);
  await Deno.writeTextFile(
    resolve(input.directory, "results.json"),
    "broken history",
  );
  const recovered = await runNativeTests({ ...input, shards: 2 });
  assert.equal(recovered.scheduling, "round-robin");
  assert.equal(recovered.success, true);
});
