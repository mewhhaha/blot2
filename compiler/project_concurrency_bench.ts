// Run with taskset so the host and every native worker inherit the same affinity.
import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { createNativeCompiler } from "./native.ts";
import type { loadSourceProject, SourceInput } from "./source_project.ts";

const [
  report,
  projects = ".",
  shape = "modules",
  repetitions = "5",
  workerCount = "8",
] = Deno.args;
const samples = Number(repetitions);
const threads = Number(workerCount);
ok(
  report && Deno.args.length <= 5,
  "Usage: project_concurrency_bench.ts report projects modules|wide_modules samples threads",
);
ok(["modules", "wide_modules"].includes(shape));
ok(Number.isInteger(samples) && samples >= 1 && samples <= 100);
ok(Number.isInteger(threads) && threads >= 1 && threads <= 8);
const affinity = /^Cpus_allowed_list:\s+(.+)$/m.exec(
  await Deno.readTextFile("/proc/self/status"),
)![1];
const roots = projects.split(",").map((root) => resolve(root));
const sources = new Map<string, string>();
sources.set(
  "main.blot",
  Array.from(
    { length: 8 },
    (_, index) => `import * as part${index} from "./part${index}"`,
  ).join("\n") +
    "\nexport fn answer value => " +
    Array.from({ length: 8 }, (_, index) => `part${index}.f0 value`).join(
      " + ",
    ) +
    "\n",
);
for (let index = 0; index < 8; index++) {
  sources.set(
    `part${index}.blot`,
    shape === "modules"
      ? `export fn f0 value => do:\n${
        Array.from(
          { length: 256 },
          (_, step) =>
            `  let v${step} = @u32.add ${step ? `v${step - 1}` : "value"} 1`,
        ).join("\n")
      }\n  return v255\n`
      : Array.from(
        { length: 16 },
        (_, fn) =>
          `export fn f${fn} value => ${
            Array.from({ length: 96 }, () => "value").join(" + ")
          }\n`,
      ).join(""),
  );
}
const variants = [];
for (const root of roots) {
  const executable = resolve(root, "generated/compiler/blotc");
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", await Deno.readFile(executable)),
  );
  variants.push({
    root,
    executable,
    executable_sha256: Array.from(
      digest,
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join(""),
  });
}
const rows = [];
let expected: unknown;
for (let sample = 0; sample < samples; sample++) {
  for (const variant of sample % 2 ? variants.toReversed() : variants) {
    const nativeModule = await import(
      pathToFileURL(resolve(variant.root, "compiler/native.ts")).href
    ) as { createNativeCompiler: typeof createNativeCompiler };
    const projectModule = await import(
      pathToFileURL(resolve(variant.root, "compiler/source_project.ts")).href
    ) as { loadSourceProject: typeof loadSourceProject };
    const input: SourceInput = await projectModule.loadSourceProject(
      new URL("file:///blot-concurrency/main.blot"),
      {
        readSource(url) {
          const source = sources.get(url.pathname.split("/").at(-1)!);
          if (source === undefined) {
            throw new Error(`Missing benchmark module: ${url}`);
          }
          return Promise.resolve(source);
        },
      },
    );
    const compiler = await nativeModule.createNativeCompiler({
      threads,
      executable: variant.executable,
    });
    try {
      for (let warmup = 0; warmup < 2; warmup++) await compiler.compile(input);
      const start = performance.now();
      const artifact = await compiler.compile(input);
      const elapsed_ms = performance.now() - start;
      if (expected === undefined) expected = artifact;
      else equal(artifact, expected);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      equal(
        (instance.exports.answer as CallableFunction)(1),
        shape === "modules" ? 2056 : 768,
      );
      rows.push({ root: variant.root, sample, elapsed_ms });
      console.error(
        `${shape} ${variant.root} sample ${sample + 1}: ${
          elapsed_ms.toFixed(2)
        } ms`,
      );
    } finally {
      await compiler.dispose();
    }
  }
}
await Deno.mkdir(resolve(report, ".."), { recursive: true });
await Deno.writeTextFile(
  report,
  JSON.stringify(
    {
      shape,
      threads,
      affinity,
      samples,
      variants,
      artifact_parity: true,
      rows,
    },
    null,
    2,
  ) + "\n",
);
