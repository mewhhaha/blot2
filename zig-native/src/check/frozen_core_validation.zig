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

// These validators observe executable foreign scheme/body authority beyond
// OwnerBounds. Until its relocation is owned, validate the candidate afresh.
fn reusableModules(modules: []const *const core.Module, comptime caller: bool) bool {
    for (modules) |module| {
        if (module.has_usage_contracts or module.has_rank_contracts) return false;
        if (module.capability_contracts.bindings.len != 0) return false;
        if (caller and module.has_numeric_proofs) return false;
        // Staged calls now inspect exact foreign bodies and schemes. An owner
        // receipt containing only table bounds cannot reuse that authority.
        for (module.nodes) |node| if (node.tag == .staging or node.tag == .effect_scope) return false;
        for (module.bindings) |binding| if (binding.scheme.generative.len != 0 or binding.capability_parameters.invokes() or binding.capability_flow == .input_shape or binding.capability_flow == .consume_task or binding.capability_flow == .scope_task or binding.capability_flow == .spawn_task) return false;
        for (module.types.nodes) |node| {
            if (node.tag == .existential or node.tag == .forall) return false;
            if (node.tag == .instance_version) return false;
            if (node.tag == .scoped) return false;
        }
    }
    return true;
}
fn reusableContext(context: Context, callers: []const *const core.Module) bool {
    // The equal local graph is owned separately. Its actual callers must
    // classify every validator that can observe foreign semantic bodies/types.
    if (callers.len == 0 or !reusableModules(callers, true)) return false;
    _ = context;
    return true;
}

/// Ordinary callers observe foreign nominal affinity/storage facts even when
/// none of their executable validators reads a foreign body or source scheme.
pub const NominalFact = struct {
    identity: T.NominalIdentity,
    affine: bool,
    has_usage: bool,
    closed_storage: bool,
    fn of(value: core.Nominal) NominalFact {
        return .{ .identity = value.identity, .affine = value.affine, .has_usage = value.has_usage, .closed_storage = value.closed_storage };
    }
};

/// Owned projection of exactly the context observed by frozen validation.
/// A new context field must be handled here and in equivalentContext.
pub const ContextImage = struct {
    const Owner = struct { unit: u32, bounds: OwnerBounds, nominals: core.List };
    owners: []Owner,
    nominal_facts: []NominalFact,
    reusable: bool,
    symbol_count: ?usize,
    source_length: ?u32,

    pub fn capture(a: std.mem.Allocator, context: Context, callers: []const *const core.Module) std.mem.Allocator.Error!ContextImage {
        const owners = try a.alloc(Owner, context.units.len);
        errdefer a.free(owners);
        var count: usize = 0;
        for (context.units) |module| count = std.math.add(usize, count, module.nominals.len) catch return error.OutOfMemory;
        if (count > std.math.maxInt(u32)) return error.OutOfMemory;
        const nominal_facts = try a.alloc(NominalFact, count);
        var offset: u32 = 0;
        for (context.units, owners) |module, *owner| {
            owner.* = .{ .unit = module.unit, .bounds = OwnerBounds.of(module), .nominals = .{ .start = offset, .len = @intCast(module.nominals.len) } };
            for (module.nominals, nominal_facts[offset..][0..module.nominals.len]) |nominal, *fact| fact.* = .of(nominal);
            offset += @intCast(module.nominals.len);
        }
        return .{ .owners = owners, .nominal_facts = nominal_facts, .reusable = reusableContext(context, callers), .symbol_count = context.symbol_count, .source_length = context.source_length };
    }
    pub fn deinit(self: *ContextImage, a: std.mem.Allocator) void {
        a.free(self.owners);
        a.free(self.nominal_facts);
        self.* = undefined;
    }
    pub fn matches(self: *const ContextImage, context: Context, callers: []const *const core.Module) bool {
        if (!self.reusable or !reusableContext(context, callers)) return false;
        inline for (@typeInfo(Context).@"struct".field_names) |name| switch (@field(std.meta.FieldEnum(Context), name)) {
            .units => {
                if (self.owners.len != context.units.len) return false;
                for (self.owners, context.units) |owner, module| {
                    if (owner.unit != module.unit or !std.meta.eql(owner.bounds, OwnerBounds.of(module)) or owner.nominals.len != module.nominals.len) return false;
                    for (self.nominal_facts[owner.nominals.start..][0..owner.nominals.len], module.nominals) |old, current| if (!std.meta.eql(old, NominalFact.of(current))) return false;
                }
            },
            .symbol_count, .source_length => if (!std.meta.eql(@field(self, name), @field(context, name))) return false,
        };
        return true;
    }
};

/// Equal contexts give equal validation results for an equal local graph.
/// This proves no local graph or semantic dependency by itself.
pub fn equivalentContext(before: Context, after: Context, before_callers: []const *const core.Module, after_callers: []const *const core.Module) bool {
    if (!reusableContext(before, before_callers) or !reusableContext(after, after_callers)) return false;
    return equivalentContextFacts(before, after);
}
/// Shared global bounds and nominal observations. Rich executable validators
/// additionally require exact immutable caller and transitive foreign owners.
pub fn equivalentContextFacts(before: Context, after: Context) bool {
    inline for (@typeInfo(Context).@"struct".field_names) |name| {
        switch (@field(std.meta.FieldEnum(Context), name)) {
            .units => {
                if (before.units.len != after.units.len) return false;
                for (before.units, after.units) |old, current| {
                    if (old.unit != current.unit or !std.meta.eql(OwnerBounds.of(old), OwnerBounds.of(current))) return false;
                    if (old.nominals.len != current.nominals.len) return false;
                    for (old.nominals, current.nominals) |left, right| if (!std.meta.eql(NominalFact.of(left), NominalFact.of(right))) return false;
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
        .neg, .abs, .ceil, .floor, .trunc, .sqrt, .convert_u32_f32, .convert_f32_u32, .convert_i32_f32, .convert_f32_i32, .bit_not, .any_true, .all_true, .bits, .from_bits => 1,
        else => 2,
    };
}
fn arrayArity(op: core.ArrayOp) BoundsError!u8 {
    try enumValue(core.ArrayOp, op);
    return @import("../backend/collection_ops.zig").arity(op);
}

const Bounds = struct {
    m: *const core.Module,
    context: Context,
    scoped_work: *usize,
    fn scopedCharge(self: Bounds) BoundsError!void {
        try require(self.scoped_work.* != 0);
        self.scoped_work.* -= 1;
    }
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
            return require((value.decl >= 1 and value.decl <= 6) or @import("task_types.zig").isIdentity(value.unit, value.decl));
        }
        _ = try self.owner(value.unit);
        if (value.unit != 0 and value.decl & T.opaque_name_bit != 0) try self.symbol(value.decl & ~T.opaque_name_bit, false);
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
        try require(value.generative.len <= 32 and value.generative.len % 2 == 0);
        try self.listTypes(value.generative);
        const binders = self.m.types.list(value.generative);
        for (0..binders.len / 2) |ordinal| {
            const selected = self.m.types.node(binders[ordinal * 2 + 1]);
            try require(self.m.types.node(binders[ordinal * 2]).tag == .function and selected.tag == .scoped and selected.b == 0 and self.m.types.node(selected.c).tag == .instance_selection);
        }
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
        // Resolver continuations bind the checker's synthetic local payload.
        if (value.binding != 0) try require(self.m.bindings[value.binding].kind == .parameter or self.m.bindings[value.binding].kind == .local);
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
        try @import("quantifier_goals.zig").validate(self.m.types.nodes, self.m.types.quantifier_goals, self.m.types.quantifier_obligations);
        const builtins = [_]T.Tag{ .absent, .unit, .boolean, .u32, .f32, .never };
        for (self.m.types.nodes, 0..) |value, id| {
            try enumValue(T.Tag, value.tag);
            if (id < builtins.len) try require(value.tag == builtins[id] and value.a == 0 and value.b == 0 and value.c == 0);
            if (id >= builtins.len) try require(value.tag != .absent);
            switch (value.tag) {
                .erased_proof => try require(self.m.has_numeric_proofs and value.a == 0 and value.b == 0 and value.c == 0),
                // Rank graphs stay private until portable binder scope and
                // dictionary/carrier evidence have one complete schema.
                .usage => {
                    try self.ty(value.a);
                    try require(self.m.has_usage_contracts and value.b <= @backingInt(T.UsageKind.concurrent));
                    if (value.c != 0) try self.ty(value.c);
                },
                .bound => {
                    if (value.b == 0) {
                        try require(self.m.has_rank_contracts and value.a < 128 and (value.c == 0 or value.c < self.m.bindings.len));
                    } else if (value.c == 0) {
                        try require(self.m.has_rank_contracts and value.a < 128 and (value.b == 1 or (self.m.has_usage_contracts and value.b == 2)));
                    } else try require(self.m.has_usage_contracts and value.a == 0 and value.b == 2 and value.c < self.m.bindings.len);
                },
                .forall, .existential => {
                    try require(self.m.has_rank_contracts);
                    try self.ty(value.a);
                    try self.listTypes(.{ .start = value.b, .len = value.c });
                },
                .rigid => return error.InvalidArtifact,
                .instance_version => {
                    try require(value.a != 0 and value.b != 0 and value.b < 0x04000000 and value.c < 16);
                    _ = try self.owner(value.a);
                },
                .instance_selection => {
                    try require(value.a != 0 and value.b != 0);
                    try index(self.m.types.extra.len, value.c);
                    const count = self.m.types.extra[value.c];
                    try require(count == 2 or count == 3);
                    if (count == 2) try require(value.a == self.m.unit);
                    try self.listTypes(.{ .start = value.c + 1, .len = count });
                    const children = self.m.types.nominalArguments(value);
                    for (children[0..2]) |choice| try require(self.m.types.node(choice).tag == .scoped);
                    if (count == 3) try require(self.m.types.node(children[2]).tag == .instance_version);
                },
                .scoped => {
                    try self.ty(value.a);
                    try require(self.m.types.node(value.a).tag == .nominal and value.c != 0);
                    try self.scopedInstance(.{ .unit = value.b, .decl = value.c });
                },
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
                .nominal, .projection => {
                    if (@import("typed_staging.zig").isIdentity(value.a, value.b)) {
                        try require(value.tag == .nominal);
                    } else try self.identity(.{ .unit = value.a, .decl = value.b }, false);
                    try index(self.m.types.extra.len, value.c);
                    const start = std.math.add(u32, value.c, 1) catch return error.InvalidArtifact;
                    try self.listTypes(.{ .start = start, .len = self.m.types.extra[value.c] });
                    if (value.tag == .projection) {
                        const slot = std.math.add(u32, start, self.m.types.extra[value.c]) catch return error.InvalidArtifact;
                        try index(self.m.types.extra.len, slot);
                        try self.symbol(self.m.types.extra[slot], false);
                        var declared = false;
                        for (self.m.contracts) |contract| {
                            if (contract.identity.unit != value.a or contract.identity.decl != value.b) continue;
                            try require(contract.parameters.len == self.m.types.extra[value.c]);
                            try range(self.m.contract_members.len, contract.members.start, contract.members.len);
                            for (self.m.contract_members[contract.members.start..][0..contract.members.len]) |member| if (member.name == self.m.types.extra[slot] and member.kind != .value) {
                                declared = true;
                            };
                        }
                        try require(declared);
                    }
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
        try require(self.m.types.effects.variable_count <= T.Effects.formal_key_bit);
        for (self.m.types.effects.rows, 0..) |value, id| {
            try enumValue(std.meta.Tag(T.Effects.Tail), std.meta.activeTag(value.tail));
            try range(self.m.types.effects.labels.len, value.labels.start, value.labels.len);
            for (self.m.types.effects.labels[value.labels.start..][0..value.labels.len]) |label_| try self.label(label_);
            switch (value.tail) {
                .closed, .parameter => {},
                .formal => |formal| {
                    try self.ty(formal);
                    const leaf = self.m.types.node(formal);
                    try require(leaf.tag == .bound and leaf.b == 1 and leaf.c == 0);
                },
                .variable => |v| try index(self.m.types.effects.variable_count, v),
            }
            if (id == 0) try require(value.labels.len == 0 and value.tail == .closed);
        }
        for (self.m.types.effects.labels) |label_| try self.label(label_);
        try require(self.m.types.operations.len >= 2);
        for (self.m.types.operations, 0..) |value, id| {
            try self.scopedInstance(value.instance);
            if (value.identity.unit == 0) try require(value.instance.unit == 0 and value.instance.decl == 0);
            try self.identity(value.identity, id == 0);
            try self.listTypes(value.arguments);
            if (id == 0) try require(value.identity.unit == 0 and value.identity.decl == 0 and value.arguments.len == 0);
            if (id == T.foreign_operation) try require(value.identity.unit == 0 and value.identity.decl == 1 and value.arguments.len == 0);
        }
    }
    fn scopedInstance(self: Bounds, instance: T.NominalIdentity) BoundsError!void {
        if (instance.decl == 0) return require(instance.unit == 0);
        if (instance.unit == 0) {
            try self.ty(instance.decl);
            if (self.m.types.node(instance.decl).tag == .instance_selection) return;
            const region = self.m.types.node(instance.decl);
            if (region.tag == .bound and region.b == 2) return;
            try require(self.m.types.node(instance.decl).tag == .variable);
            for (self.m.bindings) |binding_| {
                try self.scopedCharge();
                if (binding_.kind != .parameter or binding_.ty >= self.m.types.nodes.len) continue;
                const input = self.m.types.node(binding_.ty);
                if (input.tag == .scoped and input.b == 0 and input.c == instance.decl) return;
            }
            // A stored/factory callable may quantify receiver identities in
            // its result without a direct capability parameter. The executable
            // declaration owns those exact generalized variables; an arbitrary free
            // variable in a result is insufficient.
            for (self.m.bindings, 0..) |definition, binding_id| {
                try self.scopedCharge();
                if (definition.kind == .global and definition.body_id != 0) {
                    try index(self.m.bodies.len, definition.body_id);
                    try require(self.m.bodies[definition.body_id].binding == binding_id);
                } else if (definition.kind == .local and definition.initializer != 0) {
                    try self.node(definition.initializer, false);
                } else continue;
                try range(self.m.types.extra.len, definition.scheme.variables.start, definition.scheme.variables.len);
                for (self.m.types.list(definition.scheme.variables)) |variable| {
                    try self.scopedCharge();
                    if (variable == instance.decl) return;
                }
            }
            return error.InvalidArtifact;
        }
        try require(instance.unit == self.m.unit);
        for (self.m.nodes) |node_| {
            var callback_id = node_.a;
            if (node_.tag == .task and (node_.c == @backingInt(@import("task_types.zig").Op.scope) or node_.c == @backingInt(@import("task_types.zig").Op.split))) {
                if (node_.b == 0 or node_.a >= self.m.extra.len or node_.b > self.m.extra.len - node_.a) continue;
                callback_id = self.m.extra[node_.a + node_.b - 1];
            } else if (node_.tag != .effect_scope) continue;
            if (callback_id >= self.m.nodes.len) continue;
            const callback = self.m.nodes[callback_id];
            if (callback.tag != .closure or callback.a >= self.m.closures.len) continue;
            const parameter_type = self.m.closures[callback.a].parameter.ty;
            if (parameter_type >= self.m.types.nodes.len) continue;
            const capability = self.m.types.nodes[parameter_type];
            if (capability.tag == .scoped and capability.b == instance.unit and capability.c == instance.decl) return;
            if (node_.tag == .task and node_.c == @backingInt(@import("task_types.zig").Op.split) and capability.tag == .product) {
                for (self.m.types.list(.{ .start = capability.a, .len = capability.b })) |input| {
                    const view = @import("task_types.zig").viewInfo(&self.m.types, input) orelse continue;
                    const scope = self.m.types.node(view.scope);
                    if (scope.b == instance.unit and scope.c == instance.decl) return;
                }
            }
        }
        return error.InvalidArtifact;
    }
    fn catalogs(self: Bounds) BoundsError!void {
        self.m.capability_contracts.validate(self.m.bindings.len, self.context.symbol_count orelse std.math.maxInt(u32)) catch return error.InvalidArtifact;
        if (self.m.capability_contracts.bindings.len != 0) {
            // Only feature-bearing modules pay for a bounded private shape
            // reconstruction. No capture table can stand in for body proof.
            var storage: [1024 * 1024]u8 align(@alignOf(usize)) = undefined;
            var buffer: std.heap.FixedBufferAllocator = .init(&storage);
            const allocator = buffer.allocator();
            for (self.m.capability_contracts.bindings) |entry| {
                buffer.reset();
                const binding_ = self.m.bindings[entry.binding];
                try require(binding_.capability_parameters.present() and binding_.body_id != 0 and binding_.body_id < self.m.bodies.len);
                const claimed = self.m.capability_contracts.header(entry.binding, binding_.capability_parameters.arity()).?;
                claimed.view().validate(claimed.root, claimed.arity, true) catch return error.InvalidArtifact;
                var reconstructed: @import("capability_contracts.zig").Store = .{};
                defer reconstructed.deinit(allocator);
                const root = @import("capability_contract_core.zig").deriveWithOwners(allocator, &reconstructed, self.m, self.m.bodies[binding_.body_id], binding_.capability_parameters, self.context.units) catch return error.InvalidArtifact;
                try require(root != null);
                const same = @import("capability_contracts.zig").equivalent(claimed.view(), claimed.root, reconstructed.view(), root.?) catch return error.InvalidArtifact;
                try require(same);
            }
        }

        for (self.m.bindings, 0..) |value, id| {
            try enumValue(check.Kind, value.kind);
            try enumValue(check.CapabilityFlow, value.capability_flow);
            try require(value.capability_parameters.valid());
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
            if (value.capability_parameters.present()) {
                try require(value.kind == .global and value.body_id != 0);
                try require(@import("capability_flow.zig").parameterCoreWithOwners(self.m, self.m.bodies[value.body_id], value.capability_parameters, self.context.units));
            }
            if (value.capability_flow != .unknown) {
                try require(value.kind == .global and value.body_id != 0);
                const body = self.m.bodies[value.body_id];
                if (value.capability_flow == .input_shape) {
                    try require(value.scheme.generative.len == 0 and @import("capability_flow.zig").unaryCoreWithOwners(self.m, body, .input_shape, self.context.units));
                    continue;
                }
                if (value.capability_flow == .consume_task) {
                    try @import("task_core.zig").receiveWrapper(self.m, @intCast(id), self.context.units);
                    continue;
                }
                if (value.capability_flow == .spawn_task) {
                    try @import("task_core.zig").spawnWrapper(self.m, @intCast(id), self.context.units);
                    continue;
                }
                if (value.capability_flow == .scope_task) {
                    try require(@import("task_core.zig").scopeWrapper(self.m, body.root));
                    continue;
                }
                const curried = value.capability_flow == .invoke_with_capability;
                const pair = value.capability_flow == .member_first_unit or value.capability_flow == .member_second_unit;
                var arity: u32 = 1;
                if (curried or pair) arity = 2;
                try require(body.is_function and body.parameters.len == arity and body.root != 0);
                try range(self.m.parameters.len, body.parameters.start, body.parameters.len);
                var input_index = body.parameters.start;
                if (pair) for (self.m.parameters[body.parameters.start..][0..2]) |entry| {
                    try self.ty(entry.ty);
                    try require(self.m.types.node(entry.ty).tag == .scoped);
                };
                if (curried) {
                    try self.ty(self.m.parameters[input_index].ty);
                    try require(self.m.types.node(self.m.parameters[input_index].ty).tag == .scoped);
                    input_index += 1;
                }
                if (value.capability_flow == .member_second_unit) input_index += 1;
                const input_binding = self.m.parameters[input_index].binding;
                try self.node(body.root, false);
                const root = self.m.node(body.root);
                var returned = root;
                if (value.capability_flow == .invoke_unit or value.capability_flow == .member_unit or curried or pair) {
                    try require(root.tag == .apply);
                    try self.node(root.a, false);
                    try self.node(root.b, false);
                    const argument = self.m.node(root.b);
                    try require(argument.tag == .constant and argument.ty == T.unit and argument.a == 0);
                    returned = self.m.node(root.a);
                }
                if (value.capability_flow == .member_unit or pair) {
                    try require(returned.tag == .operation_value);
                    try index(self.m.operation_values.len, returned.a);
                    const selected = self.m.operation_values[returned.a];
                    try self.node(selected.capability, false);
                    returned = self.m.node(selected.capability);
                }
                try require(returned.tag == .reference);
                try index(self.m.references.len, returned.a);
                const target = self.m.references[returned.a];
                try require((target.unit == 0 or target.unit == self.m.unit) and target.binding == input_binding);
            }
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
        try require(self.m.implementations.len <= 4096);
        for (self.m.implementations) |implementation| {
            try self.identity(implementation.identity, false);
            try self.identity(implementation.contract, false);
            try self.symbol(implementation.name, false);
            try require(implementation.declaration == 0 and implementation.identity.decl == T.opaque_name_bit | implementation.name);
            try self.listTypes(implementation.head);
            try self.listTypes(implementation.variables);
            for (self.m.types.list(implementation.variables)) |root| try require(self.m.types.node(root).tag == .variable);
            try range(self.m.types.extra.len, implementation.parameter_names.start, implementation.parameter_names.len);
            for (self.m.types.list(implementation.parameter_names)) |name| try self.symbol(name, false);
            try range(self.m.types.extra.len, implementation.row_parameter_names.start, implementation.row_parameter_names.len);
            for (self.m.types.list(implementation.row_parameter_names)) |name| try self.symbol(name, false);
            try require(implementation.parameter_names.len == implementation.variables.len and implementation.row_parameter_names.len == implementation.row_variables.len and implementation.row_parameters.len == implementation.row_variables.len);
            try range(self.m.types.extra.len, implementation.row_variables.start, implementation.row_variables.len);
            for (self.m.types.list(implementation.row_variables)) |variable| try index(self.m.types.effects.variable_count, variable);
            try range(self.m.types.extra.len, implementation.row_parameters.start, implementation.row_parameters.len);
            for (self.m.types.list(implementation.row_parameters)) |row_id| try index(self.m.types.effects.rows.len, row_id);
            try range(self.m.obligations.len, implementation.predicates.start, implementation.predicates.len);
            try range(self.m.implementation_members.len, implementation.members.start, implementation.members.len);
        }
        for (self.m.implementation_members) |member| {
            try self.symbol(member.name, false);
            try self.ty(member.root);
            try require(member.root != 0);
            if (member.kind == .type_) try require(member.target.unit == 0 and member.target.binding == 0) else {
                try self.bindingRef(.{ .unit = member.target.unit, .binding = member.target.binding }, false);
                try require(self.m.types.node(member.root).tag == .function);
            }
        }
        for (self.m.member_templates) |template| {
            try self.binding(template.binding, false);
            try self.identity(template.contract, false);
            try self.symbol(template.name, false);
            try self.listTypes(template.arguments);
        }
        for (self.m.selected_members) |member| {
            try self.symbol(member.name, false);
            try self.ty(member.root);
            try require(member.root != 0);
            if (member.kind == .type_) try require(member.target.unit == 0 and member.target.binding == 0) else try self.bindingRef(.{ .unit = member.target.unit, .binding = member.target.binding }, false);
        }
        for (self.m.selected_proofs, 0..) |proof, ordinal| {
            if (proof.predicate_target.binding != 0) try self.bindingRef(.{ .unit = proof.predicate_target.unit, .binding = proof.predicate_target.binding }, false) else try require(proof.predicate_target.unit == 0);
            if (proof.context != 0) _ = try self.owner(proof.context);
            try self.identity(proof.implementation, proof.kind == .predicate);
            try self.identity(proof.contract, proof.kind == .predicate);
            try self.listTypes(proof.arguments);
            inline for (.{ "ty", "other", "result", "signature" }) |field| try self.ty(@field(proof.predicate, field));
            try range(self.m.selected_members.len, proof.members.start, proof.members.len);
            try range(self.m.selected_edges.len, proof.prerequisites.start, proof.prerequisites.len);
            for (self.m.selected_edges[proof.prerequisites.start..][0..proof.prerequisites.len]) |child| try require(child < ordinal);
        }
        for (self.m.dictionary_selections) |selection| {
            try self.node(selection.owner, false);
            const package_node = self.m.node(selection.owner);
            try require(package_node.tag == .package_pack and package_node.ty == selection.quantifier);
            try self.ty(selection.quantifier);
            try index(self.m.types.quantifierGoals(selection.quantifier).len, selection.goal);
            switch (selection.proof) {
                .selected => |proof| {
                    try index(self.m.selected_proofs.len, proof);
                    try require(self.m.selected_proofs[proof].kind == .implementation);
                },
                .given => |given| {
                    try self.binding(given.opening, given.introduction != 0);
                    try self.node(given.introduction, true);
                    try self.ty(given.quantifier);
                    const quantifier = self.m.types.node(given.quantifier);
                    if (given.introduction == 0) {
                        try require(quantifier.tag == .existential and self.m.binding(given.opening).kind == .local);
                    } else try require(given.opening == 0 and quantifier.tag == .forall);
                    try index(self.m.types.quantifierGoals(given.quantifier).len, given.goal);
                    try self.listTypes(given.arguments);
                },
            }
            try range(self.m.extra.len, selection.members.start, selection.members.len);
            for (self.m.extra[selection.members.start..][0..selection.members.len]) |member| try self.node(member, true);
            try self.listNodes(selection.contents);
            try require(selection.contents.len != 0 and self.m.extra[selection.contents.start] == package_node.a);
        }
        for (self.m.dictionary_uses) |use| {
            try self.node(use.node, false);
            try self.binding(use.binding, false);
            try self.binding(use.opening, use.introduction != 0);
            try self.node(use.introduction, true);
            try self.ty(use.quantifier);
            if (use.introduction == 0) {
                try require(self.m.types.node(use.quantifier).tag == .existential);
            } else {
                try require(use.opening == 0 and self.m.types.node(use.quantifier).tag == .forall);
            }
            try index(self.m.types.quantifierGoals(use.quantifier).len, use.goal);
            try require(self.m.binding(use.binding).kind == .local);
            if (use.introduction == 0) try require(self.m.binding(use.opening).kind == .local);
            const use_node = self.m.node(use.node);
            try require(use_node.tag == .reference);
            try index(self.m.references.len, use_node.a);
            const use_reference = self.m.references[use_node.a];
            try require((use_reference.unit == 0 or use_reference.unit == self.m.unit) and use_reference.binding == use.binding);
        }
        for (self.m.selected_uses) |use| {
            try self.node(use.node, false);
            try index(self.m.selected_proofs.len, use.proof);
            try require(self.m.selected_proofs[use.proof].kind == .implementation);
        }
        for (self.m.contracts) |contract| {
            try self.identity(contract.identity, false);
            try self.symbol(contract.name, false);
            try self.listTypes(contract.parameters);
            try self.listTypes(contract.variables);
            for (self.m.types.list(contract.variables)) |id| try require(self.m.types.node(id).tag == .variable);
            try range(self.m.types.extra.len, contract.row_variables.start, contract.row_variables.len);
            for (self.m.types.list(contract.row_variables)) |variable| try index(self.m.types.effects.variable_count, variable);
            try range(self.m.types.extra.len, contract.row_parameters.start, contract.row_parameters.len);
            try range(self.m.types.extra.len, contract.row_parameter_names.start, contract.row_parameter_names.len);
            try require(contract.row_parameters.len == contract.row_parameter_names.len);
            for (self.m.types.list(contract.row_parameters)) |row_id| {
                try index(self.m.types.effects.rows.len, row_id);
                const value = self.m.types.effects.rows[row_id];
                try require(value.tail == .variable and value.labels.len == 0);
                const bound = for (self.m.types.list(contract.row_variables)) |variable| {
                    if (variable == value.tail.variable) break true;
                } else false;
                try require(bound);
            }
            for (self.m.types.list(contract.row_parameter_names), 0..) |name, ordinal| {
                try self.symbol(name, false);
                for (self.m.types.list(contract.row_parameter_names)[0..ordinal]) |previous| try require(name != previous);
            }
            try range(self.m.obligations.len, contract.predicates.start, contract.predicates.len);
            try range(self.m.contract_members.len, contract.members.start, contract.members.len);
            var requires_implementation = false;
            for (self.m.contract_members[contract.members.start..][0..contract.members.len], 0..) |member, ordinal| {
                try self.identity(member.contract, false);
                try require(std.meta.eql(member.contract, contract.identity));
                try self.symbol(member.name, false);
                try self.ty(member.root);
                try enumValue(@FieldType(@import("../reuse/principal_interface.zig").ContractMember, "kind"), member.kind);
                try require((member.kind == .abstract_type) == (member.root == 0));
                if (member.kind == .value) try require(self.m.types.node(member.root).tag == .function);
                for (self.m.contract_members[contract.members.start..][0..ordinal]) |old| try require(old.name != member.name);
                requires_implementation = requires_implementation or member.kind != .defined_type;
            }
            try require(requires_implementation == contract.requires_implementation);
        }
        for (self.m.nominals, 0..) |value, id| {
            try require(!value.affine or value.has_usage);
            try require(!value.closed_storage or !value.has_usage);
            if (value.has_usage) try require(self.m.has_usage_contracts);
            if (value.identity.unit != 0 and value.identity.unit != std.math.maxInt(u32)) try require(value.is_opaque == (value.identity.decl & T.opaque_name_bit != 0));
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
            try self.listTypes(value.variables);
            try self.listTypes(value.parameters);
            try self.ty(value.parameter);
            try self.ty(value.result);
            try require((value.parameter == 0) == (value.result == 0));
            if (value.parameter == 0) try require(value.variables.len == 0 and value.parameters.len == 0);
            const variables = self.m.types.list(value.variables);
            for (variables, 0..) |variable, index_| {
                try require(self.m.types.node(variable).tag == .variable);
                try require(std.mem.findScalar(T.Id, variables[0..index_], variable) == null);
            }
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
            try self.scopedInstance(value.instance);
            try self.node(value.capability, true);
            if (value.instance.decl != 0) {
                try require(value.capability != 0);
                const capability = self.m.types.node(self.m.typeOf(value.capability));
                try require(capability.tag == .scoped and capability.b == value.instance.unit and capability.c == value.instance.decl);
            } else try require(value.capability == 0);
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
            try self.node(value.selector, true);
            const operation = self.m.types.operation(value.operation);
            if (operation.instance.decl != 0) {
                try require(value.selector != 0);
                const signature = self.m.types.node(self.m.typeOf(value.selector));
                try require(signature.tag == .function);
                const labels = self.m.types.rowLabels(signature.c);
                try require(labels.len == 1 and labels[0] == value.operation);
            } else try require(value.selector == 0);
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
                .task => {
                    const operation = std.enums.fromInt(@import("task_types.zig").Op, value.c) orelse return error.InvalidArtifact;
                    try require(value.op == .none and value.b == @import("task_types.zig").arity(operation));
                    try self.listNodes(.{ .start = value.a, .len = value.b });
                },
                .package_pack => {
                    try require(self.m.has_rank_contracts and value.op == .none);
                    try self.node(value.a, false);
                    try self.listTypes(.{ .start = value.b, .len = value.c });
                    try require(self.m.types.node(value.ty).tag == .existential);
                },
                .package_unpack => {
                    try require(self.m.has_rank_contracts and value.op == .none);
                    try self.node(value.a, false);
                    try requiredIndex(self.m.bindings.len, value.b);
                    try range(self.m.extra.len, value.c, 3);
                    const opening = self.m.packageOpening(@intCast(id));
                    try self.node(opening.body, false);
                    try self.listTypes(opening.binders);
                    try require(self.m.types.node(self.m.typeOf(value.a)).tag == .existential);
                },
                .resource_acquire => {
                    try require(self.m.has_usage_contracts and value.op == .none and value.c == 0);
                    try self.node(value.a, false);
                    try self.node(value.b, false);
                    try require(self.m.node(value.a).tag == .closure and (self.m.node(value.b).tag == .closure or self.m.node(value.b).tag == .reference));
                },
                .resource_release => {
                    try require(self.m.has_usage_contracts and value.op == .none and value.b == 0 and value.c == 0);
                    try self.node(value.a, false);
                },
                .resource_scope => {
                    try require(self.m.has_usage_contracts and value.op == .none);
                    try self.node(value.a, false);
                    try self.node(value.b, false);
                    try self.node(value.c, false);
                    try require(self.m.node(value.a).tag == .closure and (self.m.node(value.b).tag == .closure or self.m.node(value.b).tag == .reference) and self.m.node(value.c).tag == .closure);
                },
                .usage_borrow => {
                    try self.node(value.a, false);
                    try self.node(value.b, false);
                    try require(self.m.has_usage_contracts and self.m.node(value.b).tag == .closure and value.c <= 1);
                },
                .usage_share => {
                    try self.node(value.a, false);
                    try require(self.m.has_usage_contracts and value.b == 0 and value.c == 0 and value.op == .none);
                },
                .usage_read => {
                    try self.node(value.a, false);
                    try require(self.m.has_usage_contracts and value.b <= 2 and value.c == 0);
                },
                .staging => {
                    const op = std.enums.fromInt(@import("typed_staging.zig").Op, value.c) orelse return error.InvalidArtifact;
                    try require(value.op == .none);
                    try self.node(value.a, false);
                    try self.node(value.b, op != .same);
                    if (op != .same) try require(value.b == 0);
                },
                .effect_scope => {
                    try self.node(value.a, false);
                    try require(self.m.node(value.a).tag == .closure);
                    const callback = self.m.closure(value.a);
                    try require(self.m.types.node(callback.parameter.ty).tag == .scoped);
                    try require(value.b == 0 and value.c == 0);
                },
                .proof_guard => {
                    try self.node(value.a, false);
                    try self.node(value.b, false);
                    const relation = std.enums.fromInt(@import("numeric_proof_terms.zig").Relation, value.c) orelse return error.InvalidArtifact;
                    const left = self.m.types.node(self.m.typeOf(value.a)).tag;
                    const right = self.m.types.node(self.m.typeOf(value.b)).tag;
                    try require(self.m.types.node(value.ty).tag == .erased_proof and right == .u32);
                    if (relation == .index) try require(left == .array or left == .list) else try require(left == .u32);
                },
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
                .contract_method => {
                    try index(self.m.member_templates.len, value.a);
                    try self.listNodes(.{ .start = value.b, .len = value.c });
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
                    if (value.tag == .apply and value.c != 0) try self.ty(value.c);
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
                    try require(value.op == .none or value.op == .continue_);
                    try self.control(value.a, true, false);
                    try self.listNodes(.{ .start = value.b, .len = value.c });
                    const target = self.m.nodes[value.a];
                    if (value.op == .continue_) try require(target.tag == .loop);
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
    try require(module.proof_contracts.len <= 4096);
    try require(module.has_numeric_proofs or module.proof_contracts.len == 0);
    for (module.proof_contracts) |value| {
        try requiredIndex(module.bindings.len, value.binding);
        try require(value.header.arity <= 4096 and value.header.operands.len <= 4096 and value.header.requirements.len <= 256);
    }
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
    var scoped_work: usize = 65_536;
    const b: Bounds = .{ .m = module, .context = context, .scoped_work = &scoped_work };
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
    for (module.nominals) |nominal| {
        if (nominal.identity.unit == module.unit or nominal.identity.unit == 0) continue;
        var producer = false;
        for (context.units) |owner| {
            if (owner.unit != nominal.identity.unit) continue;
            producer = true;
            var found = false;
            for (owner.nominals) |definition| if (std.meta.eql(definition.identity, nominal.identity)) {
                try require(definition.affine == nominal.affine and definition.has_usage == nominal.has_usage and definition.closed_storage == nominal.closed_storage);
                found = true;
            };
            try require(found);
        }
        // An imported affinity fact is portable authority only with its exact
        // producer. Source and dependency archives supply these module views.
        if (module.has_usage_contracts or nominal.closed_storage) try require(producer);
    }
    try @import("generative_core.zig").validate(module, context.units);
    if (module.has_usage_contracts) try @import("usage_core.zig").validate(module) else try @import("closed_nominal_storage.zig").validate(module);
}

pub const Kind = enum { type_, row, operation, node, pattern, closure, match_, arm, pattern_row, update, update_step, loop, request_loop, request_arm, resolver, operation_value, scheme, obligation };
const kind_count = @typeInfo(Kind).@"enum".field_names.len;
pub const Frame = struct { vertex: usize, edge: usize = 0 };
pub const Scratch = struct { colors: []u8, path: []Frame };
pub const Requirements = struct { colors: usize, path: usize };

const Role = enum(u8) { unset, type_, symbol, row_variable, row, count, node, binding, pattern, constructor, projection, destination };
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
    try mark(roles, scheme.generative.start, scheme.generative.len, .type_);
}
fn listRoles(m: *const core.Module, type_roles: []u8, core_roles: []u8) BoundsError!void {
    @memset(type_roles, 0);
    @memset(core_roles, 0);
    for (m.types.nodes) |n| switch (n.tag) {
        .forall, .existential => try mark(type_roles, n.b, n.c, .type_),
        .product => try mark(type_roles, n.a, n.b, .type_),
        .record => for (0..n.b) |i| {
            try mark(type_roles, @intCast(@as(usize, n.a) + i * 2), 1, .symbol);
            try mark(type_roles, @intCast(@as(usize, n.a) + i * 2 + 1), 1, .type_);
        },
        .nominal, .projection, .instance_selection => {
            try mark(type_roles, n.c, 1, .count);
            try mark(type_roles, n.c + 1, m.types.extra[n.c], .type_);
            if (n.tag == .projection) try mark(type_roles, n.c + 1 + m.types.extra[n.c], 1, .symbol);
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
    for (m.contracts) |contract| {
        try mark(type_roles, contract.parameters.start, contract.parameters.len, .type_);
        try mark(type_roles, contract.variables.start, contract.variables.len, .type_);
        try mark(type_roles, contract.row_variables.start, contract.row_variables.len, .row_variable);
        try mark(type_roles, contract.row_parameters.start, contract.row_parameters.len, .row);
        try mark(type_roles, contract.row_parameter_names.start, contract.row_parameter_names.len, .symbol);
    }
    for (m.implementations) |implementation| {
        try mark(type_roles, implementation.head.start, implementation.head.len, .type_);
        try mark(type_roles, implementation.variables.start, implementation.variables.len, .type_);
        try mark(type_roles, implementation.parameter_names.start, implementation.parameter_names.len, .symbol);
        try mark(type_roles, implementation.row_variables.start, implementation.row_variables.len, .row_variable);
        try mark(type_roles, implementation.row_parameters.start, implementation.row_parameters.len, .row);
        try mark(type_roles, implementation.row_parameter_names.start, implementation.row_parameter_names.len, .symbol);
    }
    for (m.member_templates) |template| try mark(type_roles, template.arguments.start, template.arguments.len, .type_);
    for (m.selected_proofs) |proof| try mark(type_roles, proof.arguments.start, proof.arguments.len, .type_);
    for (m.dictionary_selections) |selection| {
        switch (selection.proof) {
            .selected => {},
            .given => |given| try mark(type_roles, given.arguments.start, given.arguments.len, .type_),
        }
        try mark(core_roles, selection.members.start, selection.members.len, .node);
        try mark(core_roles, selection.contents.start, selection.contents.len, .node);
    }
    for (m.nominals) |n| {
        try mark(type_roles, n.parameters.start, n.parameters.len, .type_);
        try mark(type_roles, n.variables.start, n.variables.len, .type_);
        try mark(core_roles, n.constructors.start, n.constructors.len, .constructor);
    }
    for (m.operation_names) |operation| {
        try mark(type_roles, operation.variables.start, operation.variables.len, .type_);
        try mark(type_roles, operation.parameters.start, operation.parameters.len, .type_);
    }
    for (m.closures) |c| {
        try mark(type_roles, c.closed_rows.start, c.closed_rows.len, .row_variable);
        try mark(core_roles, c.captures.start, c.captures.len, .binding);
    }
    for (m.operation_values) |o| try mark(type_roles, o.arguments.start, o.arguments.len, .type_);
    for (m.nodes) |n| switch (n.tag) {
        .task, .block, .suite, .product, .array, .array_op => try mark(core_roles, n.a, n.b, .node),
        .record => {
            try mark(core_roles, n.a, n.b, .node);
            try mark(core_roles, n.c, n.b, .destination);
        },
        .call, .break_ => try mark(core_roles, n.b, n.c, .node),
        .package_pack => try mark(type_roles, n.b, n.c, .type_),
        .package_unpack => {
            try mark(core_roles, n.c, 1, .node);
            try mark(core_roles, n.c + 1, 2, .count);
            try mark(type_roles, m.extra[n.c + 1], m.extra[n.c + 2], .type_);
        },
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

pub const Graph = struct {
    m: *const core.Module,
    starts: [kind_count + 1]usize,
    pub fn init(m: *const core.Module) BoundsError!Graph {
        var result: Graph = .{ .m = m, .starts = @splat(0) };
        const counts = [_]usize{ m.types.nodes.len, m.types.effects.rows.len, m.types.operations.len, m.nodes.len, m.patterns.len, m.closures.len, m.matches.len, m.match_arms.len, m.pattern_rows.len, m.updates.len, m.update_steps.len, m.loops.len, m.request_loops.len, m.request_arms.len, m.resolver_ops.len, m.operation_values.len, m.bindings.len, m.obligations.len };
        for (counts, 0..) |size_, i| result.starts[i + 1] = try sum(result.starts[i], size_);
        return result;
    }
    pub fn vertex(self: Graph, kind: Kind, id: usize) usize {
        return self.starts[@backingInt(kind)] + id;
    }
    fn count(self: Graph) usize {
        return self.starts[kind_count];
    }
    pub fn item(self: *const Graph, vertex_: usize) struct { kind: Kind, id: usize } {
        var k: usize = 0;
        while (vertex_ >= self.starts[k + 1]) : (k += 1) {}
        return .{ .kind = @fromBackingInt(@intCast(k)), .id = vertex_ - self.starts[k] };
    }
    pub fn edge(self: *const Graph, vertex_: usize, slot: usize) ?usize {
        var k: usize = 0;
        while (vertex_ >= self.starts[k + 1]) : (k += 1) {}
        const id = vertex_ - self.starts[k];
        const m = self.m;
        switch (@as(Kind, @fromBackingInt(@intCast(k)))) {
            .type_ => {
                const v = m.types.nodes[id];
                return switch (v.tag) {
                    .forall, .existential => blk: {
                        if (slot == 0) break :blk self.vertex(.type_, v.a);
                        if (slot - 1 < v.c) break :blk self.vertex(.type_, m.types.extra[v.b + slot - 1]);
                        const goals = m.types.quantifierGoals(@intCast(id));
                        const goal_slot = slot - 1 - v.c;
                        if (goal_slot / 4 >= goals.len) break :blk null;
                        const goal = goals[goal_slot / 4];
                        const children = [_]T.Id{ goal.ty, goal.other, goal.result, goal.signature };
                        break :blk self.vertex(.type_, children[goal_slot % 4]);
                    },
                    .function => switch (slot) {
                        0 => self.vertex(.type_, v.a),
                        1 => self.vertex(.type_, v.b),
                        2 => if (m.types.effects.rows.len == 0) null else self.vertex(.row, v.c),
                        else => null,
                    },
                    .product => if (slot < v.b) self.vertex(.type_, m.types.extra[v.a + slot]) else null,
                    .record => if (slot < v.b) self.vertex(.type_, m.types.extra[v.a + slot * 2 + 1]) else null,
                    .nominal => if (slot < m.types.extra[v.c]) self.vertex(.type_, m.types.extra[v.c + 1 + slot]) else null,
                    .projection => blk: {
                        const argument_count = m.types.extra[v.c];
                        if (slot < argument_count) break :blk self.vertex(.type_, m.types.extra[v.c + 1 + slot]);
                        if (slot != argument_count) break :blk null;
                        const name = m.types.extra[v.c + 1 + argument_count];
                        for (m.contract_members) |member| if (member.contract.unit == v.a and member.contract.decl == v.b and member.name == name and member.kind == .defined_type) break :blk self.vertex(.type_, member.root);
                        break :blk null;
                    },
                    .instance_selection => if (slot < m.types.extra[v.c]) self.vertex(.type_, m.types.extra[v.c + 1 + slot]) else null,
                    .usage => switch (slot) {
                        0 => self.vertex(.type_, v.a),
                        1 => if (v.c == 0) null else self.vertex(.type_, v.c),
                        else => null,
                    },
                    .scoped => switch (slot) {
                        0 => self.vertex(.type_, v.a),
                        1 => if (v.b == 0) self.vertex(.type_, v.c) else null,
                        else => null,
                    },
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
                    .resource_acquire, .usage_borrow, .staging, .scalar, .logical, .apply, .associated, .record_merge, .type_same, .effect_provider, .handle, .proof_guard => switch (slot) {
                        0 => self.vertex(.node, v.a),
                        1 => self.vertex(.node, v.b),
                        else => null,
                    },
                    .resource_scope, .if_value, .if_stmt, .state_provider => switch (slot) {
                        0 => self.vertex(.node, v.a),
                        1 => self.vertex(.node, v.b),
                        2 => self.vertex(.node, v.c),
                        else => null,
                    },
                    .task, .block, .suite, .product, .record, .array, .array_op => if (slot < v.b) self.vertex(.node, m.extra[v.a + slot]) else null,
                    .call, .contract_method, .break_ => if (slot < v.c) self.vertex(.node, m.extra[v.b + slot]) else null,
                    .bind, .construct => if (slot == 0) self.vertex(.node, v.b) else null,
                    .package_unpack => switch (slot) {
                        0 => self.vertex(.node, v.a),
                        1 => self.vertex(.node, m.extra[v.c]),
                        else => null,
                    },
                    .package_pack => if (slot < m.children(@intCast(id)).len) self.vertex(.node, m.children(@intCast(id))[slot]) else null,
                    .resource_release, .usage_share, .usage_read, .return_, .project, .force, .result_associated, .computation, .effect_scope => if (slot == 0) self.vertex(.node, v.a) else null,
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
            .request_arm => return switch (slot) {
                0 => self.vertex(.node, m.request_arms[id].callback),
                1 => self.vertex(.node, m.request_arms[id].selector),
                else => null,
            },
            .resolver => {
                const v = m.resolver_ops[id];
                if (slot == 0) return self.vertex(.node, v.resolver);
                return if (slot - 1 < v.arguments.len) self.vertex(.node, m.extra[v.arguments.start + slot - 1]) else null;
            },
            .operation_value => return switch (slot) {
                0 => self.vertex(.node, m.operation_values[id].witness),
                1 => self.vertex(.node, m.operation_values[id].capability),
                else => null,
            },
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
    return .{ .colors = try sum(count, try sum(try sum(module.types.extra.len, module.extra.len), stagingBindingCount(module))), .path = count };
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

fn stageBinding(bindings: []u8, binding: core.BindingId, stage: u8) BoundsError!void {
    if (binding == 0) return;
    const encoded = stage + 1;
    try require(bindings[binding] == 0 or bindings[binding] == encoded);
    bindings[binding] = encoded;
}
fn stageCarries(m: *const core.Module, bindings: []u8, carries: core.List, stage: u8) BoundsError!void {
    for (m.loop_carries[carries.start..][0..carries.len]) |carry| inline for (.{ "incoming", "iteration", "backedge", "outgoing" }) |field| try stageBinding(bindings, @field(carry, field), stage);
}
fn stagingBindingCount(m: *const core.Module) usize {
    for (m.nodes) |node| if (node.tag == .staging) return m.bindings.len;
    return 0;
}
fn stagingScopes(graph: Graph, context: Context, scratch: Scratch, allocator: ?std.mem.Allocator, workspace: ?*@import("scheme_equations.zig").Workspace) Error!void {
    const m = graph.m;
    if (stagingBindingCount(m) == 0) return;
    const bindings = scratch.colors[graph.count() + m.types.extra.len + m.extra.len ..][0..m.bindings.len];
    @memset(bindings, 0);
    @memset(scratch.colors[0..graph.count()], 0);
    var remaining: usize = 1_000_000;
    var capture_rights: @import("staging_capture_rights.zig").Checker = .{ .allocator = allocator, .module = m, .units = context.units, .remaining = &remaining };
    defer capture_rights.deinit();
    for (m.bodies[1..]) |body| {
        for (m.parameters[body.parameters.start..][0..body.parameters.len]) |parameter_| try stageBinding(bindings, parameter_.binding, 0);
        const root = graph.vertex(.node, body.root);
        if (scratch.colors[root] != 0) {
            try require(scratch.colors[root] == 1);
            continue;
        }
        scratch.colors[root] = 1;
        var depth: usize = 1;
        scratch.path[0] = .{ .vertex = root };
        while (depth != 0) {
            const top = &scratch.path[depth - 1];
            const current_stage = scratch.colors[top.vertex] - 1;
            const node_start = graph.starts[@backingInt(Kind.node)];
            const node_end = graph.starts[@backingInt(Kind.node) + 1];
            const is_node = top.vertex >= node_start and top.vertex < node_end;
            if (top.edge == 0) {
                if (is_node) {
                    const id: core.Id = @intCast(top.vertex - node_start);
                    const n = m.nodes[id];
                    const quote = n.tag == .staging and n.c == @backingInt(@import("typed_staging.zig").Op.quote);
                    var future_reference = n.tag == .reference and current_stage != 0;
                    if (future_reference) {
                        const reference = m.reference(id);
                        if (reference.unit == 0 or reference.unit == m.unit) {
                            const kind = m.binding(reference.binding).kind;
                            future_reference = kind != .parameter and kind != .local;
                        }
                    }
                    if (quote or future_reference or (n.tag == .call and current_stage != 0)) {
                        var closed_rows = body.closed_rows;
                        var owner_depth = depth;
                        while (owner_depth != 0) {
                            owner_depth -= 1;
                            const vertex = scratch.path[owner_depth].vertex;
                            const start = graph.starts[@backingInt(Kind.closure)];
                            if (vertex >= start and vertex < graph.starts[@backingInt(Kind.closure) + 1]) {
                                closed_rows = m.closures[vertex - start].closed_rows;
                                break;
                            }
                        }
                        if (quote) {
                            @import("staging_core.zig").quoteEffectsContextWorkspace(m, context.units, n, closed_rows, &remaining, workspace) catch |err| {
                                if (workspace) |owner| if (owner.oom) return error.OutOfMemory;
                                return err;
                            };
                        } else if (future_reference) {
                            @import("staging_core.zig").namedReferenceContextWorkspace(m, context.units, id, closed_rows, &remaining, workspace) catch |err| {
                                if (workspace) |owner| if (owner.oom) return error.OutOfMemory;
                                return err;
                            };
                        } else _ = @import("staging_core.zig").namedCallContextWorkspace(m, context.units, id, &remaining, workspace) catch |err| {
                            if (workspace) |owner| if (owner.oom) return error.OutOfMemory;
                            return err;
                        };
                    }
                    for (m.dictionary_uses) |use| if (use.introduction != 0 and use.introduction == id) try stageBinding(bindings, use.binding, current_stage);
                    if (n.tag == .bind) try stageBinding(bindings, n.a, current_stage);
                    if (n.tag == .package_unpack) {
                        try stageBinding(bindings, n.b, current_stage);
                        for (m.dictionary_uses) |use| if (use.opening == n.b) try stageBinding(bindings, use.binding, current_stage);
                    }
                    for (m.merges[m.merge_ranges[id].start..][0..m.merge_ranges[id].len]) |merge| {
                        try stageBinding(bindings, merge.result, current_stage);
                        try stageBinding(bindings, merge.then_binding, current_stage);
                        try stageBinding(bindings, merge.else_binding, current_stage);
                    }
                    if (n.tag == .loop) try stageCarries(m, bindings, m.loops[n.a].carries, current_stage);
                    if (n.tag == .request_loop) {
                        const request = m.request_loops[n.a];
                        try stageCarries(m, bindings, request.carries, current_stage);
                        for (m.extra[request.completion_state_bindings.start..][0..request.completion_state_bindings.len]) |binding_| try stageBinding(bindings, binding_, current_stage);
                    }
                    if (n.tag == .update) try stageBinding(bindings, m.updates[n.a].self_binding, current_stage);
                } else if (top.vertex >= graph.starts[@backingInt(Kind.pattern)] and top.vertex < graph.starts[@backingInt(Kind.pattern) + 1]) {
                    const pattern = m.patterns[top.vertex - graph.starts[@backingInt(Kind.pattern)]];
                    if (pattern.tag == .bind) try stageBinding(bindings, pattern.a, current_stage);
                } else if (top.vertex >= graph.starts[@backingInt(Kind.closure)] and top.vertex < graph.starts[@backingInt(Kind.closure) + 1]) {
                    const catalog = top.vertex - graph.starts[@backingInt(Kind.closure)];
                    const closure = m.closures[catalog];
                    try stageBinding(bindings, closure.parameter.binding, current_stage);
                    if (current_stage != 0) {
                        var scopes: [128]core.Id = undefined;
                        var scope_count: usize = 0;
                        var loans: [128]core.Id = undefined;
                        var loan_count: usize = 0;
                        var closure_node: core.Id = 0;
                        for (scratch.path[0..depth], 0..) |entry, position| {
                            if (entry.vertex < node_start or entry.vertex >= node_end) continue;
                            if (scratch.colors[entry.vertex] != current_stage + 1) continue;
                            const id: core.Id = @intCast(entry.vertex - node_start);
                            const node = m.node(id);
                            if (@import("capability_lifetimes.zig").isScope(node)) {
                                try require(scope_count < scopes.len);
                                scopes[scope_count] = id;
                                scope_count += 1;
                            }
                            if (node.tag == .usage_borrow or node.tag == .resource_scope) {
                                var callback: core.Id = node.b;
                                if (node.tag == .resource_scope) callback = node.c;
                                try require(m.node(callback).tag == .closure);
                                const owner = graph.vertex(.closure, m.node(callback).a);
                                for (scratch.path[position + 1 .. depth]) |ancestor| {
                                    if (ancestor.vertex != owner or scratch.colors[owner] != current_stage + 1) continue;
                                    try require(loan_count < loans.len);
                                    loans[loan_count] = id;
                                    loan_count += 1;
                                    break;
                                }
                            }
                            if ((node.tag == .closure or node.tag == .suspend_) and node.a == catalog) closure_node = id;
                        }
                        if (loan_count != 0) {
                            try require(closure_node != 0);
                            try capture_rights.requireLoanCaptures(closure_node, loans[0..loan_count]);
                        }
                        for (m.extra[closure.captures.start..][0..closure.captures.len]) |binding| {
                            try require(binding != closure.parameter.binding);
                            if (try @import("staging_core.zig").authorityFree(m, m.bindings[binding].ty)) continue;
                            try require(closure_node != 0);
                            try capture_rights.capture(closure_node, binding, scopes[0..scope_count], loans[0..loan_count]);
                        }
                    }
                }
            }
            if (graph.edge(top.vertex, top.edge)) |child| {
                top.edge += 1;
                if (child == node_start or (m.patterns.len != 0 and child == graph.vertex(.pattern, 0))) continue;
                var stage = current_stage;
                if (is_node) {
                    const n = m.nodes[top.vertex - node_start];
                    if (n.tag == .staging) {
                        const op: @import("typed_staging.zig").Op = @fromBackingInt(n.c);
                        if (op == .quote) {
                            try require(stage < 128);
                            stage += 1;
                        } else if (op == .lift or op == .splice) {
                            try require(stage != 0);
                            stage -= 1;
                        }
                    }
                }
                if (scratch.colors[child] != 0) {
                    try require(scratch.colors[child] == stage + 1);
                    continue;
                }
                scratch.colors[child] = stage + 1;
                scratch.path[depth] = .{ .vertex = child };
                depth += 1;
            } else depth -= 1;
        }
    }
    for (m.nodes, 0..) |n, id| {
        const stage = scratch.colors[graph.vertex(.node, id)];
        if (stage == 0) continue;
        if ((n.tag == .closure or n.tag == .suspend_) and stage > 1) {
            const captures = m.closures[n.a].captures;
            for (m.extra[captures.start..][0..captures.len]) |binding_| {
                const captured = m.bindings[binding_];
                try require((captured.kind == .parameter or captured.kind == .local) and bindings[binding_] == stage);
            }
        }
        var ref: ?core.BindingRef = null;
        if (n.tag == .reference) ref = m.references[n.a];
        if (n.tag == .call) ref = m.calls[n.a].target;
        if (ref) |target| {
            if (target.unit == 0 or target.unit == m.unit) {
                const binding_ = m.bindings[target.binding];
                if (binding_.kind == .parameter or binding_.kind == .local) {
                    try require(bindings[target.binding] == stage);
                    continue;
                }
            }
            // Exact producer calls and immutable free references were proved
            // during the enclosing owner walk, including callable bodies.
            if (stage > 1) {
                try require(n.tag == .call or n.tag == .reference);
            }
        }
    }
}

fn associatedCharge(remaining: *usize) BoundsError!void {
    try require(remaining.* != 0);
    remaining.* -= 1;
}
fn associatedScope(graph: Graph, contract: core.Contract, root: T.Id, member: bool, scratch: Scratch, remaining: *usize) BoundsError!void {
    const type_count = graph.starts[@backingInt(Kind.row)];
    const row_start = graph.starts[@backingInt(Kind.row)];
    const operation_start = graph.starts[@backingInt(Kind.operation)];
    const count = graph.starts[@backingInt(Kind.node)];
    @memset(scratch.colors[0..count], 0);
    var depth: usize = 1;
    scratch.path[0] = .{ .vertex = root };
    while (depth != 0) {
        const top = &scratch.path[depth - 1];
        if (scratch.colors[top.vertex] == 0) {
            try associatedCharge(remaining);
            try require(depth <= 256);
            scratch.colors[top.vertex] = 1;
            if (top.vertex < type_count) {
                const node = graph.m.types.nodes[top.vertex];
                if (node.tag == .variable) {
                    const bound = for (graph.m.types.list(contract.variables)) |id| {
                        if (graph.m.types.node(id).tag == .variable and graph.m.types.node(id).a == node.a) break true;
                    } else false;
                    try require(bound);
                }
            } else if (top.vertex < operation_start) {
                const row = graph.m.types.effects.rows[top.vertex - row_start];
                try require(row.tail != .parameter);
                if (row.tail == .variable) {
                    var bound = false;
                    if (member) {
                        for (graph.m.types.list(contract.row_parameters)) |id| {
                            const declared = graph.m.types.effects.rows[id];
                            if (declared.tail == .variable and declared.tail.variable == row.tail.variable) bound = true;
                        }
                    } else {
                        for (graph.m.types.list(contract.row_variables)) |id| {
                            if (row.tail.variable == id) bound = true;
                        }
                    }
                    try require(bound);
                }
            }
        }
        // Scope follows application arguments, never the referenced recipe's
        // separate binders. The preceding cycle check follows both edges.
        const recipe_edge = top.vertex < type_count and graph.m.types.nodes[top.vertex].tag == .projection and top.edge == graph.m.types.extra[graph.m.types.nodes[top.vertex].c];
        const child = if (recipe_edge) null else graph.edge(top.vertex, top.edge);
        if (child) |vertex| {
            top.edge += 1;
            if (scratch.colors[vertex] == 0) {
                scratch.path[depth] = .{ .vertex = vertex };
                depth += 1;
            }
        } else depth -= 1;
    }
}
fn associatedScopes(graph: Graph, scratch: Scratch, remaining: *usize) BoundsError!void {
    const m = graph.m;
    if (m.contract_members.len == 0) return;
    for (m.contracts, 0..) |contract, ordinal| {
        try associatedCharge(remaining);
        try require(contract.identity.unit != 0 and contract.identity.decl == T.opaque_name_bit | contract.name);
        for (m.contracts[0..ordinal]) |previous| {
            try associatedCharge(remaining);
            try require(!std.meta.eql(previous.identity, contract.identity));
        }
        for (m.contract_members[contract.members.start..][0..contract.members.len]) |member| try associatedScope(graph, contract, member.root, true, scratch, remaining);
        for (m.obligations[contract.predicates.start..][0..contract.predicates.len]) |predicate| inline for (.{ "ty", "other", "result", "signature" }) |field| try associatedScope(graph, contract, @field(predicate, field), false, scratch, remaining);
    }
    for (0..m.contract_members.len) |index_| {
        var claims: usize = 0;
        for (m.contracts) |contract| {
            try associatedCharge(remaining);
            if (index_ >= contract.members.start and index_ - contract.members.start < contract.members.len) claims += 1;
        }
        try require(claims == 1);
    }
}

/// Complete validation with explicit caller-owned linear workspace. An
/// undersized workspace is an API error (InvalidArtifact), never a size policy.
pub fn validateWithScratch(module: *const core.Module, context: Context, scratch: Scratch) BoundsError!void {
    try validateBounds(module, context);
    // Implementation admission owns its required coherence/proof workspace.
    // Callers of this allocation-free API must use validateWithBudget when
    // such declarations are present; never publish unchecked feature graphs.
    try require(module.implementations.len == 0 and module.member_templates.len == 0 and module.selected_proofs.len == 0);
    try require(!module.has_numeric_proofs and module.proof_contracts.len == 0);
    for (module.types.nodes) |node| try require(node.tag != .erased_proof);
    const graph = try Graph.init(module);
    const needed = try scratchRequirements(module);
    try require(scratch.colors.len >= needed.colors and scratch.path.len >= needed.path);
    const start = graph.count();
    try listRoles(module, scratch.colors[start..][0..module.types.extra.len], scratch.colors[start + module.types.extra.len ..][0..module.extra.len]);
    try cycles(graph, scratch);
    try @import("task_core.zig").validateContext(module, context.units);
    try @import("staging_core.zig").shapes(module);
    stagingScopes(graph, context, scratch, null, null) catch return error.InvalidArtifact;
    var remaining: usize = 1_000_000;
    try associatedScopes(graph, scratch, &remaining);
    try @import("rank_portable.zig").executable(module, context);
    try @import("capability_invocations.zig").validateWithScratch(module, context.units);
    try @import("capability_lifetimes.zig").rejectSupportedEscapesWithScratch(module, context.units);
}

pub fn validate(allocator: std.mem.Allocator, module: *const core.Module, context: Context) Error!void {
    var remaining: usize = 1_000_000;
    return validateWithBudget(allocator, module, context, &remaining);
}
pub fn validateWithBudget(allocator: std.mem.Allocator, module: *const core.Module, context: Context, remaining: *usize) Error!void {
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
    var equations: @import("scheme_equations.zig").Workspace = .{ .allocator = allocator };
    @import("task_core.zig").validateContextWorkspace(module, context.units, &equations) catch |err| {
        if (equations.oom) return error.OutOfMemory;
        return err;
    };
    try @import("staging_core.zig").shapes(module);
    try stagingScopes(graph, context, .{ .colors = colors, .path = path }, allocator, &equations);
    try associatedScopes(graph, .{ .colors = colors, .path = path }, remaining);
    try @import("../eval/implementation_admission.zig").scopes(allocator, &module.types, module, module.obligations, remaining);
    try @import("../eval/selected_implementation_admission.zig").core(allocator, module, remaining);
    try @import("numeric_proof_core.zig").validate(allocator, module, context.units, remaining);
    try @import("rank_portable.zig").executableWorkspace(module, context, &equations);
    try @import("capability_invocations.zig").validate(allocator, module, context.units);
    try @import("capability_lifetimes.zig").rejectSupportedEscapes(allocator, module, context.units);
}
