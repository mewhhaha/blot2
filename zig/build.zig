const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Transitional source migration; generated output is ordinary native Zig.
    // Python reads the retained algorithms but never invokes the Bend compiler.
    const generate = b.addSystemCommand(&.{ "python3", "tools/generate.py" });
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const executable = b.addExecutable(.{ .name = "blotc-zig", .root_module = module });
    executable.step.dependOn(&generate.step);
    b.installArtifact(executable);
    const tests = b.addTest(.{ .root_module = module });
    tests.step.dependOn(&generate.step);
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run native compiler and protocol tests").dependOn(&run_tests.step);
    const run = b.addRunArtifact(executable);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the native compiler process").dependOn(&run.step);
}
