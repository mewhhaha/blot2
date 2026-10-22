//! Owned public footprint relationships, distinct from ordinary type/effect
//! headers. Exact admitted bodies have no captures or store sink. Identity
//! returns binder0; Unit invocation returns its callback's result. Capability
//! members and curried callbacks retain their input identity in effect rows.
//! Unknown relationships cannot license an authority transfer.
const ast = @import("../parse/ast.zig");
pub const Contract = enum(u8) { unknown, identity, invoke_unit, member_unit, invoke_with_capability, member_first_unit, member_second_unit, input_shape };

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

pub fn memberSource(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id) bool {
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

pub fn pairMemberSource(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id) ?u8 {
    const outer = tree.node(unwrap(tree, initial) orelse return null);
    if (outer.tag != .lambda) return null;
    const inner = tree.node(outer.b);
    if (inner.tag != .lambda) return null;
    const left = tree.parameter(outer.a);
    const right = tree.parameter(inner.a);
    if (left.name == 0 or right.name == 0 or left.demanded or right.demanded or left.is_unit or right.is_unit) return null;
    const call = tree.node(unwrap(tree, inner.b) orelse return null);
    if (call.tag != .apply or tree.node(unwrap(tree, call.b) orelse return null).tag != .unit) return null;
    var receiver: @import("../parse/symbols.zig").Symbol = 0;
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
pub const ParameterResult = enum(u8) { product, invoke_unit, invalid, member_closure_unit, captured_unit, invoke_input, invoke_inputs };
pub const Parameters = struct {
    kind: ParameterResult = .product,
    // invoke_input stores callback/input ordinals in the low/high nibble;
    // every other discriminator retains its positional result mask.
    mask: u16 = 0,
    inputs: u8 = 0,
    invocation_arguments: u64 = 0,
    invocation_count: u8 = 0,

    pub fn init(inputs: u8, mask: u16) Parameters {
        return .{ .mask = mask, .inputs = inputs };
    }
    pub fn result(self: Parameters) u16 {
        if (self.kind == .invoke_input) return @as(u16, 1) << @intCast(self.callback());
        return self.mask;
    }
    pub fn invokes(self: Parameters) bool {
        return self.kind == .invoke_unit or self.inputInvokes();
    }
    pub fn inputInvokes(self: Parameters) bool {
        return self.kind == .invoke_input or self.kind == .invoke_inputs;
    }
    pub fn argumentCount(self: Parameters) u8 {
        if (self.kind == .invoke_input) return 1;
        if (self.kind == .invoke_inputs) return self.invocation_count;
        return 0;
    }
    pub fn argumentAt(self: Parameters, index: usize) u8 {
        if (self.kind == .invoke_input) return self.argument();
        return @intCast((self.invocation_arguments >> @intCast(index * 4)) & 15);
    }
    pub fn callback(self: Parameters) u8 {
        if (self.kind == .invoke_input) return @intCast(self.mask & 15);
        return @intCast(@ctz(self.mask));
    }
    pub fn argument(self: Parameters) u8 {
        return @intCast((self.mask >> 4) & 15);
    }
    pub fn arity(self: Parameters) u8 {
        return self.inputs;
    }
    pub fn valid(self: Parameters) bool {
        if (@backingInt(self.kind) > @backingInt(ParameterResult.invoke_inputs)) return false;
        if (self.kind == .invalid) return false;
        if (self.kind != .invoke_inputs and (self.invocation_arguments != 0 or self.invocation_count != 0)) return false;
        if (self.kind == .invoke_inputs) {
            if (self.inputs == 0 or self.inputs > 16 or @popCount(self.mask) != 1 or self.callback() >= self.inputs or self.invocation_count < 2 or self.invocation_count > 16) return false;
            if (self.invocation_count != 16 and self.invocation_arguments >> @intCast(self.invocation_count * 4) != 0) return false;
            for (0..self.invocation_count) |index| {
                const selected = self.argumentAt(index);
                if (selected >= self.inputs or selected == self.callback()) return false;
            }
            return true;
        }
        const inputs = self.arity();
        if (inputs == 0) return self.kind == .product and self.result() == 0;
        if (inputs > 16) return false;
        if (self.kind == .invoke_input) return self.mask <= 255 and self.callback() < inputs and self.argument() < inputs and self.callback() != self.argument();
        if ((self.kind == .member_closure_unit or self.kind == .captured_unit) and inputs == 16) return false;
        const available: u32 = (@as(u32, 1) << @intCast(inputs)) - 1;
        if (self.result() & ~available != 0) return false;
        if (self.kind == .invoke_unit or self.kind == .member_closure_unit) return @popCount(self.result()) == 1;
        return true;
    }
    pub fn present(self: Parameters) bool {
        return self.arity() != 0;
    }
};

pub fn parameterArity(tree: *const ast.Tree, initial: ast.Id, annotation_: ast.Id) u8 {
    var source_id = initial;
    var count: u8 = 0;
    var signature = annotation_;
    var transparent = annotation_ == 0;
    for (0..128) |_| {
        if (signature == 0) break;
        const written = tree.node(signature);
        if (written.tag == .type_usage) signature = written.b else if (written.tag == .type_forall) signature = tree.extra.items[written.c] else if (written.tag == .type_effect) signature = written.a else break;
    }
    while (true) {
        if (!transparent and tree.node(source_id).tag == .group) break;
        source_id = unwrap(tree, source_id) orelse return 0;
        const lambda = tree.node(source_id);
        if (lambda.tag != .lambda) break;
        const parameter = tree.parameter(lambda.a);
        if (parameter.is_unit and count != 0) return 0;
        if (count == 16 or (parameter.name == 0 and !parameter.is_unit) or parameter.demanded) return 0;
        count += 1;
        source_id = lambda.b;
        var result = lambda.c;
        if (signature != 0 and tree.node(signature).tag == .type_function) signature = tree.node(signature).b;
        if (result == 0) result = signature;
        if (result != 0 and tree.node(result).tag == .type_effect) result = tree.node(result).a;
        if (result != 0 and (tree.node(result).tag == .type_usage or tree.node(result).tag == .type_forall)) break;
        transparent = annotation_ == 0 and lambda.c == 0;
    }
    return count;
}

pub fn parameterSource(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id, annotation_: ast.Id) Parameters {
    return parameterSourceWithContracts(tree, pool, initial, annotation_, null);
}
pub const SourceContracts = struct {
    context: *const anyopaque,
    lookup: *const fn (*const anyopaque, ast.Id) ?Parameters,
};
pub fn parameterSourceWithContracts(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id, annotation_: ast.Id, contracts: ?SourceContracts) Parameters {
    var names: [16]@import("../parse/symbols.zig").Symbol = undefined;
    var count: usize = 0;
    var expression = unwrap(tree, initial) orelse return .{};
    // Core flattens unannotated curried headers through source groups.
    // Annotated callable results may retain usage/rank boundaries; their
    // groups continue to mark returned closures until a checked header owns
    // the exact boundary.
    var transparent_groups = annotation_ == 0;
    var signature = annotation_;
    for (0..128) |_| {
        if (signature == 0) break;
        const written = tree.node(signature);
        if (written.tag == .type_usage) signature = written.b else if (written.tag == .type_forall) signature = tree.extra.items[written.c] else if (written.tag == .type_effect) signature = written.a else break;
    }
    while (true) {
        if (!transparent_groups and tree.node(expression).tag == .group) break;
        expression = unwrap(tree, expression) orelse return .{};
        const lambda = tree.node(expression);
        if (lambda.tag != .lambda) break;
        const parameter = tree.parameter(lambda.a);
        if (parameter.is_unit and !parameter.demanded and count != 0) {
            // The backend's sixteen parameters include the final Unit binder.
            if (count == names.len) return capturedSource(tree, pool, expression, names[0..count]);
            const member = unwrap(tree, lambda.b) orelse return capturedSource(tree, pool, expression, names[0..count]);
            const call = tree.node(member);
            if (call.tag != .apply or tree.node(unwrap(tree, call.b) orelse return .{}).tag != .unit) return capturedSource(tree, pool, expression, names[0..count]);
            const callee = tree.node(unwrap(tree, call.a) orelse return .{});
            var receiver: @import("../parse/symbols.zig").Symbol = 0;
            if (callee.tag == .field_access) {
                const root = tree.node(unwrap(tree, callee.a) orelse return .{});
                if (root.tag != .name) return capturedSource(tree, pool, expression, names[0..count]);
                receiver = root.a;
            } else if (callee.tag == .name) {
                const name = pool.get(callee.a);
                const separator = @import("std").mem.findScalarLast(u8, name, '.') orelse return capturedSource(tree, pool, expression, names[0..count]);
                receiver = pool.lookup(name[0..separator]) orelse return capturedSource(tree, pool, expression, names[0..count]);
            } else return capturedSource(tree, pool, expression, names[0..count]);
            const selected = parameterName(receiver, names[0..count]) orelse return capturedSource(tree, pool, expression, names[0..count]);
            return .{ .kind = .member_closure_unit, .inputs = @intCast(count), .mask = selected };
        }
        if (count == names.len) return .{};
        if (parameter.name == 0 or parameter.demanded or parameter.is_unit) return .{};
        names[count] = parameter.name;
        count += 1;
        expression = lambda.b;
        var result = lambda.c;
        if (signature != 0 and tree.node(signature).tag == .type_function) signature = tree.node(signature).b;
        if (result == 0) result = signature;
        if (result != 0 and tree.node(result).tag == .type_effect) result = tree.node(result).a;
        if (result != 0 and (tree.node(result).tag == .type_usage or tree.node(result).tag == .type_forall)) break;
        transparent_groups = annotation_ == 0 and lambda.c == 0;
    }
    expression = unwrap(tree, expression) orelse return .{};
    if (count == 0) return .{};
    var remaining: usize = 4096;
    var bindings: SourceBindings = .{};
    for (names[0..count], 0..) |name, index| bindings.bind(name, @as(u16, 1) << @intCast(index)) catch return .{};
    if (sourceInvocation(tree, expression, &bindings, @intCast(count), contracts, &remaining, 0)) |invocation| return invocation;
    const result = sourceParameters(tree, pool, expression, &bindings, &remaining, 0) orelse return .{};
    return .init(@intCast(count), result);
}

fn invocationResult(inputs: u8, callback: u16, arguments: []const u16, unit: bool) ?Parameters {
    if (@popCount(callback) != 1 or arguments.len > 16) return null;
    if (unit) return .{ .kind = .invoke_unit, .inputs = inputs, .mask = callback };
    if (arguments.len == 0) return null;
    var selected: u64 = 0;
    for (arguments, 0..) |argument, index| {
        if (@popCount(argument) != 1 or argument == callback) return null;
        selected |= @as(u64, @ctz(argument)) << @intCast(index * 4);
    }
    var result: Parameters = .{ .kind = .invoke_inputs, .inputs = inputs, .mask = callback, .invocation_arguments = selected, .invocation_count = @intCast(arguments.len) };
    if (arguments.len == 1) result = .{ .kind = .invoke_input, .inputs = inputs, .mask = @ctz(callback) | (@as(u16, @intCast(selected)) << 4) };
    if (!result.valid()) return null;
    return result;
}

fn sourceInvocation(tree: *const ast.Tree, initial: ast.Id, bindings: *const SourceBindings, inputs: u8, contracts: ?SourceContracts, remaining: *usize, depth: usize) ?Parameters {
    if (remaining.* == 0 or depth >= 128) return null;
    remaining.* -= 1;
    var head = unwrap(tree, initial) orelse return null;
    var reverse: [16]ast.Id = undefined;
    var count: usize = 0;
    while (tree.node(head).tag == .apply) {
        if (count == reverse.len) return null;
        reverse[count] = tree.node(head).b;
        count += 1;
        head = unwrap(tree, tree.node(head).a) orelse return null;
    }
    if (count == 0 or tree.node(head).tag != .name) return null;
    if (bindings.get(tree.node(head).a)) |callback| {
        var arguments: [16]u16 = undefined;
        if (count == 1 and tree.node(unwrap(tree, reverse[0]) orelse return null).tag == .unit) return invocationResult(inputs, callback, &.{}, true);
        for (0..count) |index| {
            const argument = tree.node(unwrap(tree, reverse[count - index - 1]) orelse return null);
            if (argument.tag != .name) return null;
            arguments[index] = bindings.get(argument.a) orelse return null;
        }
        return invocationResult(inputs, callback, arguments[0..count], false);
    }
    if (contracts) |catalog| if (catalog.lookup(catalog.context, head)) |contract| {
        if (!contract.valid() or !contract.invokes() or contract.arity() != count) return null;
        var actuals: [16]u16 = undefined;
        for (0..count) |index| {
            const actual = tree.node(unwrap(tree, reverse[count - index - 1]) orelse return null);
            if (actual.tag != .name) return null;
            actuals[index] = bindings.get(actual.a) orelse return null;
        }
        var selected: [16]u16 = undefined;
        for (0..contract.argumentCount()) |index| selected[index] = actuals[contract.argumentAt(index)];
        return invocationResult(inputs, actuals[contract.callback()], selected[0..contract.argumentCount()], contract.kind == .invoke_unit);
    };
    if (remaining.* < tree.roots.items.len) return null;
    remaining.* -= tree.roots.items.len;
    const call = localSourceCall(tree, initial) orelse return null;
    var nested: SourceBindings = .{};
    for (call.arguments[0..call.len], call.parameters[0..call.len]) |argument, formal| {
        const node = tree.node(unwrap(tree, argument) orelse return null);
        if (node.tag != .name) return null;
        nested.bind(formal, bindings.get(node.a) orelse return null) catch return null;
    }
    return sourceInvocation(tree, call.body, &nested, inputs, contracts, remaining, depth + 1);
}
/// Trusted constructors retain their explicit inputs without invoking a sink.
/// Their decoded Core counterparts prove the same owner edges independently.
pub const Construction = struct {
    kind: enum { computation, provider, state },
    inputs: [3]ast.Id = @splat(0),
    len: usize,
};
pub fn constructionSource(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id) ?Construction {
    var reverse: [3]ast.Id = undefined;
    var count: usize = 0;
    var head = initial;
    for (0..128) |_| {
        head = unwrap(tree, head) orelse return null;
        const node = tree.node(head);
        if (node.tag != .apply) break;
        if (count == reverse.len) return null;
        reverse[count] = node.b;
        count += 1;
        head = node.a;
    } else return null;
    const node = tree.node(head);
    if (node.tag != .intrinsic) return null;
    const name = pool.get(node.a);
    const std = @import("std");
    var kind: @FieldType(Construction, "kind") = .computation;
    var arity: usize = 1;
    if (std.mem.eql(u8, name, "@effect.provider")) {
        kind = .provider;
        arity = 2;
    } else if (std.mem.eql(u8, name, "@effect.state")) {
        kind = .state;
        arity = 3;
    } else if (!std.mem.eql(u8, name, "@computation")) return null;
    if (count != arity) return null;
    var result: Construction = .{ .kind = kind, .len = arity };
    for (0..arity) |index| result.inputs[index] = reverse[arity - index - 1];
    return result;
}
const SourceBindings = struct {
    entries: [128]struct { name: @import("../parse/symbols.zig").Symbol, retained: u16 } = undefined,
    len: usize = 0,
    fn bind(self: *SourceBindings, name: @import("../parse/symbols.zig").Symbol, retained: u16) error{Limit}!void {
        if (self.len == self.entries.len) return error.Limit;
        self.entries[self.len] = .{ .name = name, .retained = retained };
        self.len += 1;
    }
    fn get(self: *const SourceBindings, name: @import("../parse/symbols.zig").Symbol) ?u16 {
        var index = self.len;
        while (index != 0) {
            index -= 1;
            if (self.entries[index].name == name) return self.entries[index].retained;
        }
        return null;
    }
};
fn capturedSource(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, expression: ast.Id, names: []const u32) Parameters {
    if (names.len == 0 or names.len >= 16) return .{};
    var bindings: SourceBindings = .{};
    for (names, 0..) |name, index| bindings.entries[index] = .{ .name = name, .retained = @as(u16, 1) << @intCast(index) };
    bindings.len = names.len;
    var remaining: usize = 4096;
    const mask = sourceCaptures(tree, pool, expression, &bindings, &.{}, &remaining, 0) orelse return .{};
    return .{ .kind = .captured_unit, .inputs = @intCast(names.len), .mask = mask };
}
pub const LocalSourceCall = struct { name: u32 = 0, body: ast.Id, arguments: [16]ast.Id, parameters: [16]u32, len: usize };
pub fn localSourceCall(tree: *const ast.Tree, initial: ast.Id) ?LocalSourceCall {
    var result: LocalSourceCall = .{ .body = 0, .arguments = undefined, .parameters = undefined, .len = 0 };
    var callee = unwrap(tree, initial) orelse return null;
    while (tree.node(callee).tag == .apply) {
        if (result.len == result.arguments.len) return null;
        result.arguments[result.len] = tree.node(callee).b;
        result.len += 1;
        callee = unwrap(tree, tree.node(callee).a) orelse return null;
    }
    if (result.len == 0 or tree.node(callee).tag != .name) return null;
    result.name = tree.node(callee).a;
    const declaration = for (tree.roots.items) |root| {
        if (tree.node(root).tag == .value_decl and tree.valueDecl(root).name == tree.node(callee).a) break tree.valueDecl(root);
    } else return null;
    var body = declaration.body;
    for (0..result.len) |index| {
        body = unwrap(tree, body) orelse return null;
        const lambda = tree.node(body);
        if (lambda.tag != .lambda) return null;
        const parameter = tree.parameter(lambda.a);
        if (parameter.name == 0 or parameter.demanded or parameter.is_unit) return null;
        result.parameters[index] = parameter.name;
        body = lambda.b;
    }
    result.body = unwrap(tree, body) orelse return null;
    // A partial application retains every supplied argument physically.
    if (tree.node(result.body).tag == .lambda) return null;
    @import("std").mem.reverse(ast.Id, result.arguments[0..result.len]);
    return result;
}
pub const LocalCoreCall = struct { body: u32, target: @import("core.zig").BindingRef, signature: u32, arguments: [16]u32 = undefined, len: usize = 0, bindings: [16]u32 = undefined };
pub fn coreCall(module: anytype, id: u32) ?LocalCoreCall {
    if (id == 0 or id >= module.nodes.len) return null;
    const node = module.nodes[id];
    var result: LocalCoreCall = .{ .body = 0, .target = .{ .unit = 0, .binding = 0 }, .signature = 0 };
    if (node.tag == .call) {
        if (node.a >= module.calls.len or node.c > result.arguments.len or node.b > module.extra.len or node.c > module.extra.len - node.b) return null;
        result.target = module.calls[node.a].target;
        result.signature = module.calls[node.a].callee_type;
        result.len = node.c;
        @import("std").mem.copyForwards(u32, result.arguments[0..result.len], module.extra[node.b..][0..node.c]);
    } else {
        var callee = id;
        while (true) {
            if (callee == 0 or callee >= module.nodes.len) return null;
            const applied = module.nodes[callee];
            if (applied.tag != .apply) break;
            if (result.len == result.arguments.len or applied.b == 0 or applied.b >= module.nodes.len) return null;
            result.arguments[result.len] = applied.b;
            result.len += 1;
            callee = applied.a;
        }
        @import("std").mem.reverse(u32, result.arguments[0..result.len]);
        const head = module.nodes[callee];
        if (head.tag == .call) {
            if (head.a >= module.calls.len or head.c > result.arguments.len - result.len or head.b > module.extra.len or head.c > module.extra.len - head.b) return null;
            @import("std").mem.copyBackwards(u32, result.arguments[head.c..][0..result.len], result.arguments[0..result.len]);
            @import("std").mem.copyForwards(u32, result.arguments[0..head.c], module.extra[head.b..][0..head.c]);
            result.len += head.c;
            result.target = module.calls[head.a].target;
            result.signature = module.calls[head.a].callee_type;
        } else {
            if (head.tag != .reference or head.a >= module.references.len) return null;
            result.target = module.reference(callee);
            result.signature = head.ty;
        }
    }
    for (result.arguments[0..result.len]) |argument| if (argument == 0 or argument >= module.nodes.len) return null;
    return result;
}
pub fn localCoreCall(module: anytype, id: u32) ?LocalCoreCall {
    return coreCallBody(module, coreCall(module, id) orelse return null);
}
/// Resolve a flattened call against its exact producer while keeping argument
/// nodes owned by the caller.
pub fn coreCallBody(module: anytype, original: LocalCoreCall) ?LocalCoreCall {
    var result = original;
    const target = result.target;
    if ((target.unit != 0 and target.unit != module.unit) or target.binding == 0 or target.binding >= module.bindings.len) return null;
    const binding = module.bindings[target.binding];
    if (binding.body_id == 0 or binding.body_id >= module.bodies.len) return null;
    const body = module.bodies[binding.body_id];
    if (body.parameters.len > result.len or body.parameters.start > module.parameters.len or body.parameters.len > module.parameters.len - body.parameters.start) return null;
    var bound: usize = 0;
    for (module.parameters[body.parameters.start..][0..body.parameters.len]) |parameter| {
        if (parameter.binding == 0 or parameter.binding >= module.bindings.len or module.bindings[parameter.binding].kind != .parameter) return null;
        for (result.bindings[0..bound]) |prior| if (prior == parameter.binding) return null;
        result.bindings[bound] = parameter.binding;
        bound += 1;
    }
    result.body = body.root;
    while (bound < result.len) {
        if (result.body == 0 or result.body >= module.nodes.len) return null;
        const value = module.nodes[result.body];
        if (value.tag != .closure or value.a >= module.closures.len) return null;
        const closure = module.closures[value.a];
        const parameter = closure.parameter.binding;
        if (parameter == 0 or parameter >= module.bindings.len or module.bindings[parameter].kind != .parameter) return null;
        for (result.bindings[0..bound]) |prior| if (prior == parameter) return null;
        result.bindings[bound] = parameter;
        bound += 1;
        result.body = closure.body;
    }
    if (result.body == 0 or result.body >= module.nodes.len) return null;
    return result;
}
fn sourceParameters(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id, bindings: *const SourceBindings, remaining: *usize, depth: usize) ?u16 {
    if (remaining.* == 0 or depth >= 64) return null;
    remaining.* -= 1;
    const source_id = unwrap(tree, initial) orelse return null;
    const value = tree.node(source_id);
    switch (value.tag) {
        .name => {
            if (bindings.get(value.a)) |known| return known;
            const text = pool.get(value.a);
            const separator = @import("std").mem.findScalar(u8, text, '.') orelse return null;
            const receiver = pool.lookup(text[0..separator]) orelse return null;
            return bindings.get(receiver);
        },
        .field_access => return sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1),
        .index_access => {
            _ = sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1) orelse return null;
            return sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1);
        },
        .field => {
            if (value.b == 0) return bindings.get(value.a);
            return sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1);
        },
        .integer, .float, .boolean, .unit, .constructor_ref => return 0,
        .apply => {
            if (localSourceCall(tree, source_id)) |call| {
                if (bindings.get(call.name) != null) return null;
                var nested: SourceBindings = .{};
                for (call.parameters[0..call.len], call.arguments[0..call.len]) |parameter, argument| nested.bind(parameter, sourceParameters(tree, pool, argument, bindings, remaining, depth + 1) orelse return null) catch return null;
                return sourceParameters(tree, pool, call.body, &nested, remaining, depth + 1);
            }
            if (constructionSource(tree, pool, source_id)) |construction| {
                var result: u16 = 0;
                for (construction.inputs[0..construction.len]) |input| result |= sourceParameters(tree, pool, input, bindings, remaining, depth + 1) orelse return null;
                return result;
            }
            if (projectionSource(tree, pool, source_id)) |projection| {
                _ = sourceParameters(tree, pool, projection.index, bindings, remaining, depth + 1) orelse return null;
                return sourceParameters(tree, pool, projection.receiver, bindings, remaining, depth + 1);
            }
            const callee = tree.node(unwrap(tree, value.a) orelse return null);
            if (callee.tag != .constructor_ref) return null;
            return sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1);
        },
        .type_witness => return sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1),
        .if_expr => {
            // Reading a scalar condition does not retain it in the result.
            _ = sourceParameters(tree, pool, value.a, bindings, remaining, depth + 1) orelse return null;
            return (sourceParameters(tree, pool, value.b, bindings, remaining, depth + 1) orelse return null) | (sourceParameters(tree, pool, value.c, bindings, remaining, depth + 1) orelse return null);
        },
        .block => {
            if (value.c != 0) return null;
            var environment = bindings.*;
            const children = tree.children(source_id);
            for (children, 0..) |child, index| {
                const statement = tree.node(child);
                if (statement.tag == .return_stmt and index + 1 == children.len) return sourceParameters(tree, pool, statement.a, &environment, remaining, depth + 1);
                if (statement.tag != .let_stmt) return null;
                const binding = tree.binding(child);
                const pattern = tree.node(binding.pattern);
                if (pattern.tag != .pattern_name or binding.fallback != 0) return null;
                const retained = sourceParameters(tree, pool, binding.value, &environment, remaining, depth + 1) orelse return null;
                environment.bind(pattern.a, retained) catch return null;
            }
            return null;
        },
        .case_expr => {
            const inputs = tree.extra.items[value.a..][0..2];
            if (inputs[1] > 16) return null;
            var retained: [16]u16 = undefined;
            for (tree.list(.{ .start = inputs[0], .len = inputs[1] }), 0..) |input, index| retained[index] = sourceParameters(tree, pool, input, bindings, remaining, depth + 1) orelse return null;
            var result: u16 = 0;
            for (tree.list(.{ .start = value.b, .len = value.c })) |arm_id| {
                const arm = tree.node(arm_id);
                var environment = bindings.*;
                const start = environment.len;
                for (tree.list(.{ .start = arm.a, .len = arm.b })) |row| {
                    const patterns = tree.children(row);
                    if (patterns.len != inputs[1]) return null;
                    for (patterns, retained[0..inputs[1]]) |pattern, mask| if (!sourcePattern(tree, pattern, mask, &environment, start, remaining, depth + 1)) return null;
                }
                const details = tree.extra.items[arm.c..][0..2];
                if (details[0] != 0) _ = sourceParameters(tree, pool, details[0], &environment, remaining, depth + 1) orelse return null;
                result |= sourceParameters(tree, pool, details[1], &environment, remaining, depth + 1) orelse return null;
            }
            return result;
        },
        .lambda => return sourceCaptures(tree, pool, source_id, bindings, &.{}, remaining, depth + 1),
        .product, .array, .record => {
            var result: u16 = 0;
            for (tree.children(source_id)) |child| result |= sourceParameters(tree, pool, child, bindings, remaining, depth + 1) orelse return null;
            return result;
        },
        else => return null,
    }
}
pub const SourceProjection = struct { receiver: ast.Id, index: ast.Id };
pub fn projectionSource(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id) ?SourceProjection {
    const outer = tree.node(unwrap(tree, initial) orelse return null);
    if (outer.tag != .apply) return null;
    const inner = tree.node(unwrap(tree, outer.a) orelse return null);
    if (inner.tag != .apply) return null;
    const callee = tree.node(unwrap(tree, inner.a) orelse return null);
    if (callee.tag != .intrinsic) return null;
    const name = pool.get(callee.a);
    const std = @import("std");
    if (!std.mem.eql(u8, name, "@array.get") and !std.mem.eql(u8, name, "@product.get")) return null;
    return .{ .receiver = inner.b, .index = outer.b };
}
fn sourcePattern(tree: *const ast.Tree, source_id: ast.Id, retained: u16, bindings: *SourceBindings, start: usize, remaining: *usize, depth: usize) bool {
    if (source_id == 0 or remaining.* == 0 or depth >= 64) return false;
    remaining.* -= 1;
    const pattern = tree.node(source_id);
    switch (pattern.tag) {
        .pattern_integer, .pattern_boolean => return true,
        .pattern_name => {
            for (bindings.entries[start..bindings.len]) |*entry| if (entry.name == pattern.a) {
                entry.retained |= retained;
                return true;
            };
            bindings.bind(pattern.a, retained) catch return false;
            return true;
        },
        .pattern_field => {
            if (pattern.b != 0) return sourcePattern(tree, pattern.b, retained, bindings, start, remaining, depth + 1);
            for (bindings.entries[start..bindings.len]) |*entry| if (entry.name == pattern.a) {
                entry.retained |= retained;
                return true;
            };
            bindings.bind(pattern.a, retained) catch return false;
            return true;
        },
        .pattern_constructor => {
            if (pattern.b == 0) return true;
            return sourcePattern(tree, pattern.b, retained, bindings, start, remaining, depth + 1);
        },
        .pattern_product, .pattern_record => {
            for (tree.children(source_id)) |child| if (!sourcePattern(tree, child, retained, bindings, start, remaining, depth + 1)) return false;
            return true;
        },
        else => return false,
    }
}
// A closure retains its free input values, independently of the effects its
// body performs. The binder map preserves formal ordinals under shadowing.
fn sourceCaptures(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id, bindings: *const SourceBindings, locals: []const @import("../parse/symbols.zig").Symbol, remaining: *usize, depth: usize) ?u16 {
    if (remaining.* == 0 or depth >= 64) return null;
    remaining.* -= 1;
    const source_id = unwrap(tree, initial) orelse return null;
    const value = tree.node(source_id);
    switch (value.tag) {
        .intrinsic, .integer, .float, .string, .boolean, .unit => return 0,
        .name => {
            for (locals) |local| if (local == value.a) return 0;
            if (bindings.get(value.a)) |formal| return formal;
            const text = pool.get(value.a);
            const separator = @import("std").mem.findScalar(u8, text, '.') orelse return null;
            const receiver = pool.lookup(text[0..separator]) orelse return null;
            for (locals) |local| if (local == receiver) return 0;
            return bindings.get(receiver);
        },
        .field => {
            if (value.b == 0) {
                for (locals) |local| if (local == value.a) return 0;
                return bindings.get(value.a);
            }
            return sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1);
        },
        .lambda => {
            if (locals.len == 64) return null;
            var nested: [64]@import("../parse/symbols.zig").Symbol = undefined;
            @import("std").mem.copyForwards(@import("../parse/symbols.zig").Symbol, nested[0..locals.len], locals);
            nested[locals.len] = tree.parameter(value.a).name;
            return sourceCaptures(tree, pool, value.b, bindings, nested[0 .. locals.len + 1], remaining, depth + 1);
        },
        .field_access, .return_stmt, .function_return_stmt, .yield_stmt => return sourceCaptures(tree, pool, value.a, bindings, locals, remaining, depth + 1),
        .apply => {
            const argument = tree.node(unwrap(tree, value.b) orelse return null);
            if (argument.tag != .unit and !pureCallee(tree, pool, value.a)) return null;
            return (sourceCaptures(tree, pool, value.a, bindings, locals, remaining, depth + 1) orelse return null) | (sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1) orelse return null);
        },
        .index_access => return (sourceCaptures(tree, pool, value.a, bindings, locals, remaining, depth + 1) orelse return null) | (sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1) orelse return null),
        .unary => {
            if (!@import("std").mem.eql(u8, pool.get(value.a), "-")) return null;
            return sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1);
        },
        .binary => return (sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1) orelse return null) | (sourceCaptures(tree, pool, value.c, bindings, locals, remaining, depth + 1) orelse return null),
        .block => {
            if (value.c != 0) return null;
            var nested = bindings.*;
            var result: u16 = 0;
            for (tree.children(source_id)) |child| {
                const statement = tree.node(child);
                if (statement.tag == .let_stmt) {
                    const binding = tree.binding(child);
                    if (binding.fallback != 0) return null;
                    result |= sourceCaptures(tree, pool, binding.value, &nested, locals, remaining, depth + 1) orelse return null;
                    if (!sourcePattern(tree, binding.pattern, 0, &nested, nested.len, remaining, depth + 1)) return null;
                } else result |= sourceCaptures(tree, pool, child, &nested, locals, remaining, depth + 1) orelse return null;
            }
            return result;
        },
        .case_expr => {
            const inputs = tree.extra.items[value.a..][0..2];
            if (inputs[1] > 16) return null;
            var result: u16 = 0;
            for (tree.list(.{ .start = inputs[0], .len = inputs[1] })) |input| result |= sourceCaptures(tree, pool, input, bindings, locals, remaining, depth + 1) orelse return null;
            for (tree.list(.{ .start = value.b, .len = value.c })) |arm_id| {
                const arm = tree.node(arm_id);
                var nested = bindings.*;
                const start = nested.len;
                for (tree.list(.{ .start = arm.a, .len = arm.b })) |row| {
                    const patterns = tree.children(row);
                    if (patterns.len != inputs[1]) return null;
                    for (patterns) |pattern| if (!sourcePattern(tree, pattern, 0, &nested, start, remaining, depth + 1)) return null;
                }
                const details = tree.extra.items[arm.c..][0..2];
                if (details[0] != 0) result |= sourceCaptures(tree, pool, details[0], &nested, locals, remaining, depth + 1) orelse return null;
                result |= sourceCaptures(tree, pool, details[1], &nested, locals, remaining, depth + 1) orelse return null;
            }
            return result;
        },
        .if_expr => return (sourceCaptures(tree, pool, value.a, bindings, locals, remaining, depth + 1) orelse return null) | (sourceCaptures(tree, pool, value.b, bindings, locals, remaining, depth + 1) orelse return null) | (sourceCaptures(tree, pool, value.c, bindings, locals, remaining, depth + 1) orelse return null),
        .product, .record, .array => {
            var result: u16 = 0;
            for (tree.children(source_id)) |child| result |= sourceCaptures(tree, pool, child, bindings, locals, remaining, depth + 1) orelse return null;
            return result;
        },
        else => return null,
    }
}
fn pureCallee(tree: *const ast.Tree, pool: *const @import("../parse/symbols.zig").Pool, initial: ast.Id) bool {
    var current = initial;
    for (0..128) |_| {
        const value = tree.node(unwrap(tree, current) orelse return false);
        if (value.tag == .apply) {
            current = value.a;
            continue;
        }
        if (value.tag != .intrinsic) return false;
        const name = pool.get(value.a);
        const std = @import("std");
        if (std.mem.startsWith(u8, name, "@u32.") or std.mem.startsWith(u8, name, "@f32.")) return true;
        return std.mem.eql(u8, name, "@product.get") or std.mem.eql(u8, name, "@array.get") or std.mem.eql(u8, name, "@array.set") or std.mem.eql(u8, name, "@array.length") or std.mem.eql(u8, name, "@array.fill");
    }
    return false;
}
fn parameterName(name: @import("../parse/symbols.zig").Symbol, names: []const @import("../parse/symbols.zig").Symbol) ?u16 {
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
    return parameterCoreWithOwners(module, body, summary, &.{});
}
pub fn parameterCoreWithOwners(module: anytype, body: anytype, summary: Parameters, owners: []const *const @TypeOf(module.*)) bool {
    if (!summary.valid() or !summary.present() or !body.is_function) return false;
    var arity: u32 = summary.arity();
    if (summary.kind == .member_closure_unit or summary.kind == .captured_unit) arity += 1;
    if (body.parameters.len != arity) return false;
    if (body.parameters.start > module.parameters.len or body.parameters.len > module.parameters.len - body.parameters.start) return false;
    if (body.root == 0 or body.root >= module.nodes.len) return false;
    const root = module.nodes[body.root];
    var remaining: usize = 4096;
    const parameters = module.parameters[body.parameters.start..][0..summary.arity()];
    if (summary.invokes()) {
        const reconstructed = invocationCore(module, body, owners, &remaining) orelse return false;
        return @import("std").meta.eql(summary, reconstructed);
    }
    if (summary.kind == .product) {
        if (body.binding < module.bindings.len and module.bindings[body.binding].capability_flow == .input_shape) return @import("capability_contract_core.zig").inputBodyWithOwners(module, body, summary, owners);
        const result = coreParameters(module, body.root, parameters, &.{}, &remaining, 0) orelse return false;
        return result == summary.result();
    }
    if (summary.kind == .captured_unit) {
        const unit = module.parameters[body.parameters.start + summary.arity()];
        if (unit.ty != @import("types.zig").unit) return false;
        const result = coreCaptures(module, body.root, parameters, &.{}, &.{unit.binding}, &remaining, 0, body.closed_rows) orelse return false;
        return result == summary.result();
    }
    if (root.tag != .apply or root.b == 0 or root.b >= module.nodes.len) return false;
    const argument = module.nodes[root.b];
    if (summary.kind != .member_closure_unit or argument.tag != .constant or argument.ty != @import("types.zig").unit or argument.a != 0) return false;
    if (root.a == 0 or root.a >= module.nodes.len) return false;
    var selected = root.a;
    if (summary.kind == .member_closure_unit) {
        if (module.parameters[body.parameters.start + summary.arity()].ty != @import("types.zig").unit) return false;
        const operation = module.nodes[selected];
        if (operation.tag != .operation_value or operation.a >= module.operation_values.len) return false;
        selected = module.operation_values[operation.a].capability;
        if (selected == 0 or selected >= module.nodes.len) return false;
        const capability = module.nodes[selected];
        if (capability.ty >= module.types.nodes.len or module.types.nodes[capability.ty].tag != .scoped) return false;
    }
    if (module.nodes[selected].tag != .reference) return false;
    const target = coreParameters(module, selected, parameters, &.{}, &remaining, 0) orelse return false;
    return target == summary.result();
}

pub fn invocationCore(module: anytype, body: anytype, owners: []const *const @TypeOf(module.*), remaining: *usize) ?Parameters {
    if (!body.is_function or body.parameters.len == 0 or body.parameters.len > 16 or body.parameters.start > module.parameters.len or body.parameters.len > module.parameters.len - body.parameters.start) return null;
    var bindings: CoreInvocationBindings = .{};
    for (module.parameters[body.parameters.start..][0..body.parameters.len], 0..) |parameter, index| {
        if (remaining.* == 0) return null;
        remaining.* -= 1;
        if (parameter.binding == 0 or parameter.binding >= module.bindings.len or module.bindings[parameter.binding].kind != .parameter) return null;
        bindings.bind(parameter.binding, @as(u16, 1) << @intCast(index)) orelse return null;
    }
    return coreInvocation(module, body.root, &bindings, @intCast(body.parameters.len), owners, remaining, 0);
}

const CoreInvocationBindings = struct {
    entries: [16]struct { binding: u32, mask: u16 } = undefined,
    len: usize = 0,
    fn bind(self: *CoreInvocationBindings, binding: u32, mask: u16) ?void {
        if (binding == 0 or self.len == self.entries.len or self.get(binding) != null) return null;
        self.entries[self.len] = .{ .binding = binding, .mask = mask };
        self.len += 1;
    }
    fn get(self: *const CoreInvocationBindings, binding: u32) ?u16 {
        for (self.entries[0..self.len]) |entry| if (entry.binding == binding) return entry.mask;
        return null;
    }
};

fn coreInvocation(module: anytype, id: u32, bindings: *const CoreInvocationBindings, inputs: u8, owners: []const *const @TypeOf(module.*), remaining: *usize, depth: usize) ?Parameters {
    if (remaining.* < 17 or depth >= 128) return null;
    // coreCall inspects at most16 applications and their argument nodes.
    remaining.* -= 17;
    const call = coreCall(module, id) orelse return null;
    if (call.target.unit == 0 or call.target.unit == module.unit) {
        if (bindings.get(call.target.binding)) |callback| {
            var arguments: [16]u16 = undefined;
            if (call.len == 1) {
                const argument = module.node(call.arguments[0]);
                if (argument.tag == .constant and argument.ty == @import("types.zig").unit and argument.a == 0 and argument.b == 0 and argument.c == 0 and argument.op == .none) return invocationResult(inputs, callback, &.{}, true);
            }
            for (call.arguments[0..call.len], 0..) |argument, index| {
                const node = module.node(argument);
                if (node.tag != .reference or node.a >= module.references.len) return null;
                const reference = module.references[node.a];
                if (reference.unit != 0 and reference.unit != module.unit) return null;
                arguments[index] = bindings.get(reference.binding) orelse return null;
            }
            return invocationResult(inputs, callback, arguments[0..call.len], false);
        }
    }
    var producer: *const @TypeOf(module.*) = module;
    if (call.target.unit != 0 and call.target.unit != module.unit) {
        var selected: ?*const @TypeOf(module.*) = null;
        for (owners) |owner| {
            if (remaining.* == 0) return null;
            remaining.* -= 1;
            if (owner.unit != call.target.unit) continue;
            if (selected) |prior| if (prior != owner) return null;
            selected = owner;
        }
        producer = selected orelse return null;
    }
    if (call.target.binding == 0 or call.target.binding >= producer.bindings.len) return null;
    const binding = producer.bindings[call.target.binding];
    if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= producer.bodies.len) return null;
    const body = producer.bodies[binding.body_id];
    if (!body.is_function or body.parameters.len != call.len or body.parameters.start > producer.parameters.len or body.parameters.len > producer.parameters.len - body.parameters.start) return null;
    var nested: CoreInvocationBindings = .{};
    for (call.arguments[0..call.len], producer.parameters[body.parameters.start..][0..body.parameters.len]) |argument, formal| {
        if (formal.binding == 0 or formal.binding >= producer.bindings.len or producer.bindings[formal.binding].kind != .parameter) return null;
        const node = module.node(argument);
        if (node.tag != .reference or node.a >= module.references.len) return null;
        const reference = module.references[node.a];
        if (reference.unit != 0 and reference.unit != module.unit) return null;
        nested.bind(formal.binding, bindings.get(reference.binding) orelse return null) orelse return null;
    }
    return coreInvocation(producer, body.root, &nested, inputs, owners, remaining, depth + 1);
}

/// Exact unary contracts used when a conditional caller observes another
/// module's body. A catalog name alone is never an executable no-store proof.
pub fn unaryCore(module: anytype, body: anytype, contract: Contract) bool {
    return unaryCoreWithOwners(module, body, contract, &.{});
}
pub fn unaryCoreWithOwners(module: anytype, body: anytype, contract: Contract, owners: []const *const @TypeOf(module.*)) bool {
    if (contract == .input_shape) {
        if (body.binding >= module.bindings.len) return false;
        return @import("capability_contract_core.zig").inputBodyWithOwners(module, body, module.bindings[body.binding].capability_parameters, owners);
    }
    if (contract != .identity and contract != .member_unit) return false;
    if (!body.is_function or body.parameters.len != 1 or body.parameters.start >= module.parameters.len or body.root == 0 or body.root >= module.nodes.len) return false;
    const types = &module.types;
    if (body.scheme.root >= types.nodes.len) return false;
    const function = types.node(body.scheme.root);
    if (function.tag != .function or function.a >= types.nodes.len or function.b >= types.nodes.len) return false;
    const parameter = module.parameters[body.parameters.start];
    if (parameter.ty >= types.nodes.len or module.nodes[body.root].ty >= types.nodes.len) return false;
    const equality = @import("rank_equal.zig");
    if (!(equality.equal(types, function.a, parameter.ty, true) catch false) or !(equality.equal(types, function.b, module.nodes[body.root].ty, true) catch false)) return false;
    var value = module.nodes[body.root];
    if (contract == .member_unit) {
        if (value.tag != .apply or value.a == 0 or value.a >= module.nodes.len or value.b == 0 or value.b >= module.nodes.len) return false;
        const argument_ = module.nodes[value.b];
        if (argument_.tag != .constant or argument_.ty != @import("types.zig").unit or argument_.a != 0) return false;
        value = module.nodes[value.a];
        if (value.tag != .operation_value or value.a >= module.operation_values.len) return false;
        const receiver = module.operation_values[value.a].capability;
        if (receiver == 0 or receiver >= module.nodes.len) return false;
        value = module.nodes[receiver];
    }
    if (value.tag != .reference or value.a >= module.references.len) return false;
    const reference = module.references[value.a];
    if (value.ty >= types.nodes.len or !(equality.equal(types, value.ty, parameter.ty, true) catch false)) return false;
    return (reference.unit == 0 or reference.unit == module.unit) and reference.binding == parameter.binding;
}
/// Reconstruct which exact formal parameters can survive in a returned value.
/// Closure captures are derived from references, never absence in a catalog.
pub fn retainedCore(module: anytype, source_id: u32, bindings: []const u32, remaining: *usize) ?u16 {
    if (bindings.len > 16) return null;
    var parameters: [16]struct { binding: u32 } = undefined;
    for (bindings, 0..) |binding, index| {
        if (binding == 0 or binding >= module.bindings.len or module.bindings[binding].kind != .parameter) return null;
        for (bindings[0..index]) |prior| if (prior == binding) return null;
        parameters[index] = .{ .binding = binding };
    }
    return coreParameters(module, source_id, parameters[0..bindings.len], &.{}, remaining, 0);
}
const CoreAlias = struct { binding: u32, retained: u16 };
fn coreParameters(module: anytype, source_id: u32, parameters: anytype, aliases: []const CoreAlias, remaining: *usize, depth: usize) ?u16 {
    if (remaining.* == 0 or depth >= 64 or source_id == 0 or source_id >= module.nodes.len) return null;
    remaining.* -= 1;
    const value = module.nodes[source_id];
    switch (value.tag) {
        .call, .apply => {
            const call = localCoreCall(module, source_id) orelse return null;
            var nested: [16]CoreAlias = undefined;
            for (call.bindings[0..call.len], call.arguments[0..call.len], 0..) |binding, argument, index| nested[index] = .{ .binding = binding, .retained = coreParameters(module, argument, parameters, aliases, remaining, depth + 1) orelse return null };
            return coreParameters(module, call.body, parameters, nested[0..call.len], remaining, depth + 1);
        },
        .reference => {
            if (value.a >= module.references.len) return null;
            const reference = module.references[value.a];
            if (reference.unit != 0 and reference.unit != module.unit) return null;
            var alias = aliases.len;
            while (alias != 0) {
                alias -= 1;
                if (aliases[alias].binding == reference.binding) return aliases[alias].retained;
            }
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
        .array_op => {
            if (value.c != @backingInt(@import("core.zig").ArrayOp.get) or value.b != 2 or value.a > module.extra.len or value.b > module.extra.len - value.a) return null;
            _ = coreParameters(module, module.extra[value.a + 1], parameters, aliases, remaining, depth + 1) orelse return null;
            return coreParameters(module, module.extra[value.a], parameters, aliases, remaining, depth + 1);
        },
        .operation_value => {
            if (value.a >= module.operation_values.len) return null;
            return coreParameters(module, module.operation_values[value.a].capability, parameters, aliases, remaining, depth + 1);
        },
        .computation => return coreParameters(module, value.a, parameters, aliases, remaining, depth + 1),
        .effect_provider, .state_provider => {
            var result = coreParameters(module, value.a, parameters, aliases, remaining, depth + 1) orelse return null;
            result |= coreParameters(module, value.b, parameters, aliases, remaining, depth + 1) orelse return null;
            if (value.tag == .state_provider) result |= coreParameters(module, value.c, parameters, aliases, remaining, depth + 1) orelse return null;
            return result;
        },
        .project => {
            if (value.b >= module.projections.len) return null;
            return coreParameters(module, value.a, parameters, aliases, remaining, depth + 1);
        },
        .construct => {
            if (value.b == 0) return 0;
            return coreParameters(module, value.b, parameters, aliases, remaining, depth + 1);
        },
        .block => {
            if (value.a > module.extra.len or value.b > module.extra.len - value.a or aliases.len > 128) return null;
            var environment: [128]CoreAlias = undefined;
            @import("std").mem.copyForwards(CoreAlias, environment[0..aliases.len], aliases);
            var count = aliases.len;
            const children = module.extra[value.a..][0..value.b];
            for (children, 0..) |child, index| {
                if (child == 0 or child >= module.nodes.len) return null;
                const statement = module.nodes[child];
                if (statement.tag == .return_ and index + 1 == children.len) {
                    if (statement.b != source_id) return null;
                    return coreParameters(module, statement.a, parameters, environment[0..count], remaining, depth + 1);
                }
                if (statement.tag != .bind or count == environment.len) return null;
                const retained = coreParameters(module, statement.b, parameters, environment[0..count], remaining, depth + 1) orelse return null;
                environment[count] = .{ .binding = statement.a, .retained = retained };
                count += 1;
            }
            return null;
        },
        .if_value => {
            _ = coreParameters(module, value.a, parameters, aliases, remaining, depth + 1) orelse return null;
            return (coreParameters(module, value.b, parameters, aliases, remaining, depth + 1) orelse return null) | (coreParameters(module, value.c, parameters, aliases, remaining, depth + 1) orelse return null);
        },
        .match => {
            if (value.a >= module.matches.len or aliases.len > 128) return null;
            const match = module.matches[value.a];
            if (match.statement or match.inputs.len > 16 or match.inputs.start > module.extra.len or match.inputs.len > module.extra.len - match.inputs.start) return null;
            if (match.arms.start > module.match_arms.len or match.arms.len > module.match_arms.len - match.arms.start) return null;
            var retained: [16]u16 = undefined;
            for (module.extra[match.inputs.start..][0..match.inputs.len], 0..) |input, index| retained[index] = coreParameters(module, input, parameters, aliases, remaining, depth + 1) orelse return null;
            var result: u16 = 0;
            for (module.match_arms[match.arms.start..][0..match.arms.len]) |arm| {
                if (arm.rows.start > module.pattern_rows.len or arm.rows.len > module.pattern_rows.len - arm.rows.start) return null;
                var environment: [128]CoreAlias = undefined;
                @import("std").mem.copyForwards(CoreAlias, environment[0..aliases.len], aliases);
                var count = aliases.len;
                for (module.pattern_rows[arm.rows.start..][0..arm.rows.len]) |row| {
                    if (row.patterns.len != match.inputs.len or row.patterns.start > module.extra.len or row.patterns.len > module.extra.len - row.patterns.start) return null;
                    for (module.extra[row.patterns.start..][0..row.patterns.len], retained[0..match.inputs.len]) |pattern, mask| if (!corePattern(module, pattern, mask, &environment, &count, aliases.len, remaining, depth + 1)) return null;
                }
                if (arm.guard != 0) _ = coreParameters(module, arm.guard, parameters, environment[0..count], remaining, depth + 1) orelse return null;
                result |= coreParameters(module, arm.body, parameters, environment[0..count], remaining, depth + 1) orelse return null;
            }
            return result;
        },
        .closure => {
            if (value.a >= module.closures.len) return null;
            const closure = module.closures[value.a];
            const ignored = [_]u32{closure.parameter.binding};
            return (coreCaptures(module, closure.body, parameters, aliases, &ignored, remaining, depth + 1, closure.closed_rows) orelse return null) | (declaredCoreCaptures(module, closure, parameters, aliases, &ignored, remaining) orelse return null);
        },
        .product, .record, .array => {
            if (value.a > module.extra.len or value.b > module.extra.len - value.a) return null;
            var result: u16 = 0;
            for (module.extra[value.a..][0..value.b]) |child| result |= coreParameters(module, child, parameters, aliases, remaining, depth + 1) orelse return null;
            return result;
        },
        else => return null,
    }
}

fn corePattern(module: anytype, source_id: u32, retained: u16, environment: *[128]CoreAlias, count: *usize, start: usize, remaining: *usize, depth: usize) bool {
    if (source_id == 0 or source_id >= module.patterns.len or remaining.* == 0 or depth >= 64) return false;
    remaining.* -= 1;
    const pattern = module.patterns[source_id];
    switch (pattern.tag) {
        .wildcard, .constant => return true,
        .bind => {
            for (environment[start..count.*]) |*entry| if (entry.binding == pattern.a) {
                entry.retained |= retained;
                return true;
            };
            if (count.* == environment.len) return false;
            environment[count.*] = .{ .binding = pattern.a, .retained = retained };
            count.* += 1;
            return true;
        },
        .constructor, .record_payload => {
            if (pattern.b == 0) return true;
            return corePattern(module, pattern.b, retained, environment, count, start, remaining, depth + 1);
        },
        .product => {
            if (pattern.a > module.extra.len or pattern.b > module.extra.len - pattern.a) return false;
            for (module.extra[pattern.a..][0..pattern.b]) |child| if (!corePattern(module, child, retained, environment, count, start, remaining, depth + 1)) return false;
            return true;
        },
        else => return false,
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
    try std.testing.expect((Parameters{ .kind = .member_closure_unit, .inputs = 15, .mask = 0x4000 }).valid());
    try std.testing.expect(!(Parameters{ .kind = .member_closure_unit, .inputs = 16, .mask = 0x8000 }).valid());
    try std.testing.expect(!(Parameters{ .kind = .member_closure_unit, .inputs = 3, .mask = 3 }).valid());
    try std.testing.expect(!(Parameters{ .kind = .member_closure_unit }).valid());
    const input: Parameters = .{ .kind = .invoke_input, .inputs = 16, .mask = 0xfe };
    try std.testing.expect(input.valid());
    try std.testing.expectEqual(@as(u8, 14), input.callback());
    try std.testing.expectEqual(@as(u8, 15), input.argument());
    try std.testing.expectEqual(@as(u16, 0x4000), input.result());
    try std.testing.expect(!(Parameters{ .kind = .invoke_input, .inputs = 16, .mask = 0x1fe }).valid());
    try std.testing.expect(!(Parameters{ .kind = .invoke_input, .inputs = 16, .mask = 0xff }).valid());
    try std.testing.expect(!(Parameters{ .kind = .invoke_input, .inputs = 15, .mask = 0xfe }).valid());
}

fn declaredCoreCaptures(module: anytype, closure: anytype, parameters: anytype, aliases: []const CoreAlias, ignored: []const u32, remaining: *usize) ?u16 {
    const captures = closure.captures;
    if (captures.start > module.extra.len or captures.len > module.extra.len - captures.start) return null;
    var result: u16 = 0;
    for (module.extra[captures.start..][0..captures.len]) |binding| {
        if (remaining.* == 0 or binding == 0 or binding >= module.bindings.len) return null;
        remaining.* -= 1;
        if (@import("std").mem.findScalar(u32, ignored, binding) != null) continue;
        var known = false;
        var index = aliases.len;
        while (index != 0) {
            index -= 1;
            if (aliases[index].binding != binding) continue;
            result |= aliases[index].retained;
            known = true;
            break;
        }
        if (known) continue;
        for (parameters, 0..) |parameter, ordinal| if (parameter.binding == binding) {
            result |= @as(u16, 1) << @intCast(ordinal);
            known = true;
            break;
        };
        if (!known) return null;
    }
    return result;
}
/// A closed pure scalar call can only read primitive operands. Capturing its
/// executable arguments retains their lexical inputs; no callable storage or
/// authority-bearing argument can be inferred from the callee's result type.
pub fn scalarCallOperands(module: anytype, id: u32, closed_rows: @import("types.zig").List, remaining: *usize) ?[]const u32 {
    if (id == 0 or id >= module.nodes.len or remaining.* == 0) return null;
    remaining.* -= 1;
    const node = module.nodes[id];
    if (node.tag != .call or node.a >= module.calls.len or node.c > 16 or node.b > module.extra.len or node.c > module.extra.len - node.b) return null;
    const call = module.calls[node.a];
    if (call.target.binding == 0) return null;
    if (call.target.unit == 0 or call.target.unit == module.unit) {
        if (call.target.binding >= module.bindings.len) return null;
        const kind = module.bindings[call.target.binding].kind;
        if (kind != .global and kind != .external) return null;
    }
    var signature = call.callee_type;
    const operands = module.extra[node.b..][0..node.c];
    for (operands) |operand| {
        if (remaining.* == 0) return null;
        remaining.* -= 1;
        if (operand == 0 or operand >= module.nodes.len or signature == 0 or signature >= module.types.nodes.len) return null;
        const arrow = module.types.node(signature);
        if (arrow.tag != .function or arrow.a == 0 or arrow.a >= module.types.nodes.len or arrow.c >= module.types.effects.rows.len) return null;
        if (!primitiveType(module.types.node(arrow.a).tag)) return null;
        if (module.nodes[operand].ty != arrow.a) return null;
        const row = module.types.effects.rows[arrow.c];
        if (row.labels.len != 0) return null;
        if (row.tail != .closed) {
            if (row.tail != .variable or closed_rows.start > module.types.extra.len or closed_rows.len > module.types.extra.len - closed_rows.start) return null;
            var certified = false;
            for (module.types.extra[closed_rows.start..][0..closed_rows.len]) |variable| {
                if (remaining.* == 0) return null;
                remaining.* -= 1;
                if (variable == row.tail.variable) certified = true;
            }
            if (!certified) return null;
        }
        signature = arrow.b;
    }
    if (signature == 0 or signature >= module.types.nodes.len or node.ty != signature or !primitiveType(module.types.node(signature).tag)) return null;
    return operands;
}
fn primitiveType(tag: @import("types.zig").Tag) bool {
    return tag == .unit or tag == .boolean or tag == .u32 or tag == .f32;
}

fn coreCaptures(module: anytype, source_id: u32, parameters: anytype, aliases: []const CoreAlias, ignored: []const u32, remaining: *usize, depth: usize, closed_rows: @import("types.zig").List) ?u16 {
    if (remaining.* == 0 or depth >= 64 or source_id == 0 or source_id >= module.nodes.len) return null;
    remaining.* -= 1;
    const value = module.nodes[source_id];
    switch (value.tag) {
        .reference => {
            if (value.a >= module.references.len) return null;
            const reference = module.references[value.a];
            if (reference.unit != 0 and reference.unit != module.unit) return null;
            for (ignored) |local| if (reference.binding == local) return 0;
            var alias = aliases.len;
            while (alias != 0) {
                alias -= 1;
                if (aliases[alias].binding == reference.binding) return aliases[alias].retained;
            }
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
        .primitive_function => return 0,
        .operation_value => {
            if (value.a >= module.operation_values.len) return null;
            const operation = module.operation_values[value.a];
            if (operation.capability == 0) return null;
            return coreCaptures(module, operation.capability, parameters, aliases, ignored, remaining, depth + 1, closed_rows);
        },
        .call => {
            const operands = scalarCallOperands(module, source_id, closed_rows, remaining) orelse return null;
            var retained: u16 = 0;
            for (operands) |operand| retained |= coreCaptures(module, operand, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null;
            return retained;
        },
        .apply => {
            if (value.b == 0 or value.b >= module.nodes.len) return null;
            const argument = module.nodes[value.b];
            if (argument.tag != .constant or argument.ty != @import("types.zig").unit or argument.a != 0) return null;
            return (coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null) | (coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null);
        },
        .scalar, .logical => {
            const left = coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null;
            if (value.b == 0) return left;
            return left | (coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null);
        },
        .project, .return_, .force => return coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows),
        .construct => return coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows),
        .closure => {
            if (value.a >= module.closures.len or ignored.len == 64) return null;
            const closure = module.closures[value.a];
            var locals: [64]u32 = undefined;
            @import("std").mem.copyForwards(u32, locals[0..ignored.len], ignored);
            locals[ignored.len] = closure.parameter.binding;
            const nested = locals[0 .. ignored.len + 1];
            return (coreCaptures(module, closure.body, parameters, aliases, nested, remaining, depth + 1, closed_rows) orelse return null) | (declaredCoreCaptures(module, closure, parameters, aliases, nested, remaining) orelse return null);
        },
        .block, .suite => {
            if (value.a > module.extra.len or value.b > module.extra.len - value.a or aliases.len > 128) return null;
            var nested: [128]CoreAlias = undefined;
            @import("std").mem.copyForwards(CoreAlias, nested[0..aliases.len], aliases);
            var count = aliases.len;
            var result: u16 = 0;
            for (module.extra[value.a..][0..value.b]) |child| {
                if (child == 0 or child >= module.nodes.len) return null;
                const statement = module.nodes[child];
                if (statement.tag == .bind) {
                    result |= coreCaptures(module, statement.b, parameters, nested[0..count], ignored, remaining, depth + 1, closed_rows) orelse return null;
                    if (count == nested.len) return null;
                    nested[count] = .{ .binding = statement.a, .retained = 0 };
                    count += 1;
                } else if (statement.tag == .pattern_bind) {
                    result |= coreCaptures(module, statement.b, parameters, nested[0..count], ignored, remaining, depth + 1, closed_rows) orelse return null;
                    if (statement.c != 0) result |= coreCaptures(module, statement.c, parameters, nested[0..count], ignored, remaining, depth + 1, closed_rows) orelse return null;
                    if (!corePattern(module, statement.a, 0, &nested, &count, count, remaining, depth + 1)) return null;
                } else result |= coreCaptures(module, child, parameters, nested[0..count], ignored, remaining, depth + 1, closed_rows) orelse return null;
            }
            return result;
        },
        .match => {
            if (value.a >= module.matches.len or aliases.len > 128) return null;
            const match = module.matches[value.a];
            if (match.inputs.len > 16 or match.inputs.start > module.extra.len or match.inputs.len > module.extra.len - match.inputs.start) return null;
            if (match.arms.start > module.match_arms.len or match.arms.len > module.match_arms.len - match.arms.start) return null;
            var result: u16 = 0;
            for (module.extra[match.inputs.start..][0..match.inputs.len]) |input| result |= coreCaptures(module, input, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null;
            for (module.match_arms[match.arms.start..][0..match.arms.len]) |arm| {
                if (arm.rows.start > module.pattern_rows.len or arm.rows.len > module.pattern_rows.len - arm.rows.start) return null;
                var nested: [128]CoreAlias = undefined;
                @import("std").mem.copyForwards(CoreAlias, nested[0..aliases.len], aliases);
                var count = aliases.len;
                for (module.pattern_rows[arm.rows.start..][0..arm.rows.len]) |row| {
                    if (row.patterns.len != match.inputs.len or row.patterns.start > module.extra.len or row.patterns.len > module.extra.len - row.patterns.start) return null;
                    for (module.extra[row.patterns.start..][0..row.patterns.len]) |pattern| if (!corePattern(module, pattern, 0, &nested, &count, aliases.len, remaining, depth + 1)) return null;
                }
                if (arm.guard != 0) result |= coreCaptures(module, arm.guard, parameters, nested[0..count], ignored, remaining, depth + 1, closed_rows) orelse return null;
                result |= coreCaptures(module, arm.body, parameters, nested[0..count], ignored, remaining, depth + 1, closed_rows) orelse return null;
            }
            return result;
        },
        .if_value => return (coreCaptures(module, value.a, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null) | (coreCaptures(module, value.b, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null) | (coreCaptures(module, value.c, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null),
        .product, .record, .array, .array_op => {
            if (value.a > module.extra.len or value.b > module.extra.len - value.a) return null;
            var result: u16 = 0;
            for (module.extra[value.a..][0..value.b]) |child| result |= coreCaptures(module, child, parameters, aliases, ignored, remaining, depth + 1, closed_rows) orelse return null;
            return result;
        },
        else => return null,
    }
}
