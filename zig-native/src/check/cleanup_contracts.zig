//! Cleanup authority is derived from a finite executable recipe, independently
//! at source and immutable Core boundaries. Qualifier spelling grants nothing.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const core = @import("core.zig");
const T = @import("types.zig");
const Error = error{UnsafeCleanup};
const Budget = struct {
    remaining: usize = 65_536,
    fn repeat(self: *Budget, before: usize, iterations: u32) Error!void {
        const work = before - self.remaining;
        if (iterations <= 1 or work == 0) return;
        const repeats = iterations - 1;
        if (repeats > self.remaining / work) return error.UnsafeCleanup;
        self.remaining -= work * repeats;
    }
    fn charge(self: *Budget, depth: usize) Error!void {
        if (depth >= 128 or self.remaining == 0) return error.UnsafeCleanup;
        self.remaining -= 1;
    }
};
fn scalar(tag: T.Tag) bool {
    return tag == .unit or tag == .boolean or tag == .u32 or tag == .f32;
}
fn typeBound(store: anytype, id: T.Id) bool {
    const nodes = store.nodes;
    if (comptime @hasField(@TypeOf(nodes), "items")) return id < nodes.items.len;
    return id < nodes.len;
}
fn rowBound(store: anytype, id: T.Effects.Id) bool {
    const rows = store.effects.rows;
    if (comptime @hasField(@TypeOf(rows), "items")) return id < rows.items.len;
    return id < rows.len;
}
fn NominalTypes(comptime Store: type, comptime Nominals: type) type {
    return struct {
        store: Store,
        nominals: Nominals,
        nodes: @FieldType(@typeInfo(Store).pointer.child, "nodes"),
        extra: @FieldType(@typeInfo(Store).pointer.child, "extra"),
        effects: @FieldType(@typeInfo(Store).pointer.child, "effects"),
        operations: @FieldType(@typeInfo(Store).pointer.child, "operations"),
        pub fn head(self: *const @This(), id: T.Id, cursor: T.Cursor) T.Id {
            return self.store.head(id, cursor);
        }
        pub fn node(self: *const @This(), id: T.Id) T.Node {
            return self.store.node(id);
        }
        pub fn row(self: *const @This(), id: T.Effects.Id) T.Effects.Row {
            return self.store.row(id);
        }
        pub fn rowLabels(self: *const @This(), id: T.Effects.Id) []const T.Effects.Label {
            return self.store.rowLabels(id);
        }
        pub fn operation(self: *const @This(), id: T.Effects.Label) T.Operation {
            return self.store.operation(id);
        }
        pub fn list(self: *const @This(), values: T.List) []const T.Id {
            return self.store.list(values);
        }
        pub fn nominalArguments(self: *const @This(), node_: T.Node) []const T.Id {
            return self.store.nominalArguments(node_);
        }
        pub fn recordField(self: *const @This(), node_: T.Node, index: usize) T.Field {
            return self.store.recordField(node_, index);
        }
    };
}
fn nominalTypes(store: anytype, nominals: anytype) NominalTypes(@TypeOf(store), @TypeOf(nominals)) {
    return .{ .store = store, .nominals = nominals, .nodes = store.nodes, .extra = store.extra, .effects = store.effects, .operations = store.operations };
}
pub fn payloadNominal(store: anytype, nominals: anytype, id: T.Id) bool {
    var view = nominalTypes(store, nominals);
    return payload(&view, id);
}
pub fn pureNominal(store: anytype, nominals: anytype, id: T.Id) bool {
    var view = nominalTypes(store, nominals);
    return pureType(&view, id);
}
pub fn hostNominal(store: anytype, nominals: anytype, id: T.Id) bool {
    var view = nominalTypes(store, nominals);
    return hostType(&view, id);
}
pub fn transferableNominal(store: anytype, nominals: anytype, id: T.Id) bool {
    var view = nominalTypes(store, nominals);
    return transferableType(&view, id);
}
/// Closed storage carries no hidden callable, provider, loan or ownership
/// authority. Every recursive edge and catalog word spends the same budget.
pub fn payload(store: anytype, id: T.Id) bool {
    var budget: Budget = .{};
    return payloadDepth(store, id, &budget, 0);
}
fn payloadDepth(store: anytype, id: T.Id, budget: *Budget, depth: usize) bool {
    budget.charge(depth) catch return false;
    if (!typeBound(store, id)) return false;
    const node = store.node(store.head(id, 0));
    if (scalar(node.tag)) return node.a == 0 and node.b == 0 and node.c == 0;
    if (node.tag == .array or node.tag == .list) return node.b == 0 and node.c == 0 and payloadDepth(store, node.a, budget, depth + 1);
    if (node.tag == .nominal) {
        if (comptime !@hasField(@TypeOf(store.*), "nominals")) return false;
        const storage = store.extra;
        const values = if (comptime @hasField(@TypeOf(storage), "items")) storage.items else storage;
        if (node.c >= values.len or values[node.c] > values.len - node.c - 1) return false;
        for (store.nominals) |nominal| {
            budget.charge(depth) catch return false;
            if (nominal.identity.unit != node.a or nominal.identity.decl != node.b) continue;
            if (!nominal.closed_storage or nominal.has_usage or values[node.c] != nominal.parameters.len) return false;
            for (store.nominalArguments(node)) |argument| if (!payloadDepth(store, argument, budget, depth + 1)) return false;
            return true;
        }
        return false;
    }
    if ((node.tag != .product and node.tag != .record) or node.c != 0) return false;
    const storage = store.extra;
    const values = if (comptime @hasField(@TypeOf(storage), "items")) storage.items else storage;
    var stride: usize = 1;
    var first: usize = node.a;
    if (node.tag == .record) {
        stride = 2;
        first += 1;
    }
    if (node.a > values.len or node.b > (values.len - node.a) / stride) return false;
    for (0..node.b) |index| {
        if (!payloadDepth(store, values[first + index * stride], budget, depth + 1)) return false;
    }
    return true;
}
fn equalStorage(store: *const core.Types, left: T.Id, right: T.Id, budget: *Budget, depth: usize) Error!bool {
    try budget.charge(depth);
    if (!typeBound(store, left) or !typeBound(store, right)) return error.UnsafeCleanup;
    if (left == right) return true;
    const a = store.node(left);
    const b = store.node(right);
    if (a.tag != b.tag) return false;
    if (scalar(a.tag)) return true;
    if (a.tag == .array or a.tag == .list) return equalStorage(store, a.a, b.a, budget, depth + 1);
    if (a.tag == .nominal) {
        if (a.a != b.a or a.b != b.b) return false;
        const aa = store.nominalArguments(a);
        const bb = store.nominalArguments(b);
        if (aa.len != bb.len) return false;
        for (aa, bb) |av, bv| if (!try equalStorage(store, av, bv, budget, depth + 1)) return false;
        return true;
    }
    if ((a.tag != .product and a.tag != .record) or a.b != b.b) return false;
    for (0..a.b) |index| {
        if (a.tag == .record) {
            const af = store.recordField(a, index);
            var found = false;
            for (0..b.b) |other| {
                try budget.charge(depth);
                const bf = store.recordField(b, other);
                if (af.name != bf.name) continue;
                if (found or !try equalStorage(store, af.ty, bf.ty, budget, depth + 1)) return false;
                found = true;
            }
            if (!found) return false;
        } else if (!try equalStorage(store, store.extra[a.a + index], store.extra[b.a + index], budget, depth + 1)) return false;
    }
    return true;
}
fn closedStorage(module: *const core.Module) Error!void {
    var view = nominalTypes(&module.types, module.nominals);
    var budget: Budget = .{};
    var constructor_work: @import("usage_check.zig").Work = .{};
    for (module.nodes) |node| {
        try budget.charge(0);
        if (node.tag != .product and node.tag != .record and node.tag != .array and node.tag != .construct) continue;
        var ty = node.ty;
        if (!typeBound(&module.types, ty)) return error.UnsafeCleanup;
        const wrapper = module.types.node(ty);
        if (wrapper.tag == .usage) {
            if (wrapper.c != 0 or (wrapper.b != @backingInt(T.UsageKind.unique) and wrapper.b != @backingInt(T.UsageKind.shared))) return error.UnsafeCleanup;
            ty = wrapper.a;
        }
        if (!payloadDepth(&view, ty, &budget, 0)) {
            if (wrapper.tag == .usage) return error.UnsafeCleanup;
            continue;
        }
        if (node.tag == .construct) {
            if (!(@import("closed_nominal_storage.zig").construction(module, node, &constructor_work) catch return error.UnsafeCleanup)) return error.UnsafeCleanup;
            continue;
        }
        const shape = module.types.node(ty);
        if (node.op != .none or node.a > module.extra.len or node.b > module.extra.len - node.a) return error.UnsafeCleanup;
        if (node.tag == .array) {
            if ((shape.tag != .array and shape.tag != .list) or node.c != 0) return error.UnsafeCleanup;
        } else if (shape.tag != @as(T.Tag, if (node.tag == .product) .product else .record) or shape.b != node.b) return error.UnsafeCleanup;
        if (node.tag == .record and (node.c > module.extra.len or node.b > module.extra.len - node.c)) return error.UnsafeCleanup;
        if (node.tag == .product and node.c != 0) return error.UnsafeCleanup;
        for (module.extra[node.a..][0..node.b], 0..) |child, index| {
            try budget.charge(0);
            if (child == 0 or child >= module.nodes.len) return error.UnsafeCleanup;
            var expected = shape.a;
            if (node.tag == .record) {
                const slot = module.extra[node.c + index];
                if (slot >= node.b) return error.UnsafeCleanup;
                for (module.extra[node.c..][0..index]) |prior| {
                    try budget.charge(0);
                    if (prior == slot) return error.UnsafeCleanup;
                }
                expected = module.types.recordField(shape, slot).ty;
            } else if (node.tag == .product) expected = module.types.extra[shape.a + index];
            const actual = module.typeOf(child);
            if (!payloadDepth(&view, actual, &budget, 0) or !try equalStorage(&module.types, expected, actual, &budget, 0)) return error.UnsafeCleanup;
        }
    }
}
pub fn pureType(store: anytype, id: T.Id) bool {
    if (!typeBound(store, id)) return false;
    const wrapper = store.node(store.head(id, 0));
    if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.cleanup) or wrapper.c != 0 or !typeBound(store, wrapper.a)) return false;
    const arrow = store.node(store.head(wrapper.a, 0));
    if (arrow.tag != .function or arrow.b != T.unit or arrow.c != 0 or !rowBound(store, 0) or store.row(0).labels.len != 0 or store.row(0).tail != .closed or !typeBound(store, arrow.a)) return false;
    const owner = store.node(store.head(arrow.a, 0));
    return owner.tag == .usage and owner.b == @backingInt(T.UsageKind.unique) and owner.c == 0 and payload(store, owner.a);
}
/// Host authority has an exact closed role; ordinary Foreign arrows carry no receipt.
pub fn hostType(store: anytype, id: T.Id) bool {
    if (!typeBound(store, id)) return false;
    const wrapper = store.node(store.head(id, 0));
    if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.cleanup) or wrapper.c != 0) return false;
    if (!typeBound(store, wrapper.a)) return false;
    const arrow = store.node(store.head(wrapper.a, 0));
    if (arrow.tag != .function or arrow.b != T.unit or !typeBound(store, arrow.a) or !rowBound(store, arrow.c) or store.row(arrow.c).tail != .closed) return false;
    const owner = store.node(store.head(arrow.a, 0));
    if (owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or !payload(store, owner.a)) return false;
    const row = store.row(arrow.c);
    const storage = store.effects.labels;
    const values = if (comptime @hasField(@TypeOf(storage), "items")) storage.items else storage;
    if (row.labels.len != 1 or row.labels.start >= values.len) return false;
    const labels = store.rowLabels(arrow.c);
    const operations = store.operations;
    const operation_count = if (comptime @hasField(@TypeOf(operations), "items")) operations.items.len else operations.len;
    if (labels[0] >= operation_count) return false;
    const operation = store.operation(labels[0]);
    return operation.identity.unit == 0 and operation.identity.decl == 1 and operation.instance.unit == 0 and operation.instance.decl == 0 and operation.arguments.len == 0;
}
pub fn sourceHost(engine: anytype, root: ast.Id) bool {
    var id = root;
    var remaining: usize = 128;
    while (engine.tree.node(id).tag == .group) {
        if (remaining == 0) return false;
        remaining -= 1;
        id = engine.tree.node(id).a;
    }
    if (engine.tree.node(id).tag != .name or engine.access_paths[id].len != 0 or engine.operation_refs[id] != 0) return false;
    const binding = engine.resolved[id];
    return binding != 0 and binding < engine.bindings.items.len and engine.bindings.items[binding].kind == .parameter and hostNominal(&engine.types, engine.nominals.items, engine.bindings.items[binding].ty) and hostNominal(&engine.types, engine.nominals.items, engine.expr_types[id]);
}
pub fn immutableHost(module: *const core.Module, root: core.Id) bool {
    if (root == 0 or root >= module.nodes.len) return false;
    const node = module.node(root);
    if (node.tag != .reference or node.op != .none or node.a >= module.references.len or node.b != 0 or node.c != 0 or node.ty >= module.types.nodes.len) return false;
    const reference = module.reference(root);
    if ((reference.unit != 0 and reference.unit != module.unit) or reference.binding == 0 or reference.binding >= module.bindings.len) return false;
    const binding = module.bindings[reference.binding];
    if (binding.kind != .parameter or binding.ty >= module.types.nodes.len) return false;
    return hostNominal(&module.types, module.nominals, binding.ty) and (@import("rank_equal.zig").equal(&module.types, node.ty, binding.ty, true) catch false);
}
fn pureIntrinsic(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "@u32.") or std.mem.startsWith(u8, name, "@f32.") or std.mem.eql(u8, name, "@panic") or std.mem.eql(u8, name, "@usage.read") or std.mem.eql(u8, name, "@usage.length");
}
pub fn source(engine: anytype, root: ast.Id) bool {
    return sourceRecipe(engine, root, false).safe;
}
pub fn sourceTransferred(engine: anytype, root: ast.Id) bool {
    return sourceRecipe(engine, root, true).safe;
}
/// Acquired owners can outlive the current loan/provider boundary. Initial
/// transfer admits only independently closed data captures, never hidden scope
/// authority or a callable with an unknown capture lifetime.
pub fn transferableType(store: anytype, id: T.Id) bool {
    const wrapper = store.node(store.head(id, 0));
    if (wrapper.tag != .usage) return payload(store, id);
    if (wrapper.c != 0 or (wrapper.b != @backingInt(T.UsageKind.unique) and wrapper.b != @backingInt(T.UsageKind.shared))) return false;
    return payload(store, wrapper.a);
}
pub fn sourceForeign(engine: anytype, root: ast.Id) bool {
    return sourceRecipe(engine, root, false).host;
}
const SourceReceipt = struct { safe: bool = false, host: bool = false };
fn sourceRecipe(engine: anytype, root: ast.Id, transferred: bool) SourceReceipt {
    const Walker = struct {
        engine: @TypeOf(engine),
        budget: Budget = .{},
        transferred: bool,
        host: bool = false,
        const Self = @This();
        fn callable(self: *Self, root_: ast.Id, depth: usize) Error!void {
            try self.budget.charge(depth);
            const node = self.engine.tree.node(root_);
            switch (node.tag) {
                .group => try self.callable(node.a, depth + 1),
                .name => {
                    if (!sourceHost(self.engine, root_)) return error.UnsafeCleanup;
                    self.host = true;
                },
                .intrinsic => if (!pureIntrinsic(self.engine.pool.get(node.a))) return error.UnsafeCleanup,
                .apply => {
                    try self.callable(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                },
                else => return error.UnsafeCleanup,
            }
        }
        fn integer(self: *Self, root_: ast.Id, depth: usize) Error!u32 {
            try self.budget.charge(depth);
            const node = self.engine.tree.node(root_);
            if (node.tag == .group) return self.integer(node.a, depth + 1);
            if (node.tag != .integer) return error.UnsafeCleanup;
            return node.a;
        }
        fn range(self: *Self, first: ast.Id, end: ast.Id, body: ast.Id, depth: usize) Error!void {
            const low = try self.integer(first, depth + 1);
            const high = try self.integer(end, depth + 1);
            var iterations: u32 = 0;
            if (low < high) iterations = high - low;
            const before = self.budget.remaining;
            try self.budget.charge(depth + 1);
            try self.expression(body, depth + 1);
            try self.budget.repeat(before, iterations);
        }
        fn expression(self: *Self, id: ast.Id, depth: usize) Error!void {
            if (id == 0) return;
            try self.budget.charge(depth);
            const node = self.engine.tree.node(id);
            switch (node.tag) {
                .name => {
                    // Qualified names can already encode an implicit member
                    // invocation without an AST field-access node.
                    if (self.engine.access_paths[id].len != 0 or self.engine.operation_refs[id] != 0) return error.UnsafeCleanup;
                    if (self.transferred) {
                        const binding = self.engine.resolved[id];
                        if (binding == 0 or binding >= self.engine.bindings.items.len or (!sourceHost(self.engine, id) and (!transferableNominal(&self.engine.types, self.engine.nominals.items, self.engine.expr_types[id]) or !transferableNominal(&self.engine.types, self.engine.nominals.items, self.engine.bindings.items[binding].ty)))) return error.UnsafeCleanup;
                    }
                },
                .integer, .float, .boolean, .unit, .string => {},
                .apply => {
                    try self.callable(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                },
                .group, .return_stmt => try self.expression(node.a, depth + 1),
                .field => try self.expression(node.b, depth + 1),
                .product, .record, .array, .block => {
                    if (node.tag == .block and node.c != 0) return error.UnsafeCleanup;
                    for (self.engine.tree.children(id)) |child| try self.expression(child, depth + 1);
                },
                .let_stmt => {
                    const binding = self.engine.tree.binding(id);
                    if (binding.fallback != 0) return error.UnsafeCleanup;
                    try self.expression(binding.value, depth + 1);
                },
                .if_expr, .if_stmt => {
                    try self.expression(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                    try self.expression(node.c, depth + 1);
                },
                .range_stmt => try self.range(node.a, node.b, node.c, depth + 1),
                .for_stmt => {
                    const details = self.engine.tree.extra.items[node.c..][0..3];
                    if (details[0] == 0) return error.UnsafeCleanup;
                    try self.range(node.b, details[0], details[1], depth + 1);
                },
                // Every body is checked even for an empty range. Unknown
                // iteration protocols and calls have no finite receipt.
                else => return error.UnsafeCleanup,
            }
        }
    };
    var walker: Walker = .{ .engine = engine, .transferred = transferred };
    var direct = root;
    while (engine.tree.node(direct).tag == .group) direct = engine.tree.node(direct).a;
    if (engine.tree.node(direct).tag != .lambda) {
        const host = sourceHost(engine, direct);
        return .{ .safe = host, .host = host };
    }
    walker.expression(engine.tree.node(direct).b, 0) catch return .{};
    return .{ .safe = true, .host = walker.host };
}
pub fn immutable(module: *const core.Module, root: core.Id) Error!void {
    return immutableRecipe(module, root, false, null);
}
pub fn immutableTransferred(module: *const core.Module, root: core.Id) Error!void {
    return immutableRecipe(module, root, true, null);
}
/// The lifetime reader's scalar role has constant-size type checks. The
/// executable recipe spends its caller's shared admission budget.
pub fn immutableScalarWithBudget(module: *const core.Module, root: core.Id, remaining: *usize) Error!void {
    if (remaining.* < 8) {
        remaining.* = 0;
        return error.UnsafeCleanup;
    }
    remaining.* -= 8;
    if (root == 0 or root >= module.nodes.len or module.node(root).tag != .closure or !typeBound(&module.types, module.typeOf(root))) return error.UnsafeCleanup;
    const n = module.node(root);
    if (n.op != .none or n.b != 0 or n.c != 0 or n.a >= module.closures.len) return error.UnsafeCleanup;
    const closure_ = module.closures[n.a];
    if (closure_.body == 0 or closure_.body >= module.nodes.len or !typeBound(&module.types, module.typeOf(closure_.body)) or !typeBound(&module.types, closure_.parameter.ty)) return error.UnsafeCleanup;
    const wrapper = module.types.node(module.typeOf(root));
    if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.cleanup) or wrapper.c != 0 or !typeBound(&module.types, wrapper.a)) return error.UnsafeCleanup;
    const arrow = module.types.node(wrapper.a);
    if (arrow.tag != .function or arrow.b != T.unit or arrow.c != 0 or !typeBound(&module.types, arrow.a)) return error.UnsafeCleanup;
    const owner = module.types.node(arrow.a);
    if (owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or !typeBound(&module.types, owner.a)) return error.UnsafeCleanup;
    const payload_ = module.types.node(owner.a);
    if (!scalar(payload_.tag) or payload_.a != 0 or payload_.b != 0 or payload_.c != 0) return error.UnsafeCleanup;
    return immutableRecipe(module, root, false, remaining);
}
fn immutableRecipe(module: *const core.Module, root: core.Id, transferred: bool, remaining: ?*usize) Error!void {
    if (immutableHost(module, root)) return;
    if (root == 0 or root >= module.nodes.len or module.node(root).tag != .closure) return error.UnsafeCleanup;
    if (module.node(root).a >= module.closures.len) return error.UnsafeCleanup;
    const closure_ = module.closure(root);
    return immutableAdapter(module, module.typeOf(root), closure_.parameter, closure_.body, transferred, remaining);
}
fn immutableAdapter(module: *const core.Module, ty: T.Id, parameter: core.Parameter, body: core.Id, transferred: bool, remaining: ?*usize) Error!void {
    const Walker = struct {
        module: *const core.Module,
        budget: Budget = .{},
        transferred: bool,
        host: bool = false,
        const Self = @This();
        fn callable(self: *Self, id: core.Id, depth: usize) Error!void {
            try self.budget.charge(depth);
            if (id == 0 or id >= self.module.nodes.len) return error.UnsafeCleanup;
            const node = self.module.node(id);
            switch (node.tag) {
                .apply => {
                    try self.callable(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                },
                .reference => {
                    if (!immutableHost(self.module, id)) return error.UnsafeCleanup;
                    self.host = true;
                },
                // A first-class primitive is compiler owned; primitive effects
                // are excluded by the constructor's finite scalar catalog.
                .primitive_function => {
                    if (node.a >= self.module.primitives.len or node.op != .none or node.b != 0 or node.c != 0 or self.module.primitive(id).kind != .scalar) return error.UnsafeCleanup;
                },
                else => return error.UnsafeCleanup,
            }
        }
        fn expression(self: *Self, id: core.Id, depth: usize) Error!void {
            if (id == 0) return;
            try self.budget.charge(depth);
            if (id >= self.module.nodes.len) return error.UnsafeCleanup;
            const node = self.module.node(id);
            switch (node.tag) {
                .constant, .panic => {},
                .reference => if (self.transferred) {
                    const binding = self.module.reference(id).binding;
                    if (binding == 0 or binding >= self.module.bindings.len or (!immutableHost(self.module, id) and (!transferableNominal(&self.module.types, self.module.nominals, node.ty) or !transferableNominal(&self.module.types, self.module.nominals, self.module.bindings[binding].ty)))) return error.UnsafeCleanup;
                },
                .scalar, .logical, .proof_guard => {
                    try self.expression(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                },
                .return_, .usage_read => try self.expression(node.a, depth + 1),
                .bind => try self.expression(node.b, depth + 1),
                .product, .record, .array, .block, .suite => for (self.module.children(id)) |child| try self.expression(child, depth + 1),
                .if_value, .if_stmt => {
                    try self.expression(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                    try self.expression(node.c, depth + 1);
                },
                .loop => {
                    if (node.a >= self.module.loops.len or node.b != 0 or node.c != 0 or node.ty != T.unit) return error.UnsafeCleanup;
                    const loop = self.module.loopInfo(id);
                    if (loop.kind != .range or loop.carries.len != 0 or loop.first == 0 or loop.end == 0 or loop.body == 0 or loop.body >= self.module.nodes.len or loop.first >= self.module.nodes.len or loop.end >= self.module.nodes.len) return error.UnsafeCleanup;
                    const first = self.module.node(loop.first);
                    const end = self.module.node(loop.end);
                    if (first.tag != .constant or end.tag != .constant or first.ty != T.u32_type or end.ty != T.u32_type or first.op != .none or end.op != .none or first.b != 0 or first.c != 0 or end.b != 0 or end.c != 0) return error.UnsafeCleanup;
                    var iterations: u32 = 0;
                    if (first.a < end.a) iterations = end.a - first.a;
                    const before = self.budget.remaining;
                    try self.budget.charge(depth + 1);
                    try self.expression(loop.body, depth + 1);
                    try self.budget.repeat(before, iterations);
                },
                .apply => {
                    try self.callable(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                },
                else => return error.UnsafeCleanup,
            }
        }
    };
    var walker: Walker = .{ .module = module, .transferred = transferred };
    if (remaining) |budget| walker.budget.remaining = budget.*;
    defer if (remaining) |budget| {
        budget.* = walker.budget.remaining;
    };
    if ((!pureNominal(&module.types, module.nominals, ty) and !hostNominal(&module.types, module.nominals, ty)) or body == 0 or body >= module.nodes.len or !typeBound(&module.types, parameter.ty)) return error.UnsafeCleanup;
    const header = module.types.node(module.types.node(ty).a);
    if (!(@import("rank_equal.zig").equal(&module.types, header.a, parameter.ty, true) catch return error.UnsafeCleanup) or (module.typeOf(body) != T.never and !(@import("rank_equal.zig").equal(&module.types, header.b, module.typeOf(body), true) catch return error.UnsafeCleanup))) return error.UnsafeCleanup;
    try walker.expression(body, 0);
    if (walker.host != (header.c != 0)) return error.UnsafeCleanup;
}

/// Every cleanup qualifier needs an owning source scope and an independently
/// reconstructed executable adapter. An unused or imported type spelling is
/// not a portable cleanup receipt. All Core readers run this admission pass.
pub fn validate(module: *const core.Module) error{InvalidArtifact}!void {
    closedStorage(module) catch return error.InvalidArtifact;
    var owned: [4096]T.Id = undefined;
    var count: usize = 0;
    var budget: Budget = .{};
    for (module.nodes, 0..) |node, id| {
        budget.charge(0) catch return error.InvalidArtifact;
        if (node.tag == .resource_scope or node.tag == .resource_acquire) {
            if (count == owned.len or node.b == 0 or node.b >= module.nodes.len) return error.InvalidArtifact;
            owned[count] = module.typeOf(node.b);
            count += 1;
        }
        if (node.tag == .bind) {
            if (node.a == 0 or node.a >= module.bindings.len or node.b == 0 or node.b >= module.nodes.len) return error.InvalidArtifact;
            const binding = module.bindings[node.a];
            if (pureNominal(&module.types, module.nominals, binding.ty)) {
                const value = module.node(node.b);
                if (value.tag != .closure or value.a >= module.closures.len) return error.InvalidArtifact;
                const closure_ = module.closure(node.b);
                var actual = module.typeOf(node.b);
                if (!typeBound(&module.types, actual)) return error.InvalidArtifact;
                if (module.types.node(actual).tag == .usage) actual = module.types.node(actual).a;
                if (!typeBound(&module.types, actual) or !(@import("rank_equal.zig").equal(&module.types, module.types.node(binding.ty).a, actual, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
                immutableAdapter(module, binding.ty, closure_.parameter, closure_.body, false, null) catch return error.InvalidArtifact;
                if (count == owned.len) return error.InvalidArtifact;
                owned[count] = binding.ty;
                count += 1;
            }
        }
        if (!typeBound(&module.types, node.ty)) return error.InvalidArtifact;
        const wrapper = module.types.node(node.ty);
        if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.cleanup)) continue;
        if (node.tag != .closure and !immutableHost(module, @intCast(id))) return error.InvalidArtifact;
        immutable(module, @intCast(id)) catch return error.InvalidArtifact;
        if (node.tag == .closure) {
            if (count == owned.len) return error.InvalidArtifact;
            owned[count] = node.ty;
            count += 1;
        }
    }
    for (module.bodies, 0..) |body, body_index| {
        budget.charge(0) catch return error.InvalidArtifact;
        if (body.binding == 0) continue;
        if (body.binding >= module.bindings.len) return error.InvalidArtifact;
        const binding = module.bindings[body.binding];
        if (!typeBound(&module.types, binding.ty)) return error.InvalidArtifact;
        const wrapper = module.types.node(binding.ty);
        if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.cleanup)) continue;
        if (binding.kind != .global or binding.body_id != body_index or !body.is_function or body.parameters.len != 1 or body.parameters.start >= module.parameters.len or !pureNominal(&module.types, module.nominals, binding.ty)) return error.InvalidArtifact;
        const parameter = module.parameters[body.parameters.start];
        if (parameter.binding == 0 or parameter.binding >= module.bindings.len or module.bindings[parameter.binding].kind != .parameter or !typeBound(&module.types, parameter.ty) or !typeBound(&module.types, module.bindings[parameter.binding].ty) or !(@import("rank_equal.zig").equal(&module.types, parameter.ty, module.bindings[parameter.binding].ty, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        if (!pureNominal(&module.types, module.nominals, binding.scheme.root) or !pureNominal(&module.types, module.nominals, body.scheme.root) or !(@import("rank_equal.zig").equal(&module.types, binding.ty, binding.scheme.root, true) catch return error.InvalidArtifact) or !(@import("rank_equal.zig").equal(&module.types, binding.ty, body.scheme.root, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        immutableAdapter(module, binding.ty, parameter, body.root, false, null) catch return error.InvalidArtifact;
        if (count == owned.len) return error.InvalidArtifact;
        owned[count] = binding.ty;
        count += 1;
    }
    for (module.types.nodes, 0..) |node, id| {
        if (node.tag != .usage or node.b != @backingInt(T.UsageKind.cleanup)) continue;
        if (!pureNominal(&module.types, module.nominals, @intCast(id)) and !hostNominal(&module.types, module.nominals, @intCast(id))) return error.InvalidArtifact;
        var witnessed = false;
        for (owned[0..count]) |type_| {
            budget.charge(0) catch return error.InvalidArtifact;
            if (@import("rank_equal.zig").equal(&module.types, type_, @intCast(id), true) catch return error.InvalidArtifact) witnessed = true;
        }
        if (!witnessed and hostNominal(&module.types, module.nominals, @intCast(id))) {
            for (module.parameters) |parameter| {
                budget.charge(0) catch return error.InvalidArtifact;
                if (parameter.ty == id and parameter.binding != 0 and parameter.binding < module.bindings.len and module.bindings[parameter.binding].kind == .parameter) witnessed = true;
            }
        }
        if (!witnessed) return error.InvalidArtifact;
    }
}
