//! Opaque physical carriers follow an independently checked dictionary owner.
//! These mappings never publish a concrete associated-type equation.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const C = @import("../check/package_contracts.zig");
const L = @import("layout.zig");
const Error = error{ InvalidArtifact, OutOfMemory, LayoutLimit, TypeMismatch, UnresolvedType };
fn step(remaining: *usize) Error!void {
    if (remaining.* == 0) return error.InvalidArtifact;
    remaining.* -= 1;
}
pub fn bind(allocator: std.mem.Allocator, module: *const core.Module, layouts: *L.Store, mappings: *std.ArrayList(L.Mapping), quantifier: T.Id, opening: core.BindingId, opened: T.List, declared: bool) Error!void {
    return bindOwner(allocator, module, layouts, mappings, .{ .quantified = quantifier }, opening, opened, declared);
}
pub fn bindOwner(allocator: std.mem.Allocator, module: *const core.Module, layouts: *L.Store, mappings: *std.ArrayList(L.Mapping), dictionary: @import("../check/dictionary_owner.zig").Owner, opening: core.BindingId, opened: T.List, declared: bool) Error!void {
    if (dictionary.count(module) == 0) return;
    const has_projection = for (module.types.nodes) |node| {
        if (node.tag == .projection) break true;
    } else false;
    if (!has_projection) return;
    var remaining: usize = 65_536;
    var scopes: C.Context = .{ .types = &module.types, .remaining = &remaining };
    try scopes.initialize();
    const formals = dictionary.formals(module);
    if (opening == 0) try dictionary.enter(module, &scopes) else switch (dictionary) {
        .quantified => |quantifier| try scopes.open(quantifier, opening, opened, module.binding(opening).ty),
        .scheme => return error.InvalidArtifact,
    }
    for (0..dictionary.count(module)) |ordinal| {
        const goal = dictionary.goal(module, ordinal);
        try step(&remaining);
        if (goal.kind != .contract) return error.InvalidArtifact;
        const declaration = for (module.contracts) |candidate| {
            if (std.meta.eql(candidate.identity, goal.identity)) break candidate;
        } else return error.InvalidArtifact;
        const tuple = module.types.node(goal.ty);
        if (tuple.tag != .product or tuple.b != declaration.parameters.len or declaration.variables.len > 128) return error.InvalidArtifact;
        const arguments = module.types.list(.{ .start = tuple.a, .len = tuple.b });
        var replacements: [128]T.Id = @splat(0);
        if (declared) {
            var selector: C.Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
            for (module.types.list(declaration.parameters), arguments) |parameter, argument| {
                try selector.substituted(declaration.variables, replacements[0..declaration.variables.len], parameter, argument);
                for (selector.witnesses[0..declaration.variables.len], 0..) |witness, index| replacements[index] = witness;
            }
        }
        for (module.types.nodes, 0..) |projection, id| {
            try step(&remaining);
            if (projection.tag != .projection or projection.a != goal.identity.unit or projection.b != goal.identity.decl) continue;
            const member = module.types.projectionMember(projection);
            const allowed = for (module.contract_members[declaration.members.start..][0..declaration.members.len]) |candidate| {
                if (candidate.name == member and candidate.kind != .value) break true;
            } else false;
            if (!allowed) continue;
            const actuals = module.types.nominalArguments(projection);
            if (actuals.len != arguments.len) continue;
            var matches = true;
            for (arguments, actuals) |argument, actual| {
                var comparison: C.Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
                if (declared) comparison.substituted(declaration.variables, replacements[0..declaration.variables.len], actual, argument) catch {
                    if (remaining == 0) return error.InvalidArtifact;
                    matches = false;
                    break;
                } else comparison.substituted(formals, module.types.list(opened), argument, actual) catch {
                    if (remaining == 0) return error.InvalidArtifact;
                    matches = false;
                    break;
                };
            }
            if (!matches) continue;
            const physical = try layouts.internAssociated(@intCast(try dictionary.canonicalGoal(module, ordinal, &scopes)), member, 0);
            var found = false;
            for (mappings.items) |mapping| if (mapping.variable == id) {
                if (mapping.layout != physical) return error.InvalidArtifact;
                found = true;
            };
            if (!found) try mappings.append(allocator, .{ .variable = @intCast(id), .layout = physical });
        }
    }
}
