//! Recover a saturated call from ordinary application/method syntax. This is
//! source identity analysis, not a catalog of privileged function names.
const std = @import("std");
const core = @import("../check/core.zig");
pub const Call = struct {
    target: core.BindingRef,
    arguments: [16]core.Id = @splat(0),
    count: usize = 0,
    signature: @import("../check/types.zig").Id = 0,
};
pub fn resolve(units: []const core.Module, unit: u32, id: core.Id) ?Call {
    const m = &units[unit - 1];
    if (m.node(id).tag == .call) {
        const call = m.call(id);
        if (call.arguments.len > 16) return null;
        var result: Call = .{ .target = call.target, .count = call.arguments.len, .signature = call.callee_type };
        for (call.arguments, 0..) |argument, index| result.arguments[index] = argument;
        return result;
    }
    var result: Call = .{ .target = .{ .binding = 0 } };
    var reverse: [16]core.Id = undefined;
    var root = id;
    while (m.node(root).tag == .apply) {
        if (result.count == reverse.len) return null;
        reverse[result.count] = m.node(root).b;
        result.count += 1;
        root = m.node(root).a;
    }
    const n = m.node(root);
    if (n.tag == .reference) {
        const ref = m.reference(root);
        if (ref.unit == 0 and m.binding(ref.binding).kind != .global and m.binding(ref.binding).kind != .external) return null;
        result.target = ref;
        result.signature = n.ty;
    } else if (n.tag == .project) {
        if (result.count == reverse.len or m.projectionVariants(n.b).len != 0) return null;
        const ty = m.types.node(m.typeOf(n.a));
        // These structural types cannot have a competing record field. Nominal
        // fields use the ordinary ambiguity check in the emitter.
        if (ty.tag != .array and ty.tag != .list and ty.tag != .cursor) return null;
        const identity: @import("../check/types.zig").NominalIdentity = .{ .unit = 0, .decl = std.math.maxInt(u32) - @as(u32, if (ty.tag == .cursor) 2 else @intFromBool(ty.tag == .list)) };
        const projection = m.projection(n.b);
        result.target = for (m.associated) |method| {
            if (method.member == projection.field and std.meta.eql(method.identity, identity)) break method.target;
        } else return null;
        result.signature = m.dispatchSignature(root);
        reverse[result.count] = n.a;
        result.count += 1;
    } else return null;
    for (0..result.count) |i| result.arguments[i] = reverse[result.count - i - 1];
    return result;
}
/// The source body a saturated call reaches through imports and plain
/// function aliases, or null when it has a different arity.
pub const Wrapper = struct { target: core.BindingRef, body: core.Body };
pub fn wrapper(units: []const core.Module, owner: u32, call: Call) ?Wrapper {
    var target = call.target;
    if (target.unit == 0) target.unit = owner;
    for (0..16) |_| {
        if (target.unit == 0 or target.unit > units.len) return null;
        const source = &units[target.unit - 1];
        if (target.binding == 0 or target.binding >= source.bindings.len) return null;
        const binding = source.binding(target.binding);
        if (binding.kind == .external) {
            const previous = target.unit;
            target = binding.target;
            if (target.unit == 0) target.unit = previous;
            continue;
        }
        const body = source.body(target.binding) orelse return null;
        if (source.types.node(binding.ty).tag == .function and body.parameters.len == 0 and source.node(body.root).tag == .reference) {
            const previous = target.unit;
            target = source.reference(body.root);
            if (target.unit == 0) target.unit = previous;
            continue;
        }
        if (!body.is_function or body.parameters.len != call.count) return null;
        return .{ .target = target, .body = body.* };
    }
    return null;
}
/// The parameter position an operand reference names, marking it used. A
/// second use of the same parameter, or any other operand, has none.
pub fn parameterPosition(source: *const core.Module, unit: u32, parameters: []const core.Parameter, operand: core.Id, used: *u8) ?usize {
    if (source.node(operand).tag != .reference) return null;
    const reference = source.reference(operand);
    if (reference.unit != 0 and reference.unit != unit) return null;
    for (parameters, 0..) |parameter, index| if (parameter.binding != 0 and parameter.binding == reference.binding) {
        const bit = @as(u8, 1) << @intCast(index);
        if (used.* & bit != 0) return null;
        used.* |= bit;
        return index;
    };
    return null;
}
