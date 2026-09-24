import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { optimizeNativeStringComparison } from "./native_string_compare.ts";

const environment = { BEND_NO_TELEMETRY: "1" };
const decoder = new TextDecoder();
const target = Deno.args[0] ?? "native";
if (Deno.args.length > 1 || !["native", "js", "all"].includes(target)) {
  throw new Error("Usage: scripts/build_compiler.ts [native|js|all]");
}

async function run(command: string, args: string[]) {
  const result = await new Deno.Command(command, {
    args,
    env: environment,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(
      `${command} failed (${result.code})\n${decoder.decode(result.stdout)}${
        decoder.decode(result.stderr)
      }`,
    );
  }
  return decoder.decode(result.stdout);
}

console.log((await run("bend", ["PROOF.bend"])).trim());
const output = new URL("../generated/compiler/", import.meta.url);
await Deno.mkdir(output, { recursive: true });
if (target !== "js") {
  const staging = await Deno.makeTempDir({
    dir: fileURLToPath(output),
    prefix: ".native-backend-",
  });
  try {
    const regression = "generated/compiler/native-backend-regression";
    console.log("Checking native Bend constructor ownership...");
    await run("bend", [
      "compiler/native_backend_regression.bend",
      "-o",
      regression,
    ]);
    for (const threads of [1, 4]) {
      await run(`./${regression}`, ["--threads", String(threads)]);
    }
    console.log("Building native Bend compiler...");
    const generatedC = resolve(staging, "blotc.c");
    console.log((await run("bend", [
      "compiler/native_main.bend",
      "-o",
      generatedC,
    ])).trim());
    const specialized = optimizeNativeStringComparison(
      await Deno.readTextFile(generatedC),
      await Deno.readTextFile(
        new URL("../compiler/model.bend", import.meta.url),
      ),
      await run("bend", ["version"]),
    );
    await Deno.writeTextFile(generatedC, specialized.source);
    await run("clang", [
      "-std=c11",
      "-O3",
      "-w",
      "-pthread",
      generatedC,
      "-lm",
      "-o",
      resolve(staging, "blotc"),
    ]);
    console.log("Enabled guarded native String comparison for Bend 2.0.24");
    await Deno.rename(resolve(staging, "blotc"), new URL("blotc", output));
    console.log("Built generated/compiler/blotc (native CPU executable)");
  } finally {
    await Deno.remove(staging, { recursive: true });
  }
}
if (target === "native") Deno.exit(0);

// The binary Bend installation no longer ships its TypeScript module loader.
// Cache sources from the installed release's tag; this pure compiler
// module does not include any of Base's foreign IO implementations.
const version = (await run("bend", ["version"])).trim();
const release = /^bend (\d+\.\d+\.\d+(?:-[\w.-]+)?)$/i.exec(version)?.[1];
if (!release) {
  throw new Error(`Cannot determine Bend loader release from: ${version}`);
}
const backend = new URL(`bend-${release}/`, output);
await Deno.mkdir(backend, { recursive: true });
await Promise.all(
  ["main.ts", "bend.ts", "comp.ts", "base.bend"].map(async (name) => {
    const destination = new URL(name, backend);
    try {
      await Deno.readFile(destination);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      const response = await fetch(
        `https://raw.githubusercontent.com/bendlang/bend/v${release}/bend2/${name}`,
      );
      if (!response.ok) {
        throw new Error(
          `Bend ${release} loader download failed: ${name} (${response.status})`,
        );
      }
      await Deno.writeFile(
        destination,
        new Uint8Array(await response.arrayBuffer()),
      );
    }
  }),
);
const loader = new URL("main.ts", backend);

// Use Bend's published JS-module loader, not a second compiler implementation.
// Bun runs the upstream TypeScript loader. The emitted pure module
// runs in Deno; its host performs no Blot typing, const evaluation, or codegen.
// The separate session module exposes pure cache planning to regression tests.
for (
  const [module, filename] of [["main", "compiler"], [
    "native_session",
    "native_session",
  ], [
    "native_output",
    "native_output",
  ]]
) {
  const entry = new URL(`../compiler/${module}.bend`, import.meta.url);
  const javascript = await run("bun", [
    "--eval",
    `const { load } = await import(process.argv[1]);
const result = await load(process.argv[2], {}, () => {
  throw new Error("Bend loader did not recognize the compiler entry");
});
process.stdout.write(result.source);`,
    loader.href,
    entry.href,
  ]);
  await Deno.writeTextFile(
    new URL(`${filename}.js`, output),
    `// Generated from compiler/${module}.bend with ${version}. Do not edit.\n${javascript}`,
  );
  console.log(`Built generated/compiler/${filename}.js`);
}
