//! Reconstruct task authority from immutable Core, independently of source
//! annotations and archived capture catalogs. Ordinary affine admission still
//! checks every move and each once closure's executable uses.
const std = @import("std");
const C = @import("core.zig");
const T = @import("types.zig");
const tasks = @import("task_types.zig");
const Error = error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
fn same(module: *const C.Module, left: T.Id, right: T.Id, remaining: *usize) Error!void {
    try require(@import("rank_equal.zig").equalWithBudget(&module.types, left, right, true, remaining) catch return error.InvalidArtifact);
}
fn once(module: *const C.Module, id: C.Id) Error!T.Node {
    if (tasks.scopeCallback(&module.types, module.typeOf(id))) |arrow| return arrow;
    const wrapper = module.types.node(module.typeOf(id));
    try require(wrapper.tag == .usage and wrapper.b == @backingInt(T.UsageKind.once) and wrapper.c == 0);
    const arrow = module.types.node(wrapper.a);
    try require(arrow.tag == .function);
    return arrow;
}
fn handle(module: *const C.Module, id: T.Id) Error![]const T.Id {
    try require(tasks.isHandle(&module.types, id));
    const nominal = module.types.node(module.types.node(id).a);
    const arguments = module.types.nominalArguments(nominal);
    try require(arguments.len == 2 and tasks.isGroup(&module.types, arguments[0]));
    const arrow = module.types.node(arguments[1]);
    try require(arrow.tag == .function and arrow.a == T.unit);
    return arguments;
}
pub fn callable(module: *const C.Module, source: C.Id) Error!C.Id {
    var current = source;
    for (0..128) |_| {
        const node = module.node(current);
        if (node.tag == .closure) return current;
        if (node.tag != .reference) return error.InvalidArtifact;
        const reference = module.reference(current);
        if (reference.unit != 0 and reference.unit != module.unit) return error.InvalidArtifact;
        const binding = module.binding(reference.binding);
        if (binding.kind != .local or binding.initializer == 0) return error.InvalidArtifact;
        current = binding.initializer;
    }
    return error.InvalidArtifact;
}
pub fn receiveRequirement(module: *const C.Module, id: C.Id, remaining: *usize) Error!C.Obligation {
    const input = module.typeOf(module.children(id)[0]);
    for (module.bindings) |binding| {
        try require(remaining.* != 0);
        remaining.* -= 1;
        if (binding.capability_flow != .consume_task or binding.body_id == 0) continue;
        try require(binding.body_id < module.bodies.len);
        const body = module.bodies[binding.body_id];
        if (body.root != id or body.parameters.len != 1) continue;
        try require(body.parameters.start < module.parameters.len);
        const parameter = module.parameters[body.parameters.start];
        const reference = module.node(module.children(id)[0]);
        try require(reference.tag == .reference and module.reference(module.children(id)[0]).binding == parameter.binding);
        try require(body.scheme.obligations.start <= module.obligations.len and body.scheme.obligations.len <= module.obligations.len - body.scheme.obligations.start);
        for (module.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len]) |goal| {
            try require(remaining.* != 0);
            remaining.* -= 1;
            if (goal.kind != .task_receive) continue;
            try same(module, input, goal.ty, remaining);
            try same(module, module.typeOf(id), goal.result, remaining);
            const signature = module.types.node(goal.signature);
            try require(signature.tag == .function);
            try same(module, input, signature.a, remaining);
            try same(module, goal.result, signature.b, remaining);
            return goal;
        }
    }
    return error.InvalidArtifact;
}
pub fn receiveWrapper(initial: *const C.Module, initial_binding: C.BindingId, units: []const *const C.Module) Error!void {
    var module = initial;
    var binding_id = initial_binding;
    for (0..128) |_| {
        try require(binding_id != 0 and binding_id < module.bindings.len);
        const binding = module.bindings[binding_id];
        try require(binding.capability_flow == .consume_task and binding.body_id != 0 and binding.body_id < module.bodies.len);
        const body = module.bodies[binding.body_id];
        try require(body.root != 0 and body.root < module.nodes.len);
        const root = module.node(body.root);
        if (body.is_function) {
            try require(body.parameters.len == 1 and body.parameters.start < module.parameters.len);
            const formal = module.parameters[body.parameters.start];
            try require(root.tag == .task and (root.c == @backingInt(tasks.Op.join) or root.c == @backingInt(tasks.Op.receive)) and root.b == 1);
            const operand = module.children(body.root)[0];
            try require(module.node(operand).tag == .reference);
            const reference = module.reference(operand);
            try require((reference.unit == 0 or reference.unit == module.unit) and reference.binding == formal.binding);
            if (root.c == @backingInt(tasks.Op.join)) try require(tasks.isHandle(&module.types, formal.ty));
            return;
        }
        try require(body.parameters.len == 0 and root.tag == .reference);
        const reference = module.reference(body.root);
        binding_id = reference.binding;
        if (reference.unit != 0 and reference.unit != module.unit) {
            module = for (units) |candidate| {
                if (candidate.unit == reference.unit) break candidate;
            } else return error.InvalidArtifact;
        }
    }
    return error.InvalidArtifact;
}
fn ownerUnit(initial: *const C.Module, unit: u32, units: []const *const C.Module) Error!*const C.Module {
    if (unit == 0 or unit == initial.unit) return initial;
    var found: ?*const C.Module = null;
    for (units) |candidate| if (candidate.unit == unit) {
        try require(found == null);
        found = candidate;
    };
    return found orelse error.InvalidArtifact;
}
/// Only this exact body can defer capture admission to its callers. Aliases
/// preserve the same contract; arbitrary code cannot inherit the marker.
pub fn spawnWrapper(initial: *const C.Module, initial_binding: C.BindingId, units: []const *const C.Module) Error!void {
    var module = initial;
    var binding_id = initial_binding;
    for (0..128) |_| {
        try require(binding_id != 0 and binding_id < module.bindings.len);
        const binding = module.bindings[binding_id];
        try require(binding.kind == .global and binding.capability_flow == .spawn_task and binding.body_id != 0 and binding.body_id < module.bodies.len);
        const body = module.bodies[binding.body_id];
        try require(body.binding == binding_id);
        try require(body.root != 0 and body.root < module.nodes.len);
        const root = module.node(body.root);
        if (body.is_function) {
            try require(body.parameters.len == 2 and body.parameters.start < module.parameters.len and body.parameters.len <= module.parameters.len - body.parameters.start);
            try require(root.tag == .task and root.c == @backingInt(tasks.Op.spawn) and root.b == 2 and root.a < module.extra.len and root.b <= module.extra.len - root.a);
            for (module.children(body.root), module.parameters[body.parameters.start..][0..2]) |operand, parameter| {
                try require(operand != 0 and operand < module.nodes.len and module.node(operand).tag == .reference and module.node(operand).a < module.references.len);
                const reference = module.reference(operand);
                try require((reference.unit == 0 or reference.unit == module.unit) and reference.binding == parameter.binding);
            }
            try require(tasks.isGroup(&module.types, module.parameters[body.parameters.start].ty));
            const action = try once(module, module.children(body.root)[1]);
            try require(action.a == T.unit);
            return;
        }
        try require(body.parameters.len == 0 and root.tag == .reference and root.a < module.references.len);
        const reference = module.reference(body.root);
        binding_id = reference.binding;
        module = try ownerUnit(module, reference.unit, units);
    }
    return error.InvalidArtifact;
}
fn spawnFormal(module: *const C.Module, id: C.Id, units: []const *const C.Module) Error!bool {
    for (module.bindings, 0..) |binding, binding_id| {
        if (binding.capability_flow != .spawn_task or binding.body_id == 0) continue;
        try require(binding.body_id < module.bodies.len);
        const body = module.bodies[binding.body_id];
        if (body.root != id or !body.is_function) continue;
        try spawnWrapper(module, @intCast(binding_id), units);
        return true;
    }
    return false;
}
const SpawnValue = struct { group: C.Id = 0 };
pub const SpawnApplication = union(enum) {
    partial: C.Id,
    full: struct { group: C.Id, action: C.Id, carrier: C.Id = 0 },
};
pub fn spawnApplication(module: *const C.Module, id: C.Id, units: []const *const C.Module) Error!?SpawnApplication {
    const node = module.node(id);
    if (node.tag == .apply) {
        var remaining: usize = 65_536;
        const function = (try spawnValue(module, node.a, units, &remaining, 0)) orelse return null;
        if (function.group == 0) return .{ .partial = node.b };
        return .{ .full = .{ .group = function.group, .action = node.b, .carrier = node.a } };
    }
    if (node.tag != .call) return null;
    const call = module.call(id);
    const owner = try ownerUnit(module, call.target.unit, units);
    if (owner.binding(call.target.binding).capability_flow != .spawn_task) return null;
    try spawnWrapper(owner, call.target.binding, units);
    try require(call.arguments.len == 2);
    return .{ .full = .{ .group = call.arguments[0], .action = call.arguments[1] } };
}
fn spawnValue(module: *const C.Module, source: C.Id, units: []const *const C.Module, remaining: *usize, depth: usize) Error!?SpawnValue {
    try require(remaining.* != 0 and depth < 128);
    remaining.* -= 1;
    const node = module.node(source);
    if (node.tag == .apply) {
        const function = (try spawnValue(module, node.a, units, remaining, depth + 1)) orelse return null;
        if (function.group != 0) return null;
        return .{ .group = node.b };
    }
    if (node.tag != .reference) return null;
    const reference = module.reference(source);
    const owner = try ownerUnit(module, reference.unit, units);
    const binding = owner.binding(reference.binding);
    if (binding.capability_flow == .spawn_task) {
        try spawnWrapper(owner, reference.binding, units);
        return .{};
    }
    if (owner == module and binding.kind == .local and binding.initializer != 0) return spawnValue(module, binding.initializer, units, remaining, depth + 1);
    return null;
}
fn spawnCapture(module: *const C.Module, units: []const *const C.Module, site: C.Id, group: C.Id, action: C.Id, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    const closure = try callable(module, action);
    const owner = try groupOwner(module, units, group, remaining);
    try require(try inside(module, owner, site, remaining, 0));
    var scanner: Captures = .{ .workspace = workspace, .module = module, .units = units, .destination = owner, .remaining = remaining };
    for (module.bodies) |body| if (body.root != 0 and try inside(module, body.root, site, remaining, 0)) try scanner.rows(body.closed_rows);
    try scanner.check(closure);
}
fn spawnUses(module: *const C.Module, units: []const *const C.Module, id: C.Id, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    const node = module.node(id);
    if (node.tag == .call) {
        const call = module.call(id);
        const owner = try ownerUnit(module, call.target.unit, units);
        if (owner.binding(call.target.binding).capability_flow == .spawn_task) {
            try spawnWrapper(owner, call.target.binding, units);
            try require(call.arguments.len == 2);
            try spawnCapture(module, units, id, call.arguments[0], call.arguments[1], remaining, workspace);
        }
    } else if (node.tag == .apply) {
        if (try spawnValue(module, node.a, units, remaining, 0)) |function| {
            if (function.group != 0) try spawnCapture(module, units, id, function.group, node.b, remaining, workspace);
        }
    }
    // A transferable action needs the actual destination at a checked call.
    // Until a higher-order transfer contract exists, spawn callables and their
    // partial applications may flow through aliases, but cannot escape into
    // arbitrary data, callbacks or returned closures.
    const Visitor = struct {
        module: *const C.Module,
        units: []const *const C.Module,
        node: C.Node,
        remaining: *usize,
        pub fn append(self: *@This(), _: std.mem.Allocator, child: C.Id) error{PlanLimit}!void {
            if (child == 0) return;
            const value = spawnValue(self.module, child, self.units, self.remaining, 0) catch return error.PlanLimit;
            if (value == null) return;
            if ((self.node.tag == .apply and self.node.a == child) or (self.node.tag == .bind and self.node.b == child)) return;
            return error.PlanLimit;
        }
        pub fn appendSlice(self: *@This(), allocator: std.mem.Allocator, children: []const C.Id) error{PlanLimit}!void {
            for (children) |child| try self.append(allocator, child);
        }
    };
    var visitor: Visitor = .{ .module = module, .units = units, .node = node, .remaining = remaining };
    @import("../eval/body_recipe.zig").appendChildren(&visitor, std.heap.page_allocator, module, id, false) catch return error.InvalidArtifact;
}
pub fn receiveType(module: *const C.Module, input: T.Id, output: T.Id, remaining: *usize) Error!void {
    const shape = module.types.node(input);
    if (shape.tag != .product) {
        const arguments = try handle(module, input);
        return same(module, module.types.node(arguments[1]).b, output, remaining);
    }
    const result = module.types.node(output);
    try require(result.tag == .product and shape.b != 0 and shape.b <= 16 and shape.b == result.b);
    for (module.types.list(.{ .start = shape.a, .len = shape.b }), module.types.list(.{ .start = result.a, .len = result.b })) |item, field| {
        const arguments = try handle(module, item);
        try same(module, module.types.node(arguments[1]).b, field, remaining);
    }
}
/// Check the source-derived marker against the exact ordinary wrapper body.
/// The independently checked callback type owns the fresh-region contract.
pub fn scopeWrapper(module: *const C.Module, source: C.Id) bool {
    if (source == 0 or source >= module.nodes.len) return false;
    const node = module.node(source);
    if (node.tag != .task or node.c != @backingInt(tasks.Op.scope) or node.b != 1 or node.a >= module.extra.len) return false;
    const callback = module.children(source)[0];
    if (callback == 0 or callback >= module.nodes.len or module.node(callback).tag != .reference or module.node(callback).a >= module.references.len) return false;
    const reference = module.reference(callback);
    if (reference.unit != 0 and reference.unit != module.unit) return false;
    for (module.bindings, 0..) |binding, binding_id| {
        if (binding.capability_flow != .scope_task or binding.kind != .global or binding.body_id == 0 or binding.body_id >= module.bodies.len) continue;
        const body = module.bodies[binding.body_id];
        if (!body.is_function or body.binding != binding_id or body.root != source or body.parameters.len != 1 or body.parameters.start >= module.parameters.len) continue;
        if (module.parameters[body.parameters.start].binding == reference.binding) return true;
    }
    return false;
}
fn inside(module: *const C.Module, root: C.Id, target: C.Id, remaining: *usize, depth: usize) Error!bool {
    try require(remaining.* != 0 and depth < 128);
    remaining.* -= 1;
    if (root == target) return true;
    const node = module.node(root);
    if (node.tag == .closure or node.tag == .suspend_) return inside(module, module.closures[node.a].body, target, remaining, depth + 1);
    const Visitor = struct {
        module: *const C.Module,
        target: C.Id,
        remaining: *usize,
        depth: usize,
        found: bool = false,
        pub fn append(self: *@This(), _: std.mem.Allocator, child: C.Id) error{PlanLimit}!void {
            if (child == 0 or self.found) return;
            self.found = inside(self.module, child, self.target, self.remaining, self.depth) catch return error.PlanLimit;
        }
        pub fn appendSlice(self: *@This(), allocator: std.mem.Allocator, children: []const C.Id) error{PlanLimit}!void {
            for (children) |child| try self.append(allocator, child);
        }
    };
    var visitor: Visitor = .{ .module = module, .target = target, .remaining = remaining, .depth = depth + 1 };
    // The sink visits each edge immediately; the allocator is never used.
    @import("../eval/body_recipe.zig").appendChildren(&visitor, std.heap.page_allocator, module, root, false) catch return error.InvalidArtifact;
    return visitor.found;
}
fn groupOwner(module: *const C.Module, units: []const *const C.Module, source: C.Id, remaining: *usize) Error!C.Id {
    var current = source;
    for (0..128) |_| {
        try require(remaining.* != 0);
        remaining.* -= 1;
        const node = module.node(current);
        if (node.tag == .call) {
            const call = module.call(current);
            try require(call.arguments.len == 1);
            var producer = module;
            if (call.target.unit != 0 and call.target.unit != module.unit) {
                var found: ?*const C.Module = null;
                for (units) |candidate| {
                    if (candidate.unit != call.target.unit) continue;
                    try require(found == null);
                    found = candidate;
                }
                producer = found orelse return error.InvalidArtifact;
            }
            const body = producer.body(call.target.binding) orelse return error.InvalidArtifact;
            try require(@import("capability_flow.zig").unaryCoreWithOwners(producer, body, .identity, units));
            current = call.arguments[0];
            continue;
        }
        try require(node.tag == .reference);
        const reference = module.reference(current);
        try require(reference.unit == 0 or reference.unit == module.unit);
        const binding = module.binding(reference.binding);
        if (binding.kind == .local and binding.initializer != 0) {
            current = binding.initializer;
            continue;
        }
        try require(binding.kind == .parameter and tasks.isGroup(&module.types, binding.ty));
        for (module.nodes, 0..) |owner, id| {
            try require(remaining.* != 0);
            remaining.* -= 1;
            if (owner.tag == .closure and tasks.scopeCallback(&module.types, owner.ty) != null and module.closures[owner.a].parameter.binding == reference.binding) return @intCast(id);
            if (owner.tag != .task or owner.c != @backingInt(tasks.Op.scope)) continue;
            const callback = module.node(module.children(@intCast(id))[0]);
            if (callback.tag == .closure and module.closures[callback.a].parameter.binding == reference.binding) return @intCast(id);
        }
        return error.InvalidArtifact;
    }
    return error.InvalidArtifact;
}
fn enclosing(module: *const C.Module, raw: T.Id, destination: C.Id, remaining: *usize, depth: usize) Error!void {
    try require(remaining.* != 0 and depth < 128);
    remaining.* -= 1;
    const node = module.types.node(raw);
    if (tasks.isGroup(&module.types, raw)) {
        for (module.nodes, 0..) |owner, id| {
            try require(remaining.* != 0);
            remaining.* -= 1;
            if (owner.tag == .closure and tasks.scopeCallback(&module.types, owner.ty) != null) {
                const input = module.types.node(module.closures[owner.a].parameter.ty);
                if (input.tag == .scoped and input.b == node.b and input.c == node.c and try inside(module, @intCast(id), destination, remaining, depth + 1)) return;
            }
            if (owner.tag != .task or owner.c != @backingInt(tasks.Op.scope)) continue;
            const callback = module.node(module.children(@intCast(id))[0]);
            if (callback.tag != .closure) continue;
            const input = module.types.node(module.closures[callback.a].parameter.ty);
            if (input.tag == .scoped and input.b == node.b and input.c == node.c and try inside(module, @intCast(id), destination, remaining, depth + 1)) return;
        }
        return error.InvalidArtifact;
    }
    if (tasks.viewInfo(&module.types, raw)) |view| {
        for (module.nodes, 0..) |owner, id| {
            try require(remaining.* != 0);
            remaining.* -= 1;
            if (owner.tag != .task or owner.c != @backingInt(tasks.Op.split)) continue;
            const operands = module.children(@intCast(id));
            const callback = module.closure(operands[2]);
            const product = module.types.node(callback.parameter.ty);
            if (product.tag != .product) continue;
            for (module.types.list(.{ .start = product.a, .len = product.b })) |input| {
                const candidate = tasks.viewInfo(&module.types, input) orelse continue;
                if (candidate.scope == view.scope and candidate.version == view.version and try inside(module, @intCast(id), destination, remaining, depth + 1)) return;
            }
        }
        return error.InvalidArtifact;
    }
    switch (node.tag) {
        .usage => {
            if (node.b == @backingInt(T.UsageKind.borrow)) {
                var found = false;
                for (module.nodes, 0..) |owner, id| {
                    try require(remaining.* != 0);
                    remaining.* -= 1;
                    if (owner.tag != .usage_borrow or owner.c != 0) continue;
                    const callback = module.closure(owner.b);
                    const loan = module.types.node(callback.parameter.ty);
                    if (loan.tag == .usage and loan.b == @backingInt(T.UsageKind.borrow) and loan.c == node.c and try inside(module, @intCast(id), destination, remaining, depth + 1)) found = true;
                }
                try require(found);
            }
            try enclosing(module, node.a, destination, remaining, depth + 1);
        },
        .array, .list, .cursor, .demand => try enclosing(module, node.a, destination, remaining, depth + 1),
        .product => for (module.types.list(.{ .start = node.a, .len = node.b })) |child| try enclosing(module, child, destination, remaining, depth + 1),
        .record => for (0..node.b) |index| try enclosing(module, module.types.recordField(node, index).ty, destination, remaining, depth + 1),
        .nominal => for (module.types.nominalArguments(node)) |child| try enclosing(module, child, destination, remaining, depth + 1),
        else => {},
    }
}
pub fn validate(module: *const C.Module) Error!void {
    return validateContext(module, &.{});
}
pub fn validateContext(module: *const C.Module, units: []const *const C.Module) Error!void {
    return validateContextWorkspace(module, units, null);
}
pub fn validateContextWorkspace(module: *const C.Module, units: []const *const C.Module, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    var remaining: usize = 65_536;
    const spawn_contracts = contracts: {
        for (module.bindings) |binding| if (binding.capability_flow == .spawn_task) break :contracts true;
        for (units) |unit| for (unit.bindings) |binding| if (binding.capability_flow == .spawn_task) break :contracts true;
        break :contracts false;
    };
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .task) try validateOperationContextWorkspace(module, units, @intCast(id), &remaining, workspace);
        if (spawn_contracts and id != 0) try spawnUses(module, units, @intCast(id), &remaining, workspace);
    }
    if (spawn_contracts) for (module.bodies) |body| if (body.root != 0) {
        if (try spawnValue(module, body.root, units, &remaining, 0)) |value| try require(!body.is_function and value.group == 0 and module.binding(body.binding).capability_flow == .spawn_task);
    };
}
pub fn validateOperation(module: *const C.Module, id: C.Id, remaining: *usize) Error!void {
    return validateOperationContext(module, &.{}, id, remaining);
}
pub fn validateOperationContext(module: *const C.Module, units: []const *const C.Module, id: C.Id, remaining: *usize) Error!void {
    return validateOperationContextWorkspace(module, units, id, remaining, null);
}
pub fn validateOperationContextWorkspace(module: *const C.Module, units: []const *const C.Module, id: C.Id, remaining: *usize, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    const node = module.node(id);
    try require(node.tag == .task);
    try require(remaining.* != 0);
    remaining.* -= 1;
    const operation = std.enums.fromInt(tasks.Op, node.c) orelse return error.InvalidArtifact;
    try require(node.op == .none and node.b == tasks.arity(operation));
    const operands = module.children(@intCast(id));
    switch (operation) {
        .scope => {
            const arrow = try once(module, operands[0]);
            try require(tasks.isGroup(&module.types, arrow.a));
            if (module.node(operands[0]).tag == .closure) {
                try same(module, arrow.a, module.closure(operands[0]).parameter.ty, remaining);
            } else try require(tasks.scopeCallback(&module.types, module.typeOf(operands[0])) != null);
            try same(module, arrow.b, node.ty, remaining);
        },
        .spawn => {
            const group = module.typeOf(operands[0]);
            try require(tasks.isGroup(&module.types, group));
            const arrow = try once(module, operands[1]);
            try require(arrow.a == T.unit);
            const arguments = try handle(module, node.ty);
            try same(module, group, arguments[0], remaining);
            try same(module, module.types.node(module.typeOf(operands[1])).a, arguments[1], remaining);
            // Frozen capture lists do not grant absence of authority. Walk
            // actual executable references, including stored local callables.
            if (!try spawnFormal(module, id, units)) try spawnCapture(module, units, id, operands[0], operands[1], remaining, workspace);
        },
        .join, .cancel, .receive => {
            if (operation == .receive and module.types.node(module.typeOf(operands[0])).tag == .variable) {
                _ = try receiveRequirement(module, id, remaining);
                return;
            }
            const arguments = try handle(module, module.typeOf(operands[0]));
            var result = T.unit;
            if (operation != .cancel) result = module.types.node(arguments[1]).b;
            try same(module, result, node.ty, remaining);
        },
        .collect => {
            const input = module.types.node(module.typeOf(operands[0]));
            const output = module.types.node(node.ty);
            try require(input.tag == .product and output.tag == .product and input.b != 0 and input.b <= 16 and input.b == output.b);
            for (module.types.list(.{ .start = input.a, .len = input.b }), module.types.list(.{ .start = output.a, .len = output.b })) |item, result| {
                const arguments = try handle(module, item);
                try same(module, module.types.node(arguments[1]).b, result, remaining);
            }
        },
        .split => {
            _ = try @import("task_regions.zig").partition(module, @intCast(id));
            const arrow = try once(module, operands[2]);
            const output = module.types.node(node.ty);
            try require(output.tag == .product and output.b == 2);
            const results = module.types.list(.{ .start = output.a, .len = output.b });
            try same(module, module.typeOf(operands[0]), results[0], remaining);
            try same(module, arrow.b, results[1], remaining);
        },
        .read, .write => {
            const view = tasks.viewInfo(&module.types, module.typeOf(operands[0])) orelse return error.InvalidArtifact;
            const element = module.types.node(view.payload).a;
            if (operation == .read) {
                try require(!(@import("usage_check.zig").affineNominal(&module.types, module.nominals, element) catch return error.InvalidArtifact));
                try require((tasks.captureIssue(&module.types, element, false, remaining, 0) catch return error.InvalidArtifact) == null);
            }
            try require(module.typeOf(operands[1]) == T.u32_type);
            var result = element;
            if (operation == .write) {
                try same(module, element, module.typeOf(operands[2]), remaining);
                try require((tasks.captureIssue(&module.types, element, false, remaining, 0) catch return error.InvalidArtifact) == null);
                result = T.unit;
            }
            try same(module, result, node.ty, remaining);
        },
    }
}

const Captures = struct {
    workspace: ?*@import("scheme_equations.zig").Workspace = null,
    module: *const C.Module,
    units: []const *const C.Module,
    destination: C.Id,
    closed_rows: [4096]u32 = undefined,
    row_count: usize = 0,
    remaining: *usize,
    locals: [4096]u32 = undefined,
    local_count: usize = 0,
    seen: [4096]C.Id = undefined,
    seen_count: usize = 0,
    fn rows(self: *Captures, source: T.List) Error!void {
        const values = self.module.types.list(source);
        try require(values.len <= self.closed_rows.len - self.row_count);
        @memcpy(self.closed_rows[self.row_count..][0..values.len], values);
        self.row_count += values.len;
    }
    fn step(self: *Captures, depth: usize) Error!void {
        try require(self.remaining.* != 0 and depth < 128);
        self.remaining.* -= 1;
    }
    fn local(self: *Captures, binding: u32) Error!void {
        try self.step(0);
        if (std.mem.findScalar(u32, self.locals[0..self.local_count], binding) != null) return;
        try require(self.local_count < self.locals.len);
        self.locals[self.local_count] = binding;
        self.local_count += 1;
    }
    fn definitions(self: *Captures, id: C.Id, depth: usize) Error!void {
        try self.step(depth);
        const node = self.module.node(id);
        if (node.tag == .bind) try self.local(node.a);
        if (node.tag == .closure or node.tag == .suspend_) {
            try self.local(self.module.closures[node.a].parameter.binding);
            return self.definitions(self.module.closures[node.a].body, depth + 1);
        }
        try self.children(id, depth + 1, true);
    }
    fn references(self: *Captures, id: C.Id, depth: usize) Error!void {
        if (id == 0) return;
        try self.step(depth);
        if (std.mem.findScalar(C.Id, self.seen[0..self.seen_count], id) != null) return;
        try require(self.seen_count < self.seen.len);
        self.seen[self.seen_count] = id;
        self.seen_count += 1;
        const node = self.module.node(id);
        if (node.tag == .call) {
            // Named calls have no reference child. Their checked imported
            // signature must carry the same explicit transfer contract.
            // The selected arrow is only a use type. Reconstruct its exact
            // producer declaration, body and instantiated effects first.
            try @import("staging_core.zig").taskNamedContextWorkspace(self.module, self.units, id, false, self.remaining, self.workspace);
            const signature = self.module.call(id).callee_type;
            try require((tasks.captureIssueWithRows(&self.module.types, signature, false, self.remaining, depth + 1, self.closed_rows[0..self.row_count]) catch return error.InvalidArtifact) == null);
        }
        if (node.tag == .reference) {
            const reference = self.module.reference(id);
            if (reference.unit != 0 and reference.unit != self.module.unit) {
                try require((tasks.captureIssue(&self.module.types, node.ty, false, self.remaining, depth + 1) catch return error.InvalidArtifact) == null);
                try @import("staging_core.zig").taskNamedContextWorkspace(self.module, self.units, id, true, self.remaining, self.workspace);
                return;
            }
            if (std.mem.findScalar(u32, self.locals[0..self.local_count], reference.binding) != null) return;
            const binding = self.module.bindings[reference.binding];
            var capture_type = binding.ty;
            if (binding.kind == .global or binding.kind == .external) capture_type = node.ty;
            if (binding.kind == .global or binding.kind == .external) try @import("staging_core.zig").taskNamedContextWorkspace(self.module, self.units, id, true, self.remaining, self.workspace);
            try require((tasks.captureIssue(&self.module.types, capture_type, false, self.remaining, depth + 1) catch return error.InvalidArtifact) == null);
            try enclosing(self.module, capture_type, self.destination, self.remaining, depth + 1);
            if (tasks.isGroup(&self.module.types, capture_type)) {
                const owner = try groupOwner(self.module, self.units, id, self.remaining);
                try require(try inside(self.module, owner, self.destination, self.remaining, depth + 1));
            }
            const captured = self.module.types.node(capture_type);
            const data_scalar = captured.tag == .unit or captured.tag == .boolean or captured.tag == .u32 or captured.tag == .f32;
            if (binding.initializer != 0 and !data_scalar) {
                if (self.module.node(binding.initializer).tag == .closure) try self.definitions(binding.initializer, depth + 1);
                try self.references(binding.initializer, depth + 1);
            }
            return;
        }
        if (node.tag == .closure or node.tag == .suspend_) {
            const closure = self.module.closures[node.a];
            const previous = self.row_count;
            try self.rows(closure.closed_rows);
            defer self.row_count = previous;
            return self.references(closure.body, depth + 1);
        }
        try self.children(id, depth + 1, false);
    }
    fn children(self: *Captures, id: C.Id, depth: usize, comptime definitions_: bool) Error!void {
        const Visitor = struct {
            scanner: *Captures,
            depth: usize,
            pub fn append(visitor: *@This(), _: std.mem.Allocator, child: C.Id) error{PlanLimit}!void {
                if (child == 0) return;
                if (definitions_) {
                    visitor.scanner.definitions(child, visitor.depth) catch return error.PlanLimit;
                } else visitor.scanner.references(child, visitor.depth) catch return error.PlanLimit;
            }
            pub fn appendSlice(visitor: *@This(), allocator: std.mem.Allocator, values: []const C.Id) error{PlanLimit}!void {
                for (values) |child| try visitor.append(allocator, child);
            }
        };
        var visitor: Visitor = .{ .scanner = self, .depth = depth };
        @import("../eval/body_recipe.zig").appendChildren(&visitor, std.heap.page_allocator, self.module, id, false) catch return error.InvalidArtifact;
    }
    fn check(self: *Captures, closure: C.Id) Error!void {
        try self.definitions(closure, 0);
        try self.references(closure, 0);
    }
};
