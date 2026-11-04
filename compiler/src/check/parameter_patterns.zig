//! Owned source-argument patterns. Semantic products alone cannot distinguish
//! an array pattern from a tuple pattern after source syntax is released.
const std = @import("std");
const T = @import("types.zig");
pub const Id = u32;
pub const List = T.List;
pub const Kind = enum(u8) { binding, tuple, array, record };
pub const Node = struct { kind: Kind, a: u32, b: u32 = 0 };
pub const Field = struct { name: u32, pattern: Id };

pub const Store = struct {
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(u32) = .empty,

    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
        self.extra.deinit(allocator);
        self.* = undefined;
    }
    pub fn node(self: *const Store, id: Id) Node {
        return self.nodes.items[id];
    }
    pub fn list(self: *const Store, span: List) []const Id {
        return self.extra.items[span.start..][0..span.len];
    }
    pub fn saveList(self: *Store, allocator: std.mem.Allocator, values: []const Id) T.Error!List {
        if (values.len > std.math.maxInt(u32) - self.extra.items.len) return error.TypeLimit;
        const start: u32 = @intCast(self.extra.items.len);
        try self.extra.appendSlice(allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    pub fn add(self: *Store, allocator: std.mem.Allocator, value: Node) T.Error!Id {
        if (self.nodes.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(allocator, value);
        return id;
    }
    pub fn sequence(self: *Store, allocator: std.mem.Allocator, kind: Kind, children: []const Id) T.Error!Id {
        std.debug.assert(kind == .tuple or kind == .array);
        const span = try self.saveList(allocator, children);
        return self.add(allocator, .{ .kind = kind, .a = span.start, .b = span.len });
    }
    pub fn record(self: *Store, allocator: std.mem.Allocator, fields: []const Field) T.Error!Id {
        if (fields.len > (std.math.maxInt(u32) - self.extra.items.len) / 2) return error.TypeLimit;
        const start: u32 = @intCast(self.extra.items.len);
        try self.extra.ensureUnusedCapacity(allocator, fields.len * 2);
        for (fields) |field_| self.extra.appendSliceAssumeCapacity(&.{ field_.name, field_.pattern });
        return self.add(allocator, .{ .kind = .record, .a = start, .b = @intCast(fields.len) });
    }
    pub fn field(self: *const Store, value: Node, index: usize) Field {
        std.debug.assert(value.kind == .record and index < value.b);
        return .{ .name = self.extra.items[value.a + index * 2], .pattern = self.extra.items[value.a + index * 2 + 1] };
    }
};
