//! Selected scalar source adapters, such as U32.gt forwarding to U32.lt.
//! Only two-parameter, capture-free spines ending in one primitive qualify.
const core = @import("core.zig");
const facts = @import("function_facts.zig");
pub const Operation = struct {
    op: core.Op,
    reverse: bool = false,
    dependencies: [8]core.BindingRef = undefined,
    dependency_count: usize = 0,
};
pub fn analyze(units: []const core.Module, target: core.BindingRef) ?Operation {
    return visit(units, target, null, 8);
}
pub fn analyzeTyped(units: []const core.Module, target: core.BindingRef, machine: @import("wasm.zig").Scalar) ?Operation {
    return visit(units, target, machine, 8);
}
fn visit(units: []const core.Module, target_: core.BindingRef, machine: ?@import("wasm.zig").Scalar, remaining: usize) ?Operation {
    if (remaining == 0) return null;
    const target = normalize(units, target_, 8) orelse return null;
    const source = for (units, 0..) |*unit, index| {
        var logical = unit.unit;
        if (logical == 0) logical = @intCast(index + 1);
        if (logical == target.unit) break unit;
    } else return null;
    const body = source.body(target.binding) orelse return null;
    if (!body.is_function or body.parameters.len != 2) return null;
    const parameters = source.bodyParameters(body);
    const root = source.node(body.root);
    var args: [2]core.Id = undefined;
    var result: Operation = undefined;
    if (root.tag == .scalar and root.c == 0 and root.b != 0) {
        args = .{ root.a, root.b };
        result = .{ .op = root.op };
    } else if (root.tag == .call) {
        const call = source.call(body.root);
        if (call.arguments.len != 2) return null;
        var next = call.target;
        if (next.unit == 0) next.unit = target.unit;
        result = visit(units, next, machine, remaining - 1) orelse return null;
        args = call.arguments[0..2].*;
    } else if (root.tag == .associated or (root.tag == .scalar and root.c != 0)) {
        const scalar = machine orelse return null;
        const selected = associated(source, target.unit, scalar, root) orelse return null;
        result = visit(units, selected, machine, remaining - 1) orelse return null;
        args = .{ root.a, root.b };
    } else return null;
    var reverse = false;
    if (facts.local(source, args[0], parameters[0].binding) and facts.local(source, args[1], parameters[1].binding)) {
        reverse = false;
    } else if (facts.local(source, args[0], parameters[1].binding) and facts.local(source, args[1], parameters[0].binding)) {
        reverse = true;
    } else return null;
    result.reverse = result.reverse != reverse;
    result.dependencies[result.dependency_count] = target;
    result.dependency_count += 1;
    return result;
}
pub fn total(operation: Operation) bool {
    return operation.op != .div and operation.op != .rem and operation.op != .convert_f32_u32;
}

pub fn resolve(units: []const core.Module, target: core.BindingRef) ?core.BindingRef {
    return normalize(units, target, 8);
}
fn normalize(units: []const core.Module, target_: core.BindingRef, remaining: usize) ?core.BindingRef {
    if (remaining == 0) return null;
    const source = for (units, 0..) |*unit, index| {
        var logical = unit.unit;
        if (logical == 0) logical = @intCast(index + 1);
        if (logical == target_.unit) break unit;
    } else return null;
    if (target_.binding == 0 or target_.binding >= source.bindings.len) return null;
    const binding = source.binding(target_.binding);
    if (binding.kind != .external) return target_;
    var next = binding.target;
    if (next.unit == 0) next.unit = target_.unit;
    return normalize(units, next, remaining - 1);
}
fn associated(source: *const core.Module, origin: u32, scalar: @import("wasm.zig").Scalar, node: core.Node) ?core.BindingRef {
    const types = @import("types.zig");
    const decl = switch (scalar) {
        .u32 => types.u32_type,
        .f32 => types.f32_type,
        .bool => types.boolean,
        else => return null,
    };
    // Prepared call input facts fix the receiver. The spine forwards these
    // exact two scalar parameters; it never asks an untyped source dispatch.
    for (source.associated) |method| {
        if (method.identity.unit != 0 or method.identity.decl != decl) continue;
        if (node.tag == .associated) {
            if (method.member != node.c) continue;
        } else if (method.operator != operator(node.op)) continue;
        var target = method.target;
        if (target.unit == 0) target.unit = origin;
        return target;
    }
    return null;
}
fn operator(op: core.Op) @import("types.zig").Operator {
    return switch (op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .div,
        .rem => .rem,
        .equal => .equal,
        .not_equal => .not_equal,
        .less => .less,
        .less_equal => .less_equal,
        .greater => .greater,
        .greater_equal => .greater_equal,
        .bit_and => .bit_and,
        .bit_or => .bit_or,
        .bit_xor => .bit_xor,
        .shift_left => .shift_left,
        .shift_right => .shift_right,
        else => .none,
    };
}
