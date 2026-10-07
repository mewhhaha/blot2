//! Copy the equation observed at a failed unification. This renderer reads an
//! already resolved solver graph, asks no semantic questions and keeps no IDs.
const std = @import("std");
const types = @import("types.zig");
const core = @import("core.zig");
const identity = @import("runtime_identity.zig");
const Allocator = std.mem.Allocator;

pub const Context = struct {
    units: []const core.Module,
    identity: ?identity.View = null,
    entry: u32 = 0,
    prelude: u32 = 0,
    source_mode: bool = false,
};
const Display = struct {
    allocator: Allocator,
    store: *const types.Store,
    context: Context,
    text: std.ArrayList(u8) = .empty,

    fn append(self: *Display, bytes: []const u8) Allocator.Error!void {
        try self.text.appendSlice(self.allocator, bytes);
    }
    fn number(self: *Display, value: u32) Allocator.Error!void {
        var buffer: [10]u8 = undefined;
        try self.append(std.mem.print(&buffer, "{d}", .{value}) catch unreachable);
    }
    fn nominal(self: *Display, owner: u32, declaration: u32) Allocator.Error!bool {
        const module = for (self.context.units, 0..) |*candidate, index| {
            const unit = if (candidate.unit == 0) @as(u32, @intCast(index + 1)) else candidate.unit;
            if (unit == owner) break candidate;
        } else return false;
        const item = for (module.nominals) |candidate| {
            if (candidate.identity.decl == declaration and (candidate.identity.unit == 0 or candidate.identity.unit == owner)) break candidate;
        } else return false;
        const name = module.name(item.diagnostic_name);
        if (name.len == 0) return false;
        var allocated_origin: ?[]u8 = null;
        defer if (allocated_origin) |origin| self.allocator.free(origin);
        const origin = if (self.context.identity) |current| scope: {
            if (owner == self.context.prelude and owner != 0) break :scope "std/prelude";
            if (self.context.source_mode and owner == self.context.entry) break :scope "main";
            const entry_path = current.owner(self.context.entry) orelse return false;
            const owner_path = current.owner(owner) orelse return false;
            const directory = std.Io.Dir.path.dirname(entry_path) orelse return false;
            allocated_origin = try std.Io.Dir.path.relativeAlloc(self.allocator, directory, null, directory, owner_path);
            break :scope allocated_origin.?;
        } else module.name(item.diagnostic_origin);
        if (origin.len == 0) return false;
        try self.append(origin);
        try self.append("::");
        try self.append(name);
        return true;
    }
    fn row(self: *Display, id: types.Effects.Id, depth: u8) Allocator.Error!bool {
        const value = self.store.row(id);
        const labels = self.store.rowLabels(id);
        if (labels.len == 0 and value.tail == .closed) return true;
        try self.append(" ! {");
        for (labels, 0..) |label, index| {
            if (index != 0) try self.append(", ");
            const operation = self.store.operation(label);
            if (!try self.nominal(operation.identity.unit, operation.identity.decl)) return false;
            for (self.store.operationArguments(label)) |argument| {
                try self.append(" (");
                if (!try self.ty(argument, depth)) return false;
                try self.append(")");
            }
        }
        switch (value.tail) {
            .closed => {},
            .variable => |variable| {
                // Dense solver IDs are reported honestly. A public namespace
                // mapping must be established separately, never guessed here.
                try self.append("| ?e");
                try self.number(variable);
            },
            .parameter => return false,
        }
        try self.append("}");
        return true;
    }
    fn ty(self: *Display, id: types.Id, depth: u8) Allocator.Error!bool {
        if (depth == 0) {
            try self.append("...");
            return true;
        }
        const value = self.store.node(id);
        switch (value.tag) {
            .unit => try self.append("Unit"),
            .boolean => try self.append("Bool"),
            .u32 => try self.append("U32"),
            .f32 => try self.append("F32"),
            .never => try self.append("Never"),
            .variable => {
                try self.append("?");
                try self.number(value.a);
            },
            .function => {
                try self.append("(");
                if (!try self.ty(value.a, depth - 1)) return false;
                try self.append(" -> ");
                if (!try self.ty(value.b, depth - 1) or !try self.row(value.c, depth - 1)) return false;
                try self.append(")");
            },
            .array, .list, .cursor => {
                try self.append(if (value.tag == .cursor) "Cursor (" else if (value.tag == .list) "List (" else "Array (");
                if (!try self.ty(value.a, depth - 1)) return false;
                try self.append(")");
            },
            .product => {
                try self.append("(");
                for (self.store.list(.{ .start = value.a, .len = value.b }), 0..) |child, index| {
                    if (index != 0) try self.append(", ");
                    if (!try self.ty(child, depth - 1)) return false;
                }
                try self.append(")");
            },
            .nominal => {
                if (!try self.nominal(value.a, value.b)) return false;
                for (self.store.nominalArguments(value)) |argument| {
                    try self.append(" (");
                    if (!try self.ty(argument, depth - 1)) return false;
                    try self.append(")");
                }
            },
            else => return false,
        }
        return true;
    }
};

pub fn render(allocator: Allocator, store: *const types.Store, context: Context, actual: types.Id, expected: types.Id) Allocator.Error!?[]u8 {
    var display: Display = .{ .allocator = allocator, .store = store, .context = context };
    defer display.text.deinit(allocator);
    try display.append("cannot unify ");
    if (!try display.ty(actual, 64)) return null;
    try display.append(" with ");
    if (!try display.ty(expected, 64)) return null;
    return try display.text.toOwnedSlice(allocator);
}
