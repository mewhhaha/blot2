// `--profile` opts in to whole-build phase clocks. Unprofiled stats carry no
// zero-filled placeholders.
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler/zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const source = `const twice = func x => return x + x
const quad = func x => return twice (twice x)
entry const answer = func (x: U32) : U32 => return quad x + quad 1
`;
interface Backend {
  prepare_us: number;
  work?: { regions: unknown[]; inference_us: number; lookup_us: number };
}
interface Phases {
  total_us?: number;
  peak_rss_kib?: number;
  phases?: Record<
    string,
    {
      us: number;
      requested_bytes: number;
      allocations: number;
      rss_growth_kib: number;
    }
  >;
}
/** Frontend and backend phases a profiled project build always passes. */
const phaseNames = ["load", "lex", "parse", "check", "lower", "backend"];
function assertPhases(record: Phases) {
  assert(Number.isSafeInteger(record.total_us), JSON.stringify(record));
  let sum = 0;
  let growth = 0;
  for (const [name, phase] of Object.entries(record.phases ?? {})) {
    for (const value of Object.values(phase)) {
      assert(Number.isSafeInteger(value) && value >= 0, name);
    }
    sum += phase.us;
    growth += phase.rss_growth_kib;
  }
  for (const name of phaseNames) assert(record.phases?.[name], name);
  const { check, backend } = record.phases!;
  assert(check.us > 0 && backend.us > 0);
  // Checking and emission allocate; requests are charged where they happen.
  assert(check.allocations > 0 && check.requested_bytes > 0);
  assert(backend.allocations > 0 && backend.requested_bytes > 0);
  assert(Number.isSafeInteger(record.peak_rss_kib));
  assert(growth <= record.peak_rss_kib!);
  if (Deno.build.os === "linux") assert(record.peak_rss_kib! > 0);
  // Exclusive phases partition the clocked interval (each rounds down).
  const count = Object.keys(record.phases!).length;
  assert(sum <= record.total_us! && record.total_us! - sum <= count);
}
// Metadata counters include the canonical path, and temporary names vary in
// length, so compared builds use equal-length sibling directories.
async function build(command: string, label: string, ...extra: string[]) {
  const directory = `${root}/${label}`;
  await Deno.mkdir(directory);
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

const root = await Deno.makeTempDir({ prefix: "blot-profile-" });
for (const command of ["build", "build-project"]) {
  Deno.test(`${command} omits detailed timing unless --profile is given`, async () => {
    const plain = await build(command, `${command}-a`);
    assert(plain.success, plain.text);
    const timing: Backend = plain.metrics.backend_timing;
    assert(timing.prepare_us >= 0);
    assert.equal(timing.work, undefined);
    assert(!plain.text.includes('"regions"'), "placeholder regions printed");
    assert.deepEqual(plain.metrics.phase_profile, {});

    const profiled = await build(command, `${command}-b`, "--profile");
    assert(profiled.success, profiled.text);
    assertPhases(profiled.metrics.phase_profile);
    // Profiling observes; it does not change code.
    assert.deepEqual(profiled.wasm, plain.wasm);
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

Deno.test("project API reports clocks only when profiled", async () => {
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
    assert.equal((left.stats.backendTiming as unknown as Backend).work, undefined);
    assert.deepEqual(left.stats.phaseProfile, {});
    assertPhases(right.stats.phaseProfile as unknown as Phases);
    assert.deepEqual(left.bytes, right.bytes);
  } finally {
    await plain.dispose();
    await profiled.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("profile scratch directory is removed", async () => {
  await Deno.remove(root, { recursive: true });
});
