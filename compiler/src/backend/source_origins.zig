//! Optional diagnostic origins. Seed a detached source view before optimization;
//! provenance never authorizes ownership, reuse or a semantic transformation.
const std = @import("std");
const core = @import("../check/core.zig");
const wasm = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const identity = @import("runtime_identity.zig");
const detached = @import("cohort_candidate.zig");
const A = std.mem.Allocator;
pub const max_sites = 65_536;
pub const Context = struct { unit: u32, node: u32, parent: u32 };
pub const ContextPool = struct {
    records: std.ArrayList(Context) = .empty,
    ids: std.AutoHashMapUnmanaged(Context, u32) = .empty,
    pub fn deinit(self: *ContextPool, a: A) void {
        self.records.deinit(a);
        self.ids.deinit(a);
    }
    pub fn intern(self: *ContextPool, a: A, value: Context) (A.Error || error{ModuleTooLarge})!u32 {
        if (self.ids.get(value)) |id| return id;
        if (self.records.items.len == max_sites) return error.ModuleTooLarge;
        try self.records.ensureUnusedCapacity(a, 1);
        const id: u32 = @intCast(self.records.items.len + 1);
        try self.ids.put(a, value, id);
        self.records.appendAssumeCapacity(value);
        return id;
    }
};
pub const Frame = struct { unit: u32 = 0, node: u32 = 0, start: u32 = 0, end: u32 = 0, filename: []const u8 = "" };
pub const Site = struct {
    unit: u32,
    node: u32,
    start: u32,
    end: u32,
    filename: []const u8,
    operation: []const u8 = "",
    source_type: []const u8 = "",
    source_blake3: ?[32]u8 = null,
    inline_context: [4]Frame = @splat(.{}),
    inline_depth: u8 = 0,
    inline_truncated: bool = false,
};
pub const View = struct {
    code: detached.Extension,
    sites: std.ArrayList(Site) = .empty,
    pub fn deinit(self: *View) void {
        self.sites.deinit(self.code.module.allocator);
        self.code.deinit();
    }
    /// Source units and path names remain borrowed from the compilation owner.
    /// Zero is deliberately reserved for unattributed runtime/generated work.
    pub fn init(a: A, source: *const wasm.Module, units: []const core.Module, names: ?identity.View, source_digests: []const [32]u8, contexts: []const Context) (A.Error || error{ModuleTooLarge})!View {
        var result: View = .{ .code = try detached.detached(a, source) };
        errdefer result.deinit();
        var indexes: std.AutoHashMapUnmanaged(Context, u21) = .empty;
        defer indexes.deinit(a);
        for (source.semantic_sites.items) |record| {
            if (record.unit == 0 or record.unit > units.len or record.node == 0) continue;
            const unit = &units[record.unit - 1];
            if (record.node >= unit.nodes.len or record.function >= source.functions.items.len) continue;
            if (record.place >= source.functions.items[record.function].instructions.items.len) continue;
            const key: Context = .{ .unit = record.unit, .node = record.node, .parent = record.diagnostic_context };
            const entry = try indexes.getOrPut(a, key);
            if (!entry.found_existing) {
                if (result.sites.items.len == max_sites) return error.ModuleTooLarge;
                const span = unit.span(record.node);
                try result.sites.append(a, .{ .source_blake3 = if (record.unit <= source_digests.len) source_digests[record.unit - 1] else null, .unit = record.unit, .node = record.node, .start = span.start, .end = span.end, .operation = @tagName(unit.node(record.node).tag), .source_type = @tagName(unit.types.node(unit.typeOf(record.node)).tag), .filename = if (names) |view| view.owner(record.unit) orelse "" else "" });
                entry.value_ptr.* = @intCast(result.sites.items.len);
                const site = &result.sites.items[result.sites.items.len - 1];
                var context = record.diagnostic_context;
                while (context != 0 and context <= contexts.len and site.inline_depth < site.inline_context.len) {
                    const frame = contexts[context - 1];
                    if (frame.unit == 0 or frame.unit > units.len or frame.node >= units[frame.unit - 1].nodes.len) break;
                    const location = units[frame.unit - 1].span(frame.node);
                    site.inline_context[site.inline_depth] = .{ .unit = frame.unit, .node = frame.node, .start = location.start, .end = location.end, .filename = if (names) |view| view.owner(frame.unit) orelse "" else "" };
                    site.inline_depth += 1;
                    context = frame.parent;
                }
                site.inline_truncated = context != 0;
            }
            const body = try result.code.own(record.function);
            body.instructions.items[record.place].origin = entry.value_ptr.*;
        }
        return result;
    }
};

/// Diagnostic fields must not affect equality used to select optimizations.
pub fn same(left: ir.Instruction, right: ir.Instruction) bool {
    var a = left;
    var b = right;
    a.origin = 0;
    b.origin = 0;
    return a == b;
}

fn propagation(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const producer = try module.addFunction(&.{.i32}, .i32);
    const value = try module.addLocal(producer, .i32);
    try module.emitSlice(producer, &.{
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .call, .operand = arena.allocate, .origin = 17 },
        .{ .op = .local_set, .operand = value },
        .{ .op = .local_get, .operand = value },
        .{ .op = .local_get },
        .{ .op = .i32_store },
        .{ .op = .local_get, .operand = value },
    });
    const caller = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = producer, .origin = 23 }, .{ .op = .i32_load } });
    var inlined = (try @import("wasm_inline.zig").run(a, &module, &module.functions.items[caller])).?;
    defer inlined.deinit(a);
    var found = false;
    for (inlined.instructions.items) |inst| if (inst.op == .call and inst.operand == arena.allocate) {
        try std.testing.expectEqual(@as(u21, 17), inst.origin);
        found = true;
    };
    try std.testing.expect(found);
    var function = module.functions.items[caller];
    function.locals = inlined.locals;
    function.instructions = inlined.instructions;
    var scalar = (try @import("wasm_sroa.zig").run(a, &module, &function)).?;
    defer scalar.deinit(a);
    for (scalar.instructions.items) |inst| try std.testing.expect(inst.op != .call);
    try std.testing.expectEqual(@as(u21, 23), module.functions.items[caller].instructions.items[1].origin);
}
test "diagnostic origins remain compact and follow surviving inlined allocations" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(ir.Instruction));
    try std.testing.expect(same(.{ .op = .i32_load, .origin = 1 }, .{ .op = .i32_load, .origin = 2 }));
    try propagation(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, propagation, .{});
}
