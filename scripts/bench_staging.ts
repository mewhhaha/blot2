// deno run -A scripts/bench_staging.ts [COMPILER [OUTPUT]]
// Seven alternating ordinary/staged pairs; fresh parity and execution stay gates.
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
import { instantiateGuest } from "../compiler/guest.ts";
const root = fileURLToPath(new URL("..", import.meta.url));
if (Deno.args.length > 2) throw new Error("Expected [COMPILER [OUTPUT]]");
const out = resolve(Deno.args[1] ?? `${root}/build/bench/staging-current-cost`);
await Deno.mkdir(out, { recursive: true });
const executable = resolve(
  Deno.args[0] ?? `${root}/zig-native/zig-out/bin/blotc`,
);
const samples: Record<string, unknown>[] = [];
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) =>
    x.toString(16).padStart(2, "0")
  ).join("");
async function usage(pid: number) {
  let cpu = 0;
  for await (const task of Deno.readDir(`/proc/${pid}/task`)) {
    try {
      cpu += Number(
        (await Deno.readTextFile(`/proc/${pid}/task/${task.name}/schedstat`))
          .split(" ")[0],
      );
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  const status = await Deno.readTextFile(`/proc/${pid}/status`);
  return { cpu, rss: Number(status.match(/^VmHWM:\s+(\d+)/m)?.[1] ?? 0) };
}
const fixturePins: Record<string, string> = {};
for (const codegenTier of ["development", "optimized"] as const) {
  for (const archive of [false, true]) {
    for (let run = 0; run < 7; run++) {
      const order = [false, true];
      if (run % 2) order.reverse();
      for (const staged of order) {
        const variant = staged ? "staged" : "ordinary";
        const directory = `${out}/${codegenTier}-${archive}-${run}-${variant}`;
        await Deno.mkdir(directory, { recursive: true });
        const entry = `${directory}/main.blot`,
          producer = `${directory}/producer.blot`,
          bundle = `${directory}/producer.blotdep`;
        const entrySource = (seed: number) =>
          `import {generated, build} from "./producer"
const first = build ${seed}
entry const answer = func () => return do:
  let value = 100
  let left = ${staged ? "@code.emit generated" : "generated"}
  let right = ${staged ? "@code.emit first" : "first"}
  let again = ${staged ? "@code.emit first" : "first"}
  break #[value, left, right, again]
`;
        const library = (value: number, step: number) =>
          `opaque type Token = U32
const make = func () => return #Token ${value}
const read = func (value: Token) => return case value of
  #Token number => number
const generated = ${staged ? "@code.quote (read (make ()))" : "read (make ())"}
const build = func (value: U32) => return ${
            staged
              ? `@code.quote (@u32.add (@code.lift value) ${step})`
              : `@u32.add value ${step}`
          }
`;
        const revisions = [
          ["population", 40, 40, 2],
          ["noop", 40, 40, 2],
          ["literal_edit", 41, 40, 2],
          ["input_edit", 41, 41, 2],
          ["generator_body_edit", 41, 41, 3],
          ["revert", 40, 40, 2],
        ] as const;
        await Deno.writeTextFile(entry, entrySource(40));
        await Deno.writeTextFile(producer, library(40, 2));
        const options = {
          executable,
          entry,
          prelude: null,
          codegenTier,
          codegenWorkers: 1,
          cacheDirectory: false as const,
          dependencies: archive ? bundle : undefined,
        };
        let retained;
        let initialWasm: Uint8Array<ArrayBuffer> | undefined;
        try {
          for (const [phase, value, seed, step] of revisions) {
            const sources = {
              [entry]: entrySource(seed),
              [producer]: library(value, step),
            };
            for (const [path, text] of Object.entries(sources)) {
              await Deno.writeTextFile(path, text);
            }
            if (archive) {
              const packed = await new Deno.Command(executable, {
                args: ["dependencies", entry, bundle, "--prelude", "none"],
                stdout: "piped",
                stderr: "piped",
                env: { BLOT_CACHE_DIR: "" },
              }).output();
              assert(
                packed.success,
                new TextDecoder().decode(packed.stdout) +
                  new TextDecoder().decode(packed.stderr),
              );
            }
            retained ??= await createZigProjectCompiler(options);
            const before = await usage(retained.pid), start = performance.now();
            const result = await retained.build({ sources });
            const wall_ms = performance.now() - start,
              after = await usage(retained.pid);
            assert(result.success, JSON.stringify(result));
            if (phase === "population") initialWasm = result.bytes.slice();
            if (phase === "revert") assert.deepEqual(result.bytes, initialWasm);
            assert(
              after.cpu >= before.cpu,
              "Thread CPU accounting moved backwards",
            );
            const fresh = await createZigProjectCompiler(options);
            try {
              const expected = await fresh.build({ sources });
              assert(expected.success, JSON.stringify(expected));
              assert.deepEqual(result.bytes, expected.bytes);
            } finally {
              await fresh.dispose();
            }
            const guest = await instantiateGuest(result.bytes);
            try {
              assert.deepEqual(
                guest.call("answer", null),
                new Uint32Array([100, value, seed + step, seed + step]),
              );
            } finally {
              await guest.dispose();
            }
            const inputs = {
              entry: await hash(new TextEncoder().encode(sources[entry])),
              producer: await hash(new TextEncoder().encode(sources[producer])),
            };
            fixturePins[`${variant}/${phase}`] = JSON.stringify(inputs);
            samples.push({
              codegenTier,
              archive,
              run,
              variant,
              phase,
              cpu_ms: (after.cpu - before.cpu) / 1e6,
              wall_ms,
              peak_rss_kib: after.rss,
              wasm_sha256: await hash(result.bytes),
              stats: result.stats,
              inputs,
            });
          }
        } finally {
          await retained?.dispose();
        }
      }
    }
  }
}
const median = (xs: number[]) =>
  [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];
const summary = [];
for (const codegenTier of ["development", "optimized"]) {
  for (const archive of [false, true]) {
    for (
      const phase of [
        "population",
        "noop",
        "literal_edit",
        "input_edit",
        "generator_body_edit",
        "revert",
      ]
    ) {
      const row: Record<string, unknown> = { codegenTier, archive, phase };
      for (const variant of ["ordinary", "staged"]) {
        const rows = samples.filter((s) =>
          s.codegenTier === codegenTier && s.archive === archive &&
          s.phase === phase && s.variant === variant
        );
        row[variant] = {
          cpu_ms: median(rows.map((s) => s.cpu_ms as number)),
          wall_ms: median(rows.map((s) => s.wall_ms as number)),
          samples: rows.length,
        };
      }
      summary.push(row);
    }
  }
}
const cli = [];
for (const variant of ["ordinary", "staged"]) {
  const directory = `${out}/optimized-false-0-${variant}`;
  const result = await new Deno.Command(executable, {
    args: [
      "build",
      `${directory}/main.blot`,
      `${directory}/fresh-cli.wasm`,
      "--prelude",
      "none",
    ],
    stdout: "piped",
    stderr: "piped",
    env: { BLOT_CACHE_DIR: "" },
  }).output();
  assert(
    result.success,
    new TextDecoder().decode(result.stdout) +
      new TextDecoder().decode(result.stderr),
  );
  const records = new TextDecoder().decode(result.stdout).trim().split("\n")
    .map((line) => JSON.parse(line));
  const compiled = records.find((record) => record.kind === "compilation");
  assert(compiled.success && compiled.memory.live_bytes === 0);
  const wasm = await hash(await Deno.readFile(`${directory}/fresh-cli.wasm`));
  const population = samples.find((s) =>
    s.codegenTier === "optimized" && s.archive === false && s.run === 0 &&
    s.variant === variant && s.phase === "population"
  );
  assert.equal(wasm, population?.wasm_sha256);
  cli.push({
    variant,
    wasm_sha256: wasm,
    memory: compiled.memory,
    compilation: compiled,
  });
}
const report = {
  harness_sha256: await hash(await Deno.readFile(new URL(import.meta.url))),
  compiler_sha256: await hash(await Deno.readFile(executable)),
  fixturePins,
  summary,
  samples,
  cli,
  note:
    "Seven alternating ordinary/staged pairs per tier and source/archive mode; Linux live-thread schedstat child CPU; one codegen worker; persistence disabled; fresh parity and executed output checked per revision. Synthetic costs, not a general speed claim. Archive packing and process open excluded from build CPU/wall.",
};
await Deno.writeTextFile(
  `${out}/results.json`,
  JSON.stringify(report, null, 2) + "\n",
);
console.log(JSON.stringify({ report: `${out}/results.json`, summary }));
