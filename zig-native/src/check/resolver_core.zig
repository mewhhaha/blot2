//! Immutable resolver protocol owners shared by ordinary package and staged
//! calls. Selected arrows describe a use; declaration catalogs own dispatch.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const cross = @import("staging_type_match.zig");
pub const Error = error{InvalidArtifact};
fn require(condition: bool) Error!void {
    if (!condition) return error.InvalidArtifact;
}
pub fn owner(m: *const core.Module, units: []const *const core.Module, target: core.BindingRef) Error!*const core.Module {
    return ownerWorkspace(m, units, target, null);
}
pub fn ownerWorkspace(m: *const core.Module, units: []const *const core.Module, target: core.BindingRef, workspace: ?*@import("scheme_equations.zig").Workspace) Error!*const core.Module {
    if (target.unit == 0 or target.unit == m.unit) {
        try require(target.binding < m.bindings.len);
        return m;
    }
    var found: ?*const core.Module = null;
    for (units) |candidate| {
        if (candidate.unit != target.unit) continue;
        try require(found == null and target.binding < candidate.bindings.len);
        try @import("scheme_equations.zig").bounds(workspace, candidate, .{ .units = units });
        found = candidate;
    }
    return found orelse error.InvalidArtifact;
}
pub fn family(m: *const core.Module, id: core.Id) Error!T.NominalIdentity {
    const metadata = m.resolverInfo(id);
    var token = m.types.node(m.typeOf(metadata.resolver));
    if (metadata.operation != .monad) {
        try require(token.tag == .resolver and token.b == 0 and token.c == 0);
        token = m.types.node(token.a);
    }
    try require(token.tag == .type_constructor and token.c == 0);
    return .{ .unit = token.a, .decl = token.b };
}
pub fn shape(m: *const core.Module, id: core.Id) Error!void {
    const node = m.node(id);
    try require(node.tag == .resolver_op and node.b == 0 and node.c == 0 and node.op == .none);
    const metadata = m.resolverInfo(id);
    const identity = try family(m, id);
    const arguments = m.resolverArguments(id);
    const arity: usize = switch (metadata.operation) {
        .monad => 0,
        .pure, .forward, .run => 1,
        .bind, .iterate => 2,
    };
    try require(arguments.len == arity);
    const output = m.types.node(m.typeOf(id));
    if (metadata.operation == .monad) {
        try require(output.tag == .resolver and output.b == 0 and output.c == 0);
        const token = m.types.node(output.a);
        try require(token.tag == .type_constructor and token.a == identity.unit and token.b == identity.decl and token.c == 0);
    } else try require(output.tag == .nominal and output.a == identity.unit and output.b == identity.decl);
    if (metadata.operation == .monad or metadata.operation == .forward or metadata.operation == .run) try require(metadata.member == 0 and metadata.method.unit == 0 and metadata.method.binding == 0 and metadata.method_type == 0);
}
pub fn call(m: *const core.Module, units: []const *const core.Module, id: core.Id, remaining: *usize) Error!core.Call {
    return callWorkspace(m, units, id, remaining, null);
}
pub fn callWorkspace(m: *const core.Module, units: []const *const core.Module, id: core.Id, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!core.Call {
    if (m.node(id).tag == .call) return m.call(id);
    try require(m.node(id).tag == .resolver_op);
    try shape(m, id);
    const metadata = m.resolverInfo(id);
    try require(metadata.operation == .pure or metadata.operation == .bind or metadata.operation == .iterate);
    try require(metadata.member != 0 and metadata.method_type != 0);
    const identity = try family(m, id);
    const actual = try methodWorkspace(m, units, identity, metadata.member, remaining, workspace);
    if (metadata.method.binding != 0) {
        var selected = metadata.method;
        if (selected.unit == 0) selected.unit = m.unit;
        try require(std.meta.eql(selected, actual));
    }
    return .{ .target = actual, .callee_type = metadata.method_type, .arguments = m.resolverArguments(id) };
}

pub fn method(m: *const core.Module, units: []const *const core.Module, identity: T.NominalIdentity, member: u32, remaining: *usize) Error!core.BindingRef {
    return methodWorkspace(m, units, identity, member, remaining, null);
}
pub fn methodWorkspace(m: *const core.Module, units: []const *const core.Module, identity: T.NominalIdentity, member: u32, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!core.BindingRef {
    var nominal_owner = m;
    if (identity.unit != 0 and identity.unit != m.unit) {
        var found: ?*const core.Module = null;
        for (units) |unit| if (unit.unit == identity.unit) {
            try require(found == null);
            found = unit;
        };
        nominal_owner = found orelse return error.InvalidArtifact;
        try @import("scheme_equations.zig").bounds(workspace, nominal_owner, .{ .units = units });
    }
    var target: ?core.BindingRef = null;
    // The same origin-first/catalog fallback used by ordinary associated lookup.
    for ([_]*const core.Module{ m, nominal_owner }, 0..) |catalog, index| {
        if (index == 1 and catalog == m) continue;
        for (catalog.associated) |entry| {
            try require(remaining.* != 0);
            remaining.* -= 1;
            if (entry.member != member or entry.operator != .none or !cross.sameIdentity(catalog, entry.identity, m, identity)) continue;
            var selected = entry.target;
            if (selected.unit == 0) selected.unit = catalog.unit;
            const producer = try ownerWorkspace(m, units, selected, workspace);
            if (producer != m and producer.bindings[selected.binding].private) continue;
            if (target) |prior| try require(std.meta.eql(prior, selected));
            target = selected;
        }
        if (target != null) break;
    }
    return target orelse error.InvalidArtifact;
}

pub const Judgments = struct {
    factory: ?core.Obligation = null,
    dispatch: ?core.Obligation = null,
    result: ?core.Obligation = null,
    callback: core.Id = 0,
};
/// Read actual operand/type edges. Abstract protocol facts must be supplied by
/// an exact lexical scheme goal; concrete facts must select the real catalog.
pub fn judgments(m: *const core.Module, id: core.Id) Error!Judgments {
    const node = m.node(id);
    try require(node.tag == .resolver_op and node.op == .none and node.b == 0 and node.c == 0);
    const info = m.resolverInfo(id);
    const arguments = m.resolverArguments(id);
    var arity: usize = 1;
    if (info.operation == .monad) arity = 0;
    if (info.operation == .bind or info.operation == .iterate) arity = 2;
    try require(arguments.len == arity);
    const span = m.span(id);
    const provider = m.typeOf(info.resolver);
    var result: Judgments = .{};
    if (info.operation == .monad or info.operation == .forward or info.operation == .run) {
        try require(info.member == 0 and info.method.unit == 0 and info.method.binding == 0 and info.method_type == 0);
    } else {
        try require(info.member != 0 and info.method_type != 0);
        result.dispatch = .{ .kind = .resolver_dispatch, .ty = provider, .other = info.method_type, .result = node.ty, .name = info.member, .span = span };
    }
    if (info.operation == .monad) {
        result.factory = .{ .kind = .monad_factory, .ty = provider, .result = node.ty, .span = span };
    } else result.result = .{ .kind = .resolver_shape, .ty = provider, .result = node.ty, .span = span };
    if (info.operation == .run) result.callback = arguments[0];
    return result;
}

pub fn resolverIdentity(m: *const core.Module, resolver: T.Id) ?T.NominalIdentity {
    const provider = m.types.node(resolver);
    if (provider.tag != .resolver or provider.b != 0 or provider.c != 0) return null;
    const token = m.types.node(provider.a);
    if (token.tag != .type_constructor or token.c != 0) return null;
    return .{ .unit = token.a, .decl = token.b };
}
fn nominal(m: *const core.Module, units: []const *const core.Module, family_: T.NominalIdentity, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!core.Nominal {
    var producer = m;
    if (family_.unit != 0 and family_.unit != m.unit) {
        var found: ?*const core.Module = null;
        for (units) |unit| if (unit.unit == family_.unit) {
            try require(found == null);
            found = unit;
        };
        producer = found orelse return error.InvalidArtifact;
        try @import("scheme_equations.zig").bounds(workspace, producer, .{ .units = units });
    }
    var found: ?core.Nominal = null;
    for (producer.nominals) |entry| {
        try require(remaining.* != 0);
        remaining.* -= 1;
        if (!cross.sameIdentity(producer, entry.identity, m, family_)) continue;
        try require(found == null and (!entry.private or producer == m));
        found = entry;
    }
    return found orelse error.InvalidArtifact;
}
pub fn factory(m: *const core.Module, units: []const *const core.Module, goal: core.Obligation, remaining: *usize) Error!bool {
    return factoryWorkspace(m, units, goal, remaining, null);
}
pub fn factoryWorkspace(m: *const core.Module, units: []const *const core.Module, goal: core.Obligation, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!bool {
    try require(goal.kind == .monad_factory);
    const token = m.types.node(goal.ty);
    if (token.tag != .type_constructor or token.c != 0) return false;
    _ = try nominal(m, units, .{ .unit = token.a, .decl = token.b }, remaining, workspace);
    const actual = resolverIdentity(m, goal.result) orelse return false;
    return cross.sameIdentity(m, .{ .unit = token.a, .decl = token.b }, m, actual);
}
pub fn resultShape(m: *const core.Module, units: []const *const core.Module, goal: core.Obligation, remaining: *usize) Error!bool {
    return resultShapeWorkspace(m, units, goal, remaining, null);
}
pub fn resultShapeWorkspace(m: *const core.Module, units: []const *const core.Module, goal: core.Obligation, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!bool {
    try require(goal.kind == .resolver_shape);
    const family_ = resolverIdentity(m, goal.ty) orelse return false;
    const declaration = try nominal(m, units, family_, remaining, workspace);
    const output = m.types.node(goal.result);
    return output.tag == .nominal and cross.sameIdentity(m, family_, m, .{ .unit = output.a, .decl = output.b }) and m.types.nominalArguments(output).len == declaration.parameters.len;
}
/// A concrete operation's stored target must agree with the actual family
/// catalog. An abstract operation owns no numeric method target at all.
pub fn selectedCall(m: *const core.Module, units: []const *const core.Module, id: core.Id, remaining: *usize) Error!?core.Call {
    return selectedCallWorkspace(m, units, id, remaining, null);
}
pub fn selectedCallWorkspace(m: *const core.Module, units: []const *const core.Module, id: core.Id, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!?core.Call {
    const info = m.resolverInfo(id);
    _ = try judgments(m, id);
    if (resolverIdentity(m, m.typeOf(info.resolver))) |family_| {
        const actual = try methodWorkspace(m, units, family_, info.member, remaining, workspace);
        if (info.method.binding != 0) {
            var target = info.method;
            if (target.unit == 0) target.unit = m.unit;
            try require(std.meta.eql(actual, target));
        }
        return .{ .target = actual, .callee_type = info.method_type, .arguments = m.resolverArguments(id) };
    }
    try require(info.method.unit == 0 and info.method.binding == 0);
    return null;
}
