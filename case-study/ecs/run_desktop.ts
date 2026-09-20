const root = new URL("../../", import.meta.url);
const temporaryLibraryDirectory = await provideLibxdoSoname();
const environment = { ...Deno.env.toObject() };
// Deno 2.9.6 Desktop does not forward script arguments into the raw runtime.
for (const argument of Deno.args) {
  const option = /^--(frames|source|save|capture)=(.+)$/.exec(argument);
  if (!option) {
    throw new Error(
      `Unknown option ${argument}; use --frames=, --source=, --save=, or --capture=`,
    );
  }
  environment[`BLOT_ECS_${option[1].toUpperCase()}`] = option[2];
}
if (temporaryLibraryDirectory) {
  environment.LD_LIBRARY_PATH = [
    temporaryLibraryDirectory,
    environment.LD_LIBRARY_PATH,
  ].filter(Boolean).join(":");
}
let exitCode = 1;
try {
  await Deno.mkdir(new URL("build/", root), { recursive: true });
  const desktop = new Deno.Command(Deno.execPath(), {
    args: [
      "desktop",
      "--hmr",
      "--config",
      "case-study/ecs/deno.json",
      "--allow-read",
      "--allow-write=build",
      "--allow-net",
      "--allow-env",
      "--allow-run=generated/compiler/blotc",
      "--include",
      "case-study/ecs/compile_worker.ts",
      "--include",
      "generated/wasm",
      "--include",
      "std",
      "--include",
      "npm:imagescript@1.3.1",
      "case-study/ecs/main.ts",
    ],
    cwd: root,
    env: environment,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  }).spawn();
  exitCode = (await desktop.status).code;
} finally {
  if (temporaryLibraryDirectory) {
    await Deno.remove(temporaryLibraryDirectory, { recursive: true });
  }
}
Deno.exit(exitCode);

async function provideLibxdoSoname(): Promise<string | undefined> {
  if (Deno.build.os !== "linux") return undefined;
  const output = await new Deno.Command("ldconfig", {
    args: ["-p"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!output.success) {
    throw new Error(
      `ldconfig -p failed: ${new TextDecoder().decode(output.stderr)}`,
    );
  }
  const cache = new TextDecoder().decode(output.stdout);
  if (/\blibxdo\.so\.3\b[^\n]*=>/u.test(cache)) return undefined;
  const newerLibrary = cache.match(/\blibxdo\.so\.4\b[^\n]*=>\s+(\S+)/u)?.[1];
  if (!newerLibrary) {
    throw new Error("Deno Desktop needs libxdo.so.3 or libxdo.so.4");
  }
  const directory = await Deno.makeTempDir({ prefix: "blot-ecs-libxdo-" });
  try {
    // Deno 2.9.6 requests the older soname on distributions shipping .4.
    await Deno.symlink(newerLibrary, `${directory}/libxdo.so.3`);
    return directory;
  } catch (error) {
    await Deno.remove(directory, { recursive: true });
    throw error;
  }
}
