const std = @import("std");

pub fn build(b: *std.Build) void {
    if (comptime @import("builtin").zig_version.order(.{ .major = 0, .minor = 17, .patch = 0 }) == .lt)
        @compileError("The native compiler requires Zig 0.17.0 or newer");
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});
    const llvm_option = b.option(bool, "llvm", "Use LLVM to build the compiler executable");
    const use_llvm: ?bool = if (llvm_option) |value| value else if (optimize == .debug) null else true;
    const artifact_replay = b.option(bool, "artifact-replay", "Private owned backend reconstruction gate") orelse false;
    const identity = b.addOptions();
    identity.addOption(bool, "artifact_replay", artifact_replay);
    var compiler_digest = @import("compiler_fingerprint.zig").digest(b, target, optimize, use_llvm) catch @panic("Cannot read compiler source identity");
    if (artifact_replay) {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(&compiler_digest);
        hash.update("artifact-replay=true");
        hash.final(&compiler_digest);
    }
    identity.addOption([32]u8, "digest", compiler_digest);
    const identity_file = b.addWriteFiles().add("compiler-identity.bin", &compiler_digest);
    const install_identity = b.addInstallFile(identity_file, "compiler-identity.bin");
    b.step("compiler-identity", "Write the build-generated compiler fingerprint").dependOn(&install_identity.step);
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addOptions("compiler_identity", identity);
    const exe = b.addExecutable(.{ .name = "blotc", .root_module = module, .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    b.installArtifact(exe);
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/production_suite.zig"),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    const run_tests = b.addRunArtifact(tests);
    run_tests.setCwd(b.path(".."));
    b.step("test", "Test the handwritten compiler").dependOn(&run_tests.step);
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run the source compiler").dependOn(&run.step);
    const fixture = b.addExecutable(.{ .name = "arena-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("src/arena_fixture.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const generate_fixture = b.addRunArtifact(fixture);
    const fixture_file = generate_fixture.addOutputFileArg("arena-fixture.wasm");
    const install_fixture = b.addInstallFile(fixture_file, "arena-fixture.wasm");
    b.step("arena-fixture", "Generate the memory/array ABI execution fixture").dependOn(&install_fixture.step);
    const list_fixture = b.addExecutable(.{ .name = "list-runtime-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("src/list_runtime_fixture.zig"),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    const generate_list_fixture = b.addRunArtifact(list_fixture);
    const list_fixture_file = generate_list_fixture.addOutputFileArg("list-runtime-fixture.wasm");
    const install_list_fixture = b.addInstallFile(list_fixture_file, "list-runtime-fixture.wasm");
    b.step("list-runtime-fixture", "Generate list layout and sharing execution laws").dependOn(&install_list_fixture.step);
}
