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
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .task) try validateOperationContextWorkspace(module, units, @intCast(id), &remaining, workspace);
    }
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
            try require(module.node(operands[0]).tag == .closure and tasks.isGroup(&module.types, arrow.a));
            try same(module, arrow.a, module.closure(operands[0]).parameter.ty, remaining);
            try same(module, arrow.b, node.ty, remaining);
        },
        .spawn => {
            const group = module.typeOf(operands[0]);
            try require(tasks.isGroup(&module.types, group));
            const arrow = try once(module, operands[1]);
            try require(arrow.a == T.unit);
            const closure = try callable(module, operands[1]);
            const arguments = try handle(module, node.ty);
            try same(module, group, arguments[0], remaining);
            try same(module, module.types.node(module.typeOf(operands[1])).a, arguments[1], remaining);
            // Frozen capture lists do not grant absence of authority. Walk
            // actual executable references, including stored local callables.
            const owner = try groupOwner(module, units, operands[0], remaining);
            try require(try inside(module, owner, id, remaining, 0));
            var scanner: Captures = .{ .workspace = workspace, .module = module, .units = units, .destination = owner, .remaining = remaining };
            for (module.bodies) |body| {
                if (body.root != 0 and try inside(module, body.root, id, remaining, 0)) {
                    try scanner.rows(body.closed_rows);
                }
            }
            try scanner.check(closure);
        },
        .join, .cancel => {
            const arguments = try handle(module, module.typeOf(operands[0]));
            var result = T.unit;
            if (operation == .join) result = module.types.node(arguments[1]).b;
            try same(module, result, node.ty, remaining);
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
