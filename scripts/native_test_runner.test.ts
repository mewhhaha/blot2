import { strict as assert } from "node:assert";
import { fileURLToPath } from "node:url";

Deno.test("native runtime shards partition every test and propagate failures", async () => {
  const zig = Deno.env.get("ZIG") ?? "zig";
  const version = await new Deno.Command(zig, { args: ["version"] }).output();
  assert.equal(new TextDecoder().decode(version.stdout).trim(), "0.17.0");
  const directory = await Deno.makeTempDir({ prefix: "blot-native-shards-" });
  try {
    const source = `${directory}/laws.zig`;
    const executable = `${directory}/laws`;
    await Deno.writeTextFile(
      source,
      `const std = @import("std");
test "accepted" { try std.testing.expect(true); }
test "rejected" { return error.DeliberateFailure; }
test "skipped" { return error.SkipZigTest; }
test "allocator law" { if (std.testing.random_seed == 1) _ = try std.testing.allocator.alloc(u8, 8); }
test "logging law" { if (std.testing.random_seed == 2) std.log.err("deliberate error", .{}); }
test "panic law" { if (std.testing.random_seed == 3) @panic("deliberate panic"); }
`,
    );
    const compileArgs = [
      "test",
      source,
      "-O",
      "safe",
      "-fno-llvm",
      "--test-no-exec",
      `-femit-bin=${executable}`,
      "--test-runner",
      fileURLToPath(
        new URL("../zig-native/src/test_runner.zig", import.meta.url),
      ),
    ];
    const compiled = await new Deno.Command(zig, {
      args: compileArgs,
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.equal(compiled.code, 0, new TextDecoder().decode(compiled.stderr));
    const run = async (...args: string[]) =>
      await new Deno.Command(executable, {
        args,
        stdout: "piped",
        stderr: "piped",
      }).output();
    const names = (output: Deno.CommandOutput) =>
      new TextDecoder().decode(output.stdout).trim().split("\n").filter(
        Boolean,
      );
    const all = names(await run("--list"));
    const left = names(await run("--list", "--shard=0", "--shards=2"));
    const right = names(await run("--list", "--shard=1", "--shards=2"));
    assert.deepEqual([...left, ...right].sort(), [...all].sort());
    assert.equal(new Set([...left, ...right]).size, all.length);
    const results = await Promise.all([
      run("--shard=0", "--shards=2"),
      run("--shard=1", "--shards=2"),
    ]);
    assert.deepEqual(results.map((result) => result.code).sort(), [0, 1]);
    assert.equal((await run()).code, 1);
    // Select allocator/logging/panic laws from their exact inventory positions.
    const allocatorIndex = all.findIndex((name) =>
      name.endsWith("allocator law")
    );
    const loggingIndex = all.findIndex((name) => name.endsWith("logging law"));
    const panicIndex = all.findIndex((name) => name.endsWith("panic law"));
    const leak = await run(
      `--shard=${allocatorIndex}`,
      `--shards=${all.length}`,
      "--seed=1",
    );
    assert.equal(leak.code, 1);
    assert.match(new TextDecoder().decode(leak.stderr), /1 leaks/);
    const logged = await run(
      `--shard=${loggingIndex}`,
      `--shards=${all.length}`,
      "--seed=2",
    );
    assert.equal(logged.code, 1);
    assert.match(new TextDecoder().decode(logged.stderr), /1 logged errors/);
    assert.notEqual(
      (await run(`--shard=${panicIndex}`, `--shards=${all.length}`, "--seed=3"))
        .code,
      0,
    );

    assert.notEqual((await run("--shard=2", "--shards=2")).code, 0);
    // An empty shard is valid; a filter that discovers no laws is not a pass.
    assert.equal(
      (await run(`--shard=${all.length}`, `--shards=${all.length + 1}`)).code,
      0,
    );
    const empty = await new Deno.Command(zig, {
      args: [...compileArgs, "--test-filter", "missing test"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.equal(empty.code, 0, new TextDecoder().decode(empty.stderr));
    const unmatched = await run();
    assert.equal(unmatched.code, 1);
    assert.match(
      new TextDecoder().decode(unmatched.stderr),
      /No matching native tests/,
    );
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
