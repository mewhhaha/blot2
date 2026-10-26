import { strict as assert } from "node:assert";
import { runCli } from "./cli.ts";
import { runInstalledCli } from "./installed_cli.ts";

Deno.test({
  name: "installed CLI rejects K1 before extracting a compiler",
  permissions: "none",
  fn: async () => {
    assert.equal(
      await runInstalledCli(["check", "input.blot", "--language=k1"]),
      1,
    );
    assert.equal(
      await runInstalledCli(["--language=k1", "build", "input.blot"]),
      1,
    );
    assert.equal(
      await runInstalledCli(["check", "input.blot", "--language=unknown"]),
      2,
    );
  },
});

Deno.test({
  name: "K1 selection dispatches only to its own compiler",
  ignore: Deno.build.os === "windows",
  fn: async () => {
    const dir = await Deno.makeTempDir();
    try {
      const source = `${dir}/input.blot`;
      const log = `${dir}/calls`;
      const k1 = `${dir}/k1`;
      const legacy = `${dir}/legacy`;
      await Deno.writeTextFile(source, "");
      const quotedLog = `'${log.replaceAll("'", "'\\''")}'`;
      await Deno.writeTextFile(
        k1,
        `#!/bin/sh\nprintf 'k1\\n' >> ${quotedLog}\nprintf '%s\\n' "$@" >> ${quotedLog}\n`,
      );
      await Deno.writeTextFile(
        legacy,
        `#!/bin/sh\nprintf 'legacy\\n' >> ${quotedLog}\n`,
      );
      await Deno.chmod(k1, 0o700);
      await Deno.chmod(legacy, 0o700);

      assert.equal(
        await runCli(legacy, ["--language=k1", "check", source], k1),
        0,
      );
      assert.equal(
        await Deno.readTextFile(log),
        `k1\ncheck\n${source}\n`,
      );
      const output = `${dir}/out/module.wasm`;
      assert.equal(
        await runCli(legacy, ["build", source, output, "--language=k1"], k1),
        0,
      );
      assert.equal(
        await Deno.readTextFile(log),
        `k1\ncheck\n${source}\nk1\nbuild\n${source}\n${output}\n`,
      );
      await assert.rejects(() => Deno.stat(`${dir}/out`), Deno.errors.NotFound);

      const failure = `${dir}/failure`;
      const existing = `${dir}/existing.wasm`;
      await Deno.writeTextFile(failure, "#!/bin/sh\nexit 1\n");
      await Deno.chmod(failure, 0o700);
      await Deno.writeTextFile(existing, "keep this output");
      assert.equal(
        await runCli(
          legacy,
          ["build", source, existing, "--language=k1"],
          failure,
        ),
        1,
      );
      assert.equal(await Deno.readTextFile(existing), "keep this output");

      const before = await Deno.readTextFile(log);
      assert.equal(
        await runCli(legacy, ["check", source, "--language=k1", "--json"], k1),
        2,
      );
      assert.equal(
        await runCli(legacy, ["dependencies", source, "--language=k1"], k1),
        2,
      );
      assert.equal(
        await runCli(legacy, ["check", source, "--language=unknown"], k1),
        2,
      );
      assert.equal(
        await runCli(legacy, [
          "check",
          source,
          "--language=k1",
          "--language=k1",
        ], k1),
        2,
      );
      assert.equal(await Deno.readTextFile(log), before);

      assert.equal(
        await runCli(
          legacy,
          ["check", source, "--language=k1"],
          `${dir}/missing`,
        ),
        1,
      );
      assert.equal(await Deno.readTextFile(log), before);
      assert.equal(await runCli(legacy, ["check", source], k1), 0);
      assert.equal(await Deno.readTextFile(log), `${before}legacy\n`);
    } finally {
      await Deno.remove(dir, { recursive: true });
    }
  },
});
