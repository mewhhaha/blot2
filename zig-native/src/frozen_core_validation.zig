//! Validation at the decoded, immutable Core boundary. This module neither
//! resolves source types nor repairs a graph. Bounds are checked before any
//! indexed read; a second linear pass rejects structural cycles. Binding calls
//! and return/break targets are executable/control links, not structural edges.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const check = @import("check.zig");
pub const Error = error{ InvalidArtifact, OutOfMemory };
pub const BoundsError = error{InvalidArtifact};

pub const Context = struct {
    /// Sibling module views; the validator never retains these pointers.
    units: []const *const core.Module = &.{},
    /// Includes the absent symbol at index zero. Null leaves symbol remapping
    /// bounds to the enclosing payload validator; nonzero symbols remain required.
    symbol_count: ?usize = null,
    /// Only this module's source length; foreign qualification spans are not local.
    source_length: ?u32 = null,
};

/// The foreign-module facts observable by this validator. Keep owner lookup
/// behind this projection so context equality and validation read one domain.
const OwnerBounds = struct {
    binding_count: usize,
    fn of(module: *const core.Module) OwnerBounds {
        return .{ .binding_count = module.bindings.len };
    }
};

/// Owned projection of exactly the context observed by frozen validation.
/// A new context field must be handled here and in equivalentContext.
pub const ContextImage = struct {
    const Owner = struct { unit: u32, bounds: OwnerBounds };
    owners: []Owner,
    symbol_count: ?usize,
    source_length: ?u32,

    pub fn capture(a: std.mem.Allocator, context: Context) std.mem.Allocator.Error!ContextImage {
        const owners = try a.alloc(Owner, context.units.len);
        for (context.units, owners) |module, *owner| owner.* = .{ .unit = module.unit, .bounds = OwnerBounds.of(module) };
        return .{ .owners = owners, .symbol_count = context.symbol_count, .source_length = context.source_length };
    }
    pub fn deinit(self: *ContextImage, a: std.mem.Allocator) void {
        a.free(self.owners);
        self.* = undefined;
    }
    pub fn matches(self: *const ContextImage, context: Context) bool {
        inline for (@typeInfo(Context).@"struct".field_names) |name| switch (@field(std.meta.FieldEnum(Context), name)) {
            .units => {
                if (self.owners.len != context.units.len) return false;
                for (self.owners, context.units) |owner, module| if (owner.unit != module.unit or !std.meta.eql(owner.bounds, OwnerBounds.of(module))) return false;
            },
            .symbol_count, .source_length => if (!std.meta.eql(@field(self, name), @field(context, name))) return false,
        };
        return true;
    }
};

/// Equal contexts give equal validation results for an equal local graph.
/// This proves no local graph or semantic dependency by itself.
pub fn equivalentContext(before: Context, after: Context) bool {
    inline for (@typeInfo(Context).@"struct".field_names) |name| {
        switch (@field(std.meta.FieldEnum(Context), name)) {
            .units => {
                if (before.units.len != after.units.len) return false;
                for (before.units, after.units) |old, current| {
                    if (old.unit != current.unit or !std.meta.eql(OwnerBounds.of(old), OwnerBounds.of(current))) return false;
                }
            },
            .symbol_count, .source_length => if (!std.meta.eql(@field(before, name), @field(after, name))) return false,
        }
    }
    return true;
}

fn require(condition: bool) BoundsError!void {
    if (!condition) return error.InvalidArtifact;
}
fn enumValue(comptime E: type, value: E) BoundsError!void {
    _ = std.enums.fromInt(E, @backingInt(value)) orelse return error.InvalidArtifact;
}
fn range(total: usize, start: u32, len: u32) BoundsError!void {
    try require(start <= total and len <= total - start);
}
fn index(total: usize, value: u32) BoundsError!void {
    try require(value < total);
}
fn requiredIndex(total: usize, value: u32) BoundsError!void {
    try require(value != 0);
    try index(total, value);
}
fn sum(a: usize, b: usize) BoundsError!usize {
    return std.math.add(usize, a, b) catch error.InvalidArtifact;
}
fn scalarArity(op: core.Op) BoundsError!u8 {
    try enumValue(core.Op, op);
    return switch (op) {
        .none => error.InvalidArtifact,
        .neg, .abs, .ceil, .floor, .trunc, .sqrt, .convert_u32_f32, .convert_f32_u32 => 1,
        else => 2,
    };
}
fn arrayArity(op: core.ArrayOp) BoundsError!u8 {
    try enumValue(core.ArrayOp, op);
    return @import("collection_ops.zig").arity(op);
}

const Bounds = struct {
    m: *const core.Module,
    context: Context,
    fn owner(self: Bounds, unit: u32) BoundsError!OwnerBounds {
        if (unit == 0 or unit == self.m.unit) return OwnerBounds.of(self.m);
        try require(unit != std.math.maxInt(u32));
        for (self.context.units) |candidate| if (candidate.unit == unit) return OwnerBounds.of(candidate);
        return error.InvalidArtifact;
    }
    fn identity(self: Bounds, value: T.NominalIdentity, optional: bool) BoundsError!void {
        if (value.unit == 0 and value.decl == 0) return require(optional);
        try require(value.decl != 0);
        if (value.unit == std.math.maxInt(u32)) {
            // Compiler-owned State/read/write, reflection, Computation and Decision identities.
            return require(value.decl >= 1 and value.decl <= 6);
        }
        _ = try self.owner(value.unit);
        // Declaration numbers belong to the source producer, not Core catalogs.
    }
    fn symbol(self: Bounds, value: u32, optional: bool) BoundsError!void {
        if (value == 0) return require(optional);
        if (self.context.symbol_count) |count| try index(count, value);
    }
    fn span(self: Bounds, value: core.Span) BoundsError!void {
        try require(value.start <= value.end);
        if (self.context.source_length) |len| try require(value.end <= len);
    }
    fn ty(self: Bounds, value: T.Id) BoundsError!void {
        try index(self.m.types.nodes.len, value);
    }
    fn row(self: Bounds, value: T.Effects.Id) BoundsError!void {
        if (value == 0 and self.m.types.effects.rows.len == 0) return;
        try index(self.m.types.effects.rows.len, value);
    }
    fn label(self: Bounds, value: T.Effects.Label) BoundsError!void {
        try requiredIndex(self.m.types.operations.len, value);
    }
    fn node(self: Bounds, value: core.Id, optional: bool) BoundsError!void {
        if (value == 0) return require(optional);
        try index(self.m.nodes.len, value);
    }
    fn binding(self: Bounds, value: core.BindingId, optional: bool) BoundsError!void {
        if (value == 0) return require(optional);
        try index(self.m.bindings.len, value);
    }
    fn bindingRef(self: Bounds, value: core.BindingRef, optional: bool) BoundsError!void {
        if (value.binding == 0) return require(optional and value.unit == 0);
        const producer = try self.owner(value.unit);
        try requiredIndex(producer.binding_count, value.binding);
    }
    fn listTypes(self: Bounds, value: T.List) BoundsError!void {
        try range(self.m.types.extra.len, value.start, value.len);
        for (self.m.types.extra[value.start..][0..value.len]) |id| try self.ty(id);
    }
    fn listRows(self: Bounds, value: T.List) BoundsError!void {
        try range(self.m.types.extra.len, value.start, value.len);
        for (self.m.types.extra[value.start..][0..value.len]) |id| try index(self.m.types.effects.variable_count, id);
    }
    fn listNodes(self: Bounds, value: core.List) BoundsError!void {
        try range(self.m.extra.len, value.start, value.len);
        for (self.m.extra[value.start..][0..value.len]) |id| try self.node(id, false);
    }
    fn listBindings(self: Bounds, value: core.List) BoundsError!void {
        try range(self.m.extra.len, value.start, value.len);
        for (self.m.extra[value.start..][0..value.len]) |id| try self.binding(id, false);
    }
    fn listPatterns(self: Bounds, value: core.List) BoundsError!void {
        try range(self.m.extra.len, value.start, value.len);
        for (self.m.extra[value.start..][0..value.len]) |id| try requiredIndex(self.m.patterns.len, id);
    }
    fn scheme(self: Bounds, value: T.Scheme) BoundsError!void {
        try self.ty(value.root);
        try self.listTypes(value.variables);
        try self.listRows(value.row_variables);
        try self.listRows(value.closed_rows);
        try range(self.m.obligations.len, value.obligations.start, value.obligations.len);
    }
    fn publicSlots(self: Bounds, public: T.List, quantified: T.List, rows: bool) BoundsError!void {
        if (rows) try self.listRows(public) else try self.listTypes(public);
        const quantifiers = self.m.types.list(quantified);
        var next: usize = 0;
        for (self.m.types.list(public)) |slot| {
            if (!rows) try require(self.m.types.node(slot).tag == .variable);
            while (next < quantifiers.len and quantifiers[next] != slot) : (next += 1) {}
            try require(next < quantifiers.len);
            next += 1;
        }
    }
    fn parameter(self: Bounds, value: core.Parameter) BoundsError!void {
        try self.binding(value.binding, true);
        if (value.binding != 0) try require(self.m.bindings[value.binding].kind == .parameter);
        try self.ty(value.ty);
        try self.span(value.span);
    }
    fn control(self: Bounds, value: core.Id, request: bool, optional: bool) BoundsError!void {
        try self.node(value, optional);
        if (value == 0) return;
        const tag = self.m.nodes[value].tag;
        try require(if (request) tag == .loop or tag == .request_loop else tag == .block);
    }
    fn updateStep(self: Bounds, value: core.UpdateStep) BoundsError!void {
        try enumValue(core.UpdateKind, value.kind);
        try self.ty(value.source_type);
        try self.ty(value.result_type);
        switch (value.kind) {
            .field => {
                try index(self.m.projections.len, value.projection);
                try require(value.index == 0);
            },
            .index => {
                try self.node(value.index, false);
                try require(value.projection == 0);
            },
        }
    }
    fn types(self: Bounds) BoundsError!void {
        try require(self.m.types.nodes.len >= 6);
        const builtins = [_]T.Tag{ .absent, .unit, .boolean, .u32, .f32, .never };
        for (self.m.types.nodes, 0..) |value, id| {
            try enumValue(T.Tag, value.tag);
            if (id < builtins.len) try require(value.tag == builtins[id] and value.a == 0 and value.b == 0 and value.c == 0);
            if (id >= builtins.len) try require(value.tag != .absent);
            switch (value.tag) {
                .absent, .unit, .boolean, .u32, .f32, .never, .variable => {},
                .function => {
                    try self.ty(value.a);
                    try self.ty(value.b);
                    try self.row(value.c);
                },
                .product => try self.listTypes(.{ .start = value.a, .len = value.b }),
                .record => {
                    const count = std.math.mul(usize, value.b, 2) catch return error.InvalidArtifact;
                    try require(value.a <= self.m.types.extra.len and count <= self.m.types.extra.len - value.a);
                    for (0..value.b) |field| {
                        try self.symbol(self.m.types.extra[value.a + field * 2], false);
                        try require(self.m.fieldSpelling(self.m.types.extra[value.a + field * 2]) != null);
                        try self.ty(self.m.types.extra[value.a + field * 2 + 1]);
                    }
                },
                .nominal => {
                    try self.identity(.{ .unit = value.a, .decl = value.b }, false);
                    try index(self.m.types.extra.len, value.c);
                    const start = std.math.add(u32, value.c, 1) catch return error.InvalidArtifact;
                    try self.listTypes(.{ .start = start, .len = self.m.types.extra[value.c] });
                },
                .type_constructor => try self.identity(.{ .unit = value.a, .decl = value.b }, false),
                .array, .list, .cursor, .resolver => try self.ty(value.a),
                .demand, .provider => {
                    try self.ty(value.a);
                    try self.row(value.c);
                },
                .state_provider => {
                    try self.ty(value.a);
                    try self.ty(value.b);
                    try self.ty(value.c);
                },
            }
        }
        for (self.m.types.effects.rows, 0..) |value, id| {
            try enumValue(std.meta.Tag(T.Effects.Tail), std.meta.activeTag(value.tail));
            try range(self.m.types.effects.labels.len, value.labels.start, value.labels.len);
            for (self.m.types.effects.labels[value.labels.start..][0..value.labels.len]) |label_| try self.label(label_);
            switch (value.tail) {
                .closed, .parameter => {},
                .variable => |v| try index(self.m.types.effects.variable_count, v),
            }
            if (id == 0) try require(value.labels.len == 0 and value.tail == .closed);
        }
        for (self.m.types.effects.labels) |label_| try self.label(label_);
        try require(self.m.types.operations.len >= 2);
        for (self.m.types.operations, 0..) |value, id| {
            try self.identity(value.identity, id == 0);
            try self.listTypes(value.arguments);
            if (id == 0) try require(value.identity.unit == 0 and value.identity.decl == 0 and value.arguments.len == 0);
            if (id == T.foreign_operation) try require(value.identity.unit == 0 and value.identity.decl == 1 and value.arguments.len == 0);
        }
    }
    fn catalogs(self: Bounds) BoundsError!void {
        for (self.m.bindings, 0..) |value, id| {
            try enumValue(check.Kind, value.kind);
            try self.ty(value.ty);
            try self.scheme(value.scheme);
            try self.publicSlots(value.public_variables, value.scheme.variables, false);
            try self.publicSlots(value.public_rows, value.scheme.row_variables, true);
            var has_explicit = false;
            for (self.m.obligations[value.scheme.obligations.start..][0..value.scheme.obligations.len]) |requirement| {
                has_explicit = has_explicit or requirement.explicit;
                if (requirement.kind == .callee_use) {
                    try self.binding(requirement.identity.decl, false);
                    has_explicit = has_explicit or self.m.bindings[requirement.identity.decl].has_explicit;
                }
            }
            try require(value.has_explicit == has_explicit);
            try self.span(value.span);
            try self.node(value.initializer, true);
            try self.bindingRef(value.target, id == 0 or value.kind == .local);
            try index(self.m.bodies.len, value.body_id);
            if (id != 0 and value.kind != .external) try require((value.target.binding == id or (value.kind == .local and value.target.binding == 0)) and (value.target.unit == 0 or value.target.unit == self.m.unit));
            if (value.body_id != 0) try require(value.kind == .global and self.m.bodies[value.body_id].binding == id);
        }
        for (self.m.bodies, 0..) |value, id| {
            try self.binding(value.binding, id == 0);
            try self.node(value.root, id == 0);
            try self.scheme(value.scheme);
            try self.listRows(value.closed_rows);
            try self.span(value.span);
            try range(self.m.parameters.len, value.parameters.start, value.parameters.len);
            try range(self.m.names.len, value.export_name.start, value.export_name.len);
            if (id == 0) try require(value.binding == 0 and value.root == 0 and value.parameters.len == 0 and !value.exported and !value.runtime and !value.is_function);
            if (id != 0) try require(self.m.bindings[value.binding].body_id == id);
            if (id != 0) try require(std.meta.eql(value.scheme, self.m.bindings[value.binding].scheme));
            if (!value.is_function) try require(value.parameters.len == 0);
            if (value.exported) try require(value.export_name.len != 0);
        }
        for (self.m.parameters) |value| try self.parameter(value);
        for (self.m.references) |value| try self.bindingRef(value, false);
        for (self.m.calls) |value| {
            try self.bindingRef(value.target, false);
            try self.ty(value.callee_type);
        }
        for (self.m.merges) |value| {
            try self.node(value.node, false);
            try self.binding(value.result, false);
            try self.binding(value.then_binding, false);
            try self.binding(value.else_binding, false);
        }
        for (self.m.merge_ranges, 0..) |value, id| {
            try range(self.m.merges.len, value.start, value.len);
            for (self.m.merges[value.start..][0..value.len]) |merge| try require(merge.node == id);
        }
        for (self.m.obligations) |value| {
            try enumValue(T.ObligationKind, value.kind);
            try enumValue(T.Operator, value.operator);
            try self.ty(value.ty);
            try self.ty(value.result);
            try self.ty(value.other);
            try self.ty(value.signature);
            try self.symbol(value.name, true);
            try self.identity(value.identity, true);
            if (value.kind == .callee_use) {
                // Shared scheme references belong to this module's checked
                // binding table; external bindings carry their own target.
                try require(value.identity.unit == 0 or value.identity.unit == self.m.unit);
                try self.binding(value.identity.decl, false);
                const callee = self.m.bindings[value.identity.decl];
                try range(self.m.types.extra.len, callee.public_variables.start, callee.public_variables.len);
                try range(self.m.types.extra.len, callee.public_rows.start, callee.public_rows.len);
                const product = self.m.types.node(value.ty);
                try require(product.tag == .product);
                try require(product.b == try sum(callee.public_variables.len, callee.public_rows.len));
                try range(self.m.types.extra.len, product.a, product.b);
                const parts = self.m.types.extra[product.a..][0..product.b];
                for (parts[callee.public_variables.len..]) |part| {
                    try self.ty(part);
                    const carrier = self.m.types.node(part);
                    try require(carrier.tag == .function and carrier.a == T.unit and carrier.b == T.unit);
                }
            }
            try self.span(value.span);
            if (value.qualification_span) |s| {
                try require(s.start <= s.end);
                if (value.qualification_unit == 0 or value.qualification_unit == self.m.unit) try self.span(s) else _ = try self.owner(value.qualification_unit);
            } else try require(value.qualification_unit == 0);
            try range(self.m.names.len, value.diagnostic_name.start, value.diagnostic_name.len);
        }
        for (self.m.nominals, 0..) |value, id| {
            try range(self.m.names.len, value.diagnostic_name.start, value.diagnostic_name.len);
            try range(self.m.names.len, value.diagnostic_origin.start, value.diagnostic_origin.len);
            try self.identity(value.identity, id == 0);
            try self.listTypes(value.parameters);
            try self.listTypes(value.variables);
            try range(self.m.extra.len, value.constructors.start, value.constructors.len);
            for (self.m.extra[value.constructors.start..][0..value.constructors.len]) |constructor| {
                try requiredIndex(self.m.constructors.len, constructor);
                try require(self.m.constructors[constructor].nominal == id);
            }
        }
        for (self.m.operation_names) |value| {
            try self.identity(value.identity, false);
            try range(self.m.names.len, value.diagnostic_name.start, value.diagnostic_name.len);
            try range(self.m.names.len, value.diagnostic_origin.start, value.diagnostic_origin.len);
        }
        for (self.m.constructors, 0..) |value, id| {
            try self.identity(value.identity, id == 0);
            try self.scheme(value.scheme);
            try self.ty(value.payload);
            try index(self.m.nominals.len, value.nominal);
            if (id != 0) {
                try require(value.nominal != 0);
                const nominal = self.m.nominals[value.nominal];
                try require(value.identity.unit == nominal.identity.unit);
                try index(nominal.constructors.len, value.tag);
                try require(self.m.extra[nominal.constructors.start + value.tag] == id);
            }
        }
        for (self.m.projections) |value| {
            try self.span(.{ .start = value.diagnostic_point, .end = value.diagnostic_point });
            try self.identity(value.nominal, true);
            try self.symbol(value.field, true);
            try self.ty(value.source_type);
            try self.ty(value.result_type);
            try range(self.m.projection_variants.len, value.variants.start, value.variants.len);
            // Concrete structural projection indices are checked against their
            // exact payload. Principal nominal variants retain their producer tags.
            const source = self.m.types.nodes[value.source_type];
            if (source.tag == .product or source.tag == .record) for (self.m.projection_variants[value.variants.start..][0..value.variants.len]) |v| try require(v.field < source.b);
        }
        for (self.m.projection_variants) |v| try require(v.field <= std.math.maxInt(u32) / 4);
        for (self.m.patterns, 0..) |value, id| {
            try enumValue(core.PatternTag, value.tag);
            try self.ty(value.ty);
            try self.span(value.span);
            if (id == 0) try require(value.tag == .invalid) else try require(value.tag != .invalid);
            switch (value.tag) {
                .invalid, .wildcard, .constant => {},
                .bind => try self.binding(value.a, false),
                .value => try self.node(value.a, false),
                .product => try self.listPatterns(.{ .start = value.a, .len = value.b }),
                .constructor => {
                    try requiredIndex(self.m.constructors.len, value.a);
                    if (value.b != 0) try requiredIndex(self.m.patterns.len, value.b);
                },
                .record_payload => {
                    try requiredIndex(self.m.patterns.len, value.b);
                    const record = self.m.types.nodes[value.ty];
                    try require(record.tag == .record and value.a == record.b);
                },
            }
        }
        for (self.m.pattern_rows) |value| try self.listPatterns(value.patterns);
        for (self.m.match_arms) |value| {
            try range(self.m.pattern_rows.len, value.rows.start, value.rows.len);
            try self.node(value.guard, true);
            try self.node(value.body, true);
            try self.span(value.span);
        }
        for (self.m.matches) |value| {
            try self.listNodes(value.inputs);
            try range(self.m.match_arms.len, value.arms.start, value.arms.len);
            for (self.m.match_arms[value.arms.start..][0..value.arms.len]) |arm| {
                if (arm.body == 0) try require(value.statement);
                for (self.m.pattern_rows[arm.rows.start..][0..arm.rows.len]) |r| try require(r.patterns.len == value.inputs.len);
            }
        }
        for (self.m.update_steps) |value| try self.updateStep(value);
        for (self.m.updates) |value| {
            try self.node(value.root, false);
            try self.node(value.value, false);
            try self.binding(value.self_binding, false);
            try range(self.m.extra.len, value.path.start, value.path.len);
            for (self.m.extra[value.path.start..][0..value.path.len]) |projection| try index(self.m.projections.len, projection);
            try range(self.m.update_steps.len, value.selectors.start, value.selectors.len);
            try require((value.path.len != 0) != (value.selectors.len != 0));
        }
        for (self.m.closures) |value| {
            try self.binding(value.qualifier, true);
            try self.node(value.body, false);
            try self.parameter(value.parameter);
            try self.listBindings(value.captures);
            try self.ty(value.function_type);
            try self.listRows(value.closed_rows);
        }
        for (self.m.associated) |value| {
            try self.identity(value.identity, false);
            try self.symbol(value.member, true);
            try enumValue(T.Operator, value.operator);
            try self.bindingRef(value.target, false);
            try require(value.member != 0 or value.operator != .none);
        }
        for (self.m.primitives) |value| {
            try enumValue(core.PrimitiveKind, value.kind);
            try enumValue(core.Op, value.op);
            try enumValue(core.ArrayOp, value.array_op);
            try require(value.arity == switch (value.kind) {
                .scalar => try scalarArity(value.op),
                .array => try arrayArity(value.array_op),
            });
        }
        for (self.m.loops) |value| {
            try enumValue(core.LoopKind, value.kind);
            try self.node(value.first, value.kind == .forever);
            try self.node(value.end, value.kind != .range);
            try self.node(value.body, false);
            if (value.pattern != 0) try requiredIndex(self.m.patterns.len, value.pattern);
            if (value.kind == .forever) try require(value.first == 0 and value.end == 0 and value.pattern == 0);
            if (value.kind == .array) try require(value.end == 0);
            try range(self.m.loop_carries.len, value.carries.start, value.carries.len);
        }
        for (self.m.loop_carries) |value| {
            try self.binding(value.incoming, false);
            try self.binding(value.iteration, false);
            try self.binding(value.backedge, false);
            try self.binding(value.outgoing, false);
        }
        for (self.m.resolver_ops) |value| {
            try enumValue(core.ResolverOperation, value.operation);
            try self.node(value.resolver, false);
            try self.listNodes(value.arguments);
            try self.symbol(value.member, true);
            try self.bindingRef(value.method, true);
            try self.ty(value.method_type);
        }
        for (self.m.operation_values) |value| {
            try self.identity(value.identity, false);
            try self.listTypes(value.arguments);
            try self.ty(value.signature);
            try self.node(value.witness, true);
            try self.ty(value.witness_result);
        }
        for (self.m.handle_effects, 0..) |value, id| {
            try self.node(value.node, false);
            try self.ty(value.first);
            try self.ty(value.second);
            try self.row(value.extended);
            try self.row(value.residual);
            try require(self.m.nodes[value.node].tag == .handle and self.m.nodes[value.node].c == id + 1);
        }
        for (self.m.request_arms) |value| {
            try self.label(value.operation);
            try self.node(value.callback, false);
        }
        for (self.m.request_loops) |value| {
            try self.node(value.computation, false);
            try self.ty(value.action_type);
            try self.ty(value.value_type);
            try self.ty(value.result_type);
            try self.ty(value.state_type);
            try range(self.m.request_arms.len, value.arms.start, value.arms.len);
            if (value.completion_pattern != 0) try requiredIndex(self.m.patterns.len, value.completion_pattern);
            try self.node(value.completion_body, true);
            try self.listBindings(value.completion_state_bindings);
            try range(self.m.loop_carries.len, value.carries.start, value.carries.len);
            try self.control(value.return_target, false, true);
        }
        try require(self.m.declaration_dependencies.len == self.m.bodies.len);
        for (self.m.declaration_dependencies) |value| {
            try range(self.m.dependency_references.len, value.references.start, value.references.len);
            try range(self.m.dependency_members.len, value.members.start, value.members.len);
            try self.node(value.runtime_metadata, true);
            if (value.runtime_metadata != 0) try require(self.m.nodes[value.runtime_metadata].tag == .effect_reflection);
        }
        for (self.m.dependency_references) |value| try self.bindingRef(value, false);
        for (self.m.dependency_members) |value| {
            try self.symbol(value.name, true);
            try enumValue(T.Operator, value.operator);
            try require(value.name != 0 or value.operator != .none);
        }
        var last_erased: core.Id = 0;
        for (self.m.erased_declaration_references) |value| {
            try self.node(value.node, false);
            try require(value.node > last_erased and self.m.nodes[value.node].tag == .effect_reflection);
            try self.bindingRef(value.target, false);
            last_erased = value.node;
        }
        var last_source: u32 = 0;
        for (self.m.source_names) |value| {
            try self.binding(value.binding, false);
            try require(value.binding > last_source and self.m.bindings[value.binding].body_id != 0);
            if (self.context.source_length) |len| try require(value.point <= len);
            last_source = value.binding;
        }
        var last_runtime: u32 = 0;
        for (self.m.runtime_names) |value| {
            try self.binding(value.binding, false);
            try require(value.binding > last_runtime);
            const body_id = self.m.bindings[value.binding].body_id;
            try require(body_id != 0 and self.m.bodies[body_id].runtime);
            if (self.context.source_length) |len| try require(value.point <= len);
            last_runtime = value.binding;
        }
        var last_tag: u32 = 0;
        for (self.m.tag_calls) |id| {
            try self.node(id, false);
            try require(id > last_tag and self.m.nodes[id].tag == .apply);
            last_tag = id;
        }
    }
    fn nodes(self: Bounds) BoundsError!void {
        for (self.m.nodes, 0..) |value, id| {
            try enumValue(core.Tag, value.tag);
            try enumValue(core.Op, value.op);
            try self.ty(value.ty);
            try self.span(self.m.spans[id]);
            if (id == 0) try require(std.meta.eql(value, core.Node{ .tag = .invalid })) else try require(value.tag != .invalid);
            if (self.m.dispatch_signatures.len != 0) try self.ty(self.m.dispatch_signatures[id]);
            switch (value.tag) {
                .invalid, .constant, .type_constructor => {},
                .reference => try index(self.m.references.len, value.a),
                .scalar => {
                    try self.node(value.a, false);
                    try self.node(value.b, try scalarArity(value.op) == 1);
                    try require(value.c <= 1);
                    if (try scalarArity(value.op) == 1) try require(value.b == 0);
                },
                .logical => {
                    try require(value.op == .and_ or value.op == .or_);
                    try self.node(value.a, false);
                    try self.node(value.b, false);
                },
                .call => {
                    try index(self.m.calls.len, value.a);
                    try self.listNodes(.{ .start = value.b, .len = value.c });
                },
                .if_value, .if_stmt => {
                    try self.node(value.a, false);
                    try self.node(value.b, false);
                    try self.node(value.c, value.tag == .if_stmt);
                },
                .block, .suite, .product, .array => try self.listNodes(.{ .start = value.a, .len = value.b }),
                .record => {
                    try self.listNodes(.{ .start = value.a, .len = value.b });
                    try range(self.m.extra.len, value.c, value.b);
                    for (self.m.extra[value.c..][0..value.b]) |slot| try require(slot < value.b);
                },
                .bind => {
                    try self.binding(value.a, false);
                    try self.node(value.b, false);
                    try require(self.m.bindings[value.a].initializer == value.b);
                },
                .return_ => {
                    try self.node(value.a, false);
                    try self.control(value.b, false, false);
                },
                .construct => {
                    try requiredIndex(self.m.constructors.len, value.a);
                    try self.node(value.b, true);
                    try require(value.c <= 1);
                },
                .project => {
                    try self.node(value.a, false);
                    try index(self.m.projections.len, value.b);
                },
                .match => try index(self.m.matches.len, value.a),
                .pattern_bind => {
                    try requiredIndex(self.m.patterns.len, value.a);
                    try self.node(value.b, false);
                    try self.node(value.c, true);
                },
                .update => try index(self.m.updates.len, value.a),
                .array_op => {
                    const op = std.enums.fromInt(core.ArrayOp, value.c) orelse return error.InvalidArtifact;
                    try require(value.b == try arrayArity(op));
                    try self.listNodes(.{ .start = value.a, .len = value.b });
                },
                .closure, .suspend_ => try index(self.m.closures.len, value.a),
                .apply, .associated, .record_merge, .type_same, .effect_provider, .handle => {
                    try self.node(value.a, false);
                    try self.node(value.b, value.tag == .associated and value.op != .none and try scalarArity(value.op) == 1);
                    if (value.tag == .associated) try self.symbol(value.c, true);
                    if (value.tag == .handle and value.c != 0) {
                        try index(self.m.handle_effects.len, value.c - 1);
                        try require(self.m.handle_effects[value.c - 1].node == id);
                    }
                },
                .constructor_function => try requiredIndex(self.m.constructors.len, value.a),
                .primitive_function => try index(self.m.primitives.len, value.a),
                .panic => try range(self.m.names.len, value.a, value.b),
                .loop => try index(self.m.loops.len, value.a),
                .break_ => {
                    try self.control(value.a, true, false);
                    try self.listNodes(.{ .start = value.b, .len = value.c });
                    const target = self.m.nodes[value.a];
                    const carries = if (target.tag == .loop) self.m.loops[target.a].carries else self.m.request_loops[target.a].carries;
                    try require(value.c == carries.len);
                },
                .result_associated => {
                    try self.node(value.a, false);
                    try self.symbol(value.b, false);
                },
                .force, .computation => try self.node(value.a, false),
                .resolver_op => try index(self.m.resolver_ops.len, value.a),
                .operation_value => try index(self.m.operation_values.len, value.a),
                .state_provider => {
                    try self.node(value.a, false);
                    try self.node(value.b, false);
                    try self.node(value.c, false);
                },
                .effect_reflection => {
                    const kind = std.enums.fromInt(check.ReflectionKind, value.a) orelse return error.InvalidArtifact;
                    switch (kind) {
                        .of => try self.row(value.b),
                        .descriptor => try self.label(value.b),
                        .count => try self.node(value.b, false),
                        .has, .same => {
                            try self.node(value.b, false);
                            try self.node(value.c, false);
                        },
                    }
                },
                .request_loop => try index(self.m.request_loops.len, value.a),
                .request_decision => {
                    const kind = std.enums.fromInt(core.RequestDecisionKind, value.a) orelse return error.InvalidArtifact;
                    try self.node(value.b, kind == .break_);
                    try self.node(value.c, kind == .cancel);
                },
            }
        }
    }
};

/// No allocation and no recursive traversal. External producer references are
/// checked using Context; complete cycle validation is a separate required pass.
pub fn validateBounds(module: *const core.Module, context: Context) BoundsError!void {
    inline for (@typeInfo(core.Module).@"struct".field_names) |name| {
        const info = @typeInfo(@FieldType(core.Module, name));
        if (info == .pointer and info.pointer.size == .slice) try require(@field(module, name).len <= std.math.maxInt(u32));
    }
    try require(module.unit != std.math.maxInt(u32));
    try require(module.nodes.len != 0 and module.bindings.len != 0 and module.bodies.len != 0);
    try require(module.spans.len == module.nodes.len and module.merge_ranges.len == module.nodes.len);
    try require(module.dispatch_signatures.len == 0 or module.dispatch_signatures.len == module.nodes.len);
    try require(module.diagnostics.len == 0 and module.body_lowerings == module.bodies.len - 1);
    try require(module.types.nodes.len <= std.math.maxInt(u32) and module.types.extra.len <= std.math.maxInt(u32));
    try require(module.types.effects.rows.len <= std.math.maxInt(u32) and module.types.effects.labels.len <= std.math.maxInt(u32) and module.types.operations.len <= std.math.maxInt(u32));
    for (context.units, 0..) |unit, i| {
        try require(unit.unit != 0 and unit.unit != std.math.maxInt(u32));
        for (context.units[0..i]) |prior| try require(prior.unit != unit.unit);
    }
    const b: Bounds = .{ .m = module, .context = context };
    for (module.field_names, 0..) |field, index_| {
        try b.symbol(field.symbol, false);
        if (index_ != 0) try require(module.field_names[index_ - 1].symbol < field.symbol);
        try range(module.names.len, field.spelling.start, field.spelling.len);
        try require(field.spelling.len != 0);
    }
    try b.types();
    // Node shape checks precede catalogs: target tags are now known to be valid.
    // All referenced metadata is bounded before any tag-specific second lookup.
    for (module.nodes) |n| {
        try enumValue(core.Tag, n.tag);
        switch (n.tag) {
            .loop => try index(module.loops.len, n.a),
            .request_loop => try index(module.request_loops.len, n.a),
            else => {},
        }
    }
    try b.catalogs();
    try b.nodes();
}

const Kind = enum { type_, row, operation, node, pattern, closure, match_, arm, pattern_row, update, update_step, loop, request_loop, request_arm, resolver, operation_value, scheme, obligation };
const kind_count = @typeInfo(Kind).@"enum".field_names.len;
pub const Frame = struct { vertex: usize, edge: usize = 0 };
pub const Scratch = struct { colors: []u8, path: []Frame };
pub const Requirements = struct { colors: usize, path: usize };

const Role = enum(u8) { unset, type_, symbol, row_variable, count, node, binding, pattern, constructor, projection, destination };
fn mark(roles: []u8, start: u32, len: u32, role: Role) BoundsError!void {
    for (roles[start..][0..len]) |*slot| {
        try require(slot.* == 0 or slot.* == @backingInt(role));
        slot.* = @backingInt(role);
    }
}
fn markScheme(roles: []u8, scheme: T.Scheme) BoundsError!void {
    try mark(roles, scheme.variables.start, scheme.variables.len, .type_);
    try mark(roles, scheme.row_variables.start, scheme.row_variables.len, .row_variable);
    try mark(roles, scheme.closed_rows.start, scheme.closed_rows.len, .row_variable);
}
fn listRoles(m: *const core.Module, type_roles: []u8, core_roles: []u8) BoundsError!void {
    @memset(type_roles, 0);
    @memset(core_roles, 0);
    for (m.types.nodes) |n| switch (n.tag) {
        .product => try mark(type_roles, n.a, n.b, .type_),
        .record => for (0..n.b) |i| {
            try mark(type_roles, @intCast(@as(usize, n.a) + i * 2), 1, .symbol);
            try mark(type_roles, @intCast(@as(usize, n.a) + i * 2 + 1), 1, .type_);
        },
        .nominal => {
            try mark(type_roles, n.c, 1, .count);
            try mark(type_roles, n.c + 1, m.types.extra[n.c], .type_);
        },
        else => {},
    };
    for (m.types.operations) |o| try mark(type_roles, o.arguments.start, o.arguments.len, .type_);
    for (m.bindings) |b| {
        try markScheme(type_roles, b.scheme);
        try mark(type_roles, b.public_variables.start, b.public_variables.len, .type_);
        try mark(type_roles, b.public_rows.start, b.public_rows.len, .row_variable);
    }
    for (m.bodies) |b| {
        try markScheme(type_roles, b.scheme);
        try mark(type_roles, b.closed_rows.start, b.closed_rows.len, .row_variable);
    }
    for (m.constructors) |c| try markScheme(type_roles, c.scheme);
    for (m.nominals) |n| {
        try mark(type_roles, n.parameters.start, n.parameters.len, .type_);
        try mark(type_roles, n.variables.start, n.variables.len, .type_);
        try mark(core_roles, n.constructors.start, n.constructors.len, .constructor);
    }
    for (m.closures) |c| {
        try mark(type_roles, c.closed_rows.start, c.closed_rows.len, .row_variable);
        try mark(core_roles, c.captures.start, c.captures.len, .binding);
    }
    for (m.operation_values) |o| try mark(type_roles, o.arguments.start, o.arguments.len, .type_);
    for (m.nodes) |n| switch (n.tag) {
        .block, .suite, .product, .array, .array_op => try mark(core_roles, n.a, n.b, .node),
        .record => {
            try mark(core_roles, n.a, n.b, .node);
            try mark(core_roles, n.c, n.b, .destination);
        },
        .call, .break_ => try mark(core_roles, n.b, n.c, .node),
        else => {},
    };
    for (m.patterns) |p| if (p.tag == .product) {
        try mark(core_roles, p.a, p.b, .pattern);
    };
    for (m.pattern_rows) |p| try mark(core_roles, p.patterns.start, p.patterns.len, .pattern);
    for (m.matches) |match_| try mark(core_roles, match_.inputs.start, match_.inputs.len, .node);
    for (m.updates) |u| try mark(core_roles, u.path.start, u.path.len, .projection);
    for (m.resolver_ops) |r| try mark(core_roles, r.arguments.start, r.arguments.len, .node);
    for (m.request_loops) |r| try mark(core_roles, r.completion_state_bindings.start, r.completion_state_bindings.len, .binding);
}

const Graph = struct {
    m: *const core.Module,
    starts: [kind_count + 1]usize,
    fn init(m: *const core.Module) BoundsError!Graph {
        var result: Graph = .{ .m = m, .starts = @splat(0) };
        const counts = [_]usize{ m.types.nodes.len, m.types.effects.rows.len, m.types.operations.len, m.nodes.len, m.patterns.len, m.closures.len, m.matches.len, m.match_arms.len, m.pattern_rows.len, m.updates.len, m.update_steps.len, m.loops.len, m.request_loops.len, m.request_arms.len, m.resolver_ops.len, m.operation_values.len, m.bindings.len, m.obligations.len };
        for (counts, 0..) |size_, i| result.starts[i + 1] = try sum(result.starts[i], size_);
        return result;
    }
    fn vertex(self: Graph, kind: Kind, id: usize) usize {
        return self.starts[@backingInt(kind)] + id;
    }
    fn count(self: Graph) usize {
        return self.starts[kind_count];
    }
    fn edge(self: Graph, vertex_: usize, slot: usize) ?usize {
        var k: usize = 0;
        while (vertex_ >= self.starts[k + 1]) : (k += 1) {}
        const id = vertex_ - self.starts[k];
        const m = self.m;
        switch (@as(Kind, @fromBackingInt(@intCast(k)))) {
            .type_ => {
                const v = m.types.nodes[id];
                return switch (v.tag) {
                    .function => switch (slot) {
                        0 => self.vertex(.type_, v.a),
                        1 => self.vertex(.type_, v.b),
                        2 => if (m.types.effects.rows.len == 0) null else self.vertex(.row, v.c),
                        else => null,
                    },
                    .product => if (slot < v.b) self.vertex(.type_, m.types.extra[v.a + slot]) else null,
                    .record => if (slot < v.b) self.vertex(.type_, m.types.extra[v.a + slot * 2 + 1]) else null,
                    .nominal => if (slot < m.types.extra[v.c]) self.vertex(.type_, m.types.extra[v.c + 1 + slot]) else null,
                    .array, .list, .cursor, .resolver => if (slot == 0) self.vertex(.type_, v.a) else null,
                    .demand, .provider => switch (slot) {
                        0 => self.vertex(.type_, v.a),
                        1 => if (m.types.effects.rows.len == 0) null else self.vertex(.row, v.c),
                        else => null,
                    },
                    .state_provider => switch (slot) {
                        0 => self.vertex(.type_, v.a),
                        1 => self.vertex(.type_, v.b),
                        2 => self.vertex(.type_, v.c),
                        else => null,
                    },
                    else => null,
                };
            },
            .row => {
                const list = m.types.effects.rows[id].labels;
                return if (slot < list.len) self.vertex(.operation, m.types.effects.labels[list.start + slot]) else null;
            },
            .operation => {
                const list = m.types.operations[id].arguments;
                return if (slot < list.len) self.vertex(.type_, m.types.extra[list.start + slot]) else null;
            },
            .node => {
                const v = m.nodes[id];
                return switch (v.tag) {
                    .scalar, .logical, .apply, .associated, .record_merge, .type_same, .effect_provider, .handle => switch (slot) {
                        0 => self.vertex(.node, v.a),
                        1 => self.vertex(.node, v.b),
                        else => null,
                    },
                    .if_value, .if_stmt, .state_provider => switch (slot) {
                        0 => self.vertex(.node, v.a),
                        1 => self.vertex(.node, v.b),
                        2 => self.vertex(.node, v.c),
                        else => null,
                    },
                    .block, .suite, .product, .record, .array, .array_op => if (slot < v.b) self.vertex(.node, m.extra[v.a + slot]) else null,
                    .call, .break_ => if (slot < v.c) self.vertex(.node, m.extra[v.b + slot]) else null,
                    .bind, .construct => if (slot == 0) self.vertex(.node, v.b) else null,
                    .return_, .project, .force, .result_associated, .computation => if (slot == 0) self.vertex(.node, v.a) else null,
                    .closure, .suspend_ => if (slot == 0) self.vertex(.closure, v.a) else null,
                    .match => if (slot == 0) self.vertex(.match_, v.a) else null,
                    .pattern_bind => switch (slot) {
                        0 => self.vertex(.pattern, v.a),
                        1 => self.vertex(.node, v.b),
                        2 => self.vertex(.node, v.c),
                        else => null,
                    },
                    .update => if (slot == 0) self.vertex(.update, v.a) else null,
                    .loop => if (slot == 0) self.vertex(.loop, v.a) else null,
                    .request_loop => if (slot == 0) self.vertex(.request_loop, v.a) else null,
                    .resolver_op => if (slot == 0) self.vertex(.resolver, v.a) else null,
                    .operation_value => if (slot == 0) self.vertex(.operation_value, v.a) else null,
                    .request_decision => switch (slot) {
                        0 => self.vertex(.node, v.b),
                        1 => self.vertex(.node, v.c),
                        else => null,
                    },
                    .effect_reflection => switch (@as(check.ReflectionKind, @fromBackingInt(@intCast(v.a)))) {
                        .of, .descriptor => null,
                        .count => if (slot == 0) self.vertex(.node, v.b) else null,
                        .has, .same => switch (slot) {
                            0 => self.vertex(.node, v.b),
                            1 => self.vertex(.node, v.c),
                            else => null,
                        },
                    },
                    else => null,
                };
            },
            .pattern => {
                const v = m.patterns[id];
                return switch (v.tag) {
                    .value => if (slot == 0) self.vertex(.node, v.a) else null,
                    .product => if (slot < v.b) self.vertex(.pattern, m.extra[v.a + slot]) else null,
                    .constructor, .record_payload => if (slot == 0) self.vertex(.pattern, v.b) else null,
                    else => null,
                };
            },
            .closure => return if (slot == 0) self.vertex(.node, m.closures[id].body) else null,
            .match_ => {
                const v = m.matches[id];
                if (slot < v.inputs.len) return self.vertex(.node, m.extra[v.inputs.start + slot]);
                const arm = slot - v.inputs.len;
                return if (arm < v.arms.len) self.vertex(.arm, v.arms.start + arm) else null;
            },
            .arm => {
                const v = m.match_arms[id];
                return switch (slot) {
                    0 => self.vertex(.node, v.guard),
                    1 => self.vertex(.node, v.body),
                    else => if (slot - 2 < v.rows.len) self.vertex(.pattern_row, v.rows.start + slot - 2) else null,
                };
            },
            .pattern_row => {
                const list = m.pattern_rows[id].patterns;
                return if (slot < list.len) self.vertex(.pattern, m.extra[list.start + slot]) else null;
            },
            .update => {
                const v = m.updates[id];
                if (slot == 0) return self.vertex(.node, v.root);
                if (slot == 1) return self.vertex(.node, v.value);
                const step = slot - 2;
                return if (step < v.selectors.len) self.vertex(.update_step, v.selectors.start + step) else null;
            },
            .update_step => return if (slot == 0 and m.update_steps[id].kind == .index) self.vertex(.node, m.update_steps[id].index) else null,
            .loop => {
                const v = m.loops[id];
                return switch (slot) {
                    0 => self.vertex(.node, v.first),
                    1 => self.vertex(.node, v.end),
                    2 => self.vertex(.node, v.body),
                    3 => if (v.pattern == 0) null else self.vertex(.pattern, v.pattern),
                    else => null,
                };
            },
            .request_loop => {
                const v = m.request_loops[id];
                if (slot == 0) return self.vertex(.node, v.computation);
                if (slot == 1) return self.vertex(.node, v.completion_body);
                if (slot - 2 < v.arms.len) return self.vertex(.request_arm, v.arms.start + slot - 2);
                return if (slot - 2 == v.arms.len and v.completion_pattern != 0) self.vertex(.pattern, v.completion_pattern) else null;
            },
            .request_arm => return if (slot == 0) self.vertex(.node, m.request_arms[id].callback) else null,
            .resolver => {
                const v = m.resolver_ops[id];
                if (slot == 0) return self.vertex(.node, v.resolver);
                return if (slot - 1 < v.arguments.len) self.vertex(.node, m.extra[v.arguments.start + slot - 1]) else null;
            },
            .operation_value => return if (slot == 0) self.vertex(.node, m.operation_values[id].witness) else null,
            .scheme => {
                const list = m.bindings[id].scheme.obligations;
                return if (slot < list.len) self.vertex(.obligation, list.start + slot) else null;
            },
            .obligation => {
                const value = m.obligations[id];
                return if (slot == 0 and value.kind == .callee_use) self.vertex(.scheme, value.identity.decl) else null;
            },
        }
    }
};

/// Exact caller workspace, including one byte per mixed extra-table word to
/// reject overlapping symbol/type/binding/expression domains. Path is linear in
/// graph vertices; large acyclic modules do not incur a fixed nesting policy.
pub fn scratchRequirements(module: *const core.Module) BoundsError!Requirements {
    const count = (try Graph.init(module)).count();
    return .{ .colors = try sum(count, try sum(module.types.extra.len, module.extra.len)), .path = count };
}
/// Convenience upper bound for callers using one count for both slices.
pub fn scratchSize(module: *const core.Module) BoundsError!usize {
    const needed = try scratchRequirements(module);
    return @max(needed.colors, needed.path);
}

fn cycles(graph: Graph, scratch: Scratch) BoundsError!void {
    const count = graph.count();
    try require(scratch.colors.len >= count and scratch.path.len >= count);
    @memset(scratch.colors[0..count], 0);
    for (0..count) |root| {
        if (scratch.colors[root] != 0) continue;
        var depth: usize = 1;
        scratch.path[0] = .{ .vertex = root };
        scratch.colors[root] = 1;
        while (depth != 0) {
            const top = &scratch.path[depth - 1];
            if (graph.edge(top.vertex, top.edge)) |child| {
                top.edge += 1;
                switch (scratch.colors[child]) {
                    0 => {
                        scratch.colors[child] = 1;
                        scratch.path[depth] = .{ .vertex = child };
                        depth += 1;
                    },
                    1 => return error.InvalidArtifact,
                    2 => {},
                    else => unreachable,
                }
            } else {
                scratch.colors[top.vertex] = 2;
                depth -= 1;
            }
        }
    }
}

/// Complete validation with explicit caller-owned linear workspace. An
/// undersized workspace is an API error (InvalidArtifact), never a size policy.
pub fn validateWithScratch(module: *const core.Module, context: Context, scratch: Scratch) BoundsError!void {
    try validateBounds(module, context);
    const graph = try Graph.init(module);
    const needed = try scratchRequirements(module);
    try require(scratch.colors.len >= needed.colors and scratch.path.len >= needed.path);
    const start = graph.count();
    try listRoles(module, scratch.colors[start..][0..module.types.extra.len], scratch.colors[start + module.types.extra.len ..][0..module.extra.len]);
    try cycles(graph, scratch);
}

pub fn validate(allocator: std.mem.Allocator, module: *const core.Module, context: Context) Error!void {
    try validateBounds(module, context);
    const graph = try Graph.init(module);
    const needed = try scratchRequirements(module);
    const colors = try allocator.alloc(u8, needed.colors);
    defer allocator.free(colors);
    const path = try allocator.alloc(Frame, needed.path);
    defer allocator.free(path);
    const start = graph.count();
    try listRoles(module, colors[start..][0..module.types.extra.len], colors[start + module.types.extra.len ..][0..module.extra.len]);
    try cycles(graph, .{ .colors = colors, .path = path });
}
