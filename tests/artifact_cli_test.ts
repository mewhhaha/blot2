import { assert } from "./session_harness.ts";
const decoder = new TextDecoder();
async function command(args: string[], env?: Record<string, string>) {
  return await new Deno.Command("build/blot", {
    args,
    env,
    stdout: "piped",
    stderr: "piped",
  }).output();
}
async function run(path: string, x = 40) {
  const { instance } = await WebAssembly.instantiate(await Deno.readFile(path));
  return (instance.exports.run as (x: number) => number)(x) >>> 0;
}
Deno.test("ART required Core is independently admitted and locally rebuilt without source files", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-required-core-" });
  try {
    for (
      const fixture of [
        "examples/static_closure.blot",
        "tests/runtime_static_generic.blot",
        "tests/runtime_static_nested.blot",
        "tests/runtime_static_predicate.blot",
      ]
    ) {
      const source = `${dir}/source.blot`,
        output = `${dir}/first.wasm`,
        rebuilt = `${dir}/rebuilt.wasm`,
        core = `${dir}/checked.bk1`;
      await Deno.copyFile(fixture, source);
      const result = await command([
        "build",
        source,
        "-o",
        output,
        `--package-root=${dir}`,
        `--emit-core=${core}`,
      ]);
      assert(result.success, decoder.decode(result.stderr));
      await Deno.remove(source);
      const reload = await command(["rebuild", core, "-o", rebuilt]);
      assert(reload.success, decoder.decode(reload.stderr));
      for (const x of [0, 2, 40, 0xffffffff]) {
        assert(await run(output, x) === await run(rebuilt, x));
      }
      const stable = await Deno.readFile(rebuilt),
        bytes = await Deno.readFile(core);
      for (
        const corrupt of [
          bytes.slice(0, 7),
          new Uint8Array([...bytes, 0]),
          bytes.map((b, i) => i === 8 ? b ^ 255 : b),
        ]
      ) {
        await Deno.writeFile(`${dir}/corrupt.bk1`, corrupt);
        const rejected = await command([
          "rebuild",
          `${dir}/corrupt.bk1`,
          "-o",
          rebuilt,
        ]);
        assert(!rejected.success, "malformed required Core accepted");
        const after = await Deno.readFile(rebuilt);
        assert(
          after.length === stable.length &&
            after.every((b, i) => b === stable[i]),
        );
      }
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
Deno.test("REV output pair rolls back failed publication and rejects aliased destinations", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-publication-" });
  try {
    const source = `${dir}/source.blot`,
      core = `${dir}/checked.bk1`,
      output = `${dir}/run.wasm`;
    const write = (n: number) =>
      Deno.writeTextFile(
        source,
        `pub let run: Unit -> U32 ! {} resources {depth:1,frame:0} = fn () => return ${n}\n`,
      );
    const args = [
      "build",
      source,
      "-o",
      output,
      `--package-root=${dir}`,
      `--emit-core=${core}`,
    ];
    await write(41);
    assert((await command(args)).success);
    const beforeCore = await Deno.readFile(core),
      beforeWasm = await Deno.readFile(output);
    await write(42);
    const failures = [
      await command(args, {
        LD_PRELOAD: `${Deno.cwd()}/build/publication_fault.so`,
        BLOT_FAIL_RENAME_TARGET: output,
      }),
      await command([
        "build",
        source,
        "-o",
        `${dir}/absent/out.wasm`,
        `--package-root=${dir}`,
        `--emit-core=${core}`,
      ]),
      await command([
        "build",
        source,
        "-o",
        `${dir}/./checked.bk1`,
        `--package-root=${dir}`,
        `--emit-core=${core}`,
      ]),
    ];
    assert(failures.every((r) => !r.success));
    for (
      const [path, bytes] of [[core, beforeCore], [output, beforeWasm]] as const
    ) {
      const after = await Deno.readFile(path);
      assert(
        after.length === bytes.length && after.every((b, i) => b === bytes[i]),
      );
    }
    for await (const entry of Deno.readDir(dir)) {
      assert(!entry.name.includes(".blot-"), "staging file leaked");
    }
    assert(await run(output) === 41);
    assert((await command(args)).success);
    assert(await run(output) === 42);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("REV generated Wasm replacement handles staging faults without durability sync", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-generated-publication-" });
  try {
    const source = `${dir}/source.blot`, output = `${dir}/run.wasm`;
    const write = (n: number) =>
      Deno.writeTextFile(
        source,
        `pub let run: Unit -> U32 ! {} resources {depth:1,frame:0} = fn () => return ${n}\n`,
      );
    const args = ["build", source, "-o", output, `--package-root=${dir}`];
    const env = {
      LD_PRELOAD: `${Deno.cwd()}/build/publication_fault.so`,
      BLOT_PUBLICATION_TARGET: output,
    };
    const noStage = async () => {
      for await (const entry of Deno.readDir(dir)) {
        assert(
          !entry.name.includes(".blot-"),
          "generated output staging file leaked",
        );
      }
    };
    await write(41);
    assert((await command(args)).success);
    await Deno.chmod(output, 0o751);
    const before = await Deno.readFile(output);
    await write(42);
    for (
      const fault of [
        { BLOT_PUBLICATION_WRITE: "zero" },
        { BLOT_PUBLICATION_WRITE: "error" },
        { BLOT_PUBLICATION_WRITE: "partial-error" },
        { BLOT_PUBLICATION_CLOSE: "1" },
        { BLOT_PUBLICATION_CHMOD: "1" },
        { BLOT_FAIL_RENAME_TARGET: output },
      ] as Record<string, string>[]
    ) {
      const failed = await command(args, { ...env, ...fault });
      assert(
        !failed.success &&
          decoder.decode(failed.stderr).includes("k1_io_error"),
      );
      const after = await Deno.readFile(output);
      assert(
        after.length === before.length &&
          after.every((b, i) => b === before[i]),
      );
      assert(
        ((await Deno.stat(output)).mode! & 0o777) === 0o751,
        "failure changed output mode",
      );
      await noStage();
    }
    assert(await run(output) === 41);
    // EINTR and a positive short write must both be retried. An injected fsync
    // failure remains irrelevant for this generated-file publication contract.
    const success = await command(args, {
      ...env,
      BLOT_PUBLICATION_WRITE: "eintr-short",
      BLOT_PUBLICATION_FSYNC: "1",
    });
    assert(success.success, decoder.decode(success.stderr));
    assert(await run(output) === 42);
    assert(((await Deno.stat(output)).mode! & 0o777) === 0o751);
    await noStage();

    await Deno.remove(output);
    for (
      const fault of [
        { BLOT_PUBLICATION_WRITE: "zero" },
        { BLOT_PUBLICATION_WRITE: "error" },
        { BLOT_PUBLICATION_WRITE: "partial-error" },
        { BLOT_PUBLICATION_CLOSE: "1" },
        { BLOT_FAIL_RENAME_TARGET: output },
      ] as Record<string, string>[]
    ) {
      assert(!(await command(args, { ...env, ...fault })).success);
      let absent = false;
      try {
        await Deno.lstat(output);
      } catch (error) {
        absent = error instanceof Deno.errors.NotFound;
      }
      assert(absent, "failed first publication created an output");
      await noStage();
    }
    const reference = `${dir}/mode-reference`;
    await Deno.writeTextFile(reference, "reference");
    const fresh = await command(args, { ...env, BLOT_PUBLICATION_FSYNC: "1" });
    assert(fresh.success, decoder.decode(fresh.stderr));
    assert(
      ((await Deno.stat(output)).mode! & 0o777) ===
        ((await Deno.stat(reference)).mode! & 0o777),
      "new output must honor the process umask",
    );
    assert(await run(output) === 42);
    await noStage();

    await Deno.remove(output);
    await Deno.mkdir(output);
    assert(!(await command(args)).success, "directory destination accepted");
    assert((await Deno.lstat(output)).isDirectory);
    await Deno.remove(output);
    await Deno.symlink(reference, output);
    assert(!(await command(args)).success, "symlink destination accepted");
    assert((await Deno.lstat(output)).isSymlink);
    assert(
      await Deno.readTextFile(reference) === "reference",
      "symlink target changed",
    );
    await noStage();
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
