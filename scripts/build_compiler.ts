import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const requiredVersion = "bend 2.0.21";
const upstreamCommit = "62e7825660327384473304f0001be1b97604eb2c";
const loaderFiles = {
  "main.ts": "34c69df407a8abff02752f26821ee2ff7c0a303e97a32b8b5e0082b142e63f59",
  "bend.ts": "8ac546e7b4de498973405a8e5ebf5589075814c15b80668db1eec9a2e90ef475",
  "comp.ts": "1cf3b5ffea86697656f8ef4d6c26040f16ac512fd92485d164f8a14425871bd0",
  "base.bend":
    "b8c2734d45ec6b4ce70fee70ff06ef35e08fce885af8852d8eb77dbff020e946",
};
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

const version = (await run("bend", ["version"])).trim();
if (version !== requiredVersion) {
  throw new Error(
    `Compiler bootstrap requires ${requiredVersion}; found ${version}`,
  );
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
    console.log((await run("bend", [
      "compiler/native_main.bend",
      "-o",
      resolve(staging, "blotc"),
    ])).trim());
    await Deno.rename(resolve(staging, "blotc"), new URL("blotc", output));
    console.log("Built generated/compiler/blotc (native CPU executable)");
  } finally {
    await Deno.remove(staging, { recursive: true });
  }
}
if (target === "native") Deno.exit(0);

// The binary Bend installation no longer ships its TypeScript module loader.
// Cache the matching upstream sources with integrity checks; this pure compiler
// module does not include any of Base's foreign IO implementations.
const backend = new URL("bend-2.0.21/", output);
await Deno.mkdir(backend, { recursive: true });
await Promise.all(
  Object.entries(loaderFiles).map(async ([name, expected]) => {
    const destination = new URL(name, backend);
    let bytes: Uint8Array<ArrayBuffer>;
    let downloaded = false;
    try {
      bytes = await Deno.readFile(destination);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      const response = await fetch(
        `https://raw.githubusercontent.com/bendlang/bend/${upstreamCommit}/bend2/${name}`,
      );
      if (!response.ok) {
        throw new Error(
          `Bend loader download failed: ${name} (${response.status})`,
        );
      }
      bytes = new Uint8Array(await response.arrayBuffer());
      downloaded = true;
    }
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const actual = Array.from(
      digest,
      (byte) => byte.toString(16).padStart(2, "0"),
    )
      .join("");
    if (actual !== expected) {
      throw new Error(
        `Bend loader integrity mismatch: ${destination.pathname}`,
      );
    }
    if (downloaded) await Deno.writeFile(destination, bytes);
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
    `// Generated from compiler/${module}.bend with ${requiredVersion}. Do not edit.\n${javascript}`,
  );
  console.log(`Built generated/compiler/${filename}.js`);
}
