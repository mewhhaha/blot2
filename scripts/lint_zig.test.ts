import { strict as assert } from "node:assert";
import {
  affectedFiles,
  changedPaths,
  checkSelection,
  dependencyInputs,
  hasOpaqueImports,
  importGraph,
} from "./lint_zig.ts";

Deno.test("broad lint edits batch analyzer processes without dropping files or caching failed roots", async () => {
  const paths = Array.from(
    { length: 40 },
    (_, i) => `zig-native/src/law${i}.zig`,
  );
  paths.push("zig-native/fixtures/root.zig");
  const calls: string[] = [];
  const results = await checkSelection(paths, async (path) => {
    calls.push(path);
    return path === "zig-native/src" ? 1 : 0;
  });
  assert.deepEqual(calls, ["zig-native/src", "zig-native/fixtures"]);
  assert.equal(results.size, paths.length);
  assert(paths.slice(0, -1).every((path) => results.get(path) === 1));
  assert.equal(results.get(paths.at(-1)!), 0);
});

Deno.test("local Zig lint follows import dependents including deleted inputs and cycles", () => {
  const graph = importGraph(
    new Map([
      ["zig-native/src/a.zig", '@import("b.zig"); @import("missing.zig");'],
      ["zig-native/src/b.zig", '@import("a.zig");'],
      ["zig-native/src/unrelated.zig", '@import("std");'],
    ]),
  );
  assert.deepEqual(affectedFiles(graph, ["zig-native/src/missing.zig"]), [
    "zig-native/src/a.zig",
    "zig-native/src/b.zig",
  ]);
  assert.deepEqual(dependencyInputs(graph, "zig-native/src/b.zig"), [
    "zig-native/src/a.zig",
    "zig-native/src/b.zig",
    "zig-native/src/missing.zig",
  ]);
  assert.deepEqual(affectedFiles(graph, ["zig-native/src/new.zig"]), []);
});

Deno.test("local Zig lint tracks embedded fixture changes and relative imports", () => {
  const graph = importGraph(
    new Map([
      [
        "zig-native/src/tests/a.zig",
        '@embedFile("input.blot"); @import("../check/core.zig");',
      ],
      ["zig-native/src/check/core.zig", ""],
    ]),
  );
  assert.deepEqual(affectedFiles(graph, ["zig-native/src/tests/input.blot"]), [
    "zig-native/src/tests/a.zig",
  ]);
  assert.deepEqual(affectedFiles(graph, ["zig-native/src/check/core.zig"]), [
    "zig-native/src/check/core.zig",
    "zig-native/src/tests/a.zig",
  ]);
});

Deno.test("local Zig lint follows the external fixture catalog including added and deleted inputs", () => {
  const graph = importGraph(
    new Map([
      [
        "zig-native/src/consumer.zig",
        '@import("fixtures").source("sample.blot")',
      ],
      ["zig-native/src/other.zig", '@import("std")'],
    ]),
    ["zig-native/fixtures/root.zig", "zig-native/fixtures/sample.blot"],
  );
  for (const path of ["root.zig", "sample.blot", "new.blot", "deleted.blot"]) {
    assert.deepEqual(affectedFiles(graph, [`zig-native/fixtures/${path}`]), [
      "zig-native/src/consumer.zig",
    ]);
  }
  assert(
    dependencyInputs(graph, "zig-native/src/consumer.zig").includes(
      "zig-native/fixtures/sample.blot",
    ),
  );
});

Deno.test("local Zig lint caches only passes and invalidates content and tool changes", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-lint-test-" });
  try {
    await Deno.mkdir(`${directory}/scripts`);
    await Deno.mkdir(`${directory}/zig-native/src`, { recursive: true });
    await Deno.copyFile(
      new URL("lint_zig.ts", import.meta.url),
      `${directory}/scripts/lint_zig.ts`,
    );
    await Deno.writeTextFile(
      `${directory}/zig-native/src/a.zig`,
      '@import("b.zig"); @import("missing.zig"); @embedFile("fixtures/" ++ name ++ ".blot");',
    );
    await Deno.writeTextFile(`${directory}/zig-native/src/b.zig`, "good");
    await Deno.mkdir(`${directory}/zig-native/src/fixtures`);
    await Deno.writeTextFile(
      `${directory}/zig-native/src/fixtures/one.blot`,
      "one",
    );
    const binary = `${directory}/tools/bin`;
    const library = `${directory}/tools/lib/std`;
    const backend = `${directory}/tools/libexec/zig-analyzer`;
    await Deno.mkdir(binary, { recursive: true });
    await Deno.mkdir(library, { recursive: true });
    await Deno.mkdir(backend, { recursive: true });
    await Deno.writeTextFile(`${library}/std.zig`, "standard library");
    await Deno.writeTextFile(`${backend}/zig`, "compiler backend");
    await Deno.writeTextFile(
      `${backend}/zig-analyzer-backend.json`,
      "compatible",
    );
    const zig = `${binary}/zig`;
    await Deno.writeTextFile(
      zig,
      '#!/bin/sh\ncase "$1" in version) cat "$(dirname "$0")/version";; env) cat "$(dirname "$0")/env";; esac\n',
    );
    await Deno.chmod(zig, 0o755);
    await Deno.writeTextFile(`${binary}/version`, "0.17.0");
    await Deno.writeTextFile(
      `${binary}/env`,
      `.{ .zig_exe = ${JSON.stringify(zig)}, .lib_dir = ${
        JSON.stringify(`${directory}/tools/lib`)
      } }`,
    );
    const analyzer = `${binary}/analyzer`;
    await Deno.writeTextFile(
      analyzer,
      `#!/bin/sh
if [ "$1" = "doctor" ]; then
  if [ "$(zig version)" != "0.17.0" ]; then echo "missing or incompatible Zig" >&2; exit 1; fi
  backend="$(dirname "$0")/../libexec/zig-analyzer"
  if [ ! -f "$backend/zig" ]; then echo "compiler backend missing" >&2; exit 1; fi
  if [ "$(cat "$backend/zig-analyzer-backend.json")" != "compatible" ]; then echo "compiler backend incompatible" >&2; exit 1; fi
  exit 0
fi
printf 'check\\n' >> "$(dirname "$0")/../../checks.log"
case "$(cat "$2")" in *bad*) exit 7;; esac
exit 0
`,
    );
    await Deno.chmod(analyzer, 0o755);
    async function run(
      args = ["--files", "zig-native/src/b.zig"],
      path = `${binary}:/usr/bin:/bin`,
    ) {
      const result = await new Deno.Command(Deno.execPath(), {
        cwd: directory,
        args: [
          "run",
          "--allow-env=ZIG_ANALYZER",
          "--allow-read",
          "--allow-write",
          "--allow-run",
          "scripts/lint_zig.ts",
          ...args,
        ],
        env: { ZIG_ANALYZER: analyzer, PATH: path },
        stdout: "piped",
        stderr: "piped",
      }).output();
      return {
        code: result.code,
        output: new TextDecoder().decode(result.stdout),
        error: new TextDecoder().decode(result.stderr),
      };
    }
    assert.match((await run()).output, /2 checked, 0 unchanged/);
    assert.match((await run()).output, /0 checked, 2 unchanged/);
    const checks = () => Deno.readTextFile(`${directory}/checks.log`);
    const previousChecks = await checks();
    for (
      const mode of [[], ["--changed"], ["--files", "zig-native/src/b.zig"]]
    ) {
      const missingZig = await run(mode, "/usr/bin:/bin");
      assert.notEqual(missingZig.code, 0);
      assert.match(
        missingZig.error,
        /Zig lint backend unavailable or incompatible/,
      );
      await Deno.writeTextFile(`${binary}/version`, "0.18.0");
      const incompatibleZig = await run(mode);
      assert.notEqual(incompatibleZig.code, 0);
      assert.match(incompatibleZig.error, /missing or incompatible Zig/);
      await Deno.writeTextFile(`${binary}/version`, "0.17.0");
      await Deno.remove(`${backend}/zig`);
      const missingBackend = await run(mode);
      assert.notEqual(missingBackend.code, 0);
      assert.match(missingBackend.error, /compiler backend missing/);
      await Deno.writeTextFile(`${backend}/zig`, "compiler backend");
      await Deno.writeTextFile(
        `${backend}/zig-analyzer-backend.json`,
        "incompatible",
      );
      const incompatible = await run(mode);
      assert.notEqual(incompatible.code, 0);
      assert.match(incompatible.error, /compiler backend incompatible/);
      await Deno.writeTextFile(
        `${backend}/zig-analyzer-backend.json`,
        "compatible",
      );
      await Deno.remove(`${library}/std.zig`);
      const missingStandardLibrary = await run(mode);
      assert.notEqual(missingStandardLibrary.code, 0);
      assert.match(
        missingStandardLibrary.error,
        /standard library unavailable/,
      );
      await Deno.writeTextFile(`${library}/std.zig`, "standard library");
    }
    assert.equal(
      await checks(),
      previousChecks,
      "preflight rejects before checks or successful-cache reuse",
    );
    assert.match((await run()).output, /0 checked, 2 unchanged/);
    await Deno.writeTextFile(
      zig,
      (await Deno.readTextFile(zig)) + "# changed Zig\n",
    );
    assert.match((await run()).output, /2 checked, 0 unchanged/);
    assert.match((await run()).output, /0 checked, 2 unchanged/);
    await Deno.writeTextFile(
      `${backend}/zig`,
      "changed compatible compiler backend",
    );
    assert.match((await run()).output, /2 checked, 0 unchanged/);
    await Deno.writeTextFile(`${library}/std.zig`, "changed standard library");
    assert.match((await run()).output, /2 checked, 0 unchanged/);
    await Deno.writeTextFile(
      `${directory}/zig-native/src/fixtures/two.blot`,
      "two",
    );
    assert.match((await run()).output, /1 checked, 1 unchanged/);
    await Deno.remove(`${directory}/zig-native/src/fixtures/one.blot`);
    assert.match((await run()).output, /1 checked, 1 unchanged/);
    await Deno.writeTextFile(
      `${directory}/zig-native/src/missing.zig`,
      "missing",
    );
    assert.match((await run()).output, /1 checked, 1 unchanged/);
    await Deno.remove(`${directory}/zig-native/src/missing.zig`);
    assert.match((await run()).output, /0 checked, 2 unchanged/);
    await Deno.writeTextFile(`${directory}/zig-native/src/b.zig`, "edit");
    assert.match((await run()).output, /2 checked, 0 unchanged/);
    await Deno.writeTextFile(`${directory}/zig-native/src/b.zig`, "good");
    assert.match((await run()).output, /0 checked, 2 unchanged/);
    await Deno.writeTextFile(
      analyzer,
      (await Deno.readTextFile(analyzer)) + "# changed tool\n",
    );
    assert.match((await run()).output, /2 checked, 0 unchanged/);
    await Deno.writeTextFile(`${directory}/zig-native/.zig-version`, "0.17.0");
    assert.match((await run()).output, /2 checked, 0 unchanged/);
    await Deno.writeTextFile(`${directory}/zig-native/src/b.zig`, "bad!");
    const failure = await run();
    assert.equal(failure.code, 7);
    assert.match((await run()).output, /1 checked, 1 unchanged/);
    assert.equal((await run([])).code, 0);
    assert.match((await run()).output, /1 checked, 1 unchanged/);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("local Zig lint includes staged unstaged untracked deleted and both rename paths", () => {
  assert.deepEqual(
    changedPaths(
      " M unstaged.zig\0M  staged.zig\0?? new.zig\0 D deleted.zig\0R  new name.zig\0old name.zig\0",
    ),
    [
      "unstaged.zig",
      "staged.zig",
      "new.zig",
      "deleted.zig",
      "new name.zig",
      "old name.zig",
    ],
  );
});

Deno.test("local Zig lint falls back to the complete check for computed or escaped imports", () => {
  assert.equal(hasOpaqueImports('@import("core.zig")'), false);
  assert.equal(hasOpaqueImports('@import(prefix ++ ".zig")'), true);
  assert.equal(hasOpaqueImports("@embedFile(filename)"), true);
  assert.equal(hasOpaqueImports('@import("co\\x72e.zig")'), true);
});

Deno.test("local Zig lint tracks computed fixture paths including directory additions and deletions", () => {
  const source = '@embedFile("fixtures/" ++ name ++ ".blot")';
  assert.equal(hasOpaqueImports(source), false);
  const graph = importGraph(new Map([["zig-native/src/tests.zig", source]]), [
    "zig-native/src/fixtures/a.blot",
  ]);
  assert.deepEqual(
    affectedFiles(graph, ["zig-native/src/fixtures/deleted.blot"]),
    ["zig-native/src/tests.zig"],
  );
  assert.deepEqual(dependencyInputs(graph, "zig-native/src/tests.zig"), [
    "zig-native/src/fixtures/",
    "zig-native/src/fixtures/a.blot",
    "zig-native/src/tests.zig",
  ]);
});
