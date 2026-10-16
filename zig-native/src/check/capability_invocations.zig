//! A conditional input-invocation contract is not a callable-type no-store
//! promise. Reconstruct the actual callback before transferring live authority.
const std = @import("std");
const C = @import("core.zig");
const T = @import("types.zig");
const flow = @import("capability_flow.zig");
const terms = @import("capability_contracts.zig");
const lifetimes = @import("capability_lifetimes.zig");
const Error = std.mem.Allocator.Error || error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
const Scan = struct {
    allocator: std.mem.Allocator,
    module: *const C.Module,
    owners: []const *const C.Module,
    graph: @import("frozen_core_validation.zig").Graph,
    remaining: usize = 65_536,
    scopes: std.ArrayList(struct { root: C.Id, report: ?lifetimes.Report }) = .empty,
    fn deinit(self: *Scan) void {
        for (self.scopes.items) |*item| if (item.report) |*report| report.deinit(self.allocator);
        self.scopes.deinit(self.allocator);
    }
    fn localStateStore(self: *Scan, scope: C.Id, call: C.Id, contract: flow.Parameters) Error!bool {
        if (scope == 0 or contract.argumentCount() != 1) return false;
        for (self.scopes.items) |*item| {
            try self.step(0);
            if (item.root == scope) return self.stateReport(item.report, call, contract);
        }
        const report = lifetimes.analyzeScope(self.allocator, self.module, self.owners, scope, &self.remaining) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => null,
            else => return error.InvalidArtifact,
        };
        var owned = report;
        errdefer if (owned) |*value| value.deinit(self.allocator);
        try self.scopes.append(self.allocator, .{ .root = scope, .report = owned });
        owned = null;
        return self.stateReport(self.scopes.items[self.scopes.items.len - 1].report, call, contract);
    }
    fn stateReport(self: *Scan, report: ?lifetimes.Report, call: C.Id, contract: flow.Parameters) Error!bool {
        return lifetimes.localStateInvocation(&(report orelse return false), self.module.unit, call, contract.callback(), contract.argumentAt(0), &self.remaining) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidArtifact;
    }
    fn step(self: *Scan, depth: usize) Error!void {
        try require(depth < 128 and self.remaining != 0);
        self.remaining -= 1;
    }
    fn owner(self: *const Scan, unit: u32) Error!*const C.Module {
        if (unit == 0 or unit == self.module.unit) return self.module;
        for (self.owners) |module| if (module.unit == unit) return module;
        return error.InvalidArtifact;
    }
    fn authority(self: *Scan, id: C.Id, scoped: bool, depth: usize) Error!bool {
        try self.step(depth);
        try require(id != 0 and id < self.module.nodes.len);
        const n = self.module.node(id);
        switch (self.module.types.node(n.ty).tag) {
            .scoped => return true,
            .unit, .boolean, .u32, .f32, .never => return false,
            else => {},
        }
        switch (n.tag) {
            .reference => {
                const ref = self.module.reference(id);
                if (ref.unit != 0 and ref.unit != self.module.unit) return scoped;
                const binding = self.module.bindings[ref.binding];
                if (binding.initializer != 0) return self.authority(binding.initializer, scoped, depth + 1);
                return scoped;
            },
            .product, .record, .array => {
                for (self.module.extra[n.a..][0..n.b]) |child| if (try self.authority(child, scoped, depth + 1)) return true;
                return false;
            },
            .construct => {
                if (n.b == 0) return false;
                return self.authority(n.b, scoped, depth + 1);
            },
            .closure, .suspend_ => {
                const closure = self.module.closures[n.a];
                for (self.module.extra[closure.captures.start..][0..closure.captures.len]) |binding| {
                    const capture = self.module.bindings[binding];
                    if (self.module.types.node(capture.ty).tag == .scoped) return true;
                    if (capture.initializer != 0 and try self.authority(capture.initializer, scoped, depth + 1)) return true;
                    if (capture.initializer == 0 and scoped) return true;
                }
                return false;
            },
            .if_value => return try self.authority(n.b, scoped, depth + 1) or try self.authority(n.c, scoped, depth + 1),
            else => return scoped,
        }
    }
    fn noStore(self: *Scan, id: C.Id, arity: u8, depth: usize) Error!bool {
        try self.step(depth);
        try require(id != 0 and id < self.module.nodes.len);
        const n = self.module.node(id);
        if (n.tag == .reference) {
            try require(n.a < self.module.references.len and n.ty < self.module.types.nodes.len);
            const ref = self.module.reference(id);
            const module = try self.owner(ref.unit);
            try require(ref.binding < module.bindings.len);
            const binding = module.bindings[ref.binding];
            if (module == self.module and binding.kind == .local and binding.initializer != 0) return self.noStore(binding.initializer, arity, depth + 1);
            if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= module.bodies.len) return false;
            const body = module.bodies[binding.body_id];
            if (body.parameters.len != arity) return false;
            const signature = self.module.types.node(n.ty);
            if (signature.tag != .function) return false;
            _ = @import("generative_relocation.zig").Relocation.init(module, self.module, binding.scheme, n.ty, n.ty, 0, 0) catch return false;
            if (arity == 1 and (binding.capability_flow == .identity or binding.capability_flow == .member_unit)) return flow.unaryCore(module, body, binding.capability_flow);
            if (binding.capability_flow != .input_shape or binding.scheme.generative.len != 0) return false;
            return @import("capability_contract_core.zig").inputBodyWithOwners(module, body, binding.capability_parameters, self.owners);
        }
        if (n.tag == .if_value) {
            const left = try self.noStore(n.b, arity, depth + 1);
            const right = try self.noStore(n.c, arity, depth + 1);
            return left and right;
        }
        if (n.tag != .closure and n.tag != .suspend_) {
            var value: terms.Store = .{};
            defer value.deinit(self.allocator);
            const root = @import("capability_contract_core.zig").callableValue(self.allocator, &value, self.module, id, self.owners) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return false;
            };
            return value.callableArity(root orelse return false, arity, &self.remaining, depth + 1) catch false;
        }
        if (n.a >= self.module.closures.len) return error.InvalidArtifact;
        var result: terms.Store = .{};
        defer result.deinit(self.allocator);
        const root = @import("capability_contract_core.zig").deriveInputFunctionClosureWithOwners(self.allocator, &result, self.module, self.module.closures[n.a], arity, self.owners) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        return root != null;
    }
    fn expression(self: *Scan, vertex: usize, scoped: bool, parent: C.Id, scope_root: C.Id, depth: usize) Error!void {
        try self.step(depth);
        const item = self.graph.item(vertex);
        var inside = scoped;
        var scope = scope_root;
        if (item.kind == .node and item.id != 0) {
            const id: C.Id = @intCast(item.id);
            const n = self.module.node(id);
            inside = scoped or n.tag == .effect_scope;
            if (scope == 0 and n.tag == .effect_scope) scope = id;
            if (parent == 0 and (n.tag == .call or n.tag == .apply)) {
                if (flow.coreCall(self.module, id)) |call| {
                    const producer = try self.owner(call.target.unit);
                    try require(call.target.binding < producer.bindings.len);
                    const contract = producer.bindings[call.target.binding].capability_parameters;
                    if (contract.inputInvokes() and contract.valid() and contract.arity() == call.len) {
                        var transfers = false;
                        for (0..contract.argumentCount()) |index| transfers = transfers or try self.authority(call.arguments[contract.argumentAt(index)], inside, 0);
                        if (transfers) try require(try self.noStore(call.arguments[contract.callback()], contract.argumentCount(), 0) or try self.localStateStore(scope, id, contract));
                    }
                }
            }
        }
        var slot: usize = 0;
        while (self.graph.edge(vertex, slot)) |child| : (slot += 1) {
            var application: C.Id = 0;
            if (item.kind == .node and item.id != 0) {
                const n = self.module.node(@intCast(item.id));
                const target = self.graph.item(child);
                if (n.tag == .apply and target.kind == .node and target.id == n.a) {
                    application = @intCast(item.id);
                    if (parent != 0) application = parent;
                }
            }
            try self.expression(child, inside, application, scope, depth + 1);
        }
    }
};
fn active(module: *const C.Module, owners: []const *const C.Module) bool {
    var contracts = false;
    for (module.bindings) |binding| if (binding.capability_parameters.inputInvokes()) {
        contracts = true;
        break;
    };
    if (!contracts) for (owners) |owner_| {
        for (owner_.bindings) |binding| if (binding.capability_parameters.inputInvokes()) {
            contracts = true;
            break;
        };
        if (contracts) break;
    };
    if (!contracts) return false;
    var scoped = false;
    for (module.types.nodes) |n| if (n.tag == .scoped) {
        scoped = true;
        break;
    };
    return scoped;
}
pub fn validateWithScratch(module: *const C.Module, owners: []const *const C.Module) error{InvalidArtifact}!void {
    if (!active(module, owners)) return;
    return buffered(module, owners);
}
noinline fn buffered(module: *const C.Module, owners: []const *const C.Module) error{InvalidArtifact}!void {
    var buffer: [1_048_576]u8 align(@alignOf(usize)) = undefined;
    var allocator: std.heap.FixedBufferAllocator = .init(&buffer);
    validate(allocator.allocator(), module, owners) catch return error.InvalidArtifact;
}
pub fn validate(allocator: std.mem.Allocator, module: *const C.Module, owners: []const *const C.Module) Error!void {
    if (!active(module, owners)) return;
    var scan: Scan = .{ .allocator = allocator, .module = module, .owners = owners, .graph = try @import("frozen_core_validation.zig").Graph.init(module) };
    defer scan.deinit();
    for (module.bodies) |body| if (body.root != 0) try scan.expression(scan.graph.vertex(.node, body.root), false, 0, 0, 0);
}

test "input invocation inspects storing conditions and opaque callback owners" {
    const allocator = std.testing.allocator;
    var types = try T.Store.init(allocator);
    defer types.deinit();
    const callback = try types.function(T.u32_type, T.u32_type);
    const predicate = try types.function(T.u32_type, T.boolean);
    const nested_callback = try types.function(T.unit, T.u32_type);
    var nodes = [_]C.Node{
        .{ .tag = .invalid },
        .{ .tag = .constant, .ty = T.boolean, .a = 1 },
        .{ .tag = .constant, .ty = T.u32_type, .a = 42 },
        .{ .tag = .reference, .ty = T.u32_type },
        .{ .tag = .reference, .ty = predicate, .a = 1 },
        .{ .tag = .apply, .ty = T.boolean, .a = 4, .b = 3 },
        .{ .tag = .if_value, .ty = T.u32_type, .a = 1, .b = 2, .c = 2 },
        .{ .tag = .logical, .ty = T.boolean, .op = .and_, .a = 5, .b = 1 },
        .{ .tag = .closure, .ty = callback },
        .{ .tag = .reference, .ty = callback, .a = 2 },
        .{ .tag = .closure, .ty = nested_callback, .a = 1 },
        .{ .tag = .bind, .a = 3, .b = 10 },
        .{ .tag = .return_, .ty = T.u32_type, .a = 2, .b = 13 },
        .{ .tag = .block, .ty = T.u32_type, .a = 1, .b = 2 },
        .{ .tag = .apply, .ty = T.u32_type, .a = 10, .b = 15 },
        .{ .tag = .constant, .ty = T.unit },
    };
    var spans: [nodes.len]C.Span = @splat(.{ .start = 0, .end = 1 });
    var bindings = [_]C.Binding{
        .{ .kind = .parameter, .ty = T.u32_type, .scheme = .{}, .target = .{ .binding = 0 }, .span = spans[0] },
        .{ .kind = .global, .ty = callback, .scheme = .{ .root = callback }, .target = .{ .binding = 1 }, .span = spans[0], .body_id = 1, .capability_flow = .identity },
        .{ .kind = .parameter, .ty = T.u32_type, .scheme = .{ .root = T.u32_type }, .target = .{ .binding = 2 }, .span = spans[0] },
        .{ .kind = .local, .ty = nested_callback, .scheme = .{ .root = nested_callback }, .target = .{ .binding = 3 }, .span = spans[0] },
        .{ .kind = .parameter, .ty = T.unit, .scheme = .{ .root = T.unit }, .target = .{ .binding = 4 }, .span = spans[0] },
    };
    var bodies = [_]C.Body{ .{}, .{ .binding = 1, .root = 3, .parameters = .{ .len = 1 }, .scheme = .{ .root = callback }, .is_function = true } };
    var parameters = [_]C.Parameter{.{ .binding = 2, .ty = T.u32_type, .span = spans[0] }};
    var references = [_]C.BindingRef{ .{ .binding = 2 }, .{ .unit = 2, .binding = 1 }, .{ .unit = 1, .binding = 1 } };
    var closures = [_]C.ClosureInfo{
        .{ .body = 6, .parameter = .{ .binding = 2, .ty = T.u32_type, .span = spans[0] }, .captures = .{}, .function_type = callback },
        .{ .body = 3, .parameter = .{ .binding = 4, .ty = T.unit, .span = spans[0] }, .captures = .{ .len = 1 }, .function_type = nested_callback },
    };
    var extra = [_]C.Id{ 2, 11, 12 };
    const module: C.Module = .{ .unit = 1, .types = .{ .nodes = types.nodes.items, .extra = types.extra.items, .effects = .{ .rows = types.effects.rows.items, .labels = types.effects.labels.items }, .operations = types.operations.items }, .nodes = &nodes, .spans = &spans, .extra = &extra, .bindings = &bindings, .bodies = &bodies, .parameters = &parameters, .references = &references, .calls = &.{}, .closures = &closures, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = 0 };
    var scan: Scan = .{ .allocator = allocator, .module = &module, .owners = &.{}, .graph = try @import("frozen_core_validation.zig").Graph.init(&module) };
    try std.testing.expect(try scan.noStore(8, 1, 0));
    // Equal scalar results do not erase a condition's argument transfer.
    nodes[6].a = 5;
    try std.testing.expect(!try scan.noStore(8, 1, 0));
    nodes[6].a = 7;
    try std.testing.expect(!try scan.noStore(8, 1, 0));
    closures[0].body = 13;
    try std.testing.expect(!try scan.noStore(8, 1, 0));
    closures[0].body = 14;
    try std.testing.expect(!try scan.noStore(8, 1, 0));
    // A same-shaped global reference supplies no executable callback proof.
    nodes[8] = .{ .tag = .reference, .ty = callback, .a = 1 };
    try std.testing.expectError(error.InvalidArtifact, scan.noStore(8, 1, 0));
    try std.testing.expect(try scan.noStore(9, 1, 0));
    parameters[0].binding = 0;
    try std.testing.expect(!try scan.noStore(9, 1, 0));
    parameters[0].binding = 2;
    bodies[1].root = 6;
    try std.testing.expect(!try scan.noStore(9, 1, 0));
    // The new marker proves this actual named body, including every discarded
    // prefix. A result graph alone cannot certify a hidden capture or sink.
    nodes[6].a = 1;
    bindings[1].capability_flow = .input_shape;
    bindings[1].capability_parameters = .init(1, 0);
    bodies[1].binding = 1;
    try std.testing.expect(try scan.noStore(9, 1, 0));
    bodies[1].root = 13;
    try std.testing.expect(!try scan.noStore(9, 1, 0));
    bodies[1].root = 14;
    try std.testing.expect(!try scan.noStore(9, 1, 0));
    bodies[1].root = 6;
    nodes[6].a = 5;
    try std.testing.expect(!try scan.noStore(9, 1, 0));
    nodes[6].a = 1;
    bodies[1].parameters.start = @intCast(parameters.len);
    try std.testing.expect(!try scan.noStore(9, 1, 0));
}

test "input invocation cannot hide opaque input transfer in discarded Unit request payloads" {
    const allocator = std.testing.allocator;
    var types = try T.Store.init(allocator);
    defer types.deinit();
    const payload = try types.array(T.u32_type);
    const descriptor = try types.nominal(.{ .unit = 1, .decl = 9 }, &.{payload});
    const carrier = try types.scoped(descriptor, .{ .unit = 1, .decl = 40 });
    const operation = try types.internScopedOperation(.{ .unit = 1, .decl = 11 }, .{ .unit = 1, .decl = 40 }, &.{payload});
    const row = try types.effects.row(&.{operation}, .closed);
    const request = try types.functionWithEffects(T.unit, payload, row);
    const callback = try types.functionWithEffects(carrier, T.u32_type, row);
    const opaque_signature = try types.function(carrier, carrier);
    var nodes = [_]C.Node{
        .{ .tag = .invalid },
        .{ .tag = .reference, .ty = carrier },
        .{ .tag = .reference, .ty = opaque_signature, .a = 1 },
        .{ .tag = .apply, .ty = carrier, .a = 2, .b = 1 },
        .{ .tag = .operation_value, .ty = request },
        .{ .tag = .constant, .ty = T.unit },
        .{ .tag = .apply, .ty = payload, .a = 4, .b = 5 },
        .{ .tag = .bind, .a = 1, .b = 6 },
        .{ .tag = .constant, .ty = T.u32_type },
        .{ .tag = .return_, .ty = T.u32_type, .a = 8, .b = 10 },
        .{ .tag = .block, .ty = T.u32_type, .b = 2 },
        .{ .tag = .closure, .ty = callback },
    };
    var spans: [nodes.len]C.Span = @splat(.{ .start = 0, .end = 1 });
    var extra = [_]C.Id{ 7, 9 };
    var bindings = [_]C.Binding{
        .{ .kind = .parameter, .ty = carrier, .scheme = .{}, .target = .{ .binding = 0 }, .span = spans[0] },
        .{ .kind = .local, .ty = payload, .scheme = .{}, .target = .{ .binding = 1 }, .span = spans[0] },
    };
    var references = [_]C.BindingRef{ .{ .binding = 0 }, .{ .unit = 2, .binding = 1 } };
    var closures = [_]C.ClosureInfo{.{ .body = 10, .parameter = .{ .binding = 0, .ty = carrier, .span = spans[0] }, .captures = .{}, .function_type = callback }};
    var operations = [_]C.OperationValue{.{ .identity = .{ .unit = 1, .decl = 11 }, .arguments = .{}, .signature = request, .instance = .{ .unit = 1, .decl = 40 }, .capability = 1 }};
    const module: C.Module = .{ .unit = 1, .types = .{ .nodes = types.nodes.items, .extra = types.extra.items, .effects = .{ .rows = types.effects.rows.items, .labels = types.effects.labels.items }, .operations = types.operations.items }, .nodes = &nodes, .spans = &spans, .extra = &extra, .bindings = &bindings, .bodies = &.{}, .parameters = &.{}, .references = &references, .calls = &.{}, .closures = &closures, .operation_values = &operations, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = 0 };
    var scan: Scan = .{ .allocator = allocator, .module = &module, .owners = &.{}, .graph = try @import("frozen_core_validation.zig").Graph.init(&module) };
    // A discarded non-scalar result is safe when the receiver is already
    // available; the unknown result cannot authorize an escaping value.
    try std.testing.expect(try scan.noStore(11, 1, 0));
    // An equally typed receiver obtained by transferring input to an opaque
    // helper cannot use that same discarded payload to erase the transfer.
    operations[0].capability = 3;
    try std.testing.expect(!try scan.noStore(11, 1, 0));
    operations[0].capability = 1;
    nodes[6].ty = @intCast(module.types.nodes.len);
    try std.testing.expect(!try scan.noStore(11, 1, 0));
}
