import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { installBlotLanguage } from "./helix_languages.ts";

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const grammarDirectory = fileURLToPath(
  new URL("../editor/tree-sitter-blot2/", import.meta.url),
);
const extensions: Partial<Record<typeof Deno.build.os, string>> = {
  linux: "so",
  darwin: "dylib",
  windows: "dll",
};
const extension = extensions[Deno.build.os];
if (extension === undefined) {
  throw new Error(`Unsupported operating system: ${Deno.build.os}`);
}

let configDirectory = Deno.env.get("XDG_CONFIG_HOME");
if (!configDirectory) {
  const userHome = Deno.env.get("HOME");
  if (!userHome) {
    throw new Error("Set XDG_CONFIG_HOME or HOME to locate the Helix runtime.");
  }
  configDirectory = join(userHome, ".config");
}
const helixDirectory = join(configDirectory, "helix");
const languagesPath = join(helixDirectory, "languages.toml");
const libraryName = `blot.${extension}`;
const builtLibrary = join(grammarDirectory, libraryName);

let existingLanguages = "";
try {
  existingLanguages = await Deno.readTextFile(languagesPath);
} catch (error) {
  if (!(error instanceof Deno.errors.NotFound)) throw error;
}
const installedLanguages = installBlotLanguage(existingLanguages, {
  repository,
  definition: await Deno.readTextFile(
    new URL("../editor/helix/languages.toml", import.meta.url),
  ),
});

// Build before touching installed files. A failed build leaves Helix unchanged.
const build = await new Deno.Command("tree-sitter", {
  args: ["build", "--output", builtLibrary, grammarDirectory],
  env: { XDG_CACHE_HOME: join(grammarDirectory, ".cache") },
  stdout: "inherit",
  stderr: "inherit",
}).spawn().status;
if (!build.success) {
  throw new Error(`Tree-sitter build failed with exit code ${build.code}.`);
}

const replacements: {
  relativePath: string;
  contents: Uint8Array | undefined;
}[] = [
  {
    relativePath: join("runtime", "grammars", libraryName),
    contents: await Deno.readFile(builtLibrary),
  },
];
for (const name of ["highlights.scm", "rainbows.scm"]) {
  replacements.push({
    relativePath: join("runtime", "queries", "blot", name),
    contents: await Deno.readFile(join(grammarDirectory, "queries", name)),
  });
}

// These legacy queries refer to nodes the highlighting grammar does not have.
for (
  const name of [
    "indents.scm",
    "textobjects.scm",
    "tags.scm",
    "locals.scm",
    "injections.scm",
  ]
) {
  replacements.push({
    relativePath: join("runtime", "queries", "blot", name),
    contents: undefined,
  });
}
// Retire the separate runtime installed by the initial project-local setup.
for (
  const relativePath of [
    join("runtime", "grammars", `blot2.${extension}`),
    join("runtime", "queries", "blot2", "highlights.scm"),
    join("runtime", "queries", "blot2", "rainbows.scm"),
  ]
) {
  replacements.push({ relativePath, contents: undefined });
}
replacements.push({
  relativePath: "languages.toml",
  contents: new TextEncoder().encode(installedLanguages),
});

const changes = [];
for (const replacement of replacements) {
  let previous: Uint8Array | undefined;
  try {
    previous = await Deno.readFile(
      join(helixDirectory, replacement.relativePath),
    );
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  if (
    replacement.relativePath === "languages.toml" &&
    new TextDecoder().decode(previous) !== existingLanguages
  ) {
    throw new Error(
      "languages.toml changed while building; re-run the installer.",
    );
  }
  const { contents } = replacement;
  if (contents === undefined && previous === undefined) continue;
  if (
    contents !== undefined && previous !== undefined &&
    contents.length === previous.length && contents.every((byte, index) =>
      byte === previous[index]
    )
  ) continue;
  changes.push({ ...replacement, previous });
}

await Deno.mkdir(helixDirectory, { recursive: true });
if (changes.some(({ previous }) => previous !== undefined)) {
  const backupDirectory = await Deno.makeTempDir({
    dir: helixDirectory,
    prefix: "blot-backup-",
  });
  for (const { relativePath, previous } of changes) {
    if (previous === undefined) continue;
    const backup = join(backupDirectory, relativePath);
    await Deno.mkdir(dirname(backup), { recursive: true });
    await Deno.writeFile(backup, previous);
  }
  console.log(`Backed up replaced Blot files to ${backupDirectory}`);
}

for (const { relativePath, contents } of changes) {
  const target = join(helixDirectory, relativePath);
  if (contents === undefined) {
    await Deno.remove(target);
    console.log(`Removed obsolete ${target}`);
    continue;
  }
  await Deno.mkdir(dirname(target), { recursive: true });
  const pending = `${target}.pending`;
  await Deno.writeFile(pending, contents);
  await Deno.rename(pending, target);
  console.log(`Installed ${target}`);
}

// Run outside the checkout so project-local registration cannot mask a failure.
const health = await new Deno.Command("hx", {
  args: ["--health", "blot"],
  cwd: helixDirectory,
  env: { XDG_CONFIG_HOME: configDirectory, NO_COLOR: "1" },
}).output();
const report = new TextDecoder().decode(health.stdout);
const required = [
  "Configured language servers: None",
  "Configured formatter: None",
  "Tree-sitter parser: ✓",
  "Highlight queries: ✓",
  "Rainbow queries: ✓",
];
if (!health.success || required.some((line) => !report.includes(line))) {
  throw new Error(
    `Helix did not load the installed Blot configuration:\n${report}${
      new TextDecoder().decode(health.stderr)
    }`,
  );
}
console.log(report.trimEnd());
console.log("Restart Helix to use the new Blot highlighting for .blot files.");
