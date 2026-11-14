const std = @import("std");
const TestSuite = enum { all, syntax, types, checker, project };

pub fn build(b: *std.Build) void {
    if (comptime @import("builtin").zig_version.order(.{ .major = 0, .minor = 17, .patch = 0 }) == .lt)
        @compileError("The native compiler requires Zig 0.17.0 or newer");
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});
    const llvm_option = b.option(bool, "llvm", "Use LLVM to build the compiler executable");
    const use_llvm: ?bool = if (llvm_option) |value| value else if (optimize == .debug) null else true;
    const error_tracing = b.option(bool, "error-tracing", "Enable compiler error-return traces for integration diagnostics");
    const identity = b.addOptions();
    identity.addOption(usize, "inference_budget", 1_000_000);
    var compiler_digest = @import("compiler_fingerprint.zig").digest(b, target, optimize, use_llvm) catch @panic("Cannot read compiler source identity");
    if (error_tracing) |enabled| {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(&compiler_digest);
        hash.update(if (enabled) "error-tracing=true" else "error-tracing=false");
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
        .error_tracing = error_tracing,
    });
    module.addOptions("compiler_identity", identity);
    // Profiling only: keep frame pointers and link libc dynamically, so a
    // preloaded sampling library can run inside the compiler and walk its stacks.
    if (b.option(bool, "profiling", "Build a dynamically linked compiler with frame pointers for sampling profilers") orelse false) {
        module.omit_frame_pointer = false;
        module.link_libc = true;
    }
    const exe = b.addExecutable(.{ .name = "blotc", .root_module = module, .use_llvm = use_llvm, .use_lld = if (use_llvm == true) true else null });
    b.installArtifact(exe);
    const suite = b.option(TestSuite, "test-suite", "Native test subsystem (all, syntax, types, checker, project)") orelse .all;
    const test_source = switch (suite) {
        .all => "src/tests.zig",
        .syntax => "src/syntax_suite.zig",
        .types => "src/types_suite.zig",
        .checker => "src/checker_suite.zig",
        .project => "src/project_suite.zig",
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
    const demand_inventory_module = b.createModule(.{
        .root_source_file = b.path("src/bench_declaration_demand.zig"),
        .target = target,
        .optimize = .safe,
    });
    const demand_inventory_exe = b.addExecutable(.{
        .name = "blot-demand-inventory",
        .root_module = demand_inventory_module,
        .use_llvm = false,
    });
    const install_demand_inventory = b.addInstallArtifact(demand_inventory_exe, .{});
    const demand_inventory = b.step("demand-inventory", "Inventory real project declaration demand before semantic checking");
    demand_inventory.dependOn(&install_demand_inventory.step);
}

