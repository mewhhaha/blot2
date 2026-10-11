import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { instantiateGuest } from "../mod.ts";
import { runCli } from "./cli.ts";
import { resolveProject } from "./packages.ts";
import { fileURLToPath } from "node:url";

const executable = Deno.args[0] ??
  new URL("../zig-native/zig-out/bin/blotc", import.meta.url);

async function writeProject(
  directory: string,
  options: { prelude?: string } = {},
) {
  const library = `${directory}/library`;
  const app = `${directory}/app`;
  await Deno.mkdir(`${library}/src`, { recursive: true });
  await Deno.mkdir(`${app}/nested/deep`, { recursive: true });
  let workspace = "exports:\n  .: ./src\n";
  if (options.prelude) workspace += "prelude: ./src/prelude.blot\n";
  await Deno.writeTextFile(
    `${library}/blot-workspace.yaml`,
    workspace,
  );
  await Deno.writeTextFile(`${library}/src/value.blot`, "const value = 42\n");
  if (options.prelude) {
    await Deno.writeTextFile(
      `${library}/src/prelude.blot`,
      "const from_package_prelude = 9\n",
    );
  }
  const project: { dependencies: Record<string, unknown>; prelude?: string } = {
    dependencies: { math: { path: "../library" } },
  };
  if (options.prelude) project.prelude = options.prelude;
  await Deno.writeTextFile(`${app}/blot.json`, JSON.stringify(project));
  await Deno.writeTextFile(
    `${app}/nested/deep/main.blot`,
    'import { value } from "math/value"\nentry const answer = fn () => value\n',
  );
  return { app, entry: `${app}/nested/deep/main.blot`, library };
}

Deno.test("CLI resolves declared local imports and package prelude from the nearest project", async () => {
  const directory = await Deno.makeTempDir();
  try {
    const { app, entry, library } = await writeProject(directory, {
      prelude: "math",
    });
    const resolved = await resolveProject(entry);
    ok(resolved);
    equal(resolved.root, app);
    equal(resolved.prelude, `${library}/src/prelude.blot`);
    equal(resolved.imports["math/"], `${library}/src`);

    // A deeper config is nearest and may select the same dependency with no prelude.
    await Deno.writeTextFile(
      `${app}/nested/blot.json`,
      JSON.stringify({ dependencies: { math: { path: "../../library" } } }),
    );
    await Deno.writeTextFile(
      `${app}/nested/blot-workspace.yaml`,
      "exports:\n  .: ./src\n",
    );
    const nearest = await resolveProject(entry);
    ok(nearest);
    equal(nearest.root, `${app}/nested`);
    equal(nearest.prelude, null);
    equal(await runCli(executable, ["check", entry]), 0);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("CLI manifest defaults can be overridden and omitted prelude stays absent", async () => {
  const directory = await Deno.makeTempDir();
  try {
    const { entry, library } = await writeProject(directory, {
      prelude: "math",
    });
    // Package import is loaded while an explicit prelude suppresses the manifest's prelude.
    await Deno.writeTextFile(
      entry,
      'import { value } from "math/value"\nentry const answer = fn () => value\n',
    );
    equal(await runCli(executable, ["check", entry, "--prelude", "none"]), 0);

    // The declared prelude is used by default.
    await Deno.writeTextFile(
      entry,
      "entry const answer = fn () => from_package_prelude\n",
    );
    equal(await runCli(executable, ["check", entry]), 0);

    // No manifest prelude means no implicit standard prelude.
    await Deno.writeTextFile(
      `${directory}/app/blot.json`,
      JSON.stringify({ dependencies: { math: { path: "../library" } } }),
    );
    await Deno.writeTextFile(entry, "entry const answer = fn () => Array\n");
    equal(await runCli(executable, ["check", entry]), 1);

    // An explicit alias with the same prefix replaces the package mapping.
    const override = `${directory}/override`;
    await Deno.mkdir(override);
    await Deno.writeTextFile(`${override}/value.blot`, "const value = 43\n");
    await Deno.writeTextFile(
      entry,
      'import { value } from "math/value"\nentry const answer = fn () => value\n',
    );
    const output = `${directory}/answer.wasm`;
    equal(
      await runCli(executable, [
        "build",
        entry,
        output,
        "--alias",
        `math/=${override}`,
        "--prelude",
        "none",
      ]),
      0,
    );
    const guest = await instantiateGuest(await Deno.readFile(output));
    try {
      equal(guest.call("answer", null), 43);
    } finally {
      guest.dispose();
    }
    ok(library.endsWith("/library"));
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("manifest dependency failures are surfaced by CLI", async () => {
  const directory = await Deno.makeTempDir();
  try {
    const app = `${directory}/app`;
    await Deno.mkdir(app);
    await Deno.writeTextFile(
      `${app}/blot.json`,
      JSON.stringify({ dependencies: { missing: "owner/repo#tag" } }),
    );
    await Deno.writeTextFile(
      `${app}/blot-workspace.yaml`,
      "exports:\n  .: ./src\n",
    );
    const entry = `${app}/main.blot`;
    await Deno.writeTextFile(entry, "entry const answer = fn () => 42\n");
    equal(await runCli(executable, ["check", entry]), 1);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("this checkout exports the standard prelude as an explicit package choice", async () => {
  const directory = await Deno.makeTempDir();
  try {
    const dependencies = {
      std: { path: fileURLToPath(new URL("../", import.meta.url)) },
    };
    const manifest = `${directory}/blot.json`;
    const entry = `${directory}/main.blot`;
    const output = `${directory}/answer.wasm`;
    await Deno.writeTextFile(
      manifest,
      JSON.stringify({ dependencies, prelude: "std" }),
    );
    await Deno.writeTextFile(
      entry,
      "entry const answer = fn () => (Array.from_list [40, 2])[0] + 2\n",
    );
    equal(await runCli(executable, ["build", entry, output]), 0);
    const guest = await instantiateGuest(await Deno.readFile(output));
    try {
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
    await Deno.writeTextFile(manifest, JSON.stringify({ dependencies }));
    equal(await runCli(executable, ["check", entry]), 1);
    await Deno.writeTextFile(entry, "entry const answer = fn () => 42\n");
    equal(await runCli(executable, ["check", entry]), 0);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
