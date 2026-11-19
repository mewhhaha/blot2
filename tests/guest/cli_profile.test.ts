// `--profile` opts in to whole-build phase clocks. Unprofiled stats carry no
// zero-filled placeholders.
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const source = `const twice = func x => return x + x
const quad = func x => return twice (twice x)
entry const answer = func (x: U32) : U32 => return quad x + quad 1
`;
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
    assert.deepEqual(plain.metrics.phase_profile ?? {}, {});

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
    assert.deepEqual(left.stats.phaseProfile, {});
    assertPhases(right.stats.phaseProfile as unknown as Phases);
    assert.deepEqual(left.bytes, right.bytes);
  } finally {
    await plain.dispose();
    await profiled.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("independent field requirements take linear candidate scans", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const count = 128;
  const lines = Array.from(
    { length: count },
    (_, i) => `func read${i} x => return x.value`,
  );
  lines.push(
    `entry func answer (x: U32): U32 => return read0 {value: read${
      count - 1
    } {value: x}}`,
  );
  try {
    await Deno.writeTextFile(entry, lines.join("\n"));
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      profileBackend: true,
      frontendWorkers: 1,
    });
    try {
      const result = await compiler.build();
      if (!result.success) assert.fail(JSON.stringify(result.diagnostics));
      const { checking } = result.stats.phaseProfile as {
        checking: Record<string, number>;
      };
      assert(checking.candidates >= count);
      assert(checking.candidate_scans <= 8 * count, JSON.stringify(checking));
      const { instance } = await WebAssembly.instantiate(result.bytes);
      assert.equal((instance.exports.answer as (x: number) => number)(42), 42);
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("ownership analysis handles shared tuple and record subtrees", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const lines = [];
  for (
    const [name, seed, layers] of [
      ["pair", "(x, x)", 10],
      ["mixed", "(x, 0, x)", 10],
      ["diamond", "((x, 0), (0, x))", 8],
      ["record", "{left: x, middle: 0, right: x}", 10],
    ] as const
  ) {
    lines.push(`func ${name}0 x => return ${seed}`);
    for (let i = 1; i < layers; i++) {
      const previous = name + (i - 1);
      lines.push(`func ${name}${i} x => return ${previous} (${previous} x)`);
    }
  }
  lines.push(
    "entry func answer (x: U32): U32 => return do:",
    "  let (_, _, (_, _, (_, _, (_, _, right)))) = mixed2 x",
    "  let ((left, _), _) = diamond0 right",
    "  break (record0 left).right",
  );
  try {
    await Deno.writeTextFile(entry, lines.join("\n"));
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
    });
    try {
      const result = await compiler.build({
        signal: AbortSignal.timeout(5000),
      });
      if (!result.success) assert.fail(JSON.stringify(result.diagnostics));
      const { instance } = await WebAssembly.instantiate(result.bytes);
      assert.equal((instance.exports.answer as (x: number) => number)(42), 42);
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("profile scratch directory is removed", async () => {
  await Deno.remove(root, { recursive: true });
});
