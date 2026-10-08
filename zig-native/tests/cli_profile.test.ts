// `--profile` opts in to detailed backend clocks; deterministic work counters
// are always reported. Unprofiled stats carry no zero-filled placeholders.
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const source = `const twice = fn x => x + x
const quad = fn x => twice (twice x)
entry const answer = fn (x: U32) -> U32 => quad x + quad 1
`;
const counterNames = [
  "inference_regions",
  "region_scopes",
  "max_region_scopes",
  "call_collections_closed",
  "call_collections_unresolved",
  "call_memo_hits",
  "solver_passes",
  "solver_constraint_visits",
  "occurs_steps",
];

interface Backend {
  prepare_us: number;
  work?: { regions: unknown[]; inference_us: number; lookup_us: number };
}
async function build(command: string, ...extra: string[]) {
  const directory = await Deno.makeTempDir({ prefix: "blot-profile-" });
  try {
    const input = `${directory}/main.blot`;
    const output = `${directory}/main.wasm`;
    await Deno.writeTextFile(input, source);
    const result = await new Deno.Command(executable, {
      args: [command, input, output, "--prelude", prelude, ...extra],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(result.stdout);
    return {
      success: result.success,
      text,
      metrics: text.trim().split("\n").map((line) => JSON.parse(line)).find((
        record,
      ) => record.kind === "compilation"),
      wasm: result.success ? await Deno.readFile(output) : new Uint8Array(),
    };
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

for (const command of ["build", "build-project"]) {
  Deno.test(`${command} omits detailed timing unless --profile is given`, async () => {
    const plain = await build(command);
    assert(plain.success, plain.text);
    const timing: Backend = plain.metrics.backend_timing;
    assert(timing.prepare_us >= 0);
    assert.equal(timing.work, undefined);
    assert(!plain.text.includes('"regions"'), "placeholder regions printed");
    for (const name of counterNames) {
      assert(
        Number.isSafeInteger(plain.metrics.work_counters[name]),
        `missing counter ${name}`,
      );
    }
    assert(plain.metrics.work_counters.inference_regions > 0);
    assert(plain.metrics.work_counters.solver_passes > 0);

    const profiled = await build(command, "--profile");
    assert(profiled.success, profiled.text);
    const detail: Backend = profiled.metrics.backend_timing;
    assert(Array.isArray(detail.work?.regions));
    assert(Number.isSafeInteger(detail.work?.inference_us));
    assert(Number.isSafeInteger(detail.work?.lookup_us));
    // Profiling observes; it neither changes code nor the deterministic work.
    assert.deepEqual(profiled.wasm, plain.wasm);
    assert.deepEqual(
      profiled.metrics.work_counters,
      plain.metrics.work_counters,
    );
  });
}

Deno.test("--profile is rejected where it has no effect", async () => {
  for (const command of ["check-project", "parse-project"]) {
    const directory = await Deno.makeTempDir({ prefix: "blot-profile-" });
    try {
      const input = `${directory}/main.blot`;
      await Deno.writeTextFile(input, source);
      const result = await new Deno.Command(executable, {
        args: [command, input, "--prelude", prelude, "--profile"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(!result.success, `${command} accepted --profile`);
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  }
});

Deno.test("project API reports counters always and clocks only when profiled", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-profile-" });
  const entry = `${directory}/main.blot`;
  await Deno.writeTextFile(entry, source);
  const options = { executable, entry, prelude };
  const plain = await createZigProjectCompiler(options);
  const profiled = await createZigProjectCompiler({
    ...options,
    profileBackend: true,
  });
  try {
    const left = await plain.build();
    const right = await profiled.build();
    assert(left.success && right.success);
    const counters = left.stats.workCounters as Record<string, number>;
    for (const name of counterNames) {
      assert(Number.isSafeInteger(counters[name]), `missing counter ${name}`);
    }
    assert(counters.inference_regions > 0);
    assert.deepEqual(right.stats.workCounters, left.stats.workCounters);
    assert.equal((left.stats.backendTiming as unknown as Backend).work, undefined);
    assert(
      Array.isArray((right.stats.backendTiming as unknown as Backend).work?.regions),
    );
    assert.deepEqual(left.bytes, right.bytes);
  } finally {
    await plain.dispose();
    await profiled.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
