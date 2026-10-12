const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const archive = @import("backend_checkpoint.zig");
const a = std.testing.allocator;
const source =
    \\type Tick is effect = { read: Array U32 -> Array U32 }
    \\const work = @computation (fn () => do:
    \\  use value <- Tick.read #[41, 42]
    \\  return value
    \\)
    \\entry const run = fn (host: Array U32 -> Array U32 ! {Foreign}) => do:
    \\  let saved = #[90, 91]
    \\  for request in @requests work:
    \\    case request of
    \\      effect Tick.read value =>
    \\        use reply <- host value
    \\        saved := reply
    \\        yield saved
    \\      complete value =>
    \\        return value
;
const Fixture = struct {
    units: [1]core.Module,
    names: identity.Metadata,
    fn init() !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var module = try core.lower(a, &tree, &pool, &checked);
        errdefer module.deinit(a);
        module.unit = 1;
        return .{ .units = .{module}, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/suspended/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        self.names.deinit(a);
    }
    fn emit(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const @import("artifact_capture.zig").Capture, checkpoint: ?*const archive.Checkpoint) !backend.Result {
        return backend.compileWithOptions(allocator, &self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous, .checkpoint = checkpoint });
    }
};
fn admitted(bytes: []const u8) !void {
    const index = std.mem.findLast(u8, bytes, "blot:ownership") orelse return error.TestExpectedOwnership;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, bytes[index + "blot:ownership".len ..][0..3]);
}
fn scenario(allocator: std.mem.Allocator, fixture: *const Fixture, previous: ?*const @import("artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try fixture.emit(allocator, previous, null);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try admitted(result.bytes);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}

test "suspended ownership preserves immutable Core and fresh retained checkpoint and replay Wasm" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try admitted(first.bytes);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(33);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "suspended ownership preparation owns fresh and retained allocation failures" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{ &fixture, null, first.bytes });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{ &fixture, &first.capture.?, first.bytes });
}

test "suspended host admission requires exact generated namespace name and signature" {
    const w = @import("wasm.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    const correct = try module.importHostCallback(.{ .parameter = .array_u32, .result = .array_f32 });
    try std.testing.expectEqual(w.Callback{ .parameter = .array_u32, .result = .array_f32 }, module.hostCallbackImport(correct).?);
    const wrong_namespace = try module.importFunction("other", "call_array_u32_array_f32", &.{ .externref, .i32 }, .i32);
    const wrong_name = try module.importFunction("blot:host/1", "call_unknown_array_f32", &.{ .externref, .i32 }, .i32);
    const wrong_signature = try module.importFunction("blot:host/1", "call_u32_u32", &.{ .externref, .f32 }, .i32);
    inline for (.{ wrong_namespace, wrong_name, wrong_signature }) |id| try std.testing.expect(module.hostCallbackImport(id) == null);
}

fn borrowedHostFrames(allocator: std.mem.Allocator) !void {
    const w = @import("wasm.zig");
    const ir = @import("runtime_ir.zig");
    for (0..4) |scenario_| {
        var module = w.Module.init(allocator);
        defer module.deinit();
        const arena = try module.ensureArena();
        const references = try module.ensureHostReferences();
        var callback: w.Callback = .{ .parameter = .array_u32, .result = .u32 };
        if (scenario_ == 3) callback.result = .array_u32;
        const imported = try module.importHostCallback(callback);
        const function = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, callback.result.role());
        if (scenario_ != 2) try module.setParameterRoles(function, ir.packParameterRoles(&.{ .reference, .reference, .reference }));
        const marker: ir.Ownership = .{ .kind = .scope, .chunk = 14 };
        if (scenario_ != 1) try module.emit(function, .{ .op = .ownership, .operand = @bitCast(marker) });
        try module.emitSlice(function, &.{
            .{ .op = .local_get },               .{ .op = .global_get, .operand = references.active }, .{ .op = .i32_ne },
            .{ .op = .if_ },                     .{ .op = .unreachable_ },                             .{ .op = .end },
            .{ .op = .local_get },               .{ .op = .i32_load, .operand = 8 },                   .{ .op = .host_ref_get },
            .{ .op = .local_get, .operand = 1 }, .{ .op = .call_import, .operand = imported },
        });
        const owner = try module.addTypedFunction(&.{}, .i32, .reference);
        try module.emitSlice(owner, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.allocate_typed } });
        var pipeline = try @import("runtime_pipeline.zig").Session.init(allocator, &module);
        defer pipeline.deinit();
        try std.testing.expect(pipeline.roots);
        var transformed = try pipeline.optimize(&module.functions.items[function]);
        defer if (transformed) |*body| body.deinit(allocator);
        try std.testing.expectEqual(scenario_ != 0, transformed != null);
        if (transformed) |body| {
            var opened = false;
            for (body.instructions.items) |inst| if (inst.op == .call and inst.operand == arena.root_open) {
                opened = true;
            };
            try std.testing.expect(opened);
        }
    }
}
test "suspended scalar host stubs borrow checked arguments while unknown and owning returns retain frames through OOM" {
    try borrowedHostFrames(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, borrowedHostFrames, .{});
}

fn borrowedScalarFrames(allocator: std.mem.Allocator) !void {
    const w = @import("wasm.zig");
    const ir = @import("runtime_ir.zig");
    for (0..5) |scenario_| {
        var module = w.Module.init(allocator);
        defer module.deinit();
        const arena = try module.ensureArena();
        const target = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .scalar);
        try module.emit(target, .{ .op = .local_get, .operand = 1 });
        // A separate owned body activates the complete module journal route.
        const owner = try module.addTypedFunction(&.{}, .i32, .reference);
        try module.emitSlice(owner, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.allocate_typed } });
        const caller = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        try module.setParameterRoles(caller, ir.packParameterRoles(&.{.reference}));
        if (scenario_ == 4) {
            const hold: ir.Ownership = .{ .kind = .scope, .chunk = 5 };
            try module.emit(caller, .{ .op = .ownership, .operand = @bitCast(hold) });
        }
        if (scenario_ == 3) try module.emitSlice(caller, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .drop } });
        try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 42 }, .{ .op = .i32_const }, .{ .op = .i32_const, .operand = target, .table_reference = true } });
        var role = ir.Role.scalar;
        if (scenario_ == 1) role = .reference;
        if (scenario_ != 2) try module.emit(caller, ir.callResult(role));
        try module.emit(caller, .{ .op = .call_indirect, .operand = module.functions.items[target].signature });
        var pipeline = try @import("runtime_pipeline.zig").Session.init(allocator, &module);
        defer pipeline.deinit();
        try std.testing.expect(pipeline.roots);
        var transformed = try pipeline.optimize(&module.functions.items[caller]);
        defer if (transformed) |*body| body.deinit(allocator);
        var opened = false;
        if (transformed) |body| for (body.instructions.items) |inst| {
            if (inst.op == .call and inst.operand == arena.root_open) opened = true;
        };
        try std.testing.expectEqual(scenario_ != 0, opened);
    }
}
test "checked scalar indirect results borrow caller roots while owning unknown and published shapes retain frames through OOM" {
    try borrowedScalarFrames(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, borrowedScalarFrames, .{});
}

test "raw runtime exports remain partial instead of acquiring complete journal admission" {
    const w = @import("wasm.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    module.globals.items[arena.root_enabled].bits = @import("root_runtime.zig").enabled | @import("root_runtime.zig").complete;
    const owner = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emitSlice(owner, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.allocate_typed } });
    {
        var complete = try @import("runtime_pipeline.zig").Session.init(a, &module);
        defer complete.deinit();
        try std.testing.expect(complete.roots);
    }
    try module.exportFunction(arena.allocate_typed, "raw", .u32, .u32);
    var partial = try @import("runtime_pipeline.zig").Session.init(a, &module);
    defer partial.deinit();
    try std.testing.expect(!partial.roots);
    // Retained optimizer context names the same proof; raw exports cannot
    // borrow a previously admitted frame/flag encoding.
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .current = &capture });
    defer a.free(bytes);
    try std.testing.expect(!capture.roots);
}
