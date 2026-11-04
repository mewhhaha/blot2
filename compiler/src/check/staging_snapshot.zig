//! Staged evaluator records retain source owners, never bare graph ordinals.
//! The envelope, Core, evidence and ordinary snapshot bounds are checked first.
const core = @import("core.zig");
const eval = @import("../eval/core_eval.zig");
const staging = @import("typed_staging.zig");
const std = @import("std");
const E = @import("../eval/type_evidence.zig");
const T = @import("types.zig");
const Error = std.mem.Allocator.Error || error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
fn Shapes(comptime Units: type) type {
    return struct {
        const Self = @This();
        units: Units,
        snapshot: *const eval.Snapshot,
        store: E.Store,
        imported: []E.Id,
        remaining: usize = 1_000_000,
        formal: ?u32 = null,
        fn step(self: *Self, depth: usize) Error!void {
            try require(depth < 128 and self.remaining != 0);
            self.remaining -= 1;
        }
        fn failure(err: E.Error) Error {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.InvalidArtifact;
        }
        fn nominal(self: *Self, unit: u32, decl: u32, arguments: usize) Error!struct { module: *const core.Module, index: u32 } {
            try require(unit != 0 and unit <= self.units.len and decl != 0);
            const module = &self.units[unit - 1].core;
            var found: ?u32 = null;
            for (module.nominals, 0..) |family, index| {
                try self.step(0);
                if (family.identity.decl != decl or (family.identity.unit != 0 and family.identity.unit != unit)) continue;
                // A snapshot retains the exact producer identity and payload;
                // it grants no source-level field or constructor access. The
                // owning producer may lift its own sealed immutable values.
                try require(found == null and family.parameters.len == arguments);
                found = @intCast(index);
            }
            return .{ .module = module, .index = found orelse return error.InvalidArtifact };
        }
        fn row(self: *Self, id: E.Effects.Id, depth: usize) Error!E.Effects.Id {
            try self.step(depth);
            var labels: std.ArrayList(E.Effects.Label) = .empty;
            defer labels.deinit(self.store.allocator);
            const view = self.snapshot.evidence.view().effects;
            for (view.rowLabels(id)) |label| {
                const operation = view.operation(label);
                // Scoped operation instances need a value-owner authority proof.
                try require(operation.instance.unit != 0 or operation.instance.decl == 0);
                var arguments: std.ArrayList(E.Id) = .empty;
                defer arguments.deinit(self.store.allocator);
                for (view.operationArguments(label)) |argument| try arguments.append(self.store.allocator, try self.evidence(argument, depth + 1));
                try labels.append(self.store.allocator, self.store.effects.internOperationInstance(operation.identity, arguments.items, operation.instance) catch |err| return failure(err));
            }
            return self.store.effects.internRow(labels.items) catch |err| return failure(err);
        }
        fn evidence(self: *Self, id: E.Id, depth: usize) Error!E.Id {
            try self.step(depth);
            try require(id != 0);
            const owned = self.snapshot.evidence.view().node(id);
            if (owned.tag == .bound) {
                try require(self.formal != null and owned.a < self.formal.? and owned.b == 0 and owned.c == 0);
            }
            if (self.imported[id] != 0) return self.imported[id];
            const view = self.snapshot.evidence.view();
            const n = view.node(id);
            var result: E.Id = 0;
            switch (n.tag) {
                .unit, .boolean, .u32, .f32, .never => result = id,
                .bound => result = self.store.intern(.bound, n.a, 0, &.{}) catch |err| return failure(err),
                .existential => {
                    try require(self.formal == null);
                    self.formal = n.b;
                    defer self.formal = null;
                    result = self.store.intern(.existential, try self.evidence(n.a, depth + 1), n.b, &.{}) catch |err| return failure(err);
                },
                .function, .demand => result = self.store.internWithEffects(n.tag, try self.evidence(n.a, depth + 1), if (n.tag == .function) try self.evidence(n.b, depth + 1) else 0, try self.row(n.c, depth + 1), &.{}) catch |err| return failure(err),
                .array, .list => result = self.store.intern(n.tag, try self.evidence(n.a, depth + 1), 0, &.{}) catch |err| return failure(err),
                .product, .record, .nominal => {
                    if (n.tag == .nominal and !staging.isIdentity(n.a, n.b)) _ = try self.nominal(n.a, n.b, view.children(id).len);
                    var children: std.ArrayList(E.Id) = .empty;
                    defer children.deinit(self.store.allocator);
                    for (view.children(id), 0..) |child, index| {
                        if (n.tag == .record and index % 2 == 0) try children.append(self.store.allocator, child) else try children.append(self.store.allocator, try self.evidence(child, depth + 1));
                    }
                    result = self.store.intern(n.tag, if (n.tag == .nominal) n.a else 0, if (n.tag == .nominal) n.b else 0, children.items) catch |err| return failure(err);
                },
                else => return error.InvalidArtifact,
            }
            self.imported[id] = result;
            return result;
        }
        fn admitted(self: *Self, id: E.Id, depth: usize) Error!void {
            try self.step(depth);
            const n = self.store.node(id);
            switch (n.tag) {
                .unit, .boolean, .u32, .f32, .never => {},
                .existential => self.store.view().body(n.a, self.store.children(id), depth + 1, &self.remaining, null) catch |err| return failure(err),
                .array, .list, .demand => try self.admitted(n.a, depth + 1),
                .function => {
                    try self.admitted(n.a, depth + 1);
                    try self.admitted(n.b, depth + 1);
                },
                .product, .record, .nominal => {
                    if (n.tag == .nominal and !staging.isIdentity(n.a, n.b)) _ = try self.nominal(n.a, n.b, self.store.children(id).len);
                    for (self.store.children(id), 0..) |child, index| {
                        if (n.tag == .record and index % 2 == 0) continue;
                        try self.admitted(child, depth + 1);
                    }
                },
                else => return error.InvalidArtifact,
            }
            if (n.tag == .function or n.tag == .demand) {
                for (self.store.effects.view().rowLabels(n.c)) |label| {
                    const operation = self.store.effects.view().operation(label);
                    try require(operation.instance.unit != 0 or operation.instance.decl == 0);
                    for (self.store.effects.view().operationArguments(label)) |argument| try self.admitted(argument, depth + 1);
                }
            }
        }
        fn source(self: *Self, producer: *const core.Module, closure: eval.ClosureValue, ty: T.Id) Error!E.Id {
            // Substitutions instantiate this producer's open slots. Concrete type
            // nodes and operation labels remain source-owned; Core's quote effect
            // reconstruction separately proves executed operations. No unrelated
            // body or global closed-row certificate can close an observed row.
            var mappings: std.ArrayList(E.Mapping) = .empty;
            defer mappings.deinit(self.store.allocator);
            var rows: std.ArrayList(E.RowMapping) = .empty;
            defer rows.deinit(self.store.allocator);
            for (self.snapshot.type_mappings[closure.mappings.start..][0..closure.mappings.len]) |mapping| {
                try require(mapping.variable < producer.types.nodes.len);
                const node = producer.types.node(mapping.variable);
                // A retained view never overrides a concrete checked source type.
                if (node.tag != .variable and !(node.tag == .bound and node.b == 0 and node.c == 0)) continue;
                for (mappings.items) |prior| try require(prior.variable != mapping.variable);
                try mappings.append(self.store.allocator, .{ .variable = mapping.variable, .evidence = try self.evidence(mapping.evidence, 0) });
            }
            for (self.snapshot.row_mappings[closure.row_mappings.start..][0..closure.row_mappings.len]) |mapping| {
                for (rows.items) |prior| try require(prior.variable != mapping.variable);
                try rows.append(self.store.allocator, .{ .variable = mapping.variable, .evidence = try self.row(mapping.evidence, 0) });
            }
            const result = self.store.projectWithBudget(&producer.types, ty, mappings.items, rows.items, &self.remaining) catch |err| return failure(err);
            try self.admitted(result, 0);
            return result;
        }
        fn value(self: *Self, id: eval.ValueId, expected: E.Id, depth: usize) Error!void {
            try self.step(depth);
            const value_ = self.snapshot.values[id];
            const shape = self.store.node(expected);
            const children = self.snapshot.children[value_.start..][0..value_.len];
            switch (shape.tag) {
                .unit, .boolean, .u32, .f32 => {
                    try require(value_.kind == .scalar and children.len == 0 and value_.nominal == 0);
                    const scalar: @TypeOf(value_.scalar) = switch (shape.tag) {
                        .unit => .unit,
                        .boolean => .bool,
                        .u32 => .u32,
                        .f32 => .f32,
                        else => unreachable,
                    };
                    try require(value_.scalar == scalar);
                    if (shape.tag == .unit) try require(value_.bits == 0);
                    if (shape.tag == .boolean) try require(value_.bits <= 1);
                },
                .product => {
                    try require(value_.kind == .product);
                    const types_ = self.store.children(expected);
                    try require(children.len == types_.len);
                    for (children, types_) |child, child_type| {
                        try require(child < id);
                        try self.value(child, child_type, depth + 1);
                    }
                },
                .record => {
                    try require(value_.kind == .record);
                    const types_ = self.store.children(expected);
                    const layout = self.snapshot.record_layouts[self.snapshot.value_records[id]];
                    const names = self.snapshot.field_names[layout.start..][0..layout.len];
                    try require(children.len == types_.len / 2 and names.len == children.len);
                    for (children, names) |child, name| {
                        const field_type = for (0..types_.len / 2) |index| {
                            if (types_[index * 2] == name) break types_[index * 2 + 1];
                        } else return error.InvalidArtifact;
                        try require(child < id);
                        try self.value(child, field_type, depth + 1);
                    }
                    for (names, 0..) |name, index| for (names[0..index]) |prior| try require(name != prior);
                },
                .array, .list => {
                    try require((shape.tag == .array and value_.kind == .array) or (shape.tag == .list and value_.kind == .list));
                    for (children) |child| {
                        try require(child < id);
                        try self.value(child, shape.a, depth + 1);
                    }
                },
                .nominal => {
                    if (staging.isIdentity(shape.a, shape.b)) {
                        try require(shape.b == staging.code_identity.decl and value_.kind == .code);
                        const closure = self.snapshot.closures[value_.bits];
                        try require(closure.unit != 0 and closure.unit <= self.units.len);
                        const producer = &self.units[closure.unit - 1].core;
                        try require(expected == try self.source(producer, closure, closure.ty));
                    } else {
                        try require(value_.kind == .nominal and value_.nominal == (@as(u64, shape.a) << 32 | shape.b));
                        const owner = try self.nominal(shape.a, shape.b, self.store.children(expected).len);
                        const family = owner.module.nominals[owner.index];
                        try require(value_.bits < family.constructors.len);
                        const constructor = owner.module.constructors[owner.module.nominalConstructors(owner.index)[value_.bits]];
                        try require(constructor.nominal == owner.index and constructor.tag == value_.bits);
                        try require(constructor.scheme.obligations.len == 0 and constructor.scheme.row_variables.len == 0 and constructor.scheme.generative.len == 0);
                        var result_type = constructor.scheme.root;
                        var parameter_type: T.Id = 0;
                        var payload_count: usize = 0;
                        if (constructor.payload != 0) {
                            payload_count = 1;
                            const arrow = owner.module.types.node(result_type);
                            try require(arrow.tag == .function);
                            const row_ = owner.module.types.effects.node(arrow.c);
                            try require(row_.labels.len == 0 and row_.tail == .closed);
                            parameter_type = arrow.a;
                            result_type = arrow.b;
                        }
                        try require(children.len == payload_count);
                        var mappings: std.ArrayList(E.Mapping) = .empty;
                        defer mappings.deinit(self.store.allocator);
                        var rows: std.ArrayList(E.RowMapping) = .empty;
                        defer rows.deinit(self.store.allocator);
                        try require(self.store.matchWithRowsBudget(&owner.module.types, result_type, expected, &mappings, &rows, &self.remaining) catch |err| return failure(err));
                        try require(rows.items.len == 0);
                        for (mappings.items) |mapping| {
                            try require(std.mem.findScalar(T.Id, owner.module.types.list(constructor.scheme.variables), mapping.variable) != null);
                            try require(std.mem.findScalar(T.Id, owner.module.types.list(family.variables), mapping.variable) != null);
                        }
                        // Matching alone admits Never widening. Re-project the exact
                        // constructor result before its owned payload can cross.
                        try require(expected == (self.store.projectWithBudget(&owner.module.types, result_type, mappings.items, rows.items, &self.remaining) catch |err| return failure(err)));
                        if (constructor.payload != 0) {
                            const payload_type = self.store.projectWithBudget(&owner.module.types, constructor.payload, mappings.items, rows.items, &self.remaining) catch |err| return failure(err);
                            const parameter = self.store.projectWithBudget(&owner.module.types, parameter_type, mappings.items, rows.items, &self.remaining) catch |err| return failure(err);
                            const storage = self.store.node(payload_type);
                            if (family.is_opaque) {
                                try require(parameter == payload_type);
                            } else if (storage.tag == .record) {
                                const fields = self.store.children(payload_type);
                                if (fields.len == 2) {
                                    try require(parameter == fields[1]);
                                } else {
                                    try require(self.store.node(parameter).tag == .product);
                                    const parts = self.store.children(parameter);
                                    try require(parts.len == fields.len / 2);
                                    for (parts, 0..) |part, index| try require(part == fields[index * 2 + 1]);
                                }
                            } else try require(parameter == payload_type);
                            try self.admitted(payload_type, depth + 1);
                            try require(children[0] < id);
                            try self.value(children[0], payload_type, depth + 1);
                        }
                    }
                },
                else => return error.InvalidArtifact,
            }
            if (self.snapshot.value_evidence[id] != 0) try require(expected == try self.evidence(self.snapshot.value_evidence[id], 0));
        }
    };
}
pub fn validate(allocator: std.mem.Allocator, snapshot: *const eval.Snapshot, units: anytype) Error!void {
    var previous_origin_value: u32 = 0;
    for (snapshot.code_origins) |origin| {
        try require(origin.value != 0 and origin.value > previous_origin_value and origin.value < snapshot.values.len);
        try require(snapshot.values[origin.value].kind == .code);
        try require(origin.generator.unit != 0 and origin.generator.unit <= units.len);
        const owner = &units[origin.generator.unit - 1].core;
        try require(origin.generator.node != 0 and origin.generator.node < owner.nodes.len and origin.generator.node < owner.spans.len);
        previous_origin_value = origin.value;
    }
    for (snapshot.closures) |closure| {
        try require(closure.staged < snapshot.values.len);
        if (closure.staged != 0) try require(snapshot.values[closure.staged].kind == .code);
    }
    const staged = for (snapshot.values) |value| {
        if (value.kind == .code or value.kind == .descriptor) break true;
    } else false;
    if (!staged) return;
    const imported = try allocator.alloc(E.Id, snapshot.evidence.nodes.len);
    defer allocator.free(imported);
    @memset(imported, 0);
    const Shape = Shapes(@TypeOf(units));
    var shapes: Shape = .{ .units = units, .snapshot = snapshot, .store = E.Store.init(allocator) catch |err| return Shape.failure(err), .imported = imported };
    defer shapes.store.deinit();
    const evidence = snapshot.evidence.view();
    for (snapshot.values, 0..) |value, id| {
        if (value.kind == .descriptor) {
            try require(value.nominal != 0 and value.nominal < evidence.nodes.len and value.len == 0 and value.bits == 0);
            if (snapshot.value_evidence[id] != 0) {
                const ty = evidence.node(snapshot.value_evidence[id]);
                try require(ty.tag == .nominal and ty.a == staging.descriptor_identity.unit and ty.b == staging.descriptor_identity.decl);
                const args = evidence.children(snapshot.value_evidence[id]);
                try require(args.len == 1 and args[0] == value.nominal);
            }
            _ = try shapes.evidence(@intCast(value.nominal), 0);
        }
        if (value.kind != .code) continue;
        try require(value.bits < snapshot.closures.len);
        const closure = snapshot.closures[value.bits];
        try require(closure.unit != 0 and closure.unit <= units.len and closure.origin == .anonymous and closure.applied == 0 and closure.staged == 0);
        const producer: *const core.Module = &units[closure.unit - 1].core;
        try require(closure.identity != 0 and closure.identity < producer.nodes.len and value.nominal == closure.identity and closure.ty < producer.types.nodes.len);
        try require(staging.codeInfo(&producer.types, closure.ty) != null);
        const introduced = for (producer.nodes) |node| {
            if (node.tag == .staging and node.c == @backingInt(staging.Op.quote) and node.a == closure.identity and node.ty == closure.ty) break true;
        } else false;
        try require(introduced);
        // Evaluation also retains unobserved intermediate values. Their closed
        // evidence is absent; the checked source owner still proves the shape.
        if (snapshot.value_evidence[id] != 0) {
            const ty = evidence.node(snapshot.value_evidence[id]);
            try require(ty.tag == .nominal and ty.a == staging.code_identity.unit and ty.b == staging.code_identity.decl);
            const args = evidence.children(snapshot.value_evidence[id]);
            try require(args.len == 2);
            const latent = evidence.node(args[1]);
            try require(latent.tag == .demand and latent.a == @import("types.zig").unit);
        }
        const expected = try shapes.source(producer, closure, closure.ty);
        if (snapshot.value_evidence[id] != 0) try require(expected == try shapes.evidence(snapshot.value_evidence[id], 0));
        const children = snapshot.children[value.start..][0..value.len];
        for (children, 0..) |child, ordinal| {
            const replacement = snapshot.values[child];
            try require(child < id and replacement.kind == .staged_value and replacement.nominal != 0 and replacement.nominal < producer.nodes.len and replacement.len == 1);
            const node = producer.nodes[@intCast(replacement.nominal)];
            try require(node.tag == .staging and node.c == replacement.bits and (node.c == @backingInt(staging.Op.lift) or node.c == @backingInt(staging.Op.splice)));
            for (children[0..ordinal]) |previous| try require(snapshot.values[previous].nominal != replacement.nominal);
            const payload = snapshot.children[replacement.start];
            try require(payload < child);
            const payload_type = if (node.c == @backingInt(staging.Op.splice)) producer.typeOf(node.a) else node.ty;
            try shapes.value(payload, try shapes.source(producer, closure, payload_type), 0);
        }
    }
}
