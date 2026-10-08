const std = @import("std");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const ir = @import("resolved_scalar_ssa.zig");
const wasm = @import("wasm.zig");
const a = std.testing.allocator;

const source =
    \\entry const arithmetic = fn (value: U32) => @u32.add (@u32.mul value 3) (@u32.div 24 value)
    \\entry const floating = fn (value: F32) => @f32.div (-0.0) value
    \\entry const converted = fn (value: F32) => @f32.to_u32 value
    \\entry const branching = fn (value: U32) => if @u32.eq value 0 then 7 else @u32.div 24 value
    \\entry const nested = fn (value: U32) => @u32.add 1 (if @u32.eq value 0 then 7 else if @u32.eq value 1 then 8 else @u32.div 24 value)
;
const Fixture = struct {
    units: [1]core.Module,
    fn init() !Fixture {
        var pool: @import("symbols.zig").Pool = .{};
        defer pool.deinit(a);
        var tokens = try @import("lexer.zig").lex(a, source);
        defer tokens.deinit(a);
        var tree = try @import("parser.zig").parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try @import("check.zig").checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .units = .{try core.lower(a, &tree, &pool, &checked)} };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
    }
};
fn scenario(allocator: std.mem.Allocator, fixture: *const Fixture, expected: []const u8) !void {
    var policy = @import("execution_policy.zig").Policy.project;
    policy.resolve_scalar_bodies = true;
    var compiled = try backend.compileWithOptions(allocator, &fixture.units, 1, .{ .policy = policy, .retain_artifacts = true, .artifact_replay = true });
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.reuse.resolved_scalar_bodies >= 4);
    try std.testing.expect(compiled.reuse.resolved_scalar_values > compiled.reuse.resolved_scalar_bodies);
    try std.testing.expectEqualSlices(u8, expected, compiled.bytes);
}
test "resolved scalar SSA preserves exact Wasm, traps, float bits, fallback and allocation ownership" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var baseline = try backend.compileWithOptions(a, &fixture.units, 1, .{ .policy = .project, .retain_artifacts = true });
    defer baseline.deinit(a);
    try std.testing.expect(baseline.diagnostic == null);
    try scenario(a, &fixture, baseline.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{ &fixture, baseline.bytes });
}
test "resolved scalar SSA emits after checked source and solver owners are destroyed" {
    var body = blk: {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const unit = &fixture.units[0];
        const function = &unit.bodies[1];
        break :blk (try ir.resolve(a, unit, unit.bodyParameters(function), function.root)).?;
    };
    defer body.deinit(a);
    var module = wasm.Module.init(a);
    defer module.deinit();
    const function = try module.addFunction(&.{.i32}, .i32);
    try body.emit(&module, function);
    try module.exportFunction(function, "answer", .u32, .u32);
    const bytes = try module.assemble();
    defer a.free(bytes);
    try std.testing.expect(bytes.len > 8);
    var traps: usize = 0;
    for (body.nodes.items, 0..) |node, index| {
        for (node.operands[0..node.arity]) |operand| try std.testing.expect(@backingInt(operand) < index);
        if (node.may_trap) traps += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), traps);
}
