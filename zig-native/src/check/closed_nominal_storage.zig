//! Conditional closed storage is independent of affine/repeatable usage facts.
//! Nominal parameters must themselves be closed at each concrete use.
const T = @import("types.zig");
const usage = @import("usage_check.zig");
const core = @import("core.zig");
fn bounded(store: anytype, id: T.Id) bool {
    const storage = store.nodes;
    if (comptime @hasField(@TypeOf(storage), "items")) return id < storage.items.len;
    return id < storage.len;
}
fn words(store: anytype) []const T.Id {
    const storage = store.extra;
    if (comptime @hasField(@TypeOf(storage), "items")) return storage.items;
    return storage;
}
fn validList(store: anytype, list: T.List) bool {
    const extra = words(store);
    return list.start <= extra.len and list.len <= extra.len - list.start;
}
fn expression(store: anytype, nominals: anytype, owner: usize, root: T.Id, work: *usage.Work, depth: usize) T.Error!bool {
    try work.charge(1);
    if (depth >= 128 or !bounded(store, root)) return error.TypeLimit;
    const id = store.head(root, 0);
    if (!bounded(store, id)) return error.TypeLimit;
    const n = store.node(id);
    try usage.nominalShape(store, nominals, n, work);
    switch (n.tag) {
        .unit, .boolean, .u32, .f32 => return n.a == 0 and n.b == 0 and n.c == 0,
        .variable, .bound => {
            if (!validList(store, nominals[owner].variables)) return error.TypeLimit;
            for (store.list(nominals[owner].variables)) |variable| {
                try work.charge(1);
                if (!bounded(store, variable)) return error.TypeLimit;
                const formal = store.node(store.head(variable, 0));
                if (n.tag == .variable and formal.tag == .variable and n.a == formal.a) return true;
                if (n.tag == .bound and formal.tag == .bound and id == variable and n.b == 0) return true;
            }
            return false;
        },
        .array, .list => return n.b == 0 and n.c == 0 and try expression(store, nominals, owner, n.a, work, depth + 1),
        .product => {
            if (n.c != 0) return false;
            for (store.list(.{ .start = n.a, .len = n.b })) |child| if (!try expression(store, nominals, owner, child, work, depth + 1)) return false;
            return true;
        },
        .record => {
            if (n.c != 0) return false;
            for (0..n.b) |index| if (!try expression(store, nominals, owner, store.recordField(n, index).ty, work, depth + 1)) return false;
            return true;
        },
        .nominal => {
            // Definitions commonly refer to their own or preceding family.
            // Start at that owned catalog position; every comparison remains
            // charged, and wrapping still visits the complete catalog once.
            var index = owner;
            for (0..nominals.len) |_| {
                try work.charge(1);
                const nominal = nominals[index];
                if (index == 0) index = nominals.len;
                index -= 1;
                if (nominal.identity.unit != n.a or nominal.identity.decl != n.b) continue;
                if (!nominal.closed_storage or nominal.has_usage) return false;
                const arguments = store.nominalArguments(n);
                if (arguments.len != nominal.parameters.len) return false;
                for (arguments) |argument| if (!try expression(store, nominals, owner, argument, work, depth + 1)) return false;
                return true;
            }
            return false;
        },
        else => return false,
    }
}
pub fn facts(store: anytype, nominals: anytype, constructors: anytype, unit: u32, work: *usage.Work) T.Error!void {
    for (nominals) |*nominal| {
        try work.charge(1);
        if (nominal.identity.unit == unit) nominal.closed_storage = false;
    }
    for (constructors) |constructor| {
        try work.charge(1);
        if (constructor.nominal >= nominals.len or !bounded(store, constructor.payload)) return error.TypeLimit;
        const nominal = &nominals[constructor.nominal];
        if (nominal.identity.unit == unit and !nominal.has_usage) nominal.closed_storage = true;
    }
    // Greatest fixed point: recursive data is closed only if every constructor
    // is closed under its family's formal data parameter contract.
    for (0..nominals.len) |_| {
        try work.charge(1);
        var changed = false;
        for (constructors) |constructor| {
            try work.charge(1);
            const nominal = &nominals[constructor.nominal];
            if (constructor.payload == 0 or nominal.identity.unit != unit or !nominal.closed_storage) continue;
            if (try expression(store, nominals, constructor.nominal, constructor.payload, work, 0)) continue;
            nominal.closed_storage = false;
            changed = true;
        }
        if (!changed) break;
    }
}
pub fn validate(module: *const core.Module) error{InvalidArtifact}!void {
    var claimed = false;
    for (module.nominals, 0..) |nominal, index| {
        if (nominal.closed_storage and (index == 0 or nominal.identity.unit == 0 or nominal.identity.decl == 0)) return error.InvalidArtifact;
        if (nominal.closed_storage and nominal.has_usage) return error.InvalidArtifact;
        claimed = claimed or nominal.closed_storage;
    }
    if (!claimed) return;
    if (module.nominals.len > 4096) return error.InvalidArtifact;
    var storage: [4096]core.Nominal = undefined;
    const proved = storage[0..module.nominals.len];
    @memcpy(proved, module.nominals);
    var work: usage.Work = .{};
    for (proved, 0..) |nominal, owner| {
        work.charge(1) catch return error.InvalidArtifact;
        if (!nominal.closed_storage) continue;
        if (!validList(&module.types, nominal.variables) or !validList(&module.types, nominal.parameters)) return error.InvalidArtifact;
        for (module.types.list(nominal.variables)) |variable| {
            work.charge(1) catch return error.InvalidArtifact;
            if (!bounded(&module.types, variable)) return error.InvalidArtifact;
        }
        if (nominal.storage.kind == .parameter and nominal.storage.parameter >= nominal.parameters.len) return error.InvalidArtifact;
        for (module.types.list(nominal.parameters)) |parameter| {
            if (!(expression(&module.types, proved, owner, parameter, &work, 0) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        }
    }
    facts(&module.types, proved, module.constructors, module.unit, &work) catch return error.InvalidArtifact;
    for (module.nominals, proved) |declared, inferred| if (declared.closed_storage and !inferred.closed_storage) return error.InvalidArtifact;
    // Reconstruct opaque machine roles from concrete leaves, so mutually
    // claimed storage recipes cannot manufacture a reference/scalar role.
    for (proved) |*nominal| {
        if (nominal.identity.unit == module.unit and nominal.is_opaque) nominal.storage = .{};
    }
    var graph: @import("frozen_types.zig").Graph = .{ .nodes = module.types.nodes, .extra = module.types.extra, .rows = module.types.effects.rows, .labels = module.types.effects.labels, .operations = module.types.operations, .row_variable_count = module.types.effects.variable_count };
    for (0..proved.len) |_| {
        work.charge(1) catch return error.InvalidArtifact;
        var changed = false;
        for (proved, 0..) |*nominal, index| {
            work.charge(1) catch return error.InvalidArtifact;
            if (!nominal.closed_storage or !nominal.is_opaque or nominal.identity.unit != module.unit) continue;
            if (!validList(&module.types, nominal.parameters) or nominal.constructors.len != 1 or nominal.constructors.start >= module.extra.len) return error.InvalidArtifact;
            const id = module.extra[nominal.constructors.start];
            if (id == 0 or id >= module.constructors.len or module.constructors[id].nominal != index) return error.InvalidArtifact;
            const inferred = @import("../backend/opaque_storage.zig").inferPayload(.{ .frozen = &graph }, proved, module.constructors, module.constructors[id].payload, nominal.parameters, &work.remaining);
            if (work.remaining == 0) return error.InvalidArtifact;
            if (!@import("std").meta.eql(inferred, nominal.storage)) {
                nominal.storage = inferred;
                changed = true;
            }
        }
        if (!changed) break;
    }
    for (module.nominals, proved) |declared, inferred| if (inferred.closed_storage and inferred.is_opaque and inferred.identity.unit == module.unit and !@import("std").meta.eql(declared.storage, inferred.storage)) return error.InvalidArtifact;
    for (module.nodes) |node| {
        work.charge(1) catch return error.InvalidArtifact;
        if (node.tag != .constant) continue;
        if (node.op != .none or node.b != 0 or node.c != 0) return error.InvalidArtifact;
        if (!bounded(&module.types, node.ty)) return error.InvalidArtifact;
        var ty = module.types.node(node.ty);
        if (ty.tag == .usage) {
            if (!bounded(&module.types, ty.a)) return error.InvalidArtifact;
            ty = module.types.node(ty.a);
        }
        if (ty.tag != .unit and ty.tag != .boolean and ty.tag != .u32 and ty.tag != .f32) return error.InvalidArtifact;
    }
}

const Matcher = struct {
    module: *const core.Module,
    owner: usize,
    work: *usage.Work,
    formal: [128]T.Id = undefined,
    actual: [128]T.Id = undefined,
    count: usize = 0,
    fn match(self: *Matcher, expected: T.Id, actual: T.Id, replace: bool, depth: usize) T.Error!bool {
        try self.work.charge(1);
        const types = &self.module.types;
        if (depth >= 128 or !bounded(types, expected) or !bounded(types, actual)) return error.TypeLimit;
        const left = types.node(expected);
        const right = types.node(actual);
        try usage.nominalShape(types, self.module.nominals, left, self.work);
        try usage.nominalShape(types, self.module.nominals, right, self.work);
        if (replace and left.tag == .variable) {
            const vars = self.module.nominals[self.owner].variables;
            if (!validList(types, vars)) return error.TypeLimit;
            var owned = false;
            for (types.list(vars)) |variable| {
                try self.work.charge(1);
                if (!bounded(types, variable)) return error.TypeLimit;
                const leaf = types.node(variable);
                if (leaf.tag == .variable and leaf.a == left.a) owned = true;
            }
            if (!owned) return false;
            for (self.formal[0..self.count], self.actual[0..self.count]) |formal, value| {
                try self.work.charge(1);
                if (types.node(formal).a == left.a) return self.match(value, actual, false, depth + 1);
            }
            if (self.count == self.formal.len) return error.TypeLimit;
            self.formal[self.count] = expected;
            self.actual[self.count] = actual;
            self.count += 1;
            return true;
        }
        if (left.tag != right.tag) return false;
        switch (left.tag) {
            .unit, .boolean, .u32, .f32 => return left.a == 0 and left.b == 0 and left.c == 0 and right.a == 0 and right.b == 0 and right.c == 0,
            .array, .list => return try self.match(left.a, right.a, replace, depth + 1),
            .product => {
                if (left.b != right.b) return false;
                for (types.list(.{ .start = left.a, .len = left.b }), types.list(.{ .start = right.a, .len = right.b })) |a, b| if (!try self.match(a, b, replace, depth + 1)) return false;
            },
            .record => {
                if (left.b != right.b) return false;
                for (0..left.b) |index| {
                    const field = types.recordField(left, index);
                    var found = false;
                    for (0..right.b) |other| {
                        try self.work.charge(1);
                        const candidate = types.recordField(right, other);
                        if (candidate.name != field.name) continue;
                        if (found or !try self.match(field.ty, candidate.ty, replace, depth + 1)) return false;
                        found = true;
                    }
                    if (!found) return false;
                }
            },
            .nominal => {
                if (left.a != right.a or left.b != right.b) return false;
                const a = types.nominalArguments(left);
                const b = types.nominalArguments(right);
                if (a.len != b.len) return false;
                for (a, b) |av, bv| if (!try self.match(av, bv, replace, depth + 1)) return false;
            },
            else => return false,
        }
        return true;
    }
};
pub fn construction(module: *const core.Module, node: core.Node, work: *usage.Work) T.Error!bool {
    if (node.a == 0 or node.a >= module.constructors.len or !bounded(&module.types, node.ty) or node.op != .none or node.c > 1) return error.TypeLimit;
    const constructor = module.constructors[node.a];
    if (constructor.nominal >= module.nominals.len) return error.TypeLimit;
    const family = module.nominals[constructor.nominal];
    var output = module.types.node(node.ty);
    if (output.tag == .usage) {
        if (!bounded(&module.types, output.a)) return error.TypeLimit;
        output = module.types.node(output.a);
    }
    try usage.nominalShape(&module.types, module.nominals, output, work);
    if (output.tag != .nominal or output.a != family.identity.unit or output.b != family.identity.decl or !family.closed_storage) return false;
    var matcher: Matcher = .{ .module = module, .owner = constructor.nominal, .work = work };
    if (!validList(&module.types, family.parameters)) return error.TypeLimit;
    const actuals = module.types.nominalArguments(output);
    if (family.parameters.len != actuals.len) return false;
    for (module.types.list(family.parameters), actuals) |formal, actual| if (!try matcher.match(formal, actual, true, 0)) return false;
    if (node.b == 0) return constructor.payload == 0 and node.c == 0;
    if (node.b >= module.nodes.len or !bounded(&module.types, constructor.payload)) return error.TypeLimit;
    var expected = constructor.payload;
    const actual = module.typeOf(node.b);
    if (node.c != 0) {
        const record = module.types.node(expected);
        if (family.is_opaque or record.tag != .record or record.b == 0) return false;
        try usage.nominalShape(&module.types, module.nominals, record, work);
        if (record.b == 1) expected = module.types.recordField(record, 0).ty else {
            if (!bounded(&module.types, actual)) return error.TypeLimit;
            const tuple = module.types.node(actual);
            try usage.nominalShape(&module.types, module.nominals, tuple, work);
            if (tuple.tag != .product or tuple.b != record.b) return false;
            for (module.types.list(.{ .start = tuple.a, .len = tuple.b }), 0..) |field, index| if (!try matcher.match(module.types.recordField(record, index).ty, field, true, 0)) return false;
            return true;
        }
    }
    return matcher.match(expected, actual, true, 0);
}
