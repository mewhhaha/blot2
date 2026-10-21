const std = @import("std");
const TestSuite = enum { all, syntax, types, runtime, checker, evaluator, backend, retained };

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
    const suite = b.option(TestSuite, "test-suite", "Native test subsystem (all, syntax, types, runtime, checker, evaluator, backend, retained)") orelse .all;
    const test_source = switch (suite) {
        .all => "src/production_suite.zig",
        .syntax => "src/syntax_suite.zig",
        .types => "src/types_suite.zig",
        .runtime => "src/runtime_suite.zig",
        .checker => "src/checker_suite.zig",
        .evaluator => "src/evaluator_suite.zig",
        .backend => "src/backend_suite.zig",
        .retained => "src/retained_suite.zig",
    };
    const tests = b.addTest(.{ .name = "blot-tests", .test_runner = .{ .path = b.path("src/test_runner.zig"), .mode = .simple }, .filters = b.option([]const []const u8, "test-filter", "filter") orelse &.{}, .root_module = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
    }), .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    tests.root_module.addImport("fixtures", b.createModule(.{
        .root_source_file = b.path("fixtures/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const test_options = b.addOptions();
    test_options.addOption(bool, "oom_profile", b.option(bool, "oom-profile", "Report allocation-failure sweep timings and counts") orelse false);
    tests.root_module.addOptions("test_options", test_options);
    const install_tests = b.addInstallArtifact(tests, .{});
    b.step("test-compile", "Compile and install the native test suite without executing it").dependOn(&install_tests.step);
    const test_step = b.step("test", "Test the handwritten compiler");
    test_step.dependOn(&install_tests.step);
    const shards = b.option(usize, "test-shards", "Number of isolated native execution processes") orelse 1;
    if (shards == 0) @panic("test-shards must be positive");
    const inventory = b.option(bool, "test-inventory", "List the compiled tests instead of executing them") orelse false;
    const force_run = b.option(bool, "test-force-run", "Execute native tests even when their run is cached") orelse false;
    for (0..shards) |shard| {
        const run_tests = b.addRunArtifact(tests);
        run_tests.expectExitCode(0);
        run_tests.setCwd(b.path(".."));
        run_tests.addArg(b.fmt("--shard={d}", .{shard}));
        run_tests.addArg(b.fmt("--shards={d}", .{shards}));
        if (inventory) run_tests.addArg("--list");
        run_tests.has_side_effects = force_run;
        test_step.dependOn(&run_tests.step);
    }
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run the source compiler").dependOn(&run.step);
    addRuntimeFixture(b, target, .arena, "arena-fixture", "Generate the memory/array ABI execution fixture");
    addRuntimeFixture(b, target, .shared_rc, "shared-rc-fixture", "Generate checked retain/release execution laws");
    addRuntimeFixture(b, target, .cohort, "cohort-fixture", "Generate bounded activation cohort protocol laws");
    addRuntimeFixture(b, target, .list, "list-runtime-fixture", "Generate list layout and sharing execution laws");
    addRuntimeFixture(b, target, .resource, "resource-retire-fixture", "Generate deferred owning resource retirement laws");
    addRuntimeFixture(b, target, .region, "region-owner-publication-fixture", "Generate region owner publication execution laws");
    addRuntimeFixture(b, target, .task_context, "task-context-fixture", "Generate suspendable task ownership context laws");
    addRuntimeFixture(b, target, .packed_layout, "packed-layout-fixture", "Generate the experimental dense scalar row fixture");
}

const RuntimeFixture = enum { arena, shared_rc, cohort, list, resource, region, task_context, packed_layout };
fn addRuntimeFixture(b: *std.Build, target: std.Build.ResolvedTarget, kind: RuntimeFixture, name: []const u8, description: []const u8) void {
    // Fixtures are build-time Wasm generators. Release optimization belongs to
    // blotc; keeping generators on the development backend also reuses its cache.
    const module = b.createModule(.{
        .root_source_file = b.path("src/fixture_main.zig"),
        .target = target,
        .optimize = .safe,
    });
    const options = b.addOptions();
    options.addOption(RuntimeFixture, "kind", kind);
    module.addOptions("fixture_options", options);
    const executable = b.addExecutable(.{ .name = name, .root_module = module, .use_llvm = false });
    const generate = b.addRunArtifact(executable);
    const filename = b.fmt("{s}.wasm", .{name});
    const output = generate.addOutputFileArg(filename);
    const install = b.addInstallFile(output, filename);
    b.step(name, description).dependOn(&install.step);
}
