//! Executable admission adds exact body projections to the semantic gate.
//! The gate validates ordered catalogs/namespaces and transitive source reads;
//! every admitted declaration must additionally have byte-exact reachable Core,
//! lexical bindings, spans and auxiliary records. No principal-only proof is
//! promoted to executable validity. ID movement conservatively rebuilds code.
const std = @import("std");
const core = @import("../check/core.zig");
const artifacts = @import("code_artifacts.zig");
const identity = @import("../backend/runtime_identity.zig");
const principal = @import("principal_reuse_gate.zig");
const projection = @import("declaration_projection.zig");
pub const Gate = struct {
    semantic: principal.Gate,
    exact: []bool,
    pub fn init(a: std.mem.Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View, stamps: ?*artifacts.ModuleStamps) !Gate {
        var semantic = try principal.Gate.initWithStamps(a, old, units, names, stamps);
        errdefer semantic.deinit();
        const exact = try a.alloc(bool, semantic.dirty.len);
        errdefer a.free(exact);
        @memset(exact, false);
        if (semantic.enabled) for (units, old.modules, 1..) |*unit, pin, i| {
            for (unit.bindings, 0..) |binding, j| {
                if (binding.kind != .global or !semantic.admitsPrincipal(.{ .unit = @intCast(i), .binding = @intCast(j) })) continue;
                exact[semantic.offsets[i - 1] + j] = semantic.structural_units[i - 1] or try projection.definitionEqual(a, pin.module, unit, @intCast(j));
            }
        };
        return .{ .semantic = semantic, .exact = exact };
    }
    pub fn deinit(self: *Gate) void {
        self.semantic.allocator.free(self.exact);
        self.semantic.deinit();
    }
    pub fn body(self: *const Gate, target: core.BindingRef) bool {
        if (!self.semantic.admitsPrincipal(target)) return false;
        return self.exact[self.semantic.offsets[target.unit - 1] + target.binding];
    }
    /// A named body or lexical closure in one exact admitted declaration.
    /// This is executable ownership, never catalog-only identity.
    pub fn expressionRoot(self: *const Gate, unit: u32, root: core.Id) bool {
        if (!self.catalog(unit) or root == 0) return false;
        const module = &self.semantic.units[unit - 1];
        if (root >= module.nodes.len) return false;
        for (module.bodies) |body_| {
            if (body_.root == root and self.body(.{ .unit = unit, .binding = body_.binding })) return true;
        }
        for (module.closures, 0..) |closure, index| {
            if (closure.body != root) continue;
            if (self.semantic.structural_units[unit - 1]) return true;
            const owner = self.semantic.closure_owners[self.semantic.closure_offsets[unit - 1] + index];
            if (owner != 0 and self.body(.{ .unit = unit, .binding = owner })) return true;
        }
        return false;
    }
    pub fn catalog(self: *const Gate, unit: u32) bool {
        return self.semantic.enabled and unit != 0 and unit <= self.semantic.units.len;
    }
};
