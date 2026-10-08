//! Frozen source types with no variables can share an imported graph across
//! lexical scopes. Open types and open effect rows always keep scoped imports.
//! Facts belong to one immutable Core owner; imported answers belong to one
//! solver and are revoked by rollback or physical graph mutation.
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const A = std.mem.Allocator;

pub const Facts = struct {
    answers: std.AutoHashMapUnmanaged(u64, bool) = .empty,
    pub fn deinit(self: *Facts, a: A) void {
        self.answers.deinit(a);
    }
    pub fn key(owner: usize, ty: types.Id) u64 {
        return (@as(u64, @intCast(owner)) << 32) | ty;
    }
    pub fn closed(self: *Facts, a: A, units: []const core.Module, owner: usize, ty: types.Id, depth: usize) A.Error!bool {
        if (ty <= types.never) return ty != types.absent;
        if (depth >= 256) return false;
        const id = key(owner, ty);
        if (self.answers.get(id)) |known| return known;
        const source = &units[owner].types;
        const n = source.node(ty);
        const result: bool = switch (n.tag) {
            .absent, .variable => false,
            .unit, .boolean, .u32, .f32, .never, .type_constructor => true,
            .array, .list, .cursor, .resolver => try self.closed(a, units, owner, n.a, depth + 1),
            .function, .demand, .provider => try self.closed(a, units, owner, n.a, depth + 1) and
                (n.tag != .function or try self.closed(a, units, owner, n.b, depth + 1)) and
                try self.closedRow(a, units, owner, n.c, depth + 1),
            .state_provider => try self.closed(a, units, owner, n.a, depth + 1) and
                try self.closed(a, units, owner, n.b, depth + 1) and try self.closed(a, units, owner, n.c, depth + 1),
            .product, .nominal => blk: {
                const children = if (n.tag == .nominal) source.nominalArguments(n) else source.list(.{ .start = n.a, .len = n.b });
                for (children) |child| if (!try self.closed(a, units, owner, child, depth + 1)) break :blk false;
                break :blk true;
            },
            .record => blk: {
                for (0..n.b) |index| if (!try self.closed(a, units, owner, source.recordField(n, index).ty, depth + 1)) break :blk false;
                break :blk true;
            },
        };
        try self.answers.put(a, id, result);
        return result;
    }
    fn closedRow(self: *Facts, a: A, units: []const core.Module, owner: usize, row: types.Effects.Id, depth: usize) A.Error!bool {
        if (depth >= 256) return false;
        const source = &units[owner].types;
        if (source.row(row).tail != .closed) return false;
        for (source.rowLabels(row)) |label| {
            for (source.operationArguments(label)) |arg| if (!try self.closed(a, units, owner, arg, depth + 1)) return false;
        }
        return true;
    }
};

pub const Cache = struct {
    const Key = struct { source: u64, depth: usize };
    answers: std.AutoHashMapUnmanaged(Key, types.Id) = .empty,
    generation: u16 = 0,
    physical: u64 = 0,
    max_depth: usize = 0,

    pub fn deinit(self: *Cache, a: A) void {
        self.answers.deinit(a);
    }
    pub fn clearRetainingCapacity(self: *Cache) void {
        self.answers.clearRetainingCapacity();
        self.* = .{ .answers = self.answers };
    }
    pub fn activate(self: *Cache, solver: *const types.Store, max_depth: usize) bool {
        if (self.generation != solver.closed_generation or self.physical != solver.effects.physical_epoch or self.max_depth != max_depth) {
            self.answers.clearRetainingCapacity();
            self.generation = solver.closed_generation;
            self.physical = solver.effects.physical_epoch;
            self.max_depth = max_depth;
        }
        return self.generation != std.math.maxInt(u16) and self.physical != std.math.maxInt(u64);
    }
    pub fn key(owner: usize, ty: types.Id, depth: usize) Key {
        return .{ .source = Facts.key(owner, ty), .depth = depth };
    }
};
