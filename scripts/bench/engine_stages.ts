// Pinned compiler and tracing controls on actual Ink and generated Gdev sources.
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  createZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createSampledCompiler } from "./engine_sampling.ts";
const { values } = parseArgs({
  options: {
    world: { type: "boolean", default: false },
    sample: { type: "boolean", default: false },
    repetitions: { type: "string", default: "3" },
    "timeout-ms": { type: "string", default: "5000" },
    "baseline-gdev": {
      type: "string",
      default: "7733add6f89cf03deb62e1474dfaf13ef46de375",
    },
    "baseline-ink": {
      type: "string",
      default: "d520a903a13479455a4380680f64ce590e8d58c5",
    },
    compiler: {
      type: "string",
      default: "zig-native/zig-out-native-dev/bin/blotc",
    },
    baseline: { type: "string" },
    output: { type: "string", default: "build/bench/engine-stages" },
  },
});
const repo = resolve(new URL("../..", import.meta.url).pathname);
const root = resolve(repo, "../gdev");
const output = resolve(values.output!);
await Deno.mkdir(output, { recursive: true });
const settings =
  JSON.parse(await Deno.readTextFile(`${root}/pen.json`)).compiler.settings;
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
let versions = [
  {
    name: "baseline",
    executable: resolve(
      values.baseline ?? "zig-native/zig-out-engine-baseline/bin/blotc",
    ),
    trace: false,
  },
  { name: "candidate", executable: resolve(values.compiler!), trace: false },
  { name: "traced", executable: resolve(values.compiler!), trace: true },
];
const fields = "xx xy xz xw yx yy yz yw zx zy zz zw wx wy wz ww".split(" ");
const lines = [
  'import * as transform from "ink/transform"',
  'import * as math from "ink/math"',
  "const leaf = func (rows: GrowArray transform.Pose3) -> (at: U32) => return transform.matrix rows[at]",
];
let previous = "leaf";
for (let depth = 1; depth <= 6; depth++) {
  const next = `layer_${depth}`;
  lines.push(
    `const ${next} = func (rows: GrowArray transform.Pose3) -> (at: U32) => return do:`,
    `  let left = ${previous} rows at`,
    `  let right = ${previous} rows at`,
    `  return $math.Mat4 { ${
      fields.map((name) => `${name}: @f32.add left.${name} right.${name}`).join(
        ", ",
      )
    } }`,
  );
  previous = next;
}
lines.push(
  "entry const answer = func (input: F32): F32 => return do:",
  "  let pose = $transform.Pose3 {position: math.zero3, rotation: math.identity_quat, scale: math.vec3 input 1.0 1.0}",
  "  let rows: GrowArray transform.Pose3 = #[pose]",
  `  let result = ${previous} rows 0`,
  "  return result.xx",
);
let probes = [
  {
    name: "matrix6",
    source: lines.join("\n") + "\n",
    native: false,
    expected: 2624,
  },
  {
    name: "render-producer",
    source:
      'import * as render from "pen/protocol_render"\nentry const answer = func (input: U32): U32 => return do:\n  let marker: GrowArray U32 = #[input]\n  return marker[0]\n',
    native: true,
    expected: 41,
  },
];
const repetitions = Number(values.repetitions);
const timeoutMs = Number(values["timeout-ms"]);
if (!Number.isInteger(repetitions) || repetitions < 1 || repetitions > 9) {
  throw new Error("--repetitions must be 1..9");
}
if (!Number.isInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 30000) {
  throw new Error("--timeout-ms must be 100..30000");
}
if (values.sample) {
  if (!values.world || repetitions !== 1 || values.baseline !== undefined) {
    throw new Error(
      "--sample requires --world --repetitions 1 and no --baseline",
    );
  }
  if (timeoutMs > 10000) throw new Error("--sample timeout must be <=10000 ms");
  versions = versions.filter((version) => version.name === "candidate");
}
const worldBaseline: Record<string, string> = {};
const worldPins: Record<string, { baseline?: string; candidate: string }> = {};
if (values.world) {
  if (!values.sample) {
    versions = versions.slice(0, 2);
    if (values.baseline === undefined) {
      versions[0].executable = versions[1].executable;
    }
  }
  probes = [{
    name: "world-producer",
    source:
      'import * as world from "game/world_storage"\nentry const answer = func (input: U32): U32 => return do:\n  let marker: GrowArray U32 = #[input]\n  return marker[0]\n',
    native: true,
    expected: 41,
  }];
  for (
    const [project, ref, paths] of [
      ["gdev", values["baseline-gdev"]!, [
        "src/world_storage.blot",
        "tests/minor_support/owned.blot",
        "tests/minor_support/game.blot",
      ]],
      ["ink", values["baseline-ink"]!, ["lib/pen/host.blot"]],
    ] as const
  ) {
    for (const path of paths) {
      const absolute = resolve(repo, "../", project, path);
      if (values.sample) {
        worldPins[`${project}/${path}`] = {
          candidate: await hash(await Deno.readFile(absolute)),
        };
        continue;
      }
      const result = await new Deno.Command("git", {
        cwd: resolve(repo, "../", project),
        args: ["show", `${ref}:${path}`],
        stdout: "piped",
        stderr: "piped",
      }).output();
      if (!result.success) {
        throw new Error(new TextDecoder().decode(result.stderr));
      }
      worldBaseline[absolute] = new TextDecoder().decode(result.stdout);
      worldPins[`${project}/${path}`] = {
        baseline: await hash(result.stdout),
        candidate: await hash(await Deno.readFile(absolute)),
      };
    }
  }
}
if (values.world && values.baseline !== undefined) {
  for (const [path, pins] of Object.entries(worldPins)) {
    if (pins.baseline !== pins.candidate) {
      throw new Error(
        `Compiler comparison requires unchanged world source: ${path}`,
      );
    }
  }
}
const samples = [];
for (let repetition = 0; repetition < repetitions; repetition++) {
  for (const probe of probes) {
    const entry = resolve(output, `${probe.name}.blot`);
    await Deno.writeTextFile(entry, probe.source);
    for (let at = 0; at < versions.length; at++) {
      const version = versions[(at + repetition) % versions.length];
      const options: ZigProjectCompilerOptions = {
        executable: version.executable,
        entry,
        prelude: resolve(repo, "std/prelude.blot"),
        stdRoot: resolve(repo, "std"),
        imports: { "ink/": resolve(repo, "../ink/lib") },
        profileBackend: true,
        cacheDirectory: false,
        codegenWorkers: 1,
        startupTimeoutMs: timeoutMs,
      };
      if (version.trace || values.world) options.profileTrace = true;
      if (probe.native) {
        options.imports = Object.fromEntries(
          Object.entries(settings.imports).map((
            [name, path],
          ) => [name, resolve(root, path as string)]),
        );
        options.nativeAssets = {
          roots: settings.nativeAssets.roots.map((path: string) =>
            resolve(root, path)
          ),
          imports: settings.nativeAssets.imports.map((
            item: Record<string, string>,
          ) => ({
            ...item,
            module: resolve(root, item.module),
            path: resolve(root, item.path),
          })),
        };
        options.storage = settings.storage;
        options.inferenceBudget = settings.inferenceBudget;
      }
      let sampling:
        | Awaited<ReturnType<typeof createSampledCompiler>>
        | undefined;
      if (values.sample) {
        await Deno.writeTextFile(
          resolve(output, "sampling.json"),
          JSON.stringify(
            {
              diagnostic: "CPU attribution only; no latency comparison",
              compilerSha256: await hash(
                await Deno.readFile(version.executable),
              ),
              sourceSha256: await hash(new TextEncoder().encode(probe.source)),
              worldPins,
              options,
              timeoutMs,
              summarize: [
                "python3",
                "scripts/bench/summarize_stacks.py",
                output,
              ],
            },
            null,
            2,
          ) + "\n",
        );
        sampling = await createSampledCompiler(options, output, repo);
      }
      const compiler = sampling?.compiler ??
        await createZigProjectCompiler(options);
      let sample;
      try {
        const start = performance.now();
        let sources: Record<string, string> | undefined;
        if (values.world && version.name === "baseline") {
          sources = worldBaseline;
        }
        const buildOptions = {
          sources,
          signal: AbortSignal.timeout(timeoutMs),
        };
        let result;
        if (sampling) result = await sampling.build(buildOptions);
        else result = await compiler.build(buildOptions);
        const buildMs = performance.now() - start;
        if (!result.success) {
          throw new Error(JSON.stringify(result.diagnostics));
        }
        const guest = await instantiateGuest(result.bytes);
        try {
          if (guest.call("answer", 41) !== probe.expected) {
            throw new Error("Incorrect actual-source result");
          }
        } finally {
          guest.dispose();
        }
        sample = {
          probe: probe.name,
          version: version.name,
          repetition,
          buildMs,
          compilerSha256: await hash(await Deno.readFile(version.executable)),
          sourceSha256: await hash(new TextEncoder().encode(probe.source)),
          wasmBytes: result.bytes.length,
          wasmSha256: await hash(result.bytes),
          stats: result.stats,
          progress: compiler.profileProgress,
        };
      } finally {
        if (sampling) await sampling.dispose();
        else await compiler.dispose();
      }
      sample.progress = compiler.profileProgress;
      samples.push(sample);
      await Deno.writeTextFile(
        resolve(output, "partial.json"),
        JSON.stringify(
          { worldPins, repetitions, timeoutMs, samples },
          null,
          2,
        ) + "\n",
      );
      console.log(
        JSON.stringify({
          probe: sample.probe,
          version: sample.version,
          buildMs: sample.buildMs,
          wasmBytes: sample.wasmBytes,
        }),
      );
    }
  }
}
let toolchain =
  "Zig 0.17.0 safe/noLLVM; fresh sessions; cache disabled; rotated repetitions";
if (values.sample) {
  toolchain = "Single candidate; gdb diagnostic; cache disabled";
}
await Deno.writeTextFile(
  resolve(output, "result.json"),
  JSON.stringify(
    {
      toolchain,
      ...(values.sample && {
        sampling: {
          diagnostic: "CPU attribution only; no latency comparison",
          summarize: `python3 scripts/bench/summarize_stacks.py ${output}`,
        },
      }),
      worldPins,
      repetitions,
      timeoutMs,
      producerExecutionQualified: !values.world,
      samples,
    },
    null,
    2,
  ) + "\n",
);
