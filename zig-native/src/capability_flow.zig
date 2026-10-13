//! Owned public footprint relationships, distinct from ordinary type/effect
//! headers. Exact admitted bodies have no captures or store sink. Identity
//! returns binder0; Unit invocation returns its callback's result. Capability
//! members and curried callbacks retain their input identity in effect rows.
//! Unknown relationships cannot license an authority transfer.
const ast = @import("ast.zig");
pub const Contract = enum(u8) { unknown, identity, invoke_unit, member_unit, invoke_with_capability, member_first_unit, member_second_unit };

pub fn source(tree: *const ast.Tree, initial: ast.Id) Contract {
    const expression = unwrap(tree, initial) orelse return .unknown;
    const lambda = tree.node(expression);
    if (lambda.tag != .lambda) return .unknown;
    const parameter = tree.parameter(lambda.a);
    if (parameter.name == 0 or parameter.demanded or parameter.is_unit) return .unknown;
    const body = unwrap(tree, lambda.b) orelse return .unknown;
    const value = tree.node(body);
    if (value.tag == .name and value.a == parameter.name) return .identity;
    if (value.tag != .apply) return .unknown;
    const callee = unwrap(tree, value.a) orelse return .unknown;
    const argument = unwrap(tree, value.b) orelse return .unknown;
    if (tree.node(callee).tag == .name and tree.node(callee).a == parameter.name and tree.node(argument).tag == .unit) return .invoke_unit;
    return .unknown;
}
fn unwrap(tree: *const ast.Tree, initial: ast.Id) ?ast.Id {
    var current = initial;
    for (0..128) |_| {
        if (current == 0 or current >= tree.nodes.items.len) return null;
        const value = tree.node(current);
        if (value.tag != .group) return current;
        current = value.a;
    }
    return null;
}

pub fn memberSource(tree: *const ast.Tree, pool: *const @import("symbols.zig").Pool, initial: ast.Id) bool {
    const expression = unwrap(tree, initial) orelse return false;
    const lambda = tree.node(expression);
    if (lambda.tag != .lambda) return false;
    const parameter = tree.parameter(lambda.a);
    if (parameter.name == 0 or parameter.demanded) return false;
    const body = unwrap(tree, lambda.b) orelse return false;
    const value = tree.node(body);
    if (value.tag != .apply) return false;
    const argument = unwrap(tree, value.b) orelse return false;
    if (tree.node(argument).tag != .unit) return false;
    const callee = tree.node(unwrap(tree, value.a) orelse return false);
    if (callee.tag == .field_access) {
        const receiver = tree.node(unwrap(tree, callee.a) orelse return false);
        return receiver.tag == .name and receiver.a == parameter.name;
    }
    if (callee.tag != .name) return false;
    const name = pool.get(callee.a);
    const input = pool.get(parameter.name);
    return name.len > input.len + 1 and @import("std").mem.startsWith(u8, name, input) and name[input.len] == '.';
}

pub fn curriedUnitSource(tree: *const ast.Tree, initial: ast.Id) bool {
    const expression = unwrap(tree, initial) orelse return false;
    const lambda = tree.node(expression);
    if (lambda.tag != .lambda) return false;
    const parameter = tree.parameter(lambda.a);
    if (parameter.name == 0 or parameter.demanded or parameter.is_unit) return false;
    return tree.node(lambda.b).tag == .lambda and source(tree, lambda.b) == .invoke_unit;
}

pub fn pairMemberSource(tree: *const ast.Tree, pool: *const @import("symbols.zig").Pool, initial: ast.Id) ?u8 {
    const outer = tree.node(unwrap(tree, initial) orelse return null);
    if (outer.tag != .lambda) return null;
    const inner = tree.node(outer.b);
    if (inner.tag != .lambda) return null;
    const left = tree.parameter(outer.a);
    const right = tree.parameter(inner.a);
    if (left.name == 0 or right.name == 0 or left.demanded or right.demanded or left.is_unit or right.is_unit) return null;
    const call = tree.node(unwrap(tree, inner.b) orelse return null);
    if (call.tag != .apply or tree.node(unwrap(tree, call.b) orelse return null).tag != .unit) return null;
    var receiver: @import("symbols.zig").Symbol = 0;
    const callee = tree.node(unwrap(tree, call.a) orelse return null);
    if (callee.tag == .field_access) {
        const root = tree.node(unwrap(tree, callee.a) orelse return null);
        if (root.tag == .name) receiver = root.a;
    } else if (callee.tag == .name) {
        const text = pool.get(callee.a);
        const separator = @import("std").mem.findScalarLast(u8, text, '.') orelse return null;
        receiver = pool.lookup(text[0..separator]) orelse return null;
    }
    // The inner binder shadows an identically named outer parameter.
    if (receiver == right.name) return 1;
    if (receiver == left.name) return 0;
    return null;
}
