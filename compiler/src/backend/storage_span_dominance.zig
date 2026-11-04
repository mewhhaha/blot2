//! Continuing-path scopes for lazily validated immutable input descriptors.
//! Facts stay inside their original arm/block/loop; no join invents a fact.
const std = @import("std");
const ir = @import("runtime_ir.zig");

pub const Scopes = struct {
    cursor: usize = 0,
    function: ?u32 = null,
    active: std.ArrayList(bool) = .empty,
    stack: std.ArrayList(usize) = .empty,
    reset_pending: bool = true,

    pub fn deinit(self: *Scopes, a: std.mem.Allocator) void {
        self.active.deinit(a);
        self.stack.deinit(a);
    }
    pub fn reset(self: *Scopes) void {
        self.reset_pending = true;
    }
    fn enter(self: *Scopes, a: std.mem.Allocator) !void {
        try self.stack.ensureUnusedCapacity(a, 1);
        try self.active.append(a, true);
        self.stack.appendAssumeCapacity(self.active.items.len - 1);
    }
    fn leave(self: *Scopes) void {
        if (self.stack.pop()) |scope| self.active.items[scope] = false;
    }
    pub fn scan(self: *Scopes, a: std.mem.Allocator, function: u32, code: []const ir.Instruction) !void {
        if (self.reset_pending or self.function != function or self.cursor > code.len) {
            @memset(self.active.items, false);
            self.stack.clearRetainingCapacity();
            self.cursor = 0;
            self.function = function;
            self.reset_pending = false;
            try self.enter(a);
        }
        for (code[self.cursor..]) |inst| switch (inst.op) {
            .block, .loop, .if_ => try self.enter(a),
            .else_ => {
                self.leave();
                try self.enter(a);
            },
            .end => self.leave(),
            else => {},
        };
        self.cursor = code.len;
    }
    pub fn current(self: *const Scopes) ?usize {
        if (self.reset_pending or self.stack.items.len == 0) return null;
        return self.stack.items[self.stack.items.len - 1];
    }
    pub fn contains(self: *const Scopes, scope: ?usize) bool {
        if (self.reset_pending) return false;
        const id = scope orelse return false;
        return id < self.active.items.len and self.active.items[id];
    }
};

test "fixed span dominance retains incoming facts but never arm loop or block facts" {
    const a = std.testing.allocator;
    var scopes: Scopes = .{};
    defer scopes.deinit(a);
    const code = [_]ir.Instruction{
        .{ .op = .block },               .{ .op = .if_ }, .{ .op = .loop },
        .{ .op = .br_if, .operand = 2 }, .{ .op = .end }, .{ .op = .else_ },
        .{ .op = .end },                 .{ .op = .end }, .{ .op = .block },
        .{ .op = .end },
    };
    try scopes.scan(a, 1, &.{});
    const incoming = scopes.current();
    try scopes.scan(a, 1, code[0..1]);
    const block = scopes.current();
    try scopes.scan(a, 1, code[0..2]);
    const arm = scopes.current();
    try scopes.scan(a, 1, code[0..3]);
    const loop = scopes.current();
    try scopes.scan(a, 1, code[0..5]);
    try std.testing.expect(scopes.contains(incoming));
    try std.testing.expect(scopes.contains(arm));
    try std.testing.expect(!scopes.contains(loop));
    try scopes.scan(a, 1, code[0..6]);
    try std.testing.expect(!scopes.contains(arm));
    const other_arm = scopes.current();
    try scopes.scan(a, 1, code[0..8]);
    try std.testing.expect(!scopes.contains(other_arm));
    try std.testing.expect(!scopes.contains(block));
    try std.testing.expect(scopes.contains(incoming));
    try scopes.scan(a, 1, &code);
    try std.testing.expect(!scopes.contains(block));
    scopes.reset();
    try std.testing.expect(!scopes.contains(incoming));
    try scopes.scan(a, 1, code[0..1]);
    try std.testing.expect(!scopes.contains(incoming));
}

fn allocationLaw(a: std.mem.Allocator) !void {
    var scopes: Scopes = .{};
    defer scopes.deinit(a);
    const code = [_]ir.Instruction{ .{ .op = .block }, .{ .op = .if_ }, .{ .op = .else_ }, .{ .op = .end }, .{ .op = .end } };
    try scopes.scan(a, 1, code[0..2]);
    const arm = scopes.current();
    try scopes.scan(a, 1, &code);
    try std.testing.expect(!scopes.contains(arm));
    scopes.reset();
    try scopes.scan(a, 1, &code);
    try std.testing.expect(!scopes.contains(arm));
}

test "fixed span dominance scope allocations unwind through every allocation failure" {
    try allocationLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationLaw, .{});
}
