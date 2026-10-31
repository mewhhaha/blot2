//! Declaration-only structural field recipes for one immutable compilation.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const A = std.mem.Allocator;

/// The ordinal belongs to the source type's field list, not physical storage.
/// Apply ty under the current receiver environment on every use.
pub const Recipe = struct { index: u32, ty: T.Id };

const Key = struct {
    query_unit: u32,
    query_symbol: u32,
    receiver_unit: u32,
    record: T.Id,
};

/// Unit IDs and type/name tables must remain fixed for this cache's lifetime.
/// No caller substitutions, value facts or borrowed spelling bytes are retained.
pub const Cache = struct {
    allocator: A,
    entries: std.AutoHashMapUnmanaged(Key, ?Recipe) = .empty,
    maximum_entries: usize = 65_536,
    hits: u64 = 0,
    misses: u64 = 0,
    probes: u64 = 0,

    pub fn deinit(self: *Cache) void {
        self.entries.deinit(self.allocator);
    }

    pub fn get(self: *Cache, query: *const core.Module, name: u32, owner: *const core.Module, record: T.Id) A.Error!?Recipe {
        const key: Key = .{ .query_unit = query.unit, .query_symbol = name, .receiver_unit = owner.unit, .record = record };
        if (self.entries.get(key)) |recipe| {
            self.hits +|= 1;
            return recipe;
        }
        self.misses +|= 1;
        const recipe = self.lookup(query, name, owner, record);
        // Saturation declines metadata only; ordinary lookup keeps its result.
        if (self.entries.count() < self.maximum_entries) try self.entries.put(self.allocator, key, recipe);
        return recipe;
    }

    fn lookup(self: *Cache, query: *const core.Module, name: u32, owner: *const core.Module, record: T.Id) ?Recipe {
        const node = owner.types.node(record);
        if (node.tag != .record) return null;
        const spelling = query.fieldSpelling(name) orelse return null;
        for (0..node.b) |index| {
            self.probes +|= 1;
            const field = owner.types.recordField(node, index);
            const candidate = owner.fieldSpelling(field.name) orelse continue;
            if (std.mem.eql(u8, spelling, candidate)) return .{ .index = @intCast(index), .ty = field.ty };
        }
        // Immutable names/types make absence a declaration fact as well.
        return null;
    }
};
