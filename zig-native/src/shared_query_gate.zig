//! Internal source admission for one compileWithOptions epoch. The backend
//! supplies an already checked semantic Gate for its exact old/current pair.
//! This does not validate a new namespace, grant executable fragment validity,
//! or reuse admission across compilations. Both Core owners remain immutable.
const std = @import("std");
const core = @import("core.zig");
const artifacts = @import("code_artifacts.zig");
const Gate = @import("principal_reuse_gate.zig").Gate;

pub fn share(allocator: std.mem.Allocator, old: *const artifacts.Pools, units: []const core.Module, checked: *const Gate) ?Gate {
    if (checked.source_pools != old or checked.units.ptr != units.ptr or checked.units.len != units.len or checked.allocator.ptr != allocator.ptr or checked.allocator.vtable != allocator.vtable) return null;
    if (checked.structural_units.len != units.len or checked.offsets.len != units.len + 1 or checked.offsets[0] != 0 or checked.offsets[units.len] != checked.dirty.len) return null;
    for (units, 0..) |unit, i| {
        if (checked.offsets[i] > checked.offsets[i + 1] or checked.offsets[i + 1] - checked.offsets[i] != unit.bindings.len) return null;
    }
    // The immutable validation arrays are shared for this exact owner pair.
    // Consumers release independent leases; no graph-sized clone is needed.
    return checked.retain();
}

/// Logical bytes of the shared validation input (count once per owner).
pub fn validationBytes(gate: *const Gate) usize {
    return gate.structural_units.len * @sizeOf(bool) + gate.offsets.len * @sizeOf(usize) + gate.dirty.len * @sizeOf(bool);
}
