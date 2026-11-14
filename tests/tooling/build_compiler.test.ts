import { strict as assert } from "node:assert";
import { fileURLToPath } from "node:url";

Deno.test("compiler build runs one bounded Zig invocation", async () => {
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
          fileURLToPath(
            new URL("../../scripts/build_compiler.ts", import.meta.url),
          ),
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
    const selected = await run("--dev", "--incremental", "--jobs=2");
    assert.equal(selected.length, 1);
    assert.match(selected[0], /^build install compiler-identity /);
    assert.match(selected[0], /-fincremental/);
    assert.match(selected[0], /-Dllvm=false/);
    assert.match(selected[0], /-j2/);
    const cachedDev = await run("--dev");
    assert.doesNotMatch(cachedDev[0], /-fincremental/);
    const full = await run();
    assert.equal(full.length, 1);
    assert.match(full[0], /-Dllvm=true/);
    assert.doesNotMatch(full[0], /-fixture/);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
