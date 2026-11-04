//! Exact immutable acyclic layout proofs behind the runtime `no_cycle` flag.
//! Data values are immutable: a value is built from existing values, and an
//! in-place write needs an owner that no other value reaches. Only State,
//! closures, demands, providers, cursors and erased or unknown shapes can
//! close a cycle, so they decline. Nominals of any unit check every
//! constructor of their defining unit, including unused variants. Executable
//! reuse requires equal type, nominal and constructor catalogs in every unit,
//! so a foreign definition edit re-emits each claim. Array and List edges
//! follow their element. Repeated layouts close a recursive type proof; they
//! do not assert runtime pointer uniqueness.
const std = @import("std");
const core = @import("../check/core.zig");
const layout = @import("layout.zig");

pub const depth_limit = 128;
pub const default_budget = 65536;

/// Whether every value of `ty` has an acyclic reachable strong structure under
/// every allowed mutation. An exhausted proof declines.
pub fn proven(store: *layout.Store, units: []const core.Module, ty: layout.Id) std.mem.Allocator.Error!bool {
    var active: [depth_limit]layout.Id = undefined;
    var budget: usize = default_budget;
    return within(store, units, ty, &active, 0, &budget);
}

/// `active` holds the layouts being proven; a repeated one closes a recursive
/// proof. Each visited layout and scanned constructor costs one unit of budget.
pub fn within(store: *layout.Store, units: []const core.Module, ty: layout.Id, active: []layout.Id, depth: usize, budget: *usize) std.mem.Allocator.Error!bool {
    if (depth >= active.len or budget.* == 0) return false;
    budget.* -= 1;
    if (std.mem.findScalar(layout.Id, active[0..depth], ty) != null) return true;
    active[depth] = ty;
    const n = store.node(ty);
    switch (n.tag) {
        .unit, .boolean, .u32, .f32, .never, .type_constructor, .resolver => return true,
        .array, .list => return within(store, units, n.a, active, depth + 1, budget),
        .product, .record => {
            const count = store.children(ty).len;
            var first: usize = 0;
            var step: usize = 1;
            if (n.tag == .record) {
                first = 1;
                step = 2;
            }
            var index = first;
            // A nominal payload below may intern layouts and move `children`.
            while (index < count) : (index += step) if (!try within(store, units, store.children(ty)[index], active, depth + 1, budget)) return false;
            return true;
        },
        .nominal => {
            // Builtin State, Computation and task families have no source unit.
            if (n.a == 0 or n.a > units.len) return false;
            const source = &units[n.a - 1];
            var found = false;
            for (source.constructors) |constructor| {
                if (budget.* == 0) return false;
                budget.* -= 1;
                const nominal = source.nominal(constructor.nominal);
                if (nominal.identity.unit != n.a or nominal.identity.decl != n.b) continue;
                found = true;
                if (constructor.payload == 0) continue;
                const parameters = source.types.list(nominal.parameters);
                const arguments = store.children(ty);
                if (parameters.len != arguments.len or parameters.len > 32) return false;
                var mappings: [32]layout.Mapping = undefined;
                for (parameters, arguments, 0..) |parameter, argument, index| {
                    if (source.types.node(parameter).tag != .variable) return false;
                    mappings[index] = .{ .variable = parameter, .layout = argument };
                }
                const payload = store.fromTypePartial(source, constructor.payload, mappings[0..parameters.len]) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return false;
                };
                if (!try within(store, units, payload, active, depth + 1, budget)) return false;
            }
            return found;
        },
        else => return false,
    }
}
