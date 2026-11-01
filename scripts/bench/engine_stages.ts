// Pinned compiler and tracing controls on actual Ink and generated Gdev sources.
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  createZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const { values } = parseArgs({
  options: {
    compiler: {
      type: "string",
      default: "zig-native/zig-out-native-dev/bin/blotc",
    },
    baseline: {
      type: "string",
      default: "zig-native/zig-out-engine-baseline/bin/blotc",
    },
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
const versions = [
  { name: "baseline", executable: resolve(values.baseline!), trace: false },
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
const probes = [
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
const samples = [];
for (let repetition = 0; repetition < 3; repetition++) {
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
        startupTimeoutMs: 5000,
      };
      if (version.trace) options.profileTrace = true;
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
      const compiler = await createZigProjectCompiler(options);
      let sample;
      try {
        const start = performance.now();
        const result = await compiler.build({
          signal: AbortSignal.timeout(5000),
        });
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
        await compiler.dispose();
      }
      sample.progress = compiler.profileProgress;
      samples.push(sample);
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
await Deno.writeTextFile(
  resolve(output, "result.json"),
  JSON.stringify(
    {
      toolchain:
        "Zig 0.17.0 safe/noLLVM; fresh sessions; cache disabled; three rotated repetitions",
      samples,
    },
    null,
    2,
  ) + "\n",
);
