const std = @import("std");
const TestSuite = enum { all, syntax, types, runtime };

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
    identity.addOption(usize, "inference_budget", 1_000_000);
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
    // The ordinary CLI and server paths, with a small build-local budget.
    // A distinct identity keeps fixture artifacts out of production caches.
    const budget_identity = b.addOptions();
    budget_identity.addOption(bool, "artifact_replay", false);
    budget_identity.addOption(usize, "inference_budget", 256);
    var budget_digest = @import("compiler_fingerprint.zig").digest(b, target, .safe, false) catch @panic("Cannot read budget fixture identity");
    var budget_hash = std.crypto.hash.sha2.Sha256.init(.{});
    budget_hash.update(&budget_digest);
    budget_hash.update("inference-budget-fixture=256");
    budget_hash.final(&budget_digest);
    budget_identity.addOption([32]u8, "digest", budget_digest);
    const budget_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = .safe });
    budget_module.addOptions("compiler_identity", budget_identity);
    const budget_fixture = b.addExecutable(.{ .name = "budget-fixture", .root_module = budget_module, .use_llvm = false });
    const install_budget = b.addInstallArtifact(budget_fixture, .{});
    b.step("budget-fixture", "Build the small-budget CLI/server regression fixture").dependOn(&install_budget.step);
    const suite = b.option(TestSuite, "test-suite", "Native test subsystem (all, syntax, types, runtime)") orelse .all;
    const test_source = switch (suite) {
        .all => "src/production_suite.zig",
        .syntax => "src/syntax_suite.zig",
        .types => "src/types_suite.zig",
        .runtime => "src/runtime_suite.zig",
    };
    const tests = b.addTest(.{ .filters = b.option([]const []const u8, "test-filter", "filter") orelse &.{}, .root_module = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    const test_options = b.addOptions();
    test_options.addOption(bool, "oom_profile", b.option(bool, "oom-profile", "Report allocation-failure sweep timings and counts") orelse false);
    tests.root_module.addOptions("test_options", test_options);
    b.step("test-compile", "Compile the native test suite without executing it").dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    run_tests.setCwd(b.path(".."));
    run_tests.has_side_effects = b.option(bool, "test-force-run", "Execute native tests even when their run is cached") orelse false;
    b.step("test", "Test the handwritten compiler").dependOn(&run_tests.step);
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run the source compiler").dependOn(&run.step);
    const fixture = b.addExecutable(.{ .name = "arena-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("src/arena_fixture.zig"),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    const generate_fixture = b.addRunArtifact(fixture);
    const fixture_file = generate_fixture.addOutputFileArg("arena-fixture.wasm");
    const install_fixture = b.addInstallFile(fixture_file, "arena-fixture.wasm");
    b.step("arena-fixture", "Generate the memory/array ABI execution fixture").dependOn(&install_fixture.step);
    const rc_fixture = b.addExecutable(.{ .name = "shared-rc-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("src/shared_rc_fixture.zig"),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    const generate_rc = b.addRunArtifact(rc_fixture);
    const rc_file = generate_rc.addOutputFileArg("shared-rc-fixture.wasm");
    const install_rc = b.addInstallFile(rc_file, "shared-rc-fixture.wasm");
    b.step("shared-rc-fixture", "Generate checked retain/release execution laws").dependOn(&install_rc.step);
    const list_fixture = b.addExecutable(.{ .name = "list-runtime-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("src/list_runtime_fixture.zig"),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    const generate_list_fixture = b.addRunArtifact(list_fixture);
    const list_fixture_file = generate_list_fixture.addOutputFileArg("list-runtime-fixture.wasm");
    const install_list_fixture = b.addInstallFile(list_fixture_file, "list-runtime-fixture.wasm");
    b.step("list-runtime-fixture", "Generate list layout and sharing execution laws").dependOn(&install_list_fixture.step);
    const packed_fixture = b.addExecutable(.{ .name = "packed-layout-fixture", .root_module = b.createModule(.{
        .root_source_file = b.path("src/packed_layout_fixture.zig"),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    const generate_packed = b.addRunArtifact(packed_fixture);
    const packed_file = generate_packed.addOutputFileArg("packed-layout-fixture.wasm");
    const install_packed = b.addInstallFile(packed_file, "packed-layout-fixture.wasm");
    b.step("packed-layout-fixture", "Generate the experimental dense scalar row fixture").dependOn(&install_packed.step);
}
