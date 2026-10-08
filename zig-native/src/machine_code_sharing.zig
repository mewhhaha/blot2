//! Fold identical private resolved functions. Source/evidence instances stay
//! distinct, as do their indirect-table slots. Only final Wasm function indexes
//! are shared. Exported function identities remain distinct host values.
const std = @import("std");
const wasm = @import("wasm.zig");
const keys = @import("runtime_function_key.zig");
const A = std.mem.Allocator;
const absent = std.math.maxInt(u32);

pub const Index = struct {
    allocator: A,
    canonical: []u32 = &.{},
    indexes: []u32 = &.{},
    unique: usize,

    pub fn init(a: A, module: *const wasm.Module, enabled: bool) (A.Error || error{ModuleTooLarge})!Index {
        const count = module.functions.items.len;
        if (count > std.math.maxInt(u32) - module.imports.items.len) return error.ModuleTooLarge;
        if (!enabled) return .{ .allocator = a, .unique = count };
        var result: Index = .{ .allocator = a, .unique = 0 };
        errdefer result.deinit();
        result.canonical = try a.alloc(u32, count);
        result.indexes = try a.alloc(u32, count);
        const next = try a.alloc(u32, count);
        defer a.free(next);
        const public = try a.alloc(bool, count);
        defer a.free(public);
        @memset(public, false);
        for (module.exports.items) |item| if (!item.global and item.index < count) {
            public[item.index] = true;
        };
        if (module.public_arena) {
            public[module.arena.?.allocate] = true;
            public[module.arena.?.reset] = true;
        }
        var buckets: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        defer buckets.deinit(a);
        for (module.functions.items, 0..) |body, id| {
            const fingerprint = if (public[id]) 0 else keys.hash(body);
            var candidate = if (public[id]) absent else buckets.get(fingerprint) orelse absent;
            while (candidate != absent) : (candidate = next[candidate]) {
                if (keys.equal(module.functions.items[candidate], body)) break;
            }
            if (candidate != absent) {
                result.canonical[id] = candidate;
                result.indexes[id] = result.indexes[candidate];
                continue;
            }
            result.canonical[id] = @intCast(id);
            result.indexes[id] = @intCast(result.unique);
            result.unique += 1;
            if (!public[id]) {
                const entry = try buckets.getOrPut(a, fingerprint);
                next[id] = if (entry.found_existing) entry.value_ptr.* else absent;
                entry.value_ptr.* = @intCast(id);
            }
        }
        return result;
    }
    pub fn deinit(self: *Index) void {
        self.allocator.free(self.canonical);
        self.allocator.free(self.indexes);
        self.* = undefined;
    }
    pub fn emits(self: Index, id: usize) bool {
        return self.canonical.len == 0 or self.canonical[id] == id;
    }
    pub fn function(self: Index, id: u32) u32 {
        return if (self.indexes.len == 0) id else self.indexes[id];
    }
};
