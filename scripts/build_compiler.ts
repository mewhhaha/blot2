import { cp } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const requiredVersion = "bend 2.0.5";
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

const version = (await run("bend", ["--version"])).trim();
if (version !== requiredVersion) {
  throw new Error(
    `Compiler bootstrap requires ${requiredVersion}; found ${version}`,
  );
}

console.log((await run("bend", ["PROOF.bend"])).trim());
const output = new URL("../generated/compiler/", import.meta.url);
await Deno.mkdir(output, { recursive: true });
const installation = Deno.env.get("BEND_HOME") ||
  resolve(Deno.env.get("HOME") ?? ".", ".bend");
const backend = resolve(installation, "current/bend2");
if (target !== "js") {
  const original = await Deno.readTextFile(resolve(backend, "comp.ts"));
  const unsafeUnbox =
    "const z = r === undefined && (fl.hot.has(k) || fl.stat.has(k));";
  if (original.split(unsafeUnbox).length !== 2) {
    throw new Error(
      "Bend 2.0.5 native backend changed: review the owned-constructor extraction patch before building",
    );
  }
  // Bend 2.0.5 can miss sharing through generic constructors and read an RFC
  // header as record fields. Owned nodes must use ctr_take; borrowed nodes
  // retain term_peek. Patch an isolated build copy, never the installed Bend.
  const staging = await Deno.makeTempDir({
    dir: fileURLToPath(output),
    prefix: ".native-backend-",
  });
  try {
    for (const name of ["main.ts", "bend.ts", "base.bend"]) {
      await Deno.copyFile(resolve(backend, name), resolve(staging, name));
    }
    await Deno.writeTextFile(
      resolve(staging, "comp.ts"),
      original.replace(unsafeUnbox, "const z = r === undefined;"),
    );
    await cp(resolve(backend, "effs"), resolve(staging, "effs"), {
      recursive: true,
    });
    const loader = resolve(staging, "main.ts");
    const regression = "generated/compiler/native-backend-regression";
    console.log("Checking native Bend constructor ownership...");
    await run("bun", [
      loader,
      "compiler/native_backend_regression.bend",
      "-o",
      regression,
    ]);
    for (const threads of [1, 4]) {
      await run(`./${regression}`, ["--threads", String(threads)]);
    }
    console.log("Building native Bend compiler (owned-constructor fix)...");
    console.log((await run("bun", [
      loader,
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

const loader = pathToFileURL(resolve(backend, "main.ts"));
const entry = new URL("../compiler/main.bend", import.meta.url);

// Use Bend's published JS-module loader, not a second compiler implementation.
// Bun is also required by the installed Bend launcher. The emitted pure module
// runs in Deno; its host performs no Blot typing, const evaluation, or codegen.
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
  new URL("compiler.js", output),
  `// Generated from compiler/main.bend with ${requiredVersion}. Do not edit.\n${javascript}`,
);
console.log("Built generated/compiler/compiler.js");
