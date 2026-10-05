//! Internal source admission for one compileWithOptions epoch. The backend
//! supplies the already checked principal Gate for its exact old/current pair.
//! This does not validate a new namespace, grant executable fragment validity,
//! or reuse admission across compilations. Both Core owners remain immutable.
const std = @import("std");
const core = @import("core.zig");
const artifacts = @import("code_artifacts.zig");
const Gate = @import("principal_reuse_gate.zig").Gate;

pub fn clone(allocator: std.mem.Allocator, old: *const artifacts.Pools, units: []const core.Module, checked: *const Gate) std.mem.Allocator.Error!?Gate {
    if (checked.source_pools != old or checked.units.ptr != units.ptr or checked.units.len != units.len or checked.allocator.ptr != allocator.ptr or checked.allocator.vtable != allocator.vtable) return null;
    if (checked.structural_units.len != units.len or checked.offsets.len != units.len + 1 or checked.offsets[0] != 0 or checked.offsets[units.len] != checked.dirty.len) return null;
    for (units, 0..) |unit, i| {
        if (checked.offsets[i] > checked.offsets[i + 1] or checked.offsets[i + 1] - checked.offsets[i] != unit.bindings.len) return null;
    }
    const structural_units = try allocator.dupe(bool, checked.structural_units);
    errdefer allocator.free(structural_units);
    const offsets = try allocator.dupe(usize, checked.offsets);
    errdefer allocator.free(offsets);
    const dirty = try allocator.dupe(bool, checked.dirty);
    // No fallible work follows. The caller publishes this fully owned Gate at
    // the query State's final address before any Plan/scratch can bind to it.
    return .{ .allocator = allocator, .source_pools = old, .units = units, .enabled = checked.enabled, .declaration_principals = checked.declaration_principals, .structural_units = structural_units, .offsets = offsets, .dirty = dirty };
}

pub fn ownedBytes(gate: *const Gate) usize {
    return gate.structural_units.len * @sizeOf(bool) + gate.offsets.len * @sizeOf(usize) + gate.dirty.len * @sizeOf(bool);
}
