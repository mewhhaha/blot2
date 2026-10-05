//! Exact initializer purity reasons and source operation identities.
const std = @import("std");
const types = @import("types.zig");
const symbols = @import("symbols.zig");
pub const Witness = struct {
    identity: types.NominalIdentity,
    family: symbols.Symbol = 0,
    member: symbols.Symbol = 0,
    compound: bool = false,
    foreign: bool = false,
    specialized: bool = false,
    /// A raw scheme can identify an effect without carrying a source catalog.
    origin_unavailable: bool = false,
    /// Owned canonical display snapshot. Contains no source/store references.
    operation_name: ?[]const u8 = null,
    pub fn deinit(self: Witness, allocator: std.mem.Allocator) void {
        if (self.operation_name) |name| allocator.free(name);
    }
    pub fn clone(self: Witness, allocator: std.mem.Allocator) !Witness {
        var result = self;
        if (self.operation_name) |name| result.operation_name = try allocator.dupe(u8, name);
        return result;
    }
};
pub fn format(allocator: std.mem.Allocator, pool: *const symbols.Pool, module_name: []const u8, witness: Witness) ![]u8 {
    if (witness.operation_name) |name| return allocator.print("pure evaluation cannot perform {s}; sequence an operation with use inside a provider scope", .{name});
    if (witness.origin_unavailable) return error.OperationPurityOriginRequired;
    if (witness.specialized) return error.SpecializedPurityDisplayRequired;
    if (witness.foreign) return allocator.print("pure evaluation cannot perform blot:compiler::Foreign; sequence an operation with use inside a provider scope", .{});
    if (witness.family == 0) return error.OperationPurityOriginRequired;
    if (witness.compound) return allocator.print("pure evaluation cannot perform {s}::{s}.{s}; sequence an operation with use inside a provider scope", .{ module_name, pool.get(witness.family), pool.get(witness.member) });
    return allocator.print("pure evaluation cannot perform {s}::{s}; sequence an operation with use inside a provider scope", .{ module_name, pool.get(witness.family) });
}
