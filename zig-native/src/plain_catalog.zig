//! A positive plain-data proof over validated immutable source catalogs.
//! A false answer means decline; it is never a reusable negative result.
//! This performs no evaluation, cache lookup, inference, publication or allocation.
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");

pub fn prove(units: []const core.Module, unit: u32, decl: u32, max_depth: usize) bool {
    var state: Walk = .{ .units = units, .max_depth = @min(max_depth, 1024) };
    return state.nominal(unit, decl, 0);
}

const Walk = struct {
    units: []const core.Module,
    max_depth: usize,
    remaining: usize = 65536,

    fn enter(self: *Walk, depth: usize) bool {
        if (depth >= self.max_depth or self.remaining == 0) return false;
        self.remaining -= 1;
        return true;
    }
    fn nominal(self: *Walk, unit: u32, decl: u32, depth: usize) bool {
        if (!self.enter(depth)) return false;
        const owner = for (self.units, 0..) |module, index| {
            if ((if (module.unit == 0) @as(u32, @intCast(index + 1)) else module.unit) == unit) break index;
        } else return false;
        const module = &self.units[owner];
        const definition = for (module.nominals) |candidate| {
            if (candidate.identity.decl == decl and (if (candidate.identity.unit == 0) unit else candidate.identity.unit) == unit) break candidate;
        } else return false;
        if (definition.constructors.len == 0) return false;
        for (module.extra[definition.constructors.start..][0..definition.constructors.len]) |constructor| {
            const payload = module.constructor(constructor).payload;
            if (payload != 0 and !self.data(owner, payload, definition.variables, depth + 1)) return false;
        }
        return true;
    }
    fn data(self: *Walk, owner: usize, id: types.Id, variables: types.List, depth: usize) bool {
        if (!self.enter(depth) or id == 0) return false;
        const module = &self.units[owner];
        const value = module.types.node(id);
        switch (value.tag) {
            .unit, .boolean, .u32, .f32, .never => return true,
            .variable => return std.mem.findScalar(types.Id, module.types.list(variables), id) != null,
            .array, .list, .cursor => return self.data(owner, value.a, variables, depth + 1),
            .product => for (module.types.list(.{ .start = value.a, .len = value.b })) |child| {
                if (!self.data(owner, child, variables, depth + 1)) return false;
            },
            .record => for (0..value.b) |index| {
                if (!self.data(owner, module.types.recordField(value, index).ty, variables, depth + 1)) return false;
            },
            .nominal => {
                for (module.types.nominalArguments(value)) |child| {
                    if (!self.data(owner, child, variables, depth + 1)) return false;
                }
                return self.nominal(if (value.a == 0) (if (module.unit == 0) @as(u32, @intCast(owner + 1)) else module.unit) else value.a, value.b, depth + 1);
            },
            else => return false,
        }
        return true;
    }
};
