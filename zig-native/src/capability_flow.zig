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

/// Owned formal relationship: a product retains input values; Unit invocation
/// returns the selected callback's result. Zero means unknown. No source/type
/// IDs or active authority enter this summary.
pub const ParameterResult = enum(u8) { product, invoke_unit, invalid };
pub const Parameters = struct {
    kind: ParameterResult = .product,
    mask: u16 = 0,
    inputs: u8 = 0,

    pub fn init(inputs: u8, mask: u16) Parameters {
        return .{ .mask = mask, .inputs = inputs };
    }
    pub fn result(self: Parameters) u16 {
        return self.mask;
    }
    pub fn arity(self: Parameters) u8 {
        return self.inputs;
    }
    pub fn valid(self: Parameters) bool {
        if (self.kind == .invalid) return false;
        const inputs = self.arity();
        if (inputs == 0) return self.kind == .product and self.result() == 0;
        if (inputs > 16) return false;
        const available: u32 = (@as(u32, 1) << @intCast(inputs)) - 1;
        if (self.result() & ~available != 0) return false;
        if (self.kind == .invoke_unit) return @popCount(self.result()) == 1;
        return true;
    }
    pub fn present(self: Parameters) bool {
        return self.arity() != 0;
    }
};

pub fn parameterSource(tree: *const ast.Tree, initial: ast.Id) Parameters {
    var names: [16]@import("symbols.zig").Symbol = undefined;
    var count: usize = 0;
    var expression = unwrap(tree, initial) orelse return .{};
    while (tree.node(expression).tag == .lambda) {
        if (count == names.len) return .{};
        const lambda = tree.node(expression);
        const parameter = tree.parameter(lambda.a);
        if (parameter.name == 0 or parameter.demanded or parameter.is_unit) return .{};
        names[count] = parameter.name;
        count += 1;
        expression = lambda.b;
    }
    expression = unwrap(tree, expression) orelse return .{};
    if (count == 0) return .{};
    var remaining: usize = 4096;
    const value = tree.node(expression);
    if (value.tag == .product or (value.tag == .record and value.a == 0)) {
        const result = sourceParameters(tree, expression, names[0..count], &remaining, 0) orelse return .{};
        return .init(@intCast(count), result);
    }
    if (count < 2 or value.tag != .apply) return .{};
    const argument = unwrap(tree, value.b) orelse return .{};
    if (tree.node(argument).tag != .unit) return .{};
    const callee = unwrap(tree, value.a) orelse return .{};
    if (tree.node(callee).tag != .name) return .{};
    const target = sourceParameters(tree, callee, names[0..count], &remaining, 0) orelse return .{};
    return .{ .kind = .invoke_unit, .inputs = @intCast(count), .mask = target };
}
fn sourceParameters(tree: *const ast.Tree, initial: ast.Id, names: []const @import("symbols.zig").Symbol, remaining: *usize, depth: usize) ?u16 {
    if (remaining.* == 0 or depth >= 64) return null;
    remaining.* -= 1;
    const source_id = unwrap(tree, initial) orelse return null;
    const value = tree.node(source_id);
    switch (value.tag) {
        .name => return parameterName(value.a, names),
        .field => {
            if (value.b == 0) return parameterName(value.a, names);
            return sourceParameters(tree, value.b, names, remaining, depth + 1);
        },
        .integer, .float, .boolean, .unit => return 0,
        .product, .record => {
            if (value.tag == .record and value.a != 0) return null;
            var result: u16 = 0;
            for (tree.children(source_id)) |child| result |= sourceParameters(tree, child, names, remaining, depth + 1) orelse return null;
            return result;
        },
        else => return null,
    }
}
fn parameterName(name: @import("symbols.zig").Symbol, names: []const @import("symbols.zig").Symbol) ?u16 {
    var index = names.len;
    while (index != 0) {
        index -= 1;
        if (name == names[index]) return @as(u16, 1) << @intCast(index);
    }
    return null;
}

/// A decoded claim proves a product of inputs/constants or one Unit callback
/// invocation. Bounds and exact parameter references precede every child read.
pub fn parameterCore(module: anytype, body: anytype, summary: Parameters) bool {
    if (!summary.valid() or !summary.present() or !body.is_function or body.parameters.len != summary.arity()) return false;
    if (body.parameters.start > module.parameters.len or body.parameters.len > module.parameters.len - body.parameters.start) return false;
    if (body.root == 0 or body.root >= module.nodes.len) return false;
    const root = module.nodes[body.root];
    var remaining: usize = 4096;
    const parameters = module.parameters[body.parameters.start..][0..body.parameters.len];
    if (summary.kind == .product) {
        if (root.tag != .product and root.tag != .record) return false;
        const result = coreParameters(module, body.root, parameters, &remaining, 0) orelse return false;
        return result == summary.result();
    }
    if (root.tag != .apply or root.b == 0 or root.b >= module.nodes.len) return false;
    const argument = module.nodes[root.b];
    if (argument.tag != .constant or argument.ty != @import("types.zig").unit or argument.a != 0) return false;
    if (root.a == 0 or root.a >= module.nodes.len or module.nodes[root.a].tag != .reference) return false;
    const target = coreParameters(module, root.a, parameters, &remaining, 0) orelse return false;
    return target == summary.result();
}
fn coreParameters(module: anytype, source_id: u32, parameters: anytype, remaining: *usize, depth: usize) ?u16 {
    if (remaining.* == 0 or depth >= 64 or source_id == 0 or source_id >= module.nodes.len) return null;
    remaining.* -= 1;
    const value = module.nodes[source_id];
    switch (value.tag) {
        .reference => {
            if (value.a >= module.references.len) return null;
            const reference = module.references[value.a];
            if (reference.unit != 0 and reference.unit != module.unit) return null;
            for (parameters, 0..) |parameter, index| if (reference.binding == parameter.binding) return @as(u16, 1) << @intCast(index);
            return null;
        },
        .constant => {
            if (value.ty >= module.types.nodes.len) return null;
            switch (module.types.nodes[value.ty].tag) {
                .unit, .boolean, .u32, .f32 => return 0,
                else => return null,
            }
        },
        .product, .record => {
            if (value.a > module.extra.len or value.b > module.extra.len - value.a) return null;
            var result: u16 = 0;
            for (module.extra[value.a..][0..value.b]) |child| result |= coreParameters(module, child, parameters, remaining, depth + 1) orelse return null;
            return result;
        },
        else => return null,
    }
}

test "parameter footprint domains preserve the maximum binder and reject forged masks" {
    const std = @import("std");
    try std.testing.expect(Parameters.init(16, 0xffff).valid());
    try std.testing.expect(!Parameters.init(17, 1).valid());
    try std.testing.expect(!Parameters.init(0, 1).valid());
    try std.testing.expect(!Parameters.init(1, 2).valid());
    try std.testing.expect(Parameters.init(3, 5).valid());
    try std.testing.expect(Parameters.init(3, 0).present());
    try std.testing.expect(!Parameters.init(0, 0).present());
    try std.testing.expect((Parameters{ .kind = .invoke_unit, .inputs = 16, .mask = 0x8000 }).valid());
    try std.testing.expect(!(Parameters{ .kind = .invoke_unit, .inputs = 3, .mask = 3 }).valid());
    try std.testing.expect(!(Parameters{ .kind = .invoke_unit, .inputs = 3 }).valid());
    try std.testing.expect(!(Parameters{ .kind = .invoke_unit }).valid());
    try std.testing.expect(!(Parameters{ .kind = .invalid, .inputs = 3, .mask = 1 }).valid());
}
