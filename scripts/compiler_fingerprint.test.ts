import { strict as assert } from "node:assert";

const fixtureBuild = `const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const llvm = b.option(bool, "llvm", "backend");
    const identity = @import("compiler_fingerprint.zig").digest(b, target, optimize, llvm) catch |err| {
        std.debug.panic("{s}", .{@errorName(err)});
    };
    const file = b.addWriteFiles().add("compiler-identity.bin", &identity);
    b.getInstallStep().dependOn(&b.addInstallFile(file, "compiler-identity.bin").step);
}
`;

Deno.test("compiler identity follows production inputs and preserves test-only edits", async () => {
  const zig = Deno.env.get("ZIG") ?? "zig";
  const version = await new Deno.Command(zig, { args: ["version"] }).output();
  assert.equal(version.code, 0);
  assert.equal(new TextDecoder().decode(version.stdout).trim(), "0.17.0");
  const directory = await Deno.makeTempDir({ prefix: "blot-fingerprint-" });
  const write = (path: string, content: string) =>
    Deno.writeTextFile(`${directory}/${path}`, content);
  const build = async (args: string[] = [], succeeds = true) => {
    const result = await new Deno.Command(zig, {
      cwd: directory,
      args: ["build", ...args],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const stderr = new TextDecoder().decode(result.stderr);
    if (!succeeds) {
      assert.notEqual(result.code, 0, stderr);
      return stderr;
    }
    assert.equal(result.code, 0, stderr);
    return Array.from(
      await Deno.readFile(`${directory}/zig-out/compiler-identity.bin`),
    )
      .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  };
  try {
    await Deno.mkdir(`${directory}/src/nested`, { recursive: true });
    await Deno.mkdir(`${directory}/src/.zig-cache`);
    await write("build.zig", fixtureBuild);
    await Deno.copyFile(
      new URL("../zig-native/compiler_fingerprint.zig", import.meta.url),
      `${directory}/compiler_fingerprint.zig`,
    );
    await write(
      "src/main.zig",
      `const raw = @embedFile("opaque.zig");
const shared = @embedFile("nested/production_tests.zig");
const module = @import("nested/production_tests.zig");
const root = @import("root");
test "ignored dependencies" {
    _ = @import("standalone_tests.zig");
    _ = @embedFile("test-only.blot");
}
// @import("missing-comment.zig")
const text = "@import(\\\"missing-string.zig\\\")";
`,
    );
    await write(
      "src/nested/production_tests.zig",
      `const data = @embedFile("../production.blot");
const options = @import("test_options");
const cycle = @import("../main.zig");
`,
    );
    await write("src/production.blot", "entry const answer = 42\n");
    await write("src/opaque.zig", "@import(computed)\n");
    await write("src/test-only.blot", "entry const test_answer = 1\n");
    await write("src/standalone_tests.zig", "test {}\n");
    const baseline = await build();
    await write(
      "src/standalone_tests.zig",
      'test { @compileError("test edit"); }\n',
    );
    assert.equal(
      await build(),
      baseline,
      "standalone test edit changed identity",
    );
    await write("src/test-only.blot", "entry const test_answer = 2\n");
    assert.equal(await build(), baseline, "test fixture edit changed identity");
    await write("src/nested/new_tests.zig", "test {}\n");
    assert.equal(await build(), baseline, "test addition changed identity");
    await write("src/.zig-cache/ignored.zig", "@import(computed)\n");
    assert.equal(await build(), baseline, "generated cache changed identity");
    await write(
      "src/nested/production_tests.zig",
      `const data = @embedFile("../production.blot");
const options = @import("test_options");
const cycle = @import("../main.zig");
const changed = true;
`,
    );
    const changedSource = await build();
    assert.notEqual(
      changedSource,
      baseline,
      "production import edit did not change identity",
    );
    await write("src/production.blot", "entry const answer = 43\n");
    const changedEmbed = await build();
    assert.notEqual(
      changedEmbed,
      changedSource,
      "production embed edit did not change identity",
    );
    assert.notEqual(await build(["-Doptimize=fast"]), changedEmbed);
    assert.notEqual(await build(["-Dllvm=false"]), changedEmbed);
    assert.notEqual(
      await build(["-Dtarget=wasm32-freestanding"]),
      changedEmbed,
    );
    await write("build.zig", fixtureBuild + "// build configuration edit\n");
    assert.notEqual(
      await build(),
      changedEmbed,
      "build edit did not change identity",
    );
    await Deno.symlink("production.blot", `${directory}/src/linked.blot`);
    assert.match(await build([], false), /CompilerSourceSymlink/);
    await Deno.remove(`${directory}/src/linked.blot`);
    await write("src/main.zig", "const data = @embedFile(computed);\n");
    assert.match(await build([], false), /UnsupportedCompilerDependency/);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
