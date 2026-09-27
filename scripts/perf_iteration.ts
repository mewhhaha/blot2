// One fresh process executes gdev's real cold / unchanged / body-edit path.
// Run through perf_iteration.py, which creates the isolated project/import map.
import assert from "node:assert/strict";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { join } from "node:path";
import { resetTrace, trace } from "./perf_iteration_trace.ts";

const [project, profileOutput] = Deno.args;
assert.ok(project, "isolated gdev project is required");
const uri = (file: string) => pathToFileURL(join(project, file)).href;
const { createBlotCompiler } = await import(uri("blot_runtime.ts"));
const editFile = join(project, "src/daylight.blot");
const original = await Deno.readTextFile(editFile);
const before = "ambient: [0.055 + 0.24 * day + 0.08 * twilight,";
const after = "ambient: [0.155 + 0.24 * day + 0.08 * twilight,";
assert.equal(original.split(before).length, 2, "edit must match exactly once");
const edited = original.replace(before, after);

const hash = async (bytes: Uint8Array) => {
  const result = await crypto.subtle.digest("SHA-256", bytes.slice());
  return Array.from(
    new Uint8Array(result),
    (n) => n.toString(16).padStart(2, "0"),
  )
    .join("");
};
const textHash = (text: string) => hash(new TextEncoder().encode(text));

let inspector: import("node:inspector").Session | undefined;
async function post(method: string) {
  return await new Promise<Record<string, unknown>>((resolve, reject) =>
    inspector!.post(
      method,
      {},
      (error, response) =>
        error
          ? reject(error)
          : resolve((response ?? {}) as Record<string, unknown>),
    )
  );
}
if (profileOutput) {
  const { Session } = await import("node:inspector");
  inspector = new Session();
  inspector.connect();
  await post("Profiler.enable");
}

resetTrace();
let start = performance.now();
let cpu = process.cpuUsage();
const compiler = await createBlotCompiler({
  compilerBackend: "javascript",
  entry: join(project, "src/main.blot"),
  packages: join(project, "packages"),
});
const artifacts: { bytes: Uint8Array; catalog: unknown }[] = [];
const keys: string[] = [];
try {
  for (
    const phase of profileOutput ? ["cold"] : ["cold", "unchanged", "edit"]
  ) {
    if (phase === "edit") await Deno.writeTextFile(editFile, edited);
    if (phase !== "cold") {
      resetTrace();
      start = performance.now();
      cpu = process.cpuUsage();
    }
    if (inspector) await post("Profiler.start");
    const artifact = await compiler.artifact();
    const readyEpoch = Date.now();
    const elapsed = performance.now() - start;
    const used = process.cpuUsage(cpu);
    const maxRss = process.resourceUsage().maxRSS;
    if (inspector) {
      const { profile } = await post("Profiler.stop");
      await Deno.writeTextFile(profileOutput, JSON.stringify(profile));
    }
    assert.ok(
      trace.project,
      "the real project loader must run on every request",
    );
    const loaded = trace.project;
    const key = JSON.stringify([
      loaded.entry,
      loaded.modules.map((
        { name, filename, source },
      ) => [name, filename, source]),
    ]);
    keys.push(key);
    assert.equal(trace.compiles, phase === "unchanged" ? 0 : 1);
    if (phase === "unchanged") {
      assert.equal(key, keys[0]);
      assert.equal(artifact.bytes, artifacts[0].bytes);
    } else if (phase === "edit") {
      assert.notEqual(key, keys[0]);
      assert.notEqual(artifact.bytes, artifacts[0].bytes);
    }
    artifacts.push(artifact);
    const sourceHash = await textHash(JSON.stringify(
      loaded.modules.map(({ name, source }) => [name, source]),
    ));
    console.log(JSON.stringify({
      event: "measurement",
      phase,
      profiled: !!profileOutput,
      request_ms: elapsed,
      ready_epoch_ms: readyEpoch,
      project_ms: trace.project_ms,
      setup_ms: trace.setup_ms,
      compile_ms: trace.compile_ms,
      compile_calls: trace.compiles,
      process_cpu_ms: (used.user + used.system) / 1000,
      process_peak_rss_kib_so_far: maxRss,
      modules: loaded.modules.length,
      source_sha256: sourceHash,
      wasm_bytes: artifact.bytes.length,
      wasm_sha256: await hash(artifact.bytes),
      runtime: Deno.version,
    }));
  }

  // Guest execution is outside every compile timing and needs no renderer/GPU.
  const { Operation, startProgram } = await import(uri("program_runtime.ts"));
  const { encodeFrame, decodeFrame } = await import(uri("boundary.ts"));
  for (const index of profileOutput ? [0] : [0, 2]) {
    const artifact = artifacts[index];
    const program = await startProgram(artifact.bytes);
    try {
      const initial = await program.request(Operation.create);
      assert.ok(initial.length > 100);
      program.accept();
      const output = await program.request(
        Operation.frame,
        encodeFrame(
          {
            timestamp: 0,
            viewport: { width: 960n, height: 640n },
            events: [],
          },
          1 / 60,
          new Float32Array(),
        ),
      );
      const frame = decodeFrame(output, program.schema, artifact.catalog);
      assert.equal(frame.state.length, 0);
      const ambient = frame.render.ambient.x;
      assert.ok(
        Math.abs(ambient - (index === 0 ? 0.295 : 0.395)) < 0.00001,
        `unexpected ambient: ${ambient}`,
      );
      assert.ok(
        frame.render.draws.length > 0 && frame.render.solids.length > 0,
      );
      program.accept();
      console.log(JSON.stringify({
        event: "behavior",
        phase: index === 0 ? "cold" : "edit",
        schema: program.schema,
        ambient,
        draws: frame.render.draws.length,
        solids: frame.render.solids.length,
        frame_sha256: await hash(
          new Uint8Array(output.buffer, output.byteOffset, output.byteLength),
        ),
      }));
    } finally {
      await program.close();
    }
  }
} finally {
  await compiler.dispose();
  inspector?.disconnect();
  await Deno.writeTextFile(editFile, original);
}
