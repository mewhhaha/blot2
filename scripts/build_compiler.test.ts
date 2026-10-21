import { strict as assert } from "node:assert";
import { fileURLToPath } from "node:url";

Deno.test("compiler build selects fixtures in one bounded Zig invocation", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-build-selection-" });
  const log = `${directory}/commands.log`;
  try {
    await Deno.writeTextFile(
      `${directory}/zig`,
      `#!/bin/sh
if [ "$1" = version ]; then
  printf '0.17.0\\n'
else
  printf '%s\\n' "$*" >> "$BLOT_BUILD_LOG"
fi
`,
    );
    await Deno.chmod(`${directory}/zig`, 0o755);
    const run = async (...args: string[]) => {
      await Deno.writeTextFile(log, "");
      const result = await new Deno.Command(Deno.execPath(), {
        args: [
          "run",
          "-A",
          fileURLToPath(new URL("./build_compiler.ts", import.meta.url)),
          ...args,
        ],
        env: {
          PATH: `${directory}:${Deno.env.get("PATH") ?? ""}`,
          BLOT_BUILD_LOG: log,
        },
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert.equal(result.code, 0, new TextDecoder().decode(result.stderr));
      return (await Deno.readTextFile(log)).trim().split("\n");
    };
    const selected = await run(
      "--dev",
      "--incremental",
      "--fixtures=arena-fixture",
      "--fixtures",
      "shared-rc-fixture",
      "--jobs=2",
    );
    assert.equal(selected.length, 1);
    assert.match(selected[0], /arena-fixture shared-rc-fixture/);
    assert.match(selected[0], /-fincremental/);
    assert.match(selected[0], /-Dllvm=false/);
    assert.match(selected[0], /-j2/);
    assert.doesNotMatch(
      selected[0],
      /cohort-fixture|list-runtime-fixture|resource-retire-fixture|budget-fixture/,
    );
    const cachedDev = await run("--dev", "--fixtures=");
    assert.doesNotMatch(cachedDev[0], /-fincremental/);
    const empty = await run("--fixtures=");
    assert.equal(empty.length, 1);
    assert.doesNotMatch(empty[0], /-fixture/);
    const full = await run();
    assert.equal(full.length, 1);
    assert.match(full[0], /-Dllvm=true/);
    assert.match(
      full[0],
      /arena-fixture shared-rc-fixture cohort-fixture list-runtime-fixture resource-retire-fixture/,
    );
    assert.match(full[0], /region-owner-publication-fixture/);
    assert.doesNotMatch(full[0], /budget-fixture/);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
