//! Owned, relocatable checked facts for a conservative body-elaboration cutoff.
//! Unsupported syntax/types keep ordinary checking; executable lowering is fresh.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const check = @import("../check/check.zig");
const symbols = @import("../parse/symbols.zig");
const T = @import("../check/types.zig");
const F = @import("../check/frozen_types.zig");
const snapshot = @import("dependency_snapshot.zig");
const auxiliary = @import("body_auxiliary.zig");
const A = std.mem.Allocator;
pub const Digest = [32]u8;
pub const ExternalNames = struct {
    context: *const anyopaque,
    lookup: *const fn (*const anyopaque, check.ExternalTarget) ?[]const u8,
    unit_origin: ?*const fn (*const anyopaque, u32) ?Digest = null,
    closed_rows: ?*const fn (*const anyopaque, check.ExternalTarget) ?Digest = null,
    qualification: ?*const fn (*const anyopaque, u32, ast.Span) ?Digest = null,
    capabilities: ?*const fn (*const anyopaque, check.ExternalTarget) ?Digest = null,
};
pub const EffectAnnotation = struct { family: u32, member: ?u32 = null };
pub const AnnotationLookup = struct {
    context: *const anyopaque,
    lookup: *const fn (*const anyopaque, []const u8) ?usize,
    effect: ?*const fn (*const anyopaque, []const u8) ?EffectAnnotation = null,
};
pub const Values = struct {
    capability_contracts: @import("../check/capability_contracts.zig").Collection = .{},
    proof_contracts: []const check.ProofContract = &.{},
    bindings: []const check.Binding,
    tree: *const ast.Tree,
    names: ?ExternalNames = null,
    annotations: ?AnnotationLookup = null,
    ready: ?struct {
        context: *const anyopaque,
        lookup: *const fn (*const anyopaque, check.BindingId) bool,
    } = null,
};
/// One body's immutable recipe proofs. Depth and proof debit stay exact;
/// entries never cross a checker mutation or persist in a receipt.
pub const RecipeMemo = struct {
    const Entry = struct { index: usize, depth: usize, cost: usize, digest: Digest };
    entries: [64]Entry = undefined,
    len: usize = 0,
    fn lookup(self: *const RecipeMemo, index: usize, depth: usize) ?Entry {
        for (self.entries[0..self.len]) |entry| if (entry.index == index and entry.depth == depth) return entry;
        return null;
    }
    fn save(self: *RecipeMemo, index: usize, depth: usize, cost: usize, digest: Digest) void {
        if (self.len == self.entries.len) return;
        self.entries[self.len] = .{ .index = index, .depth = depth, .cost = cost, .digest = digest };
        self.len += 1;
    }
};
const PrivateFacts = struct {
    tree: *const ast.Tree,
    checked: *const check.Checked,
    ids: []const ast.Id,
    fn physical(self: PrivateFacts, identity_: T.NominalIdentity, selection: bool) ?u32 {
        if (identity_.unit != self.checked.unit) return null;
        const slot = position(self.ids, identity_.decl) orelse return null;
        for (self.checked.types.nodes.items) |node| {
            if (node.tag != .instance_selection or node.a != identity_.unit or node.b != identity_.decl) continue;
            const arguments = self.checked.types.nominalArguments(node);
            if (arguments.len == 2 or arguments.len == 3) return slot + 1;
        }
        if (selection) return null;
        for (self.checked.effect_scopes) |scope| {
            if (scope.parameter != identity_.decl or position(self.ids, scope.node) == null) continue;
            if (position(self.ids, scope.callback) == null) return null;
            const callback = self.tree.node(scope.callback);
            if (callback.tag != .lambda or callback.a != scope.parameter) return null;
            return slot + 1;
        }
        if (identity_.decl >= self.checked.resolved.len) return null;
        const binding = self.checked.resolved[identity_.decl];
        if (binding == 0 or binding >= self.checked.bindings.len) return null;
        const parameter = self.checked.bindings[binding];
        if (parameter.kind != .parameter or parameter.declaration != identity_.decl or position(self.ids, parameter.owner) == null) return null;
        const lambda = self.tree.node(parameter.owner);
        if (lambda.tag != .lambda or lambda.a != parameter.declaration) return null;
        var budget: usize = 4096;
        if (self.carrier(parameter.ty, identity_, &budget, 0)) return slot + 1;
        return null;
    }
    fn carrier(self: PrivateFacts, ty: T.Id, identity_: T.NominalIdentity, budget: *usize, depth: usize) bool {
        if (budget.* == 0 or depth >= 128) return false;
        budget.* -= 1;
        const node = self.checked.types.node(self.checked.types.head(ty, 0));
        switch (node.tag) {
            .scoped => {
                if (node.b == identity_.unit and node.c == identity_.decl) return true;
                return self.carrier(node.a, identity_, budget, depth + 1);
            },
            .usage => return self.carrier(node.a, identity_, budget, depth + 1),
            .product => for (self.checked.types.list(.{ .start = node.a, .len = node.b })) |child| {
                if (self.carrier(child, identity_, budget, depth + 1)) return true;
            },
            .record => for (0..node.b) |index| {
                if (self.carrier(self.checked.types.recordField(node, index).ty, identity_, budget, depth + 1)) return true;
            },
            else => {},
        }
        return false;
    }
    const Version = struct { kind: enum { source, binding }, operand: u32 };
    fn version(self: PrivateFacts, id: T.Id) ?Version {
        const node = self.checked.types.node(id);
        if (node.tag != .instance_version or node.a != self.checked.unit) return null;
        var result: ?Version = null;
        for (self.checked.generative_bindings) |binding| {
            const origin = position(self.ids, binding.origin) orelse continue;
            const selected = self.checked.types.node(self.checked.types.head(binding.selection, 0));
            if (selected.tag != .scoped or selected.b != 0) continue;
            const selection = self.checked.types.node(self.checked.types.head(selected.c, 0));
            if (selection.tag != .instance_selection) continue;
            const arguments = self.checked.types.nominalArguments(selection);
            if (arguments.len != 3 or self.checked.types.head(arguments[2], 0) != id) continue;
            const end = self.tree.span(binding.origin).end;
            if (end == std.math.maxInt(u32) or end + 1 != node.b) continue;
            const candidate: Version = .{ .kind = .source, .operand = origin + 1 };
            if (result) |old| if (!std.meta.eql(old, candidate)) return null;
            result = candidate;
        }
        if (result != null) return result;
        for (self.checked.types.nodes.items) |parent| {
            if (parent.tag == .instance_selection) {
                const arguments = self.checked.types.nominalArguments(parent);
                if (arguments.len != 3 or arguments[2] != id or parent.a != self.checked.unit) continue;
                const source = position(self.ids, parent.b) orelse continue;
                const end = self.tree.span(parent.b).end;
                if (end == std.math.maxInt(u32) or end + 1 != node.b) continue;
                const candidate: Version = .{ .kind = .source, .operand = source + 1 };
                if (result) |old| if (!std.meta.eql(old, candidate)) return null;
                result = candidate;
            } else if (parent.tag == .nominal) {
                const slot = T.compilerNominalVersionArgument(.{ .unit = parent.a, .decl = parent.b }) orelse continue;
                const arguments = self.checked.types.nominalArguments(parent);
                if (slot >= arguments.len or arguments[slot] != id or node.b == 0 or node.b >= self.checked.bindings.len) continue;
                const binding = self.checked.bindings[node.b];
                if ((binding.kind != .local and binding.kind != .parameter) or position(self.ids, binding.declaration) == null or position(self.ids, binding.owner) == null) continue;
                const usage = self.checked.types.node(self.checked.types.head(binding.ty, 0));
                if (usage.tag != .usage or usage.b != @backingInt(T.UsageKind.unique) or self.checked.types.node(self.checked.types.head(usage.a, 0)).tag != .array) continue;
                const candidate: Version = .{ .kind = .binding, .operand = node.b };
                if (result) |old| if (!std.meta.eql(old, candidate)) return null;
                result = candidate;
            }
        }
        return result;
    }
    fn rigid(self: PrivateFacts, scope: u32) bool {
        if (scope == 0) return false;
        for (self.checked.rank_implementations) |implementation| if (implementation.scope == scope and position(self.ids, implementation.node) != null) return true;
        for (self.checked.usage_loans) |loan| {
            if (loan.region == 0 or position(self.ids, loan.source) == null) continue;
            const region = self.checked.types.node(self.checked.types.head(loan.region, 0));
            if (region.tag == .rigid and region.a == scope) return true;
        }
        return false;
    }
    fn bound(self: PrivateFacts, id: T.Id) bool {
        // A leaf's identity is its actual immutable quantifier edge, not an
        // ordinal shared with an unrelated package or implementation scope.
        var budget: usize = 4096;
        for (self.checked.types.nodes.items) |node| {
            if (budget == 0) return false;
            budget -= 1;
            if (node.tag != .forall and node.tag != .existential) continue;
            if (std.mem.findScalar(T.Id, self.checked.types.list(.{ .start = node.b, .len = node.c }), id) != null) return true;
        }
        return false;
    }
};
const BoundScope = struct { ids: []const T.Id, parent: ?*const BoundScope };
pub const Catalog = struct {
    bound_scope: ?*const BoundScope = null,
    private: ?PrivateFacts = null,
    recipes: ?*RecipeMemo = null,
    implementation_read: ?*bool = null,
    unit: u32,
    pool: *const symbols.Pool,
    nominals: []const check.Nominal,
    constructors: []const check.Constructor,
    effect_families: []const check.EffectFamily = &.{},
    effect_templates: []const check.EffectTemplate = &.{},
    contracts: []const check.Contract = &.{},
    contract_members: []const check.ContractMember = &.{},
    contract_predicates: []const T.Obligation = &.{},
    implementations: []const check.Implementation = &.{},
    implementation_members: []const check.ImplementationMember = &.{},
    implementation_predicates: []const T.Obligation = &.{},
    values: ?Values = null,
    patterns: ?F.Patterns = null,
    fn identity(self: Catalog, value: T.NominalIdentity) ?usize {
        for (self.nominals, 0..) |nominal, index| if (std.meta.eql(nominal.identity, value)) return index;
        return null;
    }
    pub fn unitOrigin(self: Catalog, unit: u32) ?Digest {
        if (unit != 0) if (self.values) |values| if (values.names) |names| if (names.unit_origin) |lookup| return lookup(names.context, unit);
        // Standalone module callers have no project dictionary. Preserve their
        // exact ordinal authority rather than inventing a portable origin.
        var hash: std.crypto.hash.Blake3 = .init(.{});
        hashWord(&hash, unit);
        var digest: Digest = undefined;
        hash.final(&digest);
        return digest;
    }
    pub fn namedOrigin(self: Catalog, origin: Digest, name: []const u8) ?usize {
        var found: ?usize = null;
        for (self.nominals, 0..) |nominal, index| {
            if (!std.mem.eql(u8, self.pool.get(nominal.name), name)) continue;
            const current = self.unitOrigin(nominal.identity.unit) orelse return null;
            if (!std.mem.eql(u8, &origin, &current)) continue;
            if (found != null) return null;
            found = index;
        }
        return found;
    }
    pub fn named(self: Catalog, unit: u32, name: []const u8) ?usize {
        for (self.nominals, 0..) |nominal, index| if (nominal.identity.unit == unit and std.mem.eql(u8, self.pool.get(nominal.name), name)) return index;
        return null;
    }
    pub fn operation(self: Catalog, identity_: T.NominalIdentity, budget: *usize) ?usize {
        var found: ?usize = null;
        for (self.effect_templates, 0..) |value, index| {
            if (budget.* == 0) return null;
            budget.* -= 1;
            if (!std.meta.eql(value.identity, identity_)) continue;
            if (found != null) return null;
            found = index;
        }
        return found;
    }
    pub fn namedOperation(self: Catalog, origin: Digest, name: []const u8) ?usize {
        var budget: usize = 4096;
        var found: ?usize = null;
        for (self.effect_templates, 0..) |value, index| {
            if (budget == 0 or value.family >= self.effect_families.len) return null;
            budget -= 1;
            const family = self.effect_families[value.family];
            const current = self.unitOrigin(value.identity.unit) orelse return null;
            if (!std.mem.eql(u8, &origin, &current)) continue;
            const separator = std.mem.findScalar(u8, name, ':') orelse return null;
            const size = std.fmt.parseInt(usize, name[0..separator], 10) catch return null;
            const rest = name[separator + 1 ..];
            if (size > rest.len) return null;
            if (!std.mem.eql(u8, rest[0..size], self.pool.get(family.name)) or !std.mem.eql(u8, rest[size..], self.pool.get(value.name))) continue;
            if (found != null) return null;
            found = index;
        }
        return found;
    }
    pub fn familyIdentity(self: Catalog, identity_: T.NominalIdentity) ?usize {
        for (self.effect_families, 0..) |value, index| if (std.meta.eql(value.identity, identity_)) return index;
        return null;
    }
    pub fn namedFamily(self: Catalog, origin: Digest, name: []const u8) ?usize {
        var found: ?usize = null;
        for (self.effect_families, 0..) |value, index| {
            if (!std.mem.eql(u8, self.pool.get(value.name), name)) continue;
            const current = self.unitOrigin(value.identity.unit) orelse return null;
            if (!std.mem.eql(u8, &current, &origin) or found != null) return null;
            found = index;
        }
        return found;
    }
    fn contract(self: Catalog, identity_: T.NominalIdentity) ?check.Contract {
        for (self.contracts) |value| if (std.meta.eql(value.identity, identity_)) return value;
        return null;
    }
    pub fn namedContract(self: Catalog, origin: Digest, name: []const u8) ?check.Contract {
        var found: ?check.Contract = null;
        for (self.contracts) |value| {
            if (!std.mem.eql(u8, self.pool.get(value.name), name)) continue;
            const current = self.unitOrigin(value.identity.unit) orelse return null;
            if (!std.mem.eql(u8, &origin, &current)) continue;
            if (found != null) return null;
            found = value;
        }
        return found;
    }
};
pub const IdentityKind = enum { nominal, contract, operation, family };
pub const IdentityRead = struct { unit: u32, origin: Digest, name: []u8, digest: Digest, kind: IdentityKind = .nominal };
pub const TypeRead = struct { position: u32, digest: Digest, effect: bool = false };
pub fn runtimeBinding(tree: *const ast.Tree, binding: check.Binding) bool {
    return binding.kind == .global and tree.node(binding.declaration).tag == .value_decl and tree.valueDecl(binding.declaration).runtime;
}
pub fn nominalDigest(source: F.Source, catalog: Catalog, index: usize) ?Digest {
    var budget: usize = 4096;
    return nominalDigestAt(source, catalog, index, 0, &budget);
}
fn nominalDigestAt(source: F.Source, catalog: Catalog, index: usize, depth: usize, budget: *usize) ?Digest {
    if (depth >= 128 or budget.* == 0) return null;
    if (catalog.recipes) |memo| if (memo.lookup(index, depth)) |entry| {
        if (entry.cost > budget.*) return null;
        budget.* -= entry.cost;
        return entry.digest;
    };
    const available = budget.*;
    budget.* -= 1;
    const nominal = catalog.nominals[index];
    if (nominal.name == 0 or nominal.alias != 0) return null;
    var storage = nominal.storage;
    if (nominal.is_opaque and storage.kind == .unknown) {
        var storage_budget: usize = 4096;
        storage = @import("../backend/opaque_storage.zig").infer(source, catalog.nominals, catalog.constructors, @intCast(index), &storage_budget);
    }
    if (nominal.is_opaque and storage.kind == .unknown) return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, @backingInt(ast.Tag.data_decl));
    const origin = catalog.unitOrigin(nominal.identity.unit) orelse return null;
    hash.update(&origin);
    hash.update(catalog.pool.get(nominal.name));
    hashWord(&hash, @intFromBool(nominal.private));
    hashWord(&hash, @intFromBool(nominal.is_opaque));
    hashWord(&hash, @intFromBool(nominal.affine));
    hashWord(&hash, @intFromBool(nominal.has_usage));
    hashWord(&hash, @intFromBool(nominal.closed_storage));
    hashWord(&hash, @backingInt(storage.kind));
    hashWord(&hash, storage.parameter);
    hashWord(&hash, storage.selector);
    hashWord(&hash, nominal.parameters.len);
    for (source.list(nominal.parameters)) |parameter| {
        if (!typeHash(source, parameter, &hash, budget, depth + 1, false, source.list(nominal.variables), &.{}, catalog)) return null;
    }
    if (!parameterHash(source, catalog, nominal, &hash, depth + 1, budget)) return null;
    hashWord(&hash, nominal.constructors.len);
    for (source.list(nominal.constructors)) |constructor_index| {
        if (constructor_index >= catalog.constructors.len) return null;
        const constructor = catalog.constructors[constructor_index];
        const name = catalog.pool.get(constructor.name);
        if (name.len == 0) return null;
        hashWord(&hash, @intCast(name.len));
        hash.update(name);
        hashWord(&hash, constructor.tag);
        hashWord(&hash, @intFromBool(constructor.private));
        hashWord(&hash, @intFromBool(constructor.declared_record));
        if (!typeHash(source, constructor.payload, &hash, budget, depth + 1, false, source.list(nominal.variables), &.{}, catalog)) return null;
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    if (catalog.recipes) |memo| memo.save(index, depth, available - budget.*, digest);
    return digest;
}
fn parameterHash(source: F.Source, catalog: Catalog, nominal: check.Nominal, hash: *std.crypto.hash.Blake3, depth: usize, budget: *usize) bool {
    if (nominal.patterns.len != nominal.parameters.len) return false;
    if (nominal.patterns.len == 0) return true;
    const patterns = catalog.patterns orelse return false;
    hashWord(hash, nominal.patterns.len);
    for (patterns.list(nominal.patterns)) |pattern| if (!patternHash(source, patterns, pattern, source.list(nominal.variables), catalog, hash, depth, budget)) return false;
    return true;
}
fn patternHash(source: F.Source, patterns: F.Patterns, id: u32, variables: []const T.Id, catalog: Catalog, hash: *std.crypto.hash.Blake3, depth: usize, budget: *usize) bool {
    if (depth >= 128 or budget.* == 0) return false;
    budget.* -= 1;
    const node = patterns.node(id);
    hashWord(hash, @backingInt(node.kind));
    switch (node.kind) {
        .binding => return typeHash(source, node.a, hash, budget, depth + 1, false, variables, &.{}, catalog),
        .tuple, .array => {
            hashWord(hash, node.b);
            for (patterns.list(.{ .start = node.a, .len = node.b })) |child| if (!patternHash(source, patterns, child, variables, catalog, hash, depth + 1, budget)) return false;
        },
        .record => {
            hashWord(hash, node.b);
            // Parameter fields bind by spelling. Their authored order is a
            // conservative recipe read, independent of symbol ordinals.
            for (0..node.b) |index| {
                const field = patterns.field(node, index);
                const name = catalog.pool.get(field.name);
                if (name.len == 0) return false;
                hashWord(hash, @intCast(name.len));
                hash.update(name);
                if (!patternHash(source, patterns, field.pattern, variables, catalog, hash, depth + 1, budget)) return false;
            }
        },
    }
    return true;
}
pub fn operationDigest(source: F.Source, catalog: Catalog, index: usize) ?Digest {
    var budget: usize = 4096;
    return operationDigestAt(source, catalog, index, 0, &budget);
}
fn operationDigestAt(source: F.Source, catalog: Catalog, index: usize, depth: usize, budget: *usize) ?Digest {
    if (depth >= 128 or budget.* == 0 or index >= catalog.effect_templates.len) return null;
    budget.* -= 1;
    const operation_ = catalog.effect_templates[index];
    if (operation_.family >= catalog.effect_families.len) return null;
    const family = catalog.effect_families[operation_.family];
    if (family.name == 0 or operation_.name == 0 or family.operations.len == 0 or family.parameters.len != family.patterns.len) return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, 0x45524601); // complete operation family recipe
    const origin = catalog.unitOrigin(family.identity.unit) orelse return null;
    hash.update(&origin);
    for ([_]u32{ family.name, operation_.name }) |symbol| {
        const name = catalog.pool.get(symbol);
        hashWord(&hash, @intCast(name.len));
        hash.update(name);
    }
    hashWord(&hash, @intFromBool(family.private));
    hashWord(&hash, @intFromBool(family.callable));
    const variables = source.list(family.variables);
    hashWord(&hash, family.variables.len);
    hashWord(&hash, family.parameters.len);
    for (source.list(family.parameters)) |parameter| if (!typeHash(source, parameter, &hash, budget, depth + 1, false, variables, &.{}, catalog)) return null;
    if (family.patterns.len != 0) {
        const patterns = catalog.patterns orelse return null;
        for (patterns.list(family.patterns)) |pattern| if (!patternHash(source, patterns, pattern, variables, catalog, &hash, depth + 1, budget)) return null;
    }
    hashWord(&hash, family.operations.len);
    var selected = false;
    for (source.list(family.operations)) |member| {
        if (budget.* == 0 or member >= catalog.effect_templates.len) return null;
        budget.* -= 1;
        const template = catalog.effect_templates[member];
        if (template.family != operation_.family or template.identity.unit != family.identity.unit) return null;
        selected = selected or member == index;
        const name = catalog.pool.get(template.name);
        if (name.len == 0) return null;
        hashWord(&hash, @intCast(name.len));
        hash.update(name);
        if (!typeHash(source, template.parameter, &hash, budget, depth + 1, false, variables, &.{}, catalog) or !typeHash(source, template.result, &hash, budget, depth + 1, false, variables, &.{}, catalog)) return null;
    }
    if (!selected) return null;
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
pub fn familyDigest(source: F.Source, catalog: Catalog, index: usize) ?Digest {
    var budget: usize = 4096;
    return familyDigestAt(source, catalog, index, 0, &budget);
}
fn familyDigestAt(source: F.Source, catalog: Catalog, index: usize, depth: usize, budget: *usize) ?Digest {
    if (index >= catalog.effect_families.len) return null;
    const family = catalog.effect_families[index];
    if (family.operations.len == 0) return null;
    const member = source.list(family.operations)[0];
    const recipe = operationDigestAt(source, catalog, member, depth, budget) orelse return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, @backingInt(ast.Tag.effect_type_decl));
    hash.update(&recipe);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
pub fn effectAnnotationDigest(source: F.Source, catalog: Catalog, tree: *const ast.Tree, id: ast.Id) ?Digest {
    const row = tree.node(id);
    if (row.tag != .effect_row) return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    var budget: usize = 4096;
    hashWord(&hash, row.b);
    for (tree.list(.{ .start = row.a, .len = row.b })) |label| {
        if (budget == 0) return null;
        budget -= 1;
        var head = label;
        var arity: usize = 0;
        while (tree.node(head).tag == .type_apply) {
            if (budget == 0) return null;
            budget -= 1;
            arity += 1;
            head = tree.node(head).a;
        }
        const node = tree.node(head);
        if (node.tag != .type_name) return null;
        const name = catalog.pool.get(node.a);
        if (std.mem.eql(u8, name, "Foreign")) {
            if (arity != 0) return null;
            hashWord(&hash, T.foreign_operation);
            continue;
        }
        const values = catalog.values orelse return null;
        const annotations = values.annotations orelse return null;
        const lookup = annotations.effect orelse return null;
        const resolved = lookup(annotations.context, name) orelse return null;
        if (resolved.family >= catalog.effect_families.len) return null;
        const family = catalog.effect_families[resolved.family];
        if (arity != family.parameters.len or family.operations.len == 0) return null;
        hashWord(&hash, 2);
        if (resolved.member) |member| {
            if (member >= catalog.effect_templates.len or catalog.effect_templates[member].family != resolved.family) return null;
            const digest = operationDigestAt(source, catalog, member, 0, &budget) orelse return null;
            hash.update(&digest);
        } else {
            for (source.list(family.operations)) |member| {
                const digest = operationDigestAt(source, catalog, member, 0, &budget) orelse return null;
                hash.update(&digest);
            }
        }
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
pub fn annotationDigest(source: F.Source, catalog: Catalog, name: []const u8) ?Digest {
    if (@import("../check/numeric_proof_terms.zig").typeName(name)) |relation| {
        var hash: std.crypto.hash.Blake3 = .init(.{});
        hash.update("numeric-proof-annotation");
        hashWord(&hash, @backingInt(relation));
        var result: Digest = undefined;
        hash.final(&result);
        return result;
    }

    var index: ?usize = null;
    if (catalog.values) |values| if (values.annotations) |annotations| {
        index = annotations.lookup(annotations.context, name);
    };
    if (index == null) index = catalog.named(catalog.unit, name);
    if (index == null) {
        var selected: ?usize = null;
        if (catalog.values) |values| if (values.annotations) |annotations| if (annotations.effect) |lookup| {
            const effect = lookup(annotations.context, name) orelse return null;
            if (effect.member != null) return null;
            selected = effect.family;
        };
        if (selected == null) for (catalog.effect_families, 0..) |family, ordinal| {
            if (family.identity.unit != catalog.unit or !std.mem.eql(u8, catalog.pool.get(family.name), name)) continue;
            if (selected != null) return null;
            selected = ordinal;
        };
        return familyDigest(source, catalog, selected orelse return null);
    }
    const resolved = index.?;
    if (resolved >= catalog.nominals.len) return null;
    const nominal = catalog.nominals[resolved];
    if (nominal.alias != 0) {
        var budget: usize = 4096;
        var alias_hash: std.crypto.hash.Blake3 = .init(.{});
        hashWord(&alias_hash, @backingInt(ast.Tag.type_alias_decl));
        const origin = catalog.unitOrigin(nominal.identity.unit) orelse return null;
        alias_hash.update(&origin);
        alias_hash.update(catalog.pool.get(nominal.name));
        hashWord(&alias_hash, @intFromBool(nominal.private));
        hashWord(&alias_hash, nominal.parameters.len);
        if (!parameterHash(source, catalog, nominal, &alias_hash, 0, &budget)) return null;
        if (!typeHash(source, nominal.alias, &alias_hash, &budget, 0, false, source.list(nominal.variables), source.list(nominal.alias_rows), catalog)) return null;
        var digest: Digest = undefined;
        alias_hash.final(&digest);
        return digest;
    }
    const digest = nominalDigest(source, catalog, resolved) orelse return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, @backingInt(T.Tag.nominal));
    hash.update(&digest);
    hashWord(&hash, 0);
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}
pub const Fact = struct { ty: T.Id, binding: u32 = 0, closed_rows: T.List = .{} };
pub const Binding = struct {
    name: []u8,
    kind: check.Kind,
    private: bool,
    declaration: u32,
    owner: u32,
    ty: T.Id,
    scheme: bool,
    named_function: bool,
    capability_flow: check.CapabilityFlow = .unknown,
    capability_parameters: @import("../check/capability_flow.zig").Parameters = .{},
    runtime: bool,
    external: ?check.ExternalTarget,
    interface: Digest,
    predecessor: u32 = 0,
};
pub const FieldProjection = struct { position: u32, nominal: T.NominalIdentity, tags: T.List };
pub const Access = struct { position: u32, ty: T.Id, nominal: T.NominalIdentity, tags: T.List, field: u32 };
pub const LocalScheme = struct { binding: u32, principal: T.Scheme };
pub const Constructor = struct { position: u32, nominal: T.NominalIdentity, tag: u32 };
pub const Merge = struct { position: u32, result: u32, yes: u32, no: u32 };
pub const LoopCarry = struct { position: u32, incoming: u32, iteration: u32, backedge: u32, outgoing: u32 };
pub const LoopExit = struct { position: u32, loop: u32, bindings: T.List };
/// Ordinary bodies pay only for the optional pointer; loop facts share one owner.
pub const Loops = struct {
    carries: []LoopCarry = &.{},
    exits: []LoopExit = &.{},
    bindings: []u32 = &.{},
    pub fn deinit(self: *Loops, a: A) void {
        a.free(self.carries);
        a.free(self.exits);
        a.free(self.bindings);
        a.destroy(self);
    }
};
pub const Rebinding = struct { position: u32, root: u32, self_binding: u32 };
pub const Projection = struct { position: u32, index: u32, owner: u32 = 0 };
pub const Signature = struct { position: u32, ty: T.Id, kind: enum { dispatch, demand, demand_left } = .dispatch, once: bool = false };
/// A covered predicate was proven by a written top-level clause. Replay
/// appends it like a residual so the clause covers it again.
pub const Predicate = struct { value: T.Obligation, position: u32, local: bool = false, covered: bool = false, name: []u8 };
pub const Body = struct {
    owner: *Chunk,
    name: []u8,
    source: []u8,
    syntax: Digest,
    facts: []Fact,
    bindings: []Binding,
    closed_rows: []u32,
    /// The global certificate shares the same projected row-variable storage
    /// as lambda certificates; simple arrows need no auxiliary allocation.
    body_closed_rows: T.List = .{},
    type_work: usize,
    nominals: []u32 = &.{},
    type_reads: []TypeRead = &.{},
    predicates: []Predicate = &.{},
    signatures: []Signature = &.{},
    projections: []Projection = &.{},
    merges: []Merge = &.{},
    loops: ?*Loops = null,
    auxiliary: ?*auxiliary.Owner = null,
    rebindings: []Rebinding = &.{},
    constructors: []Constructor = &.{},
    local_schemes: []LocalScheme = &.{},
    fields: []FieldProjection = &.{},
    accesses: []Access = &.{},
    field_tags: []u32 = &.{},
    members: [][]u8 = &.{},
    selection_digest: ?Digest = null,
    implementation_selection: bool = false,
    pub fn bytes(self: *const Body) usize {
        var total = @sizeOf(Body) + self.name.len + self.source.len + self.facts.len * @sizeOf(Fact) + self.bindings.len * @sizeOf(Binding) + self.closed_rows.len * 4 + self.nominals.len * 4 + self.type_reads.len * @sizeOf(TypeRead);
        for (self.bindings) |binding| total += binding.name.len;
        total += self.predicates.len * @sizeOf(Predicate);
        for (self.predicates) |predicate| total += predicate.name.len;
        total += self.fields.len * @sizeOf(FieldProjection) + self.field_tags.len * 4 + self.local_schemes.len * @sizeOf(LocalScheme) + self.constructors.len * @sizeOf(Constructor) + self.merges.len * @sizeOf(Merge) + self.projections.len * @sizeOf(Projection) + self.signatures.len * @sizeOf(Signature) + self.members.len * @sizeOf([]u8);
        total += self.accesses.len * @sizeOf(Access);
        if (self.loops) |loops| total += @sizeOf(Loops) + loops.carries.len * @sizeOf(LoopCarry) + loops.exits.len * @sizeOf(LoopExit) + loops.bindings.len * @sizeOf(u32);
        if (self.auxiliary) |owner| total += owner.bytes();
        total += self.rebindings.len * @sizeOf(Rebinding);
        for (self.members) |member| total += member.len;
        return total;
    }
    pub fn deinit(self: *Body, a: A) void {
        a.free(self.name);
        a.free(self.source);
        a.free(self.facts);
        a.free(self.closed_rows);
        a.free(self.nominals);
        a.free(self.type_reads);
        for (self.bindings) |binding| a.free(binding.name);
        a.free(self.bindings);
        for (self.predicates) |predicate| a.free(predicate.name);
        a.free(self.predicates);
        a.free(self.signatures);
        a.free(self.projections);
        a.free(self.merges);
        if (self.loops) |loops| loops.deinit(a);
        if (self.auxiliary) |owner| owner.deinit(a);
        a.free(self.rebindings);
        a.free(self.constructors);
        a.free(self.local_schemes);
        a.free(self.fields);
        a.free(self.accesses);
        a.free(self.field_tags);
        for (self.members) |member| a.free(member);
        a.free(self.members);
    }
};
/// Immutable chunk ownership lets a successful replay retain its facts without
/// rebuilding a type projection. Each chunk keeps its allocation provenance.
/// The original declaration and its actual where-clause ordinal own source
/// qualification. Byte spans and numeric AST identifiers are reconstructed.
pub const Qualification = struct { name: u32, tag: ast.Tag, ordinal: u32, private: bool };
pub const Chunk = struct {
    allocator: A,
    references: usize = 1,
    graph: F.Graph,
    nominals: []IdentityRead,
    field_names: [][]u8,
    qualifications: []Qualification,
    bodies: []Body,
    body_bytes: usize,
    type_work: usize,
    fn release(self: *Chunk) void {
        self.references -= 1;
        if (self.references != 0) return;
        const a = self.allocator;
        for (self.bodies) |*body| body.deinit(a);
        a.free(self.bodies);
        snapshot.deinitGraph(a, &self.graph);
        for (self.nominals) |nominal| a.free(nominal.name);
        a.free(self.nominals);
        for (self.field_names) |name| a.free(name);
        a.free(self.field_names);
        a.free(self.qualifications);
        a.destroy(self);
    }
};
pub const Lease = struct {
    owner: *Chunk,
    index: usize,
    pub fn body(self: Lease) *const Body {
        return &self.owner.bodies[self.index];
    }
};
pub const Cache = struct {
    /// Release screens found trivial bodies at parity; retain the measured
    /// twelve-application class and larger proofs, not tiny declarations.
    minimum_nodes: usize = 64,
    bodies: std.ArrayList(Lease) = .empty,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    pub fn deinit(self: *Cache, a: A) void {
        self.index.deinit(a);
        for (self.bodies.items) |lease| lease.owner.release();
        self.bodies.deinit(a);
        self.* = .{};
    }
    pub fn find(self: *const Cache, name: []const u8) ?*const Body {
        const index = self.index.get(name) orelse return null;
        return self.bodies.items[index].body();
    }
    pub fn retain(self: *Cache, a: A, body: *const Body) A.Error!void {
        try self.bodies.ensureUnusedCapacity(a, 1);
        try self.index.ensureUnusedCapacity(a, 1);
        self.index.putAssumeCapacity(body.name, self.bodies.items.len);
        self.bodies.appendAssumeCapacity(.{ .owner = body.owner, .index = (@intFromPtr(body) - @intFromPtr(body.owner.bodies.ptr)) / @sizeOf(Body) });
        body.owner.references += 1;
    }
    /// A chunk may survive through a single body after many other bodies change.
    /// Compact when obsolete body payload dominates; never mutate an old owner.
    fn compact(self: *Cache, a: A) A.Error!void {
        var live: std.AutoHashMapUnmanaged(*Chunk, struct { bytes: usize = 0, types: usize = 0 }) = .empty;
        defer live.deinit(a);
        for (self.bodies.items) |lease| {
            const body = lease.body();
            const entry = try live.getOrPut(a, body.owner);
            if (!entry.found_existing) entry.value_ptr.* = .{};
            entry.value_ptr.bytes += body.bytes();
            entry.value_ptr.types += body.type_work;
        }
        var index: usize = 0;
        while (index < self.bodies.items.len) {
            const body = self.bodies.items[index].body();
            const active = live.get(body.owner).?;
            if (active.bytes >= (body.owner.body_bytes + 1) / 2 and active.types >= (body.owner.type_work + 1) / 2) {
                index += 1;
                continue;
            }
            _ = self.index.remove(body.name);
            _ = self.bodies.swapRemove(index);
            if (index < self.bodies.items.len) self.index.getPtr(self.bodies.items[index].body().name).?.* = index;
            body.owner.release();
        }
    }
    pub fn payload(self: *const Cache, a: A) A.Error!struct { bytes: usize, graph_nodes: usize, chunks: usize } {
        var seen: std.AutoHashMapUnmanaged(*Chunk, void) = .empty;
        defer seen.deinit(a);
        var total: usize = self.bodies.items.len * @sizeOf(Lease);
        var nodes: usize = 0;
        for (self.bodies.items) |lease| {
            const body = lease.body();
            const entry = try seen.getOrPut(a, body.owner);
            if (entry.found_existing) continue;
            const owner = body.owner;
            const graph = owner.graph;
            total += @sizeOf(Chunk) + owner.qualifications.len * @sizeOf(Qualification) + owner.body_bytes + graph.nodes.len * @sizeOf(T.Node) + graph.extra.len * 4 + graph.rows.len * @sizeOf(T.Effects.Row) + graph.labels.len * 4 + graph.operations.len * @sizeOf(T.Operation);
            total += graph.quantifier_goals.len * @sizeOf(T.QuantifierGoals) + graph.quantifier_obligations.len * @sizeOf(T.Obligation);
            total += owner.nominals.len * @sizeOf(IdentityRead);
            for (owner.nominals) |nominal| total += nominal.name.len;
            total += owner.field_names.len * @sizeOf([]u8);
            for (owner.field_names) |name| total += name.len;
            nodes += graph.nodes.len;
        }
        return .{ .bytes = total, .graph_nodes = nodes, .chunks = seen.count() };
    }
    pub fn clone(self: *const Cache, a: A) A.Error!Cache {
        var result: Cache = .{ .minimum_nodes = self.minimum_nodes };
        errdefer result.deinit(a);
        for (self.bodies.items) |lease| try result.retain(a, lease.body());
        return result;
    }
};

fn hashWord(hash: *std.crypto.hash.Blake3, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hash.update(&bytes);
}
fn declarationHash(catalog: Catalog, value: anytype, hash: *std.crypto.hash.Blake3) bool {
    const origin = catalog.unitOrigin(value.identity.unit) orelse return false;
    const name = catalog.pool.get(value.name);
    if (name.len == 0) return false;
    hash.update(&origin);
    hashWord(hash, @intCast(name.len));
    hash.update(name);
    hashWord(hash, @intFromBool(value.private));
    return true;
}
fn contractHash(catalog: Catalog, identity_: T.NominalIdentity, hash: *std.crypto.hash.Blake3) bool {
    const value = catalog.contract(identity_) orelse return false;
    if (catalog.implementation_read) |read| read.* = true;
    if (!declarationHash(catalog, value, hash)) return false;
    hashWord(hash, value.parameters.len);
    hashWord(hash, @intFromBool(value.requires_implementation));
    return true;
}
pub fn contractDigest(catalog: Catalog, identity_: T.NominalIdentity) ?Digest {
    var hash: std.crypto.hash.Blake3 = .init(.{});
    if (!contractHash(catalog, identity_, &hash)) return null;
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
fn contractPredicate(value: T.Obligation, catalog: Catalog) bool {
    return value.kind == .contract and value.other == 0 and value.result == 0 and value.signature == 0 and value.name == 0 and catalog.contract(value.identity) != null;
}
fn implementationPredicateHash(source: F.Source, catalog: Catalog, value: T.Obligation, variables: []const T.Id, hash: *std.crypto.hash.Blake3, budget: *usize) bool {
    if (budget.* == 0) return false;
    budget.* -= 1;
    switch (value.kind) {
        .contract => if (!contractPredicate(value, catalog) or !contractHash(catalog, value.identity, hash)) return false,
        .dispatch, .result_dispatch, .type_rep => if (value.identity.unit != 0 or value.identity.decl != 0) return false,
        else => return false,
    }
    hashWord(hash, @backingInt(value.kind));
    hashWord(hash, @backingInt(value.operator));
    hashWord(hash, @intFromBool(value.explicit));
    const name = catalog.pool.get(value.name);
    hashWord(hash, @intCast(name.len));
    hash.update(name);
    for ([_]T.Id{ value.ty, value.other, value.result, value.signature }) |root| {
        if (!typeHash(source, root, hash, budget, 0, false, variables, &.{}, catalog)) return false;
    }
    return true;
}
/// Checking will reconstruct every selected proof and precise use. This read
/// owns the complete semantic selection input, including losing heads and
/// prerequisite recipes; it never imports a previous proof or method target.
pub fn implementationDigest(source: F.Source, catalog: Catalog, ordinary: Digest) ?Digest {
    if (catalog.contracts.len > 64 or catalog.implementations.len > 64) return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hash.update(&ordinary);
    var budget: usize = 4096;
    hashWord(&hash, @intCast(catalog.contracts.len));
    for (catalog.contracts) |value| {
        if (value.row_variables.len != 0 or value.row_parameters.len != 0 or value.patterns.len != value.parameters.len) return null;
        if (!contractHash(catalog, value.identity, &hash)) return null;
        const variables = source.list(value.variables);
        hashWord(&hash, @intCast(variables.len));
        if (value.patterns.len != 0) {
            const patterns = catalog.patterns orelse return null;
            for (patterns.list(value.patterns)) |pattern| if (!patternHash(source, patterns, pattern, variables, catalog, &hash, 0, &budget)) return null;
        }
        for (source.list(value.parameters)) |root| if (!typeHash(source, root, &hash, &budget, 0, false, variables, &.{}, catalog)) return null;
        hashWord(&hash, value.predicates.len);
        for (catalog.contract_predicates[value.predicates.start..][0..value.predicates.len]) |predicate| if (!implementationPredicateHash(source, catalog, predicate, variables, &hash, &budget)) return null;
        hashWord(&hash, value.members.len);
        for (catalog.contract_members[value.members.start..][0..value.members.len]) |member| {
            const name = catalog.pool.get(member.name);
            hashWord(&hash, @intCast(name.len));
            hash.update(name);
            hashWord(&hash, @backingInt(member.kind));
            if (!typeHash(source, member.root, &hash, &budget, 0, false, variables, &.{}, catalog)) return null;
        }
    }
    hashWord(&hash, @intCast(catalog.implementations.len));
    for (catalog.implementations) |value| {
        if (value.row_variables.len != 0 or value.row_parameters.len != 0) return null;
        if (!declarationHash(catalog, value, &hash) or !contractHash(catalog, value.contract, &hash)) return null;
        const variables = source.list(value.variables);
        hashWord(&hash, @intCast(variables.len));
        hashWord(&hash, value.head.len);
        for (source.list(value.head)) |root| if (!typeHash(source, root, &hash, &budget, 0, false, variables, &.{}, catalog)) return null;
        hashWord(&hash, value.predicates.len);
        for (catalog.implementation_predicates[value.predicates.start..][0..value.predicates.len]) |predicate| if (!implementationPredicateHash(source, catalog, predicate, variables, &hash, &budget)) return null;
        hashWord(&hash, value.members.len);
        for (catalog.implementation_members[value.members.start..][0..value.members.len]) |member| {
            const name = catalog.pool.get(member.name);
            hashWord(&hash, @intCast(name.len));
            hash.update(name);
            hashWord(&hash, @backingInt(member.kind));
            if (member.root == 0 or !typeHash(source, member.root, &hash, &budget, 0, false, variables, &.{}, catalog)) return null;
            if (member.kind == .value) {
                const values = catalog.values orelse return null;
                var binding: ?check.Binding = null;
                if (member.target.unit == catalog.unit and member.target.binding < values.bindings.len) {
                    binding = values.bindings[member.target.binding];
                } else for (values.bindings) |candidate| if (candidate.external) |target| {
                    if (std.meta.eql(target, member.target)) {
                        binding = candidate;
                        break;
                    }
                };
                if (binding) |current| {
                    var proof: InterfaceProof = .{ .source = source, .catalog = catalog };
                    if (!proof.capabilityHash(current, &hash)) return null;
                } else {
                    const names = values.names orelse return null;
                    const lookup = names.capabilities orelse return null;
                    const digest = lookup(names.context, member.target) orelse return null;
                    hash.update(&digest);
                }
            }
        }
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
fn typeHash(source: F.Source, ty: T.Id, hash: *std.crypto.hash.Blake3, budget: *usize, depth: usize, allow_open_rows: bool, variables: []const T.Id, row_variables: []const u32, catalog: Catalog) bool {
    if (budget.* == 0 or depth >= 128) return false;
    budget.* -= 1;
    const node = source.node(source.head(ty, 0));
    hashWord(hash, @backingInt(node.tag));
    switch (node.tag) {
        .absent, .unit, .boolean, .u32, .f32, .never, .erased_proof => {},
        .variable => {
            for (variables, 0..) |variable, index| {
                const quantified = source.node(source.head(variable, 0));
                if (quantified.tag == .variable and quantified.a == node.a) {
                    hashWord(hash, @intCast(index));
                    return true;
                }
            }
            return allow_open_rows;
        },
        .function, .demand, .provider => {
            const row = source.row(node.c);
            hashWord(hash, row.labels.len);
            for (source.rowLabels(row.labels)) |label| {
                if (label == T.foreign_operation) {
                    hashWord(hash, T.foreign_operation);
                    continue;
                }
                if (label == 0 or label >= source.operationCount()) return false;
                const operation_ = source.operation(label);
                if (operation_.instance.unit != 0 or operation_.instance.decl != 0) {
                    if (!allow_open_rows) return false;
                    if (operation_.instance.unit == 0) {
                        if (!typeHash(source, operation_.instance.decl, hash, budget, depth + 1, true, variables, row_variables, catalog)) return false;
                    } else {
                        const private = catalog.private orelse return false;
                        hashWord(hash, private.physical(operation_.instance, false) orelse return false);
                    }
                }
                const index = catalog.operation(operation_.identity, budget) orelse return false;
                const digest = operationDigestAt(source, catalog, index, depth + 1, budget) orelse return false;
                if (operation_.arguments.len != catalog.effect_families[catalog.effect_templates[index].family].parameters.len) return false;
                hash.update(&digest);
                hashWord(hash, operation_.arguments.len);
                for (source.list(operation_.arguments)) |argument| if (!typeHash(source, argument, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
            }
            switch (row.tail) {
                .closed => hashWord(hash, 0),
                .variable => |variable| {
                    hashWord(hash, 1);
                    const index = std.mem.findScalar(u32, row_variables, variable);
                    if (index) |position_| {
                        hashWord(hash, @intCast(position_));
                    } else if (!allow_open_rows) return false;
                },
                .parameter => |parameter| {
                    if (parameter >= row_variables.len) return false;
                    hashWord(hash, 2);
                    hashWord(hash, parameter);
                },
                .formal => |formal| {
                    hashWord(hash, 3);
                    if (!typeHash(source, formal, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
                },
            }
            if (!typeHash(source, node.a, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
            if (node.tag == .function and !typeHash(source, node.b, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
        },
        .nominal => {
            if (T.compilerNominalArity(.{ .unit = node.a, .decl = node.b })) |arity| {
                const arguments = source.nominalArguments(node);
                if (arguments.len != arity) return false;
                hashWord(hash, node.b);
                for (arguments) |argument| if (!typeHash(source, argument, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
                return true;
            }
            const identity_: T.NominalIdentity = .{ .unit = node.a, .decl = node.b };
            var digest: Digest = undefined;
            if (catalog.identity(identity_)) |index| {
                digest = nominalDigestAt(source, catalog, index, depth + 1, budget) orelse return false;
            } else if (catalog.familyIdentity(identity_)) |index| {
                digest = familyDigestAt(source, catalog, index, depth + 1, budget) orelse return false;
            } else {
                const operation_ = catalog.operation(identity_, budget) orelse return false;
                digest = operationDigestAt(source, catalog, operation_, depth + 1, budget) orelse return false;
            }
            hash.update(&digest);
            const arguments = source.nominalArguments(node);
            hashWord(hash, @intCast(arguments.len));
            for (arguments) |argument| if (!typeHash(source, argument, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
        },
        .projection => {
            if (!contractHash(catalog, .{ .unit = node.a, .decl = node.b }, hash)) return false;
            const member = catalog.pool.get(source.projectionMember(node));
            hashWord(hash, @intCast(member.len));
            hash.update(member);
            const arguments = source.nominalArguments(node);
            hashWord(hash, @intCast(arguments.len));
            for (arguments) |argument| if (!typeHash(source, argument, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
        },
        .product => {
            hashWord(hash, node.b);
            for (source.list(.{ .start = node.a, .len = node.b })) |child| if (!typeHash(source, child, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
        },
        .record => {
            hashWord(hash, node.b);
            // Catalog symbols drift after insertion. Hash fields in spelling
            // order, with bounded scans instead of scratch allocations.
            var previous: ?[]const u8 = null;
            for (0..node.b) |_| {
                var selected: ?T.Field = null;
                for (0..node.b) |index| {
                    if (budget.* == 0) return false;
                    budget.* -= 1;
                    const field = source.recordField(node, index);
                    const name = catalog.pool.get(field.name);
                    if (previous) |prior| if (std.mem.order(u8, name, prior) != .gt) continue;
                    if (selected) |best| if (std.mem.order(u8, name, catalog.pool.get(best.name)) != .lt) continue;
                    selected = field;
                }
                const field = selected orelse return false;
                const name = catalog.pool.get(field.name);
                hashWord(hash, @intCast(name.len));
                hash.update(name);
                if (!typeHash(source, field.ty, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
                previous = name;
            }
        },
        .type_constructor => {
            if (node.c != 0) return false;
            const index = catalog.identity(.{ .unit = node.a, .decl = node.b }) orelse return false;
            const digest = nominalDigestAt(source, catalog, index, depth + 1, budget) orelse return false;
            hash.update(&digest);
        },
        .usage => {
            if (node.b >= @typeInfo(T.UsageKind).@"enum".field_names.len) return false;
            if (node.c != 0) {
                if (!allow_open_rows or catalog.private == null) return false;
                if (!typeHash(source, node.c, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
            }
            hashWord(hash, node.b);
            if (!typeHash(source, node.a, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
        },
        .scoped => {
            if (!allow_open_rows) return false;
            const private = catalog.private orelse return false;
            if (node.b == 0) {
                if (!typeHash(source, node.c, hash, budget, depth + 1, true, variables, row_variables, catalog)) return false;
            } else hashWord(hash, private.physical(.{ .unit = node.b, .decl = node.c }, false) orelse return false);
            if (!typeHash(source, node.a, hash, budget, depth + 1, true, variables, row_variables, catalog)) return false;
        },
        .instance_selection => {
            if (!allow_open_rows) return false;
            const private = catalog.private orelse return false;
            hashWord(hash, private.physical(.{ .unit = node.a, .decl = node.b }, true) orelse return false);
            const arguments = source.nominalArguments(node);
            if (arguments.len != 2 and arguments.len != 3) return false;
            for (arguments) |argument| if (!typeHash(source, argument, hash, budget, depth + 1, true, variables, row_variables, catalog)) return false;
        },
        .instance_version => {
            if (!allow_open_rows) return false;
            const private = catalog.private orelse return false;
            const version = private.version(source.head(ty, 0)) orelse return false;
            hashWord(hash, @backingInt(version.kind));
            hashWord(hash, node.c);
        },
        .rigid => {
            if (!allow_open_rows or node.c > 2) return false;
            const private = catalog.private orelse return false;
            if (!private.rigid(node.a)) return false;
            hashWord(hash, node.b);
            hashWord(hash, node.c);
        },
        .bound => {
            if (node.c != 0 or node.b > 2) return false;
            var owned = false;
            var scope = catalog.bound_scope;
            while (scope) |current| : (scope = current.parent) {
                if (std.mem.findScalar(T.Id, current.ids, source.head(ty, 0)) != null) {
                    owned = true;
                    break;
                }
            }
            if (!owned and allow_open_rows) if (catalog.private) |private| {
                owned = private.bound(source.head(ty, 0));
            };
            if (!owned) return false;
            hashWord(hash, node.a);
            hashWord(hash, node.b);
        },
        .forall, .existential => {
            if (node.c == 0 or node.c > 128) return false;
            const binders = source.list(.{ .start = node.b, .len = node.c });
            for (binders, 0..) |binder, ordinal| {
                const leaf = source.node(binder);
                if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return false;
                hashWord(hash, leaf.b);
            }
            const scope: BoundScope = .{ .ids = binders, .parent = catalog.bound_scope };
            var quantified_catalog = catalog;
            quantified_catalog.bound_scope = &scope;
            if (!typeHash(source, node.a, hash, budget, depth + 1, allow_open_rows, variables, row_variables, quantified_catalog)) return false;
            const goals = source.quantifierGoals(source.head(ty, 0));
            hashWord(hash, @intCast(goals.len));
            for (goals) |goal| {
                if (!supportedPredicate(goal) and !contractPredicate(goal, catalog) and !operationPredicate(goal, catalog)) return false;
                hashWord(hash, @backingInt(goal.kind));
                hashWord(hash, @backingInt(goal.operator));
                hashWord(hash, @intFromBool(goal.explicit));
                const name = catalog.pool.get(goal.name);
                hashWord(hash, @intCast(name.len));
                hash.update(name);
                hashWord(hash, @intFromBool(goal.qualification_span != null));
                hashWord(hash, @intFromBool(goal.qualification_unit != 0));
                if (goal.qualification_span != null or goal.qualification_unit != 0) {
                    var qualification: InterfaceProof = .{ .source = source, .catalog = catalog, .budget = budget.* };
                    const origin = qualification.qualificationOrigin(null, goal) orelse return false;
                    budget.* = qualification.budget;
                    hash.update(&origin);
                    hash.update(&(catalog.unitOrigin(goal.qualification_unit) orelse return false));
                }
                if (goal.kind == .effect_operation) {
                    const operation_ = catalog.operation(goal.identity, budget) orelse return false;
                    hash.update(&(operationDigestAt(source, catalog, operation_, depth + 1, budget) orelse return false));
                }
                if (goal.kind == .contract and !contractHash(catalog, goal.identity, hash)) return false;
                for ([_]T.Id{ goal.ty, goal.other, goal.result, goal.signature }) |root| if (!typeHash(source, root, hash, budget, depth + 1, allow_open_rows, variables, row_variables, quantified_catalog)) return false;
            }
        },
        .state_provider => for ([_]T.Id{ node.a, node.b, node.c }) |child| {
            if (!typeHash(source, child, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
        },
        .array, .list, .cursor, .resolver => if (!typeHash(source, node.a, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false,
    }
    return true;
}
pub fn typeDigest(source: F.Source, ty: T.Id, catalog: Catalog) ?Digest {
    var hash: std.crypto.hash.Blake3 = .init(.{});
    var budget: usize = 4096;
    if (!typeHash(source, ty, &hash, &budget, 0, false, &.{}, &.{}, catalog)) return null;
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
/// Closed covariance rows are not necessarily public quantifiers. Their raw
/// type paths remain available because closing returns a copy, not a solver
/// write. Imported interfaces use the producer's independently owned receipt.
pub fn closedRowsDigest(source: F.Source, raw: T.Id, principal: T.Scheme, pool: *const symbols.Pool) ?Digest {
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, principal.closed_rows.len);
    var budget: usize = 4096;
    var certificates: [128]Digest = undefined;
    if (principal.closed_rows.len > certificates.len) return null;
    for (source.list(principal.closed_rows), 0..) |variable, index| {
        var certificate: std.crypto.hash.Blake3 = .init(.{});
        if (std.mem.findScalar(u32, source.list(principal.row_variables), variable)) |position_| {
            hashWord(&certificate, 0);
            hashWord(&certificate, @intCast(position_));
            certificate.final(&certificates[index]);
            continue;
        }
        hashWord(&certificate, 1);
        var paths: [128]Digest = undefined;
        var count: usize = 0;
        if (!closedPaths(source, raw, variable, pool, @splat(0), &paths, &count, &budget, 0) or count == 0) return null;
        std.mem.sortUnstable(Digest, paths[0..count], {}, struct {
            fn less(_: void, left: Digest, right: Digest) bool {
                return std.mem.order(u8, &left, &right) == .lt;
            }
        }.less);
        hashWord(&certificate, @intCast(count));
        for (paths[0..count]) |path| certificate.update(&path);
        certificate.final(&certificates[index]);
    }
    std.mem.sortUnstable(Digest, certificates[0..principal.closed_rows.len], {}, struct {
        fn less(_: void, left: Digest, right: Digest) bool {
            return std.mem.order(u8, &left, &right) == .lt;
        }
    }.less);
    for (certificates[0..principal.closed_rows.len]) |certificate| hash.update(&certificate);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
fn closedPath(parent: Digest, tag: T.Tag, slot: u32, name: []const u8) Digest {
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hash.update(&parent);
    hashWord(&hash, @backingInt(tag));
    hashWord(&hash, slot);
    hashWord(&hash, @intCast(name.len));
    hash.update(name);
    var path: Digest = undefined;
    hash.final(&path);
    return path;
}
fn closedPaths(source: F.Source, ty: T.Id, target: u32, pool: *const symbols.Pool, path: Digest, paths: *[128]Digest, count: *usize, budget: *usize, depth: usize) bool {
    if (depth >= 128 or budget.* == 0) return false;
    budget.* -= 1;
    const node = source.node(source.head(ty, 0));
    switch (node.tag) {
        .function, .demand, .provider => {
            const tail = source.row(node.c).tail;
            if (tail == .variable and tail.variable == target) {
                if (count.* == paths.len) return false;
                paths[count.*] = closedPath(path, node.tag, 2, "");
                count.* += 1;
            }
            if (!closedPaths(source, node.a, target, pool, closedPath(path, node.tag, 0, ""), paths, count, budget, depth + 1)) return false;
            if (node.tag == .function) return closedPaths(source, node.b, target, pool, closedPath(path, node.tag, 1, ""), paths, count, budget, depth + 1);
        },
        .product => for (source.list(.{ .start = node.a, .len = node.b }), 0..) |child, index| {
            if (!closedPaths(source, child, target, pool, closedPath(path, node.tag, @intCast(index), ""), paths, count, budget, depth + 1)) return false;
        },
        .nominal, .projection, .instance_selection => for (source.nominalArguments(node), 0..) |child, index| {
            if (!closedPaths(source, child, target, pool, closedPath(path, node.tag, @intCast(index), ""), paths, count, budget, depth + 1)) return false;
        },
        .record => for (0..node.b) |index| {
            const field = source.recordField(node, index);
            if (field.name == 0) return false;
            if (!closedPaths(source, field.ty, target, pool, closedPath(path, node.tag, 0, pool.get(field.name)), paths, count, budget, depth + 1)) return false;
        },
        .usage, .scoped => {
            if (!closedPaths(source, node.a, target, pool, closedPath(path, node.tag, 0, ""), paths, count, budget, depth + 1)) return false;
            if ((node.tag == .usage and node.c != 0) or (node.tag == .scoped and node.b == 0)) return closedPaths(source, node.c, target, pool, closedPath(path, node.tag, 1, ""), paths, count, budget, depth + 1);
        },
        .forall, .existential => {
            if (!closedPaths(source, node.a, target, pool, closedPath(path, node.tag, 0, ""), paths, count, budget, depth + 1)) return false;
            for (source.quantifierGoals(source.head(ty, 0)), 0..) |goal, index| {
                for ([_]T.Id{ goal.ty, goal.other, goal.result, goal.signature }, 0..) |root, part| {
                    if (!closedPaths(source, root, target, pool, closedPath(path, node.tag, @intCast(1 + index * 4 + part), ""), paths, count, budget, depth + 1)) return false;
                }
            }
        },
        .state_provider => for ([_]T.Id{ node.a, node.b, node.c }, 0..) |child, index| {
            if (!closedPaths(source, child, target, pool, closedPath(path, node.tag, @intCast(index), ""), paths, count, budget, depth + 1)) return false;
        },
        .array, .list, .cursor, .resolver => return closedPaths(source, node.a, target, pool, closedPath(path, node.tag, 0, ""), paths, count, budget, depth + 1),
        .absent, .unit, .boolean, .u32, .f32, .never, .variable, .bound, .rigid, .instance_version, .erased_proof, .type_constructor => {},
    }
    return true;
}

pub fn interfaceDigest(source: F.Source, binding: check.Binding, obligations: []const T.Obligation, catalog: Catalog) ?Digest {
    var proof: InterfaceProof = .{ .source = source, .catalog = catalog };
    return proof.interface(binding, obligations);
}
fn operationPredicate(value: T.Obligation, catalog: Catalog) bool {
    if (value.kind != .effect_operation or value.identity.unit == 0 or value.identity.decl == 0) return false;
    if (!value.explicit and (value.qualification_span != null or value.qualification_unit != 0)) return false;
    var budget: usize = 4096;
    return catalog.operation(value.identity, &budget) != null;
}
fn supportedPredicate(value: T.Obligation) bool {
    // Every identity-free inferred obligation has the same complete owned
    // representation and is solved again by the current pending engine.
    if (value.kind == .callee_use or value.kind == .contract) return false;
    return !value.explicit and value.identity.unit == 0 and value.identity.decl == 0 and value.qualification_span == null and value.qualification_unit == 0;
}
fn declaredPredicate(value: T.Obligation) bool {
    return (value.kind == .dispatch or value.kind == .result_dispatch or value.kind == .type_rep or value.kind == .field) and value.explicit and value.identity.unit == 0 and value.identity.decl == 0 and value.qualification_span != null and value.qualification_unit != 0;
}
fn sharedPredicate(value: T.Obligation, unit: u32) bool {
    return value.kind == .callee_use and !value.explicit and value.identity.unit == unit and value.identity.decl != 0 and value.other == 0 and value.result == 0 and value.signature == 0 and value.name == 0 and value.qualification_span == null and value.qualification_unit == 0;
}
/// Read only completed principals. Shared edges retain their public-slot
/// recipe and original declaration identity; no solver identifier is a key.
const InterfaceProof = struct {
    source: F.Source,
    catalog: Catalog,
    budget: usize = 4096,
    remaining: usize = 64,
    path: [64]check.BindingId = undefined,
    depth: usize = 0,

    fn interface(self: *InterfaceProof, binding: check.Binding, obligations: []const T.Obligation) ?Digest {
        if (self.remaining == 0) return null;
        self.remaining -= 1;
        const principal = binding.scheme;
        if (principal.root == 0 or principal.generative.len != 0) return null;
        var hash: std.crypto.hash.Blake3 = .init(.{});
        const variables = self.source.list(principal.variables);
        const rows = self.source.list(principal.row_variables);
        hashWord(&hash, @intCast(variables.len));
        hashWord(&hash, principal.row_variables.len);
        const certificates = closedRowsDigest(self.source, binding.ty, principal, self.catalog.pool) orelse return null;
        hash.update(&certificates);
        if (!typeHash(self.source, principal.root, &hash, &self.budget, 0, false, variables, rows, self.catalog)) return null;
        if (self.catalog.values) |values| {
            var found = false;
            for (values.proof_contracts) |contract| {
                if (contract.binding >= values.bindings.len) return null;
                const candidate = values.bindings[contract.binding];
                if (candidate.kind != binding.kind or candidate.name != binding.name or candidate.declaration != binding.declaration or !std.meta.eql(candidate.external, binding.external)) continue;
                if (found) return null;
                found = true;
                @import("../structural.zig").hash(&hash, contract.header);
            }
            hashWord(&hash, @intFromBool(found));
        } else hashWord(&hash, 0);
        hashWord(&hash, principal.obligations.len);
        for (obligations[principal.obligations.start..][0..principal.obligations.len]) |predicate| {
            if (self.budget == 0) return null;
            self.budget -= 1;
            if (!supportedPredicate(predicate) and !declaredPredicate(predicate) and !sharedPredicate(predicate, self.catalog.unit) and !contractPredicate(predicate, self.catalog) and !operationPredicate(predicate, self.catalog)) return null;
            hashWord(&hash, @backingInt(predicate.kind));
            hashWord(&hash, @backingInt(predicate.operator));
            hashWord(&hash, @intFromBool(predicate.explicit));
            if (predicate.kind == .contract and !contractHash(self.catalog, predicate.identity, &hash)) return null;
            if (predicate.kind == .effect_operation) {
                const operation_ = self.catalog.operation(predicate.identity, &self.budget) orelse return null;
                hash.update(&(operationDigestAt(self.source, self.catalog, operation_, 0, &self.budget) orelse return null));
            }
            if (predicate.explicit) {
                const origin = self.qualificationOrigin(binding, predicate) orelse return null;
                const unit_origin = self.catalog.unitOrigin(predicate.qualification_unit) orelse return null;
                hash.update(&unit_origin);
                hash.update(&origin);
            }
            const name = self.catalog.pool.get(predicate.name);
            hashWord(&hash, @intCast(name.len));
            hash.update(name);
            for ([_]T.Id{ predicate.ty, predicate.other, predicate.result, predicate.signature }) |part| {
                if (!typeHash(self.source, part, &hash, &self.budget, 0, false, variables, rows, self.catalog)) return null;
            }
            if (predicate.kind == .callee_use) {
                const digest = self.callee(predicate.identity.decl, obligations) orelse return null;
                hash.update(&digest);
            }
        }
        var digest: Digest = undefined;
        hash.final(&digest);
        return digest;
    }
    fn qualificationOrigin(self: *InterfaceProof, binding: ?check.Binding, predicate: T.Obligation) ?Digest {
        // Synthetic member and forwarded contract requirements name their
        // contract declaration directly; authored where clauses retain spans.
        if (predicate.kind == .contract and predicate.qualification_span == null and predicate.qualification_unit == 0) return contractDigest(self.catalog, predicate.identity);
        const values = self.catalog.values orelse return null;
        if (predicate.qualification_unit != self.catalog.unit) {
            const dictionary = values.names orelse return null;
            const lookup = dictionary.qualification orelse return null;
            return lookup(dictionary.context, predicate.qualification_unit, predicate.qualification_span orelse return null);
        }
        const span = predicate.qualification_span orelse return null;
        if (binding) |owner| if (self.qualificationOwner(owner, span)) |digest| return digest;
        if (values.bindings.len > 4096) return null;
        for (values.bindings) |owner| if (self.qualificationOwner(owner, span)) |digest| return digest;
        for (self.catalog.nominals) |nominal| {
            if (nominal.identity.unit != self.catalog.unit or nominal.declaration == 0 or values.tree.node(nominal.declaration).tag != .type_alias_decl) continue;
            if (declarationQualificationDigest(values.tree, self.catalog.pool, nominal.declaration, nominal.name, nominal.private, span, &self.budget)) |digest| return digest;
        }
        return null;
    }
    fn qualificationOwner(self: *InterfaceProof, owner: check.Binding, span: ast.Span) ?Digest {
        const values = self.catalog.values orelse return null;
        return sourceQualificationDigest(values.tree, self.catalog.pool, owner, span, &self.budget);
    }
    fn callee(self: *InterfaceProof, id: check.BindingId, obligations: []const T.Obligation) ?Digest {
        const values = self.catalog.values orelse return null;
        if (id >= values.bindings.len or self.depth == self.path.len or std.mem.findScalar(check.BindingId, self.path[0..self.depth], id) != null) return null;
        const binding = values.bindings[id];
        if (binding.kind != .global and binding.kind != .external) return null;
        if (values.ready) |ready| if (!ready.lookup(ready.context, id)) return null;
        self.path[self.depth] = id;
        self.depth += 1;
        defer self.depth -= 1;
        const digest = self.read(binding, obligations, values.names) orelse return null;
        var hash: std.crypto.hash.Blake3 = .init(.{});
        hash.update(&digest);
        hashWord(&hash, @backingInt(binding.kind));
        hashWord(&hash, @intFromBool(binding.private));
        hashWord(&hash, @intFromBool(binding.named_function));
        hashWord(&hash, @backingInt(binding.capability_flow));
        if (binding.capability_parameters.present()) {
            hashWord(&hash, 0x50465002); // parameter footprint v2
            hashWord(&hash, @backingInt(binding.capability_parameters.kind));
            hashWord(&hash, binding.capability_parameters.arity());
            hashWord(&hash, binding.capability_parameters.result());
            if (binding.capability_parameters.inputInvokes()) {
                hashWord(&hash, binding.capability_parameters.mask);
                hashWord(&hash, @truncate(binding.capability_parameters.invocation_arguments));
                hashWord(&hash, @truncate(binding.capability_parameters.invocation_arguments >> 32));
                hashWord(&hash, binding.capability_parameters.invocation_count);
            }
        }
        hashWord(&hash, @intFromBool(runtimeBinding(values.tree, binding)));
        const name = self.catalog.pool.get(binding.name);
        hashWord(&hash, @intCast(name.len));
        hash.update(name);
        const summary = binding.summary;
        hashWord(&hash, summary.flat_size);
        hashWord(&hash, @intFromBool(summary.shareable));
        hashWord(&hash, @intFromBool(summary.only_result_selected));
        hashWord(&hash, @intFromBool(summary.has_explicit));
        const variables = self.source.list(binding.scheme.variables);
        const rows = self.source.list(binding.scheme.row_variables);
        for (self.source.list(summary.public_variables)) |variable| hashWord(&hash, @intCast(std.mem.findScalar(u32, variables, variable) orelse return null));
        hashWord(&hash, summary.public_variables.len);
        for (self.source.list(summary.public_rows)) |row| hashWord(&hash, @intCast(std.mem.findScalar(u32, rows, row) orelse return null));
        hashWord(&hash, summary.public_rows.len);
        for ([_]T.List{ summary.public_inputs, summary.public_outputs, summary.requirement_variables, summary.requirement_rows }) |flags| {
            hashWord(&hash, flags.len);
            for (self.source.list(flags)) |flag| hashWord(&hash, flag);
        }
        var result: Digest = undefined;
        hash.final(&result);
        return result;
    }
    fn valueRecipe(self: *InterfaceProof, binding: check.Binding) ?@import("../check/capability_contracts.zig").Recipe {
        const values = self.catalog.values orelse return null;
        for (values.capability_contracts.bindings) |entry| {
            if (entry.binding >= values.bindings.len) return null;
            const candidate = values.bindings[entry.binding];
            if (candidate.kind == binding.kind and candidate.name == binding.name and candidate.declaration == binding.declaration and std.meta.eql(candidate.external, binding.external)) return values.capability_contracts.header(entry.binding, binding.capability_parameters.arity());
        }
        return null;
    }
    fn capabilityHash(self: *InterfaceProof, binding: check.Binding, hash: *std.crypto.hash.Blake3) bool {
        const digest = capabilityDigest(self.catalog.pool, binding, self.valueRecipe(binding)) orelse return false;
        hash.update(&digest);
        return true;
    }
    fn read(self: *InterfaceProof, binding: check.Binding, obligations: []const T.Obligation, names: ?ExternalNames) ?Digest {
        var principal_binding = binding;
        var certificates: ?Digest = null;
        if (binding.kind == .external and binding.scheme.closed_rows.len != 0) {
            const dictionary = names orelse return null;
            const lookup = dictionary.closed_rows orelse return null;
            certificates = lookup(dictionary.context, binding.external orelse return null) orelse return null;
            principal_binding.scheme.closed_rows = .{};
        }
        const digest = self.interface(principal_binding, obligations) orelse return null;
        var contract_digest = digest;
        if (binding.capability_flow != .unknown or binding.capability_parameters.present()) {
            var contract_hash: std.crypto.hash.Blake3 = .init(.{});
            contract_hash.update(&digest);
            if (!self.capabilityHash(binding, &contract_hash)) return null;
            contract_hash.final(&contract_digest);
        }
        if (binding.kind != .external) return contract_digest;
        const dictionary = names orelse return null;
        const name = dictionary.lookup(dictionary.context, binding.external orelse return null) orelse return null;
        if (name.len == 0) return null;
        var hash: std.crypto.hash.Blake3 = .init(.{});
        hash.update(&contract_digest);
        if (certificates) |certificate| hash.update(&certificate);
        const origin = self.catalog.unitOrigin((binding.external orelse return null).unit) orelse return null;
        hash.update(&origin);
        hashWord(&hash, @intCast(name.len));
        hash.update(name);
        var result: Digest = undefined;
        hash.final(&result);
        return result;
    }
};
/// Local clause authority is the enclosing original global and exact where
/// position. Private local spellings are not needed by portable public schemes.
pub fn localQualificationDigest(name: []const u8, private: bool, runtime: bool, root: ast.Span, span: ast.Span) ?Digest {
    const enclosing = qualificationDigest(name, private, runtime, root, span) orelse return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hash.update(&enclosing);
    hashWord(&hash, @backingInt(ast.Tag.let_stmt));
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
pub fn sourceQualificationDigest(tree: *const ast.Tree, pool: *const symbols.Pool, owner: check.Binding, span: ast.Span, budget: *usize) ?Digest {
    if (owner.kind != .global) return null;
    return declarationQualificationDigest(tree, pool, owner.declaration, owner.name, owner.private, span, budget);
}
fn declarationQualificationDigest(tree: *const ast.Tree, pool: *const symbols.Pool, declaration_id: ast.Id, name_id: symbols.Symbol, private: bool, span: ast.Span, budget: *usize) ?Digest {
    const node = tree.node(declaration_id);
    const root = tree.span(declaration_id);
    if (span.start < root.start or span.end > root.end or span.start > span.end) return null;
    const name = pool.get(name_id);
    var runtime = false;
    if (node.tag == .value_decl) {
        const declaration = tree.valueDecl(declaration_id);
        runtime = declaration.runtime;
        if (declaration.where_node != 0 and std.meta.eql(span, tree.span(declaration.where_node))) return qualificationDigest(name, private, runtime, root, span);
    } else if (node.tag != .type_alias_decl or node.a != name_id) return null;
    if (span.start < root.start or span.end > root.end or span.start > span.end) return null;
    const nodes = tree.declarationNodes(declaration_id) orelse return null;
    if (nodes.len > budget.*) {
        budget.* = 0;
        return null;
    }
    budget.* -= nodes.len;
    var found = false;
    for (nodes.start..nodes.start + nodes.len) |index| {
        const id: ast.Id = @intCast(index);
        if (tree.node(id).tag == .where_clause and std.meta.eql(tree.span(id), span)) {
            if (found) return null;
            found = true;
        }
    }
    if (!found) return null;
    if (node.tag == .value_decl) return localQualificationDigest(name, private, runtime, root, span);
    const origin = qualificationDigest(name, private, runtime, root, span) orelse return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hash.update(&origin);
    hashWord(&hash, @backingInt(node.tag));
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
fn qualificationOrdinal(tree: *const ast.Tree, root: ast.Id, span: ast.Span) ?u32 {
    const range = tree.declarationNodes(root) orelse return null;
    var ordinal: u32 = 0;
    var found: ?u32 = null;
    for (range.start..range.start + range.len) |index| {
        const id: ast.Id = @intCast(index);
        if (tree.node(id).tag != .where_clause) continue;
        if (std.meta.eql(tree.span(id), span)) {
            if (found != null) return null;
            found = ordinal;
        }
        ordinal += 1;
    }
    return found;
}
pub fn currentQualification(tree: *const ast.Tree, pool: *const symbols.Pool, fields: []const []u8, origin: Qualification) ?ast.Span {
    if (origin.name >= fields.len) return null;
    const name = pool.lookup(fields[origin.name]) orelse return null;
    var result: ?ast.Span = null;
    for (tree.roots.items) |root| {
        const node = tree.node(root);
        if (node.tag != origin.tag or node.a != name or tree.declarationTraits(root).private != origin.private) continue;
        const range = tree.declarationNodes(root) orelse return null;
        var ordinal: u32 = 0;
        for (range.start..range.start + range.len) |index| {
            const id: ast.Id = @intCast(index);
            if (tree.node(id).tag != .where_clause) continue;
            if (ordinal == origin.ordinal) {
                if (result != null) return null;
                result = tree.span(id);
            }
            ordinal += 1;
        }
    }
    return result;
}
/// Canonical source/compiled origin route; source offsets are declaration local.
pub fn qualificationDigest(name: []const u8, private: bool, runtime: bool, root: ast.Span, span: ast.Span) ?Digest {
    if (name.len == 0 or span.start < root.start or span.end > root.end or span.start > span.end) return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, @intCast(name.len));
    hash.update(name);
    hashWord(&hash, @intFromBool(private));
    hashWord(&hash, @intFromBool(runtime));
    hashWord(&hash, span.start - root.start);
    hashWord(&hash, span.end - root.start);
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}
pub fn readDigest(source: F.Source, binding: check.Binding, obligations: []const T.Obligation, names: ?ExternalNames, catalog: Catalog) ?Digest {
    var proof: InterfaceProof = .{ .source = source, .catalog = catalog };
    return proof.read(binding, obligations, names);
}
pub fn capabilityDigest(pool: *const symbols.Pool, binding: anytype, recipe: ?@import("../check/capability_contracts.zig").Recipe) ?Digest {
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, @backingInt(binding.capability_flow));
    hashWord(&hash, @intFromBool(binding.capability_parameters.present()));
    if (binding.capability_parameters.present()) {
        hashWord(&hash, @backingInt(binding.capability_parameters.kind));
        hashWord(&hash, binding.capability_parameters.arity());
        hashWord(&hash, binding.capability_parameters.result());
        if (binding.capability_parameters.inputInvokes()) {
            hashWord(&hash, binding.capability_parameters.mask);
            hashWord(&hash, @truncate(binding.capability_parameters.invocation_arguments));
            hashWord(&hash, @truncate(binding.capability_parameters.invocation_arguments >> 32));
            hashWord(&hash, binding.capability_parameters.invocation_count);
        }
    }
    hashWord(&hash, @intFromBool(recipe != null));
    if (recipe) |value| {
        const digest = @import("../check/capability_contracts.zig").digest(value, pool) orelse return null;
        hash.update(&digest);
    }
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}

/// Every matching catalog entry is a positive or negative selection read.
/// Candidates rejected before the winner still matter after an interface edit.
/// A fixed bound keeps this proof independent of source inference work limits.
pub fn associatedDigest(source: F.Source, catalog: Catalog, tree: *const ast.Tree, entries: []const check.Associated, bindings: []const check.Binding, obligations: []const T.Obligation, names: ?ExternalNames, members: []const []const u8) ?Digest {
    var candidates: [64]Digest = undefined;
    var count: usize = 0;
    if (entries.len > 4096) return null;
    for (entries, 0..) |entry, entry_index| {
        const member = catalog.pool.get(entry.member);
        var relevant = false;
        for (members) |wanted| if (std.mem.eql(u8, member, wanted)) {
            relevant = true;
            break;
        };
        if (!relevant) continue;
        // Duplicate member keys use the catalog's insertion winner. This
        // compact proof declines them rather than discarding that order.
        for (entries[0..entry_index]) |prior| if (std.meta.eql(prior.identity, entry.identity) and prior.member == entry.member) return null;
        if (count == candidates.len or entry.binding >= bindings.len) return null;
        const binding = bindings[entry.binding];
        const interface = readDigest(source, binding, obligations, names, catalog) orelse return null;
        var hash: std.crypto.hash.Blake3 = .init(.{});
        const origin = catalog.unitOrigin(entry.identity.unit) orelse return null;
        hash.update(&origin);
        if (entry.identity.unit == 0) {
            hashWord(&hash, entry.identity.decl);
        } else {
            const index = catalog.identity(entry.identity) orelse return null;
            const identity = nominalDigest(source, catalog, index) orelse return null;
            hash.update(&identity);
        }
        hashWord(&hash, @intCast(member.len));
        hash.update(member);
        hashWord(&hash, @backingInt(entry.operator));
        hashWord(&hash, @backingInt(binding.kind));
        hashWord(&hash, @intFromBool(binding.private));
        hashWord(&hash, @intFromBool(binding.named_function));
        hashWord(&hash, @backingInt(binding.capability_flow));
        if (binding.capability_parameters.present()) {
            hashWord(&hash, 0x50465002); // parameter footprint v2
            hashWord(&hash, @backingInt(binding.capability_parameters.kind));
            hashWord(&hash, binding.capability_parameters.arity());
            hashWord(&hash, binding.capability_parameters.result());
            if (binding.capability_parameters.inputInvokes()) {
                hashWord(&hash, binding.capability_parameters.mask);
                hashWord(&hash, @truncate(binding.capability_parameters.invocation_arguments));
                hashWord(&hash, @truncate(binding.capability_parameters.invocation_arguments >> 32));
                hashWord(&hash, binding.capability_parameters.invocation_count);
            }
        }
        hashWord(&hash, @intFromBool(runtimeBinding(tree, binding)));
        const name = catalog.pool.get(binding.name);
        hashWord(&hash, @intCast(name.len));
        hash.update(name);
        hash.update(&interface);
        hash.final(&candidates[count]);
        count += 1;
    }
    std.mem.sortUnstable(Digest, candidates[0..count], {}, struct {
        fn less(_: void, left: Digest, right: Digest) bool {
            return std.mem.order(u8, &left, &right) == .lt;
        }
    }.less);
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, @intCast(count));
    for (candidates[0..count]) |candidate| hash.update(&candidate);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
fn appendMember(a: A, members: *std.ArrayList([]u8), name: []const u8) !void {
    for (members.items) |member| if (std.mem.eql(u8, member, name)) return;
    try members.ensureUnusedCapacity(a, 1);
    const owned = try a.dupe(u8, name);
    members.appendAssumeCapacity(owned);
}

fn appendSchemeMembers(a: A, members: *std.ArrayList([]u8), scheme: T.Scheme, obligations: []const T.Obligation, catalog: Catalog, budget: *usize, implementations: *bool) !bool {
    if (budget.* == 0 or scheme.generative.len != 0) return false;
    budget.* -= 1;
    for (obligations[scheme.obligations.start..][0..scheme.obligations.len]) |predicate| {
        if (supportedPredicate(predicate) or declaredPredicate(predicate) or operationPredicate(predicate, catalog)) {
            if (predicate.name != 0) try appendMember(a, members, catalog.pool.get(predicate.name));
        } else if (contractPredicate(predicate, catalog)) {
            implementations.* = true;
        } else if (sharedPredicate(predicate, catalog.unit)) {
            const values = catalog.values orelse return false;
            if (predicate.identity.decl >= values.bindings.len) return false;
            if (!try appendSchemeMembers(a, members, values.bindings[predicate.identity.decl].scheme, obligations, catalog, budget, implementations)) return false;
        } else return false;
    }
    return true;
}

const Shape = struct {
    const Visit = struct { id: ast.Id, depth: u32 };
    pending: *std.ArrayList(Visit),
    depth: u32 = 0,
    tree: *const ast.Tree,
    pool: *const symbols.Pool,
    owner: ast.List,
    start: u32,
    hash: std.crypto.hash.Blake3 = .init(.{}),
    fn word(self: *Shape, value: u32) void {
        hashWord(&self.hash, value);
    }
    fn name(self: *Shape, symbol: symbols.Symbol) void {
        const text = self.pool.get(symbol);
        self.word(@intCast(text.len));
        self.hash.update(text);
    }
    fn edge(self: *Shape, id: ast.Id) bool {
        if (id == 0) {
            self.word(0);
            return true;
        }
        if (id < self.owner.start or id - self.owner.start >= self.owner.len) return false;
        self.word(id - self.owner.start + 1);
        if (self.depth >= 128 or self.pending.items.len == self.pending.capacity) return false;
        self.pending.appendAssumeCapacity(.{ .id = id, .depth = self.depth + 1 });
        return true;
    }
    fn edges(self: *Shape, ids: []const ast.Id) bool {
        self.word(@intCast(ids.len));
        for (ids) |id| if (!self.edge(id)) return false;
        return true;
    }
    fn list(self: *Shape, range: ast.List) bool {
        return self.edges(self.tree.list(range));
    }
    fn node(self: *Shape, id: ast.Id) bool {
        const n = self.tree.node(id);
        const span = self.tree.span(id);
        if (span.start < self.start or span.start > span.end) return false;
        self.word(@backingInt(n.tag));
        self.word(span.start - self.start);
        self.word(span.end - self.start);
        return switch (n.tag) {
            .value_decl => blk: {
                const d = self.tree.valueDecl(id);
                self.name(d.name);
                self.word(@intFromBool(d.runtime));
                self.word(@intFromBool(d.exported));
                const traits = self.tree.declarationTraits(id);
                self.word(@intFromBool(traits.private));
                self.word(@intFromBool(traits.is_opaque));
                break :blk self.edges(&.{ d.annotation, d.where_node, d.body }) and self.list(d.attributes);
            },
            .lambda => self.edges(&.{ n.a, n.c, n.b }),
            .if_expr, .if_stmt, .range_stmt, .request_arm => self.edges(&.{ n.a, n.b, n.c }),
            .parameter => blk: {
                const p = self.tree.parameter(id);
                self.name(p.name);
                self.word(@intFromBool(p.demanded));
                self.word(@intFromBool(p.is_unit));
                break :blk self.edges(&.{ p.annotation, p.where_node });
            },
            .apply, .index_access, .type_apply, .type_effect, .type_code => self.edges(&.{ n.a, n.b }),
            .type_function => self.edges(&.{ n.a, n.b, n.c }),
            .group, .type_demand, .type_witness, .type_descriptor, .forever_stmt, .attribute => self.edge(n.a),
            .name, .intrinsic, .string, .selector, .type_name, .pattern_name, .pattern_value, .constructor_ref => blk: {
                self.name(n.a);
                break :blk true;
            },
            .field_access, .type_binder => blk: {
                self.name(if (n.tag == .field_access) n.b else n.a);
                break :blk self.edge(if (n.tag == .field_access) n.a else n.b);
            },
            .field, .type_field, .pattern_field, .pattern_constructor, .iterator_bind => blk: {
                self.name(n.a);
                break :blk self.edge(n.b);
            },
            .binary => blk: {
                self.name(n.a);
                break :blk self.edges(&.{ n.b, n.c });
            },
            .operator_tail => blk: {
                self.name(n.a);
                self.word(n.c);
                break :blk self.edge(n.b);
            },
            .unary => blk: {
                self.name(n.a);
                break :blk self.edge(n.b);
            },
            .infix_chain => self.edge(n.a) and self.list(.{ .start = n.b, .len = n.c }),
            .where_clause, .product, .type_product, .type_array, .type_record, .pattern_product, .pattern_record, .pattern_row => self.list(.{ .start = n.a, .len = n.b }),
            .array => blk: {
                self.word(n.c);
                break :blk self.list(.{ .start = n.a, .len = n.b });
            },
            .record => blk: {
                self.name(n.a);
                break :blk self.list(.{ .start = n.b, .len = n.c });
            },
            .block, .effect_row => self.list(.{ .start = n.a, .len = n.b }) and self.edge(n.c),
            .constraint => blk: {
                self.name(n.a);
                self.name(n.b);
                const x = self.tree.extra.items[n.c..][0..3];
                break :blk self.list(.{ .start = x[0], .len = x[1] }) and self.edge(x[2]);
            },
            .let_stmt => blk: {
                const b = self.tree.binding(id);
                break :blk self.edges(&.{ b.where_node, b.annotation, b.value, b.pattern, b.fallback });
            },
            .rebind_stmt, .yield_stmt => self.edges(&.{ n.a, n.b }),
            .use_stmt => blk: {
                self.name(n.a);
                break :blk self.edges(&.{ n.b, n.c });
            },
            .return_stmt => blk: {
                self.word(n.b);
                break :blk self.edge(n.a);
            },
            .for_stmt => blk: {
                const x = self.tree.extra.items[n.c..][0..4];
                self.word(x[2]);
                break :blk self.edges(&.{ n.a, n.b, x[0], x[1], x[3] });
            },
            .if_let_stmt => self.edges(&.{ n.a, n.b }) and self.edges(self.tree.extra.items[n.c..][0..2]),
            .case_expr, .request_case => blk: {
                const x = self.tree.extra.items[n.a..][0..2];
                break :blk self.list(.{ .start = x[0], .len = x[1] }) and self.list(.{ .start = n.b, .len = n.c });
            },
            .case_arm => self.list(.{ .start = n.a, .len = n.b }) and self.edges(self.tree.extra.items[n.c..][0..2]),
            .type_forall, .type_exists, .package_pack => self.list(.{ .start = n.a, .len = n.b }) and self.edges(self.tree.extra.items[n.c..][0..2]),
            .package_unpack => blk: {
                const x = self.tree.extra.items[n.c..][0..3];
                self.name(x[1]);
                break :blk self.edge(n.a) and self.list(.{ .start = n.b, .len = x[0] }) and self.edge(x[2]);
            },
            .type_usage => blk: {
                self.word(n.a);
                self.name(n.c);
                break :blk self.edge(n.b);
            },
            .quantified_binder => blk: {
                self.name(n.a);
                self.word(n.b);
                break :blk true;
            },
            .integer, .float, .boolean, .pattern_integer, .pattern_boolean => blk: {
                self.word(n.a);
                break :blk true;
            },
            .unit, .break_stmt => true,
            .invalid, .numeric_error, .import_decl, .export_decl, .import_binding, .data_decl, .type_alias_decl, .contract_decl, .contract_type_member, .contract_value_member, .implementation_decl, .effect_decl, .effect_type_decl, .fixity_decl, .constructors, .effect_operations, .effect_operation => false,
        };
    }
};
pub const Syntax = struct { ids: []ast.Id, digest: Digest };
pub fn syntax(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, root: ast.Id) A.Error!?Syntax {
    const owner = tree.declarationNodes(root) orelse return null;
    if (owner.len > 4096) return null;
    var pending: std.ArrayList(Shape.Visit) = .empty;
    defer pending.deinit(a);
    try pending.ensureTotalCapacity(a, owner.len);
    const seen = try a.alloc(bool, owner.len);
    defer a.free(seen);
    @memset(seen, false);
    const ids = try a.alloc(ast.Id, owner.len);
    errdefer a.free(ids);
    var shape: Shape = .{ .tree = tree, .pool = pool, .owner = owner, .start = tree.span(root).start, .pending = &pending };
    var count: usize = 0;
    // Keep source evaluation traversal for type publication. Parser-owned
    // synthetic nodes not reached by those edges still have distinct ordinals.
    for (0..owner.len + 1) |index| {
        var start = root;
        if (index != 0) start = owner.start + @as(u32, @intCast(index - 1));
        if (seen[start - owner.start]) continue;
        pending.appendAssumeCapacity(.{ .id = start, .depth = 0 });
        while (pending.pop()) |visit| {
            if (seen[visit.id - owner.start]) continue;
            seen[visit.id - owner.start] = true;
            ids[count] = visit.id;
            count += 1;
            shape.depth = visit.depth;
            const first = pending.items.len;
            if (!shape.node(visit.id)) {
                a.free(ids);
                return null;
            }
            std.mem.reverse(Shape.Visit, pending.items[first..]);
        }
    }
    std.debug.assert(count == ids.len);
    var digest: Digest = undefined;
    shape.hash.final(&digest);
    return .{ .ids = ids, .digest = digest };
}
fn position(ids: []const ast.Id, id: ast.Id) ?u32 {
    for (ids, 0..) |candidate, i| if (candidate == id) return @intCast(i);
    return null;
}

pub fn capture(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, text: []const u8, checked: *const check.Checked, names: ?ExternalNames) !Cache {
    var cache: Cache = .{};
    errdefer cache.deinit(a);
    try captureInto(a, tree, pool, text, checked, names, &cache);
    return cache;
}
/// The checker has already retained successful replays. Freeze only newly
/// elaborated bodies, and publish each immutable chunk after complete ownership.
pub fn captureInto(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, text: []const u8, checked: *const check.Checked, names: ?ExternalNames, cache: *Cache) !void {
    return captureIntoResolved(a, tree, pool, text, checked, names, null, cache);
}
pub fn captureIntoResolved(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, text: []const u8, checked: *const check.Checked, names: ?ExternalNames, annotations: ?AnnotationLookup, cache: *Cache) !void {
    if (checked.diagnostics.len != 0 or text.len == 0) return;
    try cache.compact(a);
    var bodies: std.ArrayList(Body) = .empty;
    defer {
        for (bodies.items) |*body| body.deinit(a);
        bodies.deinit(a);
    }
    for (tree.roots.items) |root| {
        if (tree.node(root).tag != .value_decl or cache.find(pool.get(tree.valueDecl(root).name)) != null) continue;
        const node_owner = tree.declarationNodes(root) orelse continue;
        if (node_owner.len < cache.minimum_nodes) continue;
        const shape = try syntax(a, tree, pool, root) orelse continue;
        defer a.free(shape.ids);
        if (shape.ids.len < cache.minimum_nodes) continue;
        if (try captureBody(a, tree, pool, text, checked, root, shape, names, annotations)) |body| {
            var owned = body;
            errdefer owned.deinit(a);
            try bodies.append(a, body);
        }
    }
    if (bodies.items.len == 0) return;
    var roots: std.ArrayList(T.Id) = .empty;
    defer roots.deinit(a);
    var rows: std.ArrayList(u32) = .empty;
    defer rows.deinit(a);
    var effect_rows: std.ArrayList(u32) = .empty;
    defer effect_rows.deinit(a);
    var labels: std.ArrayList(u32) = .empty;
    defer labels.deinit(a);
    var auxiliary_roots: AuxiliaryRoots = .{ .allocator = a, .types = &roots, .rows = &effect_rows, .labels = &labels };
    for (bodies.items) |body| {
        for (body.facts) |fact| try roots.append(a, fact.ty);
        for (body.bindings) |binding| try roots.append(a, binding.ty);
        for (body.signatures) |signature| try roots.append(a, signature.ty);
        for (body.accesses) |access| try roots.append(a, access.ty);
        for (body.predicates) |predicate| try roots.appendSlice(a, &.{ predicate.value.ty, predicate.value.other, predicate.value.result, predicate.value.signature });
        try rows.appendSlice(a, body.closed_rows);
        if (body.auxiliary) |owner| {
            try owner.transform(&auxiliary_roots);
        }
    }
    const owner = freezeChunk(a, tree, pool, checked, names, &bodies, roots.items, rows.items, effect_rows.items, labels.items) catch |err| {
        if (err == error.OutOfMemory) return err;
        return;
    } orelse return;
    try publishChunk(a, cache, owner);
}
fn freezeChunk(a: A, tree: *const ast.Tree, checked_pool: *const symbols.Pool, checked: *const check.Checked, names: ?ExternalNames, bodies: *std.ArrayList(Body), roots: []T.Id, rows: []u32, effect_rows: []u32, labels: []u32) !?*Chunk {
    const catalog: Catalog = .{ .unit = checked.unit, .pool = checked_pool, .nominals = checked.nominals, .constructors = checked.constructors, .effect_families = checked.effect_families, .effect_templates = checked.effect_templates, .contracts = checked.contracts, .patterns = .{ .store = &checked.parameter_patterns }, .values = .{ .bindings = checked.bindings, .tree = tree, .names = names } };
    var schemes: std.ArrayList(T.Scheme) = .empty;
    defer schemes.deinit(a);
    for (bodies.items) |body| for (body.local_schemes) |local| {
        var principal = local.principal;
        // Owned requirements are projected with the ordinary body roots. The
        // scheme projector owns only binders and covariance certificates.
        principal.obligations = .{};
        try schemes.append(a, principal);
    };
    var private_graph: AuxiliaryGraph = .{ .tree = tree, .checked = checked, .bodies = bodies.items };
    defer private_graph.scopes.deinit(a);
    private_graph.allocator = a;
    const private_owner: snapshot.PrivateOwner = .{ .context = &private_graph, .physical = AuxiliaryGraph.physical, .rigid = AuxiliaryGraph.rigid, .version = AuxiliaryGraph.version };
    var graph = snapshot.freezeCheckedRoots(a, tree, checked, roots, rows, schemes.items, effect_rows, labels, private_owner) catch |err| {
        if (err == error.OutOfMemory) return err;
        return null;
    };
    errdefer snapshot.deinitGraph(a, &graph);
    var nominals: std.ArrayList(IdentityRead) = .empty;
    defer {
        for (nominals.items) |nominal| a.free(nominal.name);
        nominals.deinit(a);
    }
    var field_names: std.ArrayList([]u8) = .empty;
    defer {
        for (field_names.items) |name| a.free(name);
        field_names.deinit(a);
    }
    for (graph.nodes) |node| if (node.tag == .record) {
        for (0..node.b) |index| {
            const position_ = node.a + index * 2;
            graph.extra[position_] = try ownFieldName(a, &field_names, catalog.pool.get(graph.extra[position_]));
        }
    };
    for (graph.nodes) |*node| if (node.tag == .nominal or node.tag == .projection or node.tag == .type_constructor) {
        if (node.tag == .nominal and T.compilerNominalArity(.{ .unit = node.a, .decl = node.b }) != null) continue;
        const is_contract = node.tag == .projection;
        const identity_: T.NominalIdentity = .{ .unit = node.a, .decl = node.b };
        const family_descriptor = node.tag == .nominal and catalog.familyIdentity(identity_) != null;
        const operation_token = node.tag == .nominal and !family_descriptor and catalog.identity(identity_) == null;
        var slot: u32 = undefined;
        if (family_descriptor) {
            slot = try ownFamilyRead(a, catalog, .{ .store = &checked.types }, &nominals, identity_);
        } else if (operation_token) {
            slot = try ownOperationRead(a, catalog, .{ .store = &checked.types }, &nominals, identity_);
        } else slot = try ownIdentityRead(a, catalog, .{ .store = &checked.types }, &nominals, identity_, is_contract);
        if (is_contract) {
            const member = node.c + 1 + graph.extra[node.c];
            graph.extra[member] = try ownFieldName(a, &field_names, catalog.pool.get(graph.extra[member]));
        }
        // Both nominal and contract identities use this chunk's namespace.
        node.a = slot + 1;
        node.b = 0;
    };
    var qualifications: std.ArrayList(Qualification) = .empty;
    defer qualifications.deinit(a);
    for (graph.quantifier_obligations) |*goal| {
        if (goal.qualification_span) |span| {
            if (goal.qualification_unit != checked.unit) return error.DependencyLimit;
            var selected: ?Qualification = null;
            for (tree.roots.items) |root| {
                const ordinal = qualificationOrdinal(tree, root, span) orelse continue;
                const node = tree.node(root);
                if (node.tag != .value_decl and node.tag != .type_alias_decl) return error.DependencyLimit;
                if (selected != null) return error.DependencyLimit;
                selected = .{ .name = try ownFieldName(a, &field_names, checked_pool.get(node.a)), .tag = node.tag, .ordinal = ordinal, .private = tree.declarationTraits(root).private };
            }
            const origin = selected orelse return error.DependencyLimit;
            const index = for (qualifications.items, 0..) |prior, index| {
                if (std.meta.eql(prior, origin)) break index;
            } else index: {
                try qualifications.append(a, origin);
                break :index qualifications.items.len - 1;
            };
            goal.qualification_span = .{ .start = @intCast(index + 1), .end = 0 };
            goal.qualification_unit = 0;
        }

        if (goal.name != 0) goal.name = 1 + try ownFieldName(a, &field_names, catalog.pool.get(goal.name));
        if (goal.kind == .contract) {
            const slot = try ownIdentityRead(a, catalog, .{ .store = &checked.types }, &nominals, goal.identity, true);
            goal.identity = .{ .unit = slot + 1, .decl = 0 };
        } else if (goal.kind == .effect_operation) {
            const slot = try ownOperationRead(a, catalog, .{ .store = &checked.types }, &nominals, goal.identity);
            goal.identity = .{ .unit = slot + 1, .decl = 0 };
        }
    }
    if (graph.operations.len > 4096) return error.DependencyLimit;
    for (graph.operations, 0..) |*operation_, label| {
        if (label <= T.foreign_operation) continue;

        const slot = try ownOperationRead(a, catalog, .{ .store = &checked.types }, &nominals, operation_.identity);
        operation_.identity = .{ .unit = slot + 1, .decl = 0 };
    }
    var next_type: usize = 0;
    var next_row: usize = 0;
    var next_scheme: usize = 0;
    var auxiliary_rows: usize = 0;
    var auxiliary_labels: usize = 0;
    for (bodies.items) |*body| {
        for (body.local_schemes) |*local| {
            const requirements = local.principal.obligations;
            local.principal = schemes.items[next_scheme];
            local.principal.obligations = requirements;
            next_scheme += 1;
        }
        for (body.facts) |*fact| {
            fact.ty = roots[next_type];
            next_type += 1;
        }
        for (body.bindings) |*binding| {
            binding.ty = roots[next_type];
            next_type += 1;
        }
        for (body.signatures) |*signature| {
            signature.ty = roots[next_type];
            next_type += 1;
        }
        for (body.accesses) |*access| {
            access.ty = roots[next_type];
            next_type += 1;
        }
        for (body.predicates) |*predicate| {
            predicate.value.ty = roots[next_type];
            predicate.value.other = roots[next_type + 1];
            predicate.value.result = roots[next_type + 2];
            predicate.value.signature = roots[next_type + 3];
            if (predicate.value.kind == .contract) {
                const slot = try ownIdentityRead(a, catalog, .{ .store = &checked.types }, &nominals, predicate.value.identity, true);
                predicate.value.identity = .{ .unit = slot + 1, .decl = 0 };
            }
            if (predicate.value.kind == .effect_operation) {
                const slot = try ownOperationRead(a, catalog, .{ .store = &checked.types }, &nominals, predicate.value.identity);
                predicate.value.identity = .{ .unit = slot + 1, .decl = 0 };
            }
            next_type += 4;
        }
        @memcpy(body.closed_rows, rows[next_row..][0..body.closed_rows.len]);
        next_row += body.closed_rows.len;
        for (body.constructors) |*constructor| constructor.nominal = try frozenNominal(catalog, nominals.items, constructor.nominal);
        for (body.fields) |*field| field.nominal = try frozenNominal(catalog, nominals.items, field.nominal);
        for (body.accesses) |*step| {
            step.nominal = try frozenNominal(catalog, nominals.items, step.nominal);
            step.field = try ownFieldName(a, &field_names, catalog.pool.get(step.field));
        }
        if (body.auxiliary) |owner| {
            var dependencies: std.ArrayList(u32) = .empty;
            defer dependencies.deinit(a);
            var auxiliary_constructors: std.ArrayList(auxiliary.Owner.Constructor) = .empty;
            defer auxiliary_constructors.deinit(a);
            var mapper: AuxiliaryFreeze = .{ .allocator = a, .catalog = catalog, .source = .{ .store = &checked.types }, .nominals = &nominals, .fields = &field_names, .dependencies = &dependencies, .constructors = &auxiliary_constructors, .roots = roots, .rows = effect_rows, .labels = labels, .next_type = &next_type, .next_row = &auxiliary_rows, .next_label = &auxiliary_labels, .private = private_owner };
            try owner.transform(&mapper);
            owner.dependencies = try dependencies.toOwnedSlice(a);
            owner.constructors = try auxiliary_constructors.toOwnedSlice(a);
            a.free(owner.origins);
            owner.origins = &.{};
            a.free(owner.binding_origins);
            owner.binding_origins = &.{};
        }
        const reads = try bodyReads(a, &graph, body, field_names.items, nominals.items);
        body.nominals = reads.nominals;
        body.type_work = reads.bytes;
    }
    const owned_nominals = try nominals.toOwnedSlice(a);
    errdefer {
        for (owned_nominals) |nominal| a.free(nominal.name);
        a.free(owned_nominals);
    }
    const owned_fields = try field_names.toOwnedSlice(a);
    errdefer {
        for (owned_fields) |name| a.free(name);
        a.free(owned_fields);
    }
    const owned_qualifications = try qualifications.toOwnedSlice(a);
    errdefer a.free(owned_qualifications);
    const owner = try a.create(Chunk);
    errdefer a.destroy(owner);
    const owned_bodies = try bodies.toOwnedSlice(a);
    owner.* = .{ .allocator = a, .graph = graph, .nominals = owned_nominals, .field_names = owned_fields, .qualifications = owned_qualifications, .bodies = owned_bodies, .body_bytes = 0, .type_work = 0 };
    for (owned_bodies) |*body| {
        owner.body_bytes += body.bytes();
        owner.type_work += body.type_work;
    }
    // Ownership transferred to owner; any later allocation failure releases the
    // temporary reference and the caller releases its published references.
    for (owned_bodies) |*body| body.owner = owner;
    return owner;
}
fn ownFieldName(a: A, names: *std.ArrayList([]u8), name: []const u8) !u32 {
    for (names.items, 0..) |known, index| if (std.mem.eql(u8, known, name)) return @intCast(index);
    try names.ensureUnusedCapacity(a, 1);
    const owned = try a.dupe(u8, name);
    const index: u32 = @intCast(names.items.len);
    names.appendAssumeCapacity(owned);
    return index;
}
fn ownIdentityRead(a: A, catalog: Catalog, source: F.Source, reads: *std.ArrayList(IdentityRead), identity: T.NominalIdentity, is_contract: bool) !u32 {
    const kind: IdentityKind = if (is_contract) .contract else .nominal;
    var name: []const u8 = undefined;
    var nominal_index: usize = 0;
    if (is_contract) {
        const declaration = catalog.contract(identity) orelse return error.DependencyLimit;
        name = catalog.pool.get(declaration.name);
    } else {
        nominal_index = catalog.identity(identity) orelse return error.DependencyLimit;
        name = catalog.pool.get(catalog.nominals[nominal_index].name);
    }
    for (reads.items, 0..) |read, index| {
        if (read.kind == kind and read.unit == identity.unit and std.mem.eql(u8, read.name, name)) return @intCast(index);
    }
    var digest: Digest = undefined;
    if (is_contract) {
        digest = contractDigest(catalog, identity) orelse return error.DependencyLimit;
    } else digest = nominalDigest(source, catalog, nominal_index) orelse return error.DependencyLimit;
    const origin = catalog.unitOrigin(identity.unit) orelse return error.DependencyLimit;
    try reads.ensureUnusedCapacity(a, 1);
    const owned_name = try a.dupe(u8, name);
    const slot: u32 = @intCast(reads.items.len);
    reads.appendAssumeCapacity(.{ .unit = identity.unit, .origin = origin, .name = owned_name, .digest = digest, .kind = kind });
    return slot;
}
fn ownFamilyRead(a: A, catalog: Catalog, source: F.Source, reads: *std.ArrayList(IdentityRead), identity_: T.NominalIdentity) !u32 {
    const index = catalog.familyIdentity(identity_) orelse return error.DependencyLimit;
    const declaration = catalog.effect_families[index];
    const name = catalog.pool.get(declaration.name);
    for (reads.items, 0..) |read, slot| if (read.kind == .family and read.unit == identity_.unit and std.mem.eql(u8, read.name, name)) return @intCast(slot);
    const digest = familyDigest(source, catalog, index) orelse return error.DependencyLimit;
    const origin = catalog.unitOrigin(identity_.unit) orelse return error.DependencyLimit;
    try reads.ensureUnusedCapacity(a, 1);
    const owned = try a.dupe(u8, name);
    const slot: u32 = @intCast(reads.items.len);
    reads.appendAssumeCapacity(.{ .unit = identity_.unit, .origin = origin, .name = owned, .digest = digest, .kind = .family });
    return slot;
}
fn ownOperationRead(a: A, catalog: Catalog, source: F.Source, reads: *std.ArrayList(IdentityRead), identity: T.NominalIdentity) !u32 {
    var budget: usize = 4096;
    const index = catalog.operation(identity, &budget) orelse return error.DependencyLimit;
    const operation_ = catalog.effect_templates[index];
    const digest = operationDigest(source, catalog, index) orelse return error.DependencyLimit;
    const family = catalog.effect_families[operation_.family];
    const family_name = catalog.pool.get(family.name);
    const name = try a.print("{d}:{s}{s}", .{ family_name.len, family_name, catalog.pool.get(operation_.name) });
    errdefer a.free(name);
    for (reads.items, 0..) |read, slot| {
        if (budget == 0) return error.DependencyLimit;
        budget -= 1;
        if (read.kind != .operation or read.unit != identity.unit or !std.mem.eql(u8, read.name, name)) continue;
        a.free(name);
        return @intCast(slot);
    }
    const origin = catalog.unitOrigin(identity.unit) orelse return error.DependencyLimit;
    try reads.ensureUnusedCapacity(a, 1);
    const slot: u32 = @intCast(reads.items.len);
    reads.appendAssumeCapacity(.{ .unit = identity.unit, .origin = origin, .name = name, .digest = digest, .kind = .operation });
    return slot;
}
fn frozenNominal(catalog: Catalog, reads: []const IdentityRead, identity: T.NominalIdentity) !T.NominalIdentity {
    if (identity.unit == 0) return identity;
    const index = catalog.identity(identity) orelse return error.DependencyLimit;
    const original = catalog.nominals[index];
    for (reads, 0..) |read, read_index| {
        if (read.kind == .nominal and read.unit == original.identity.unit and std.mem.eql(u8, read.name, catalog.pool.get(original.name))) return .{ .unit = @intCast(read_index + 1), .decl = 0 };
    }
    return error.DependencyLimit;
}

fn bodyReads(a: A, graph: *const F.Graph, body: *const Body, names: []const []const u8, nominals: []const IdentityRead) !struct { nominals: []u32, bytes: usize } {
    var seen: std.AutoHashMapUnmanaged(T.Id, void) = .empty;
    defer seen.deinit(a);
    var pending: std.ArrayList(T.Id) = .empty;
    defer pending.deinit(a);
    var result: std.ArrayList(u32) = .empty;
    defer result.deinit(a);
    const source: F.Source = .{ .frozen = graph };
    for (body.facts) |fact| try pending.append(a, fact.ty);
    for (body.bindings) |binding| try pending.append(a, binding.ty);
    for (body.signatures) |signature| try pending.append(a, signature.ty);
    for (body.accesses) |access| try pending.append(a, access.ty);
    for (body.local_schemes) |local| {
        try pending.append(a, local.principal.root);
        try pending.appendSlice(a, source.list(local.principal.variables));
        try pending.appendSlice(a, source.list(local.principal.generative));
    }
    for (body.predicates) |predicate| try pending.appendSlice(a, &.{ predicate.value.ty, predicate.value.other, predicate.value.result, predicate.value.signature });
    var bytes: usize = 0;
    if (body.auxiliary) |owner| {
        var mapper: AuxiliaryReads = .{ .allocator = a, .source = source, .pending = &pending, .reads = &result, .nominals = nominals };
        try owner.transform(&mapper);
        bytes += mapper.bytes;
        for (owner.dependencies) |index| if (std.mem.findScalar(u32, result.items, index) == null) {
            try result.append(a, index);
            bytes += @sizeOf(IdentityRead) + nominals[index].name.len;
        };
    }
    var budget: usize = 16384;
    for (body.local_schemes) |local| bytes += (local.principal.variables.len + local.principal.row_variables.len + local.principal.closed_rows.len + local.principal.generative.len) * 4;
    while (pending.pop()) |id| {
        if (budget == 0 or pending.items.len > 16384) return error.DependencyLimit;
        budget -= 1;
        if (seen.count() >= 4096) return error.DependencyLimit;
        const entry = try seen.getOrPut(a, id);
        if (entry.found_existing) continue;
        const node = source.node(id);
        bytes += @sizeOf(T.Node);
        switch (node.tag) {
            .nominal, .projection => {
                if (node.tag == .nominal and T.compilerNominalArity(.{ .unit = node.a, .decl = node.b }) != null) {
                    try pending.appendSlice(a, source.nominalArguments(node));
                    bytes += (source.nominalArguments(node).len + 1) * 4;
                    continue;
                }
                if (std.mem.findScalar(u32, result.items, node.a - 1) == null) {
                    try result.append(a, node.a - 1);
                    bytes += @sizeOf(IdentityRead) + nominals[node.a - 1].name.len;
                }
                bytes += (source.nominalArguments(node).len + 1) * 4;
                if (node.tag == .projection) bytes += 4 + @sizeOf([]u8) + names[source.projectionMember(node)].len;
                try pending.appendSlice(a, source.nominalArguments(node));
            },
            .type_constructor => {
                if (std.mem.findScalar(u32, result.items, node.a - 1) == null) {
                    try result.append(a, node.a - 1);
                    bytes += @sizeOf(IdentityRead) + nominals[node.a - 1].name.len;
                }
            },
            .function, .demand, .provider => {
                const row = source.row(node.c);
                bytes += @sizeOf(T.Effects.Row) + row.labels.len * 4;
                for (source.rowLabels(row.labels)) |label| {
                    if (budget == 0) return error.DependencyLimit;
                    budget -= 1;
                    if (label == T.foreign_operation) continue;
                    if (label == 0 or label >= source.operationCount()) return error.DependencyLimit;
                    const operation_ = source.operation(label);
                    if (operation_.identity.unit == 0) return error.DependencyLimit;
                    const index = operation_.identity.unit - 1;
                    if (index >= nominals.len or nominals[index].kind != .operation) return error.DependencyLimit;
                    if (std.mem.findScalar(u32, result.items, index) == null) {
                        try result.append(a, index);
                        bytes += @sizeOf(IdentityRead) + nominals[index].name.len;
                    }
                    bytes += @sizeOf(T.Operation) + operation_.arguments.len * 4;
                    if (operation_.arguments.len > 16384 -| pending.items.len) return error.DependencyLimit;
                    try pending.appendSlice(a, source.list(operation_.arguments));
                    if (operation_.instance.unit == 0 and operation_.instance.decl != 0) try pending.append(a, operation_.instance.decl);
                }
                try pending.append(a, node.a);
                if (node.tag == .function) try pending.append(a, node.b);
            },
            .product => {
                bytes += node.b * 4;
                try pending.appendSlice(a, source.list(.{ .start = node.a, .len = node.b }));
            },
            .record => for (0..node.b) |index| {
                const field = source.recordField(node, index);
                bytes += 8 + @sizeOf([]u8) + names[field.name].len;
                try pending.append(a, field.ty);
            },
            .scoped => {
                try pending.append(a, node.a);
                if (node.b == 0) try pending.append(a, node.c);
            },
            .instance_selection => try pending.appendSlice(a, source.nominalArguments(node)),
            .forall, .existential => {
                try pending.append(a, node.a);
                try pending.appendSlice(a, source.list(.{ .start = node.b, .len = node.c }));
                bytes += node.c * 4;
                for (source.quantifierGoals(id)) |goal| {
                    try pending.appendSlice(a, &.{ goal.ty, goal.other, goal.result, goal.signature });
                    if (goal.kind == .contract or goal.kind == .effect_operation) {
                        if (goal.identity.unit == 0 or goal.identity.unit > nominals.len) return error.DependencyLimit;
                        const index = goal.identity.unit - 1;
                        if (std.mem.findScalar(u32, result.items, index) == null) {
                            try result.append(a, index);
                            bytes += @sizeOf(IdentityRead) + nominals[index].name.len;
                        }
                    }
                }
            },
            .state_provider => try pending.appendSlice(a, &.{ node.a, node.b, node.c }),
            .array, .list, .cursor, .resolver, .usage => try pending.append(a, node.a),
            else => {},
        }
    }
    for (body.constructors) |constructor| {
        const index = constructor.nominal.unit - 1;
        if (std.mem.findScalar(u32, result.items, index) == null) {
            try result.append(a, index);
            bytes += @sizeOf(IdentityRead) + nominals[index].name.len;
        }
    }
    for (body.fields) |field| if (field.nominal.unit != 0) {
        const index = field.nominal.unit - 1;
        if (std.mem.findScalar(u32, result.items, index) == null) {
            try result.append(a, index);
            bytes += @sizeOf(IdentityRead) + nominals[index].name.len;
        }
    };
    for (body.predicates) |predicate| if (predicate.value.kind == .contract or predicate.value.kind == .effect_operation) {
        const index = predicate.value.identity.unit - 1;
        if (std.mem.findScalar(u32, result.items, index) == null) {
            try result.append(a, index);
            bytes += @sizeOf(IdentityRead) + nominals[index].name.len;
        }
    };
    return .{ .nominals = try result.toOwnedSlice(a), .bytes = bytes };
}

fn publishChunk(a: A, cache: *Cache, owner: *Chunk) !void {
    defer owner.release();
    for (owner.bodies) |*body| try cache.retain(a, body);
}

// Syntax does not grant authority. Every auxiliary table not represented by
// this recipe must be absent from the declaration before its facts can replay.
const CheckedField = enum { facts, catalog, transient, source_records, node_records, node_indices, proof_bodies };
const CheckedFields = blk: {
    const names = @typeInfo(check.Checked).@"struct".field_names;
    var values: [names.len]u32 = undefined;
    for (&values, 0..) |*value, index| value.* = @intCast(index);
    break :blk @Enum(u32, .exhaustive, names, &values);
};
fn checkedField(comptime name: []const u8) CheckedField {
    return switch (@field(CheckedFields, name)) {
        .types, .expr_types, .resolved, .bindings, .merges, .obligations, .body_closed_rows, .lambda_closed_rows, .dispatch_signatures, .covered_requirements, .operation_uses, .operation_refs, .constructor_resolved, .projections, .access_paths, .access_nodes, .access_types, .projection_resolved, .projection_catalog, .rebindings, .loop_carries, .loop_ranges, .demand_calls, .demand_once, .demand_types, .demand_binary_left_types, .demand_binary_left, .loop_exits => .facts,
        .proof_contracts, .capability_contracts, .parameter_patterns, .effect_families, .effect_templates, .associated, .nominals, .contracts, .contract_predicates, .contract_members, .implementations, .implementation_predicates, .implementation_members, .member_templates, .selected_proofs, .selected_members, .selected_edges, .selected_uses, .constructors, .tag_origins, .unit => .catalog,
        .editor, .initializer_rejected, .diagnostics, .body_elaborations, .imported_schemes, .counters => .transient,
        .usage_loans, .dictionary_selections, .dictionary_uses => .source_records,
        .rank_implementations, .generative_bindings, .computations, .request_loops, .request_arms, .request_controls, .reflections, .effect_scopes, .effect_runners, .provider_blocks, .resolver_blocks, .resolver_ops, .resolver_joins, .resolver_completions, .resolver_loops, .statement_arms => .node_records,
        .iterator_bodies, .effect_scope_ids, .effect_runner_ids, .provider_block_ids, .resolver_block_ids, .resolver_op_ids, .resolver_join_ids, .resolver_loop_ids => .node_indices,
        .proof_bodies => .proof_bodies,
    };
}

fn unretainedFacts() bool {
    // New checker metadata must be registered before any old body can replay.
    // Syntax or source-byte equality cannot prove an omitted auxiliary owner.
    inline for (@typeInfo(check.Checked).@"struct".field_names) |field| switch (comptime checkedField(field)) {
        .facts, .catalog, .transient => {},
        .source_records, .node_records, .node_indices => {},
        .proof_bodies => {},
    };
    return false;
}

fn captureBody(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, text: []const u8, checked: *const check.Checked, root: ast.Id, shape: Syntax, names: ?ExternalNames, annotations: ?AnnotationLookup) !?Body {
    if (unretainedFacts()) return null;
    const auxiliary_owner = auxiliary.capture(a, checked, shape.ids) catch |err| {
        if (err == error.OutOfMemory) return err;
        return null;
    };
    var auxiliary_transferred = false;
    defer if (!auxiliary_transferred) {
        if (auxiliary_owner) |owner| owner.deinit(a);
    };
    // The parser owner is dense even though publication follows AST edges.
    // Mark label heads once instead of rescanning the declaration for every
    // annotation name on every allocation-failure replay.
    const source_nodes = tree.declarationNodes(root) orelse return null;
    var effect_heads: std.bit_set.Integer(4096) = .empty;
    for (shape.ids) |id| {
        const n = tree.node(id);
        if (n.tag != .effect_row) continue;
        for (tree.list(.{ .start = n.a, .len = n.b })) |label| {
            var head = label;
            var budget: usize = 128;
            while (tree.node(head).tag == .type_apply and budget != 0) : (budget -= 1) head = tree.node(head).a;
            if (budget == 0 and tree.node(head).tag == .type_apply) return null;
            if (head < source_nodes.start or head - source_nodes.start >= source_nodes.len) return null;
            effect_heads.set(head - source_nodes.start);
        }
    }
    var recipes: RecipeMemo = .{};
    var implementation_selection = false;
    const catalog: Catalog = .{ .private = .{ .tree = tree, .checked = checked, .ids = shape.ids }, .implementation_read = &implementation_selection, .recipes = &recipes, .unit = checked.unit, .pool = pool, .nominals = checked.nominals, .constructors = checked.constructors, .effect_families = checked.effect_families, .effect_templates = checked.effect_templates, .contracts = checked.contracts, .contract_members = checked.contract_members, .contract_predicates = checked.contract_predicates, .implementations = checked.implementations, .implementation_members = checked.implementation_members, .implementation_predicates = checked.implementation_predicates, .patterns = .{ .store = &checked.parameter_patterns }, .values = .{ .bindings = checked.bindings, .tree = tree, .names = names, .annotations = annotations, .proof_contracts = checked.proof_contracts, .capability_contracts = checked.capability_contracts } };
    const global = checked.resolved[root];
    for (checked.member_templates) |template| if (template.binding == global) return null;
    const span = tree.span(root);
    for (checked.selected_uses) |use| {
        const selected = tree.span(use.source);
        if (selected.start < span.start or selected.end > span.end) continue;
        // Qualified names are instantiated again by reuseBody. Other sources
        // of selection need their own current proof reconstruction first.
        if (tree.node(use.source).tag != .name) {
            var owned = false;
            for (checked.dictionary_selections) |selection| {
                if (selection.source != use.source or selection.proof != .selected or selection.proof.selected != use.proof) continue;
                owned = true;
                break;
            }
            if (!owned) return null;
        }
        implementation_selection = true;
    }
    if (global == 0 or interfaceDigest(.{ .store = &checked.types }, checked.bindings[global], checked.obligations, catalog) == null) return null;
    var facts: std.ArrayList(Fact) = .empty;
    defer facts.deinit(a);
    var bindings: std.ArrayList(Binding) = .empty;
    defer {
        for (bindings.items) |binding| a.free(binding.name);
        bindings.deinit(a);
    }
    var old_bindings: std.ArrayList(check.BindingId) = .empty;
    defer old_bindings.deinit(a);
    var closed_rows: std.ArrayList(u32) = .empty;
    defer closed_rows.deinit(a);
    var type_reads: std.ArrayList(TypeRead) = .empty;
    defer type_reads.deinit(a);
    var predicates: std.ArrayList(Predicate) = .empty;
    defer {
        for (predicates.items) |predicate| a.free(predicate.name);
        predicates.deinit(a);
    }
    const principal = checked.bindings[global].scheme;
    for (checked.obligations[principal.obligations.start..][0..principal.obligations.len]) |predicate| {
        if (!supportedPredicate(predicate) and !declaredPredicate(predicate) and !sharedPredicate(predicate, checked.unit) and !contractPredicate(predicate, catalog) and !operationPredicate(predicate, catalog)) return null;
        // Top-level declared clauses were already recreated by beginGlobal.
        if (predicate.explicit and tree.node(predicate.source).tag == .constraint) {
            if (position(shape.ids, predicate.source) == null) return null;
            continue;
        }
        const target = instantiatedReference(tree, checked, predicate);
        if (target != 0) {
            if (predicate.kind == .callee_use and checked.bindings[target].kind != .local and !forwardsShared(checked, target, predicate.identity)) return null;
            continue;
        }
        const source_position = position(shape.ids, predicate.source) orelse return null;
        try predicates.ensureUnusedCapacity(a, 1);
        const name = try a.dupe(u8, pool.get(predicate.name));
        var value = predicate;
        value.name = 0;
        value.source = 0;
        predicates.appendAssumeCapacity(.{ .value = value, .position = source_position, .name = name });
    }
    // beginGlobal recreates written clauses from syntax, but covering a body
    // requirement can also solve clause-local parts. Replay the covered
    // requirements so checkQualification reaches the published principal.
    var type_work: usize = 0;
    const scope = checked.bindings[global].declaration;
    for (checked.covered_requirements) |covered| if (covered.scope == scope) {
        const predicate = covered.value;
        if (instantiatedReference(tree, checked, predicate) != 0) continue;
        // Non-local replay keeps no clause origin to relocate.
        if (predicate.qualification_span != null or predicate.qualification_unit != 0) return null;
        if (!supportedPredicate(predicate) and !contractPredicate(predicate, catalog) and !operationPredicate(predicate, catalog)) return null;
        const source_position = position(shape.ids, predicate.source) orelse return null;
        for ([_]T.Id{ predicate.ty, predicate.other, predicate.result, predicate.signature }) |part| {
            var proof: std.crypto.hash.Blake3 = .init(.{});
            var budget: usize = 4096;
            if (!typeHash(.{ .store = &checked.types }, part, &proof, &budget, 0, true, &.{}, &.{}, catalog)) return null;
            type_work += 4096 - budget;
        }
        try predicates.ensureUnusedCapacity(a, 1);
        const name = try a.dupe(u8, pool.get(predicate.name));
        var value = predicate;
        value.name = 0;
        value.source = 0;
        predicates.appendAssumeCapacity(.{ .value = value, .position = source_position, .name = name, .covered = true });
    };
    var members: std.ArrayList([]u8) = .empty;
    defer {
        for (members.items) |member| a.free(member);
        members.deinit(a);
    }
    var projections: std.ArrayList(Projection) = .empty;
    defer projections.deinit(a);
    var signatures: std.ArrayList(Signature) = .empty;
    defer signatures.deinit(a);
    var merges: std.ArrayList(Merge) = .empty;
    defer merges.deinit(a);
    var loop_carries: std.ArrayList(LoopCarry) = .empty;
    defer loop_carries.deinit(a);
    var loop_exits: std.ArrayList(LoopExit) = .empty;
    defer loop_exits.deinit(a);
    var exit_bindings: std.ArrayList(u32) = .empty;
    defer exit_bindings.deinit(a);
    var rebindings: std.ArrayList(Rebinding) = .empty;
    defer rebindings.deinit(a);
    var constructors: std.ArrayList(Constructor) = .empty;
    defer constructors.deinit(a);
    var accesses: std.ArrayList(Access) = .empty;
    defer accesses.deinit(a);
    var fields: std.ArrayList(FieldProjection) = .empty;
    defer fields.deinit(a);
    var field_tags: std.ArrayList(u32) = .empty;
    defer field_tags.deinit(a);
    if (auxiliary_owner) |owner| if (owner.selections.len != 0) {
        implementation_selection = true;
    };
    var needs_selection = false;
    for (predicates.items) |predicate| if (predicate.name.len != 0 and !predicate.covered) {
        // Unsolved numeric dispatch is reconstructed from the current
        // principal. Concrete selections retain their signatures below.
        if (predicate.value.kind != .dispatch and predicate.value.kind != .result_dispatch) needs_selection = true;
        try appendMember(a, &members, predicate.name);
    };
    for (shape.ids, 0..) |id, position_| {
        const path = checked.types.list(checked.access_paths[id]);
        if (path.len != 0) {
            // Dotted projections retain each receiver/result type and the
            // complete positive/negative named candidate frontier.
            if (tree.node(id).tag != .name or checked.access_nodes[id].len != 0 or path.len > 128 or path.len > 4096 - accesses.items.len) return null;
            const types = checked.types.list(checked.access_types[id]);
            if (types.len != path.len + 1) return null;
            for (types) |ty| {
                var proof: std.crypto.hash.Blake3 = .init(.{});
                var budget: usize = 4096;
                if (!typeHash(.{ .store = &checked.types }, ty, &proof, &budget, 0, true, &.{}, &.{}, catalog)) return null;
            }
            for (path, 0..) |projection, index| {
                if (projection >= checked.projection_catalog.len) return null;
                const step = checked.projection_catalog[projection];
                const variants = checked.types.list(step.variants);
                if (variants.len % 2 != 0 or variants.len / 2 > 4096 - field_tags.items.len or pool.get(step.field).len == 0) return null;
                if (variants.len == 0) {
                    needs_selection = true;
                    try appendMember(a, &members, pool.get(step.field));
                }
                const start: u32 = @intCast(field_tags.items.len);
                var offset: usize = 0;
                while (offset < variants.len) : (offset += 2) try field_tags.append(a, variants[offset]);
                try accesses.append(a, .{ .position = @intCast(position_), .ty = types[index], .nominal = step.nominal, .field = step.field, .tags = .{ .start = start, .len = @intCast(variants.len / 2) } });
            }
        }
        const field_id = checked.projection_resolved[id];
        if (field_id != 0) {
            if (tree.node(id).tag != .field_access) return null;
            const field = checked.projection_catalog[field_id];
            const variants = checked.types.list(field.variants);
            if (variants.len % 2 != 0 or variants.len / 2 > 4096 - field_tags.items.len) return null;
            if (variants.len == 0) {
                if (field.field != tree.node(id).b) return null;
                needs_selection = true;
                try appendMember(a, &members, pool.get(field.field));
            }
            const start: u32 = @intCast(field_tags.items.len);
            var offset: usize = 0;
            while (offset < variants.len) : (offset += 2) try field_tags.append(a, variants[offset]);
            try fields.append(a, .{ .position = @intCast(position_), .nominal = field.nominal, .tags = .{ .start = start, .len = @intCast(variants.len / 2) } });
        }
        const constructor_id = checked.constructor_resolved[id];
        if (constructor_id != 0) {
            const constructor = checked.constructors[constructor_id];
            const nominal = checked.nominals[constructor.nominal];
            if (nominalDigest(.{ .store = &checked.types }, catalog, constructor.nominal) == null) return null;
            try constructors.append(a, .{ .position = @intCast(position_), .nominal = nominal.identity, .tag = constructor.tag });
        }
        if (tree.node(id).tag == .string) try appendMember(a, &members, pool.get(tree.node(id).a));
        if (tree.node(id).tag == .constraint and std.mem.eql(u8, pool.get(tree.node(id).a), "associated")) {
            needs_selection = true;
            try appendMember(a, &members, pool.get(tree.node(id).b));
        }
        if (checked.dispatch_signatures[id] != 0) {
            needs_selection = true;
            try signatures.append(a, .{ .position = @intCast(position_), .ty = checked.dispatch_signatures[id] });
        }
        if (checked.demand_calls[id]) {
            // Keep the original call classification and its exact suspended
            // type. Later inference alone cannot recreate this boundary.
            if (tree.node(id).tag != .apply and tree.node(id).tag != .binary) return null;
            var proof: std.crypto.hash.Blake3 = .init(.{});
            var budget: usize = 4096;
            const suspended = checked.demand_types[id];
            if (checked.types.node(checked.types.head(suspended, 0)).tag != .demand or !typeHash(.{ .store = &checked.types }, suspended, &proof, &budget, 0, true, &.{}, &.{}, catalog)) return null;
            type_work += 4096 - budget;
            try signatures.append(a, .{ .position = @intCast(position_), .ty = suspended, .kind = .demand, .once = checked.demand_once[id] });
        }
        if (checked.demand_binary_left[id]) {
            if (tree.node(id).tag != .binary) return null;
            var proof: std.crypto.hash.Blake3 = .init(.{});
            var budget: usize = 4096;
            const suspended = checked.demand_binary_left_types[id];
            if (checked.types.node(checked.types.head(suspended, 0)).tag != .demand or !typeHash(.{ .store = &checked.types }, suspended, &proof, &budget, 0, true, &.{}, &.{}, catalog)) return null;
            type_work += 4096 - budget;
            try signatures.append(a, .{ .position = @intCast(position_), .ty = suspended, .kind = .demand_left });
        }
        const ty = checked.expr_types[id];
        var proof: std.crypto.hash.Blake3 = .init(.{});
        var budget: usize = 4096;
        if (!typeHash(.{ .store = &checked.types }, ty, &proof, &budget, 0, true, &.{}, &.{}, catalog)) return null;
        type_work += 4096 - budget;
        if (tree.node(id).tag == .effect_row) {
            const digest = effectAnnotationDigest(.{ .store = &checked.types }, catalog, tree, id) orelse return null;
            try type_reads.append(a, .{ .position = @intCast(position_), .digest = digest, .effect = true });
        }
        if (tree.node(id).tag == .type_name and !effect_heads.isSet(id - source_nodes.start)) {
            const name = pool.get(tree.node(id).a);
            const variable = name.len != 0 and (std.ascii.isLower(name[0]) or name[0] == '_') and std.mem.findScalar(u8, name, '.') == null;
            if (!variable and !std.mem.eql(u8, name, "U32") and !std.mem.eql(u8, name, "F32") and !std.mem.eql(u8, name, "Bool") and !std.mem.eql(u8, name, "Unit") and !std.mem.eql(u8, name, "Array") and !std.mem.eql(u8, name, "List")) {
                const digest = annotationDigest(.{ .store = &checked.types }, catalog, name) orelse return null;
                try type_reads.append(a, .{ .position = @intCast(position_), .digest = digest });
            }
        }
        if (checked.projections[id] != std.math.maxInt(u32)) {
            var owner: u32 = 0;
            if (tree.node(id).tag == .pattern_field) {
                for (shape.ids, 0..) |parent, parent_position| if (tree.node(parent).tag == .pattern_record and std.mem.findScalar(ast.Id, tree.children(parent), id) != null) {
                    owner = @intCast(parent_position + 1);
                    break;
                };
                if (owner == 0) return null;
            }
            try projections.append(a, .{ .position = @intCast(position_), .index = checked.projections[id], .owner = owner });
        }
        var fact: Fact = .{ .ty = ty };
        const rows = checked.types.list(checked.lambda_closed_rows[id]);
        fact.closed_rows = .{ .start = @intCast(closed_rows.items.len), .len = @intCast(rows.len) };
        try closed_rows.appendSlice(a, rows);
        const old_id = checked.resolved[id];
        if (old_id != 0 and old_id != global) {
            const old = checked.bindings[old_id];
            if (old.kind != .local and old.kind != .parameter and std.mem.findScalar(check.BindingId, old_bindings.items, old_id) == null and old.scheme.obligations.len != 0) {
                needs_selection = true;
                var member_budget: usize = 64;
                if (!try appendSchemeMembers(a, &members, old.scheme, checked.obligations, catalog, &member_budget, &implementation_selection)) return null;
            }
            fact.binding = try captureRead(a, checked, pool, catalog, shape, old_id, &bindings, &old_bindings) orelse return null;
        } else if (old_id == global and id != root) return null;
        try facts.append(a, fact);
    }
    // A residual can observe a completed callee without a direct name at
    // its source node. Own that semantic edge through the same read receipt.
    for (predicates.items) |predicate| if (predicate.value.kind == .callee_use) {
        const target = predicate.value.identity.decl;
        _ = try captureRead(a, checked, pool, catalog, shape, target, &bindings, &old_bindings) orelse return null;
        needs_selection = true;
        var member_budget: usize = 64;
        if (!try appendSchemeMembers(a, &members, checked.bindings[target].scheme, checked.obligations, catalog, &member_budget, &implementation_selection)) return null;
    };
    for (checked.merges) |merge| if (position(shape.ids, merge.node)) |at| {
        const result = try captureLocal(a, checked, pool, catalog, shape, merge.result, &bindings, &old_bindings) orelse return null;
        const yes = try captureLocal(a, checked, pool, catalog, shape, merge.then_binding, &bindings, &old_bindings) orelse return null;
        const no = try captureLocal(a, checked, pool, catalog, shape, merge.else_binding, &bindings, &old_bindings) orelse return null;
        try merges.append(a, .{ .position = at, .result = result, .yes = yes, .no = no });
    };
    for (shape.ids, 0..) |id, at| {
        switch (tree.node(id).tag) {
            .for_stmt, .range_stmt, .forever_stmt => {},
            else => continue,
        }
        const carries = checked.loop_ranges[id];
        if (carries.len > 4096 - loop_carries.items.len) return null;
        for (checked.loop_carries[carries.start..][0..carries.len]) |carry| {
            if (carry.node != id) return null;
            const incoming = try captureLocal(a, checked, pool, catalog, shape, carry.incoming, &bindings, &old_bindings) orelse return null;
            const iteration = try captureLocal(a, checked, pool, catalog, shape, carry.iteration, &bindings, &old_bindings) orelse return null;
            const backedge = try captureLocal(a, checked, pool, catalog, shape, carry.backedge, &bindings, &old_bindings) orelse return null;
            const outgoing = try captureLocal(a, checked, pool, catalog, shape, carry.outgoing, &bindings, &old_bindings) orelse return null;
            try loop_carries.append(a, .{ .position = @intCast(at), .incoming = incoming, .iteration = iteration, .backedge = backedge, .outgoing = outgoing });
        }
    }
    for (checked.loop_exits) |exit| if (position(shape.ids, exit.node)) |at| {
        const target = position(shape.ids, exit.loop) orelse return null;
        const current = checked.types.list(exit.bindings);
        if (loop_exits.items.len == 4096 or current.len > 4096 - exit_bindings.items.len) return null;
        const start: u32 = @intCast(exit_bindings.items.len);
        for (current) |binding| try exit_bindings.append(a, try captureLocal(a, checked, pool, catalog, shape, binding, &bindings, &old_bindings) orelse return null);
        try loop_exits.append(a, .{ .position = at, .loop = target, .bindings = .{ .start = start, .len = @intCast(current.len) } });
    };
    for (shape.ids, 0..) |id, at| {
        const update = checked.rebindings[id];
        if (update.path.len == 0) continue;
        if (tree.node(id).tag != .rebind_stmt or update.path.len > 128 or rebindings.items.len == 4096) return null;
        const nodes = checked.types.list(checked.access_nodes[id]);
        const types = checked.types.list(checked.access_types[id]);
        if (nodes.len != update.path.len or types.len != nodes.len + 1) return null;
        // Exact expression facts and projection receipts already own each
        // selector and endpoint; do not duplicate paths or type roots here.
        var current = tree.node(id).a;
        var remaining = nodes.len;
        while (remaining != 0) {
            remaining -= 1;
            if (nodes[remaining] != current or position(shape.ids, current) == null) return null;
            const selector = tree.node(current);
            if (selector.tag != .field_access and selector.tag != .index_access) return null;
            if (!try @import("principal_type_graph.zig").sameOpen(a, &checked.types, checked.expr_types[current], types[remaining + 1], 128, 4096)) return null;
            current = selector.a;
        }
        if (tree.node(current).tag != .name or position(shape.ids, current) == null or !try @import("principal_type_graph.zig").sameOpen(a, &checked.types, checked.expr_types[current], types[0], 128, 4096)) return null;
        const root_binding = try captureLocal(a, checked, pool, catalog, shape, update.root, &bindings, &old_bindings) orelse return null;
        const self_binding = try captureLocal(a, checked, pool, catalog, shape, update.self_binding, &bindings, &old_bindings) orelse return null;
        try rebindings.append(a, .{ .position = @intCast(at), .root = root_binding, .self_binding = self_binding });
    }
    if (auxiliary_owner) |owner| {
        var mapper: AuxiliaryBindings = .{ .allocator = a, .checked = checked, .pool = pool, .catalog = catalog, .shape = shape, .bindings = &bindings, .origins = &old_bindings };
        owner.transform(&mapper) catch |err| {
            if (err == error.OutOfMemory) return err;
            return null;
        };
    }
    if (auxiliary_owner != null) for (checked.types.nodes.items, 0..) |node, id| {
        if (node.tag != .instance_version) continue;
        const version = catalog.private.?.version(@intCast(id)) orelse continue;
        if (version.kind == .binding) _ = try captureRead(a, checked, pool, catalog, shape, version.operand, &bindings, &old_bindings) orelse return null;
    };
    var semantic_index: usize = 0;
    while (semantic_index < old_bindings.items.len) : (semantic_index += 1) {
        const binding = checked.bindings[old_bindings.items[semantic_index]];
        if (binding.kind != .local) continue;
        for (checked.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate| if (sharedPredicate(predicate, checked.unit)) {
            _ = try captureRead(a, checked, pool, catalog, shape, predicate.identity.decl, &bindings, &old_bindings) orelse return null;
        };
    }
    try orderBindings(a, bindings.items, old_bindings.items, facts.items, merges.items, loop_carries.items, exit_bindings.items, rebindings.items);
    if (auxiliary_owner) |owner| {
        var mapper: AuxiliaryBindingSlots = .{ .origins = old_bindings.items };
        try owner.transform(&mapper);
    }
    if (auxiliary_owner) |owner| {
        var operation_bindings: std.ArrayList(auxiliary.Owner.OperationBinding) = .empty;
        defer operation_bindings.deinit(a);
        for (old_bindings.items, 0..) |origin, slot| {
            const old = checked.bindings[origin];
            if (old.kind != .parameter and old.kind != .local) continue;
            if (old.operation_ref == 0) continue;
            const operation_ = auxiliary.recordIndex(checked, shape.ids, "operation_uses", old.operation_ref) catch return null;
            try operation_bindings.append(a, .{ .binding = @intCast(slot + 1), .operation = operation_ });
        }
        owner.operation_bindings = try operation_bindings.toOwnedSlice(a);
        owner.binding_origins = try a.dupe(u32, old_bindings.items);
    }
    for (old_bindings.items, bindings.items) |old_id, *binding| {
        const predecessor = checked.bindings[old_id].predecessor;
        if (predecessor != 0) binding.predecessor = @intCast((std.mem.findScalar(check.BindingId, old_bindings.items, predecessor) orelse return null) + 1);
    }
    for (predicates.items) |*predicate| if (predicate.value.kind == .callee_use) {
        const target = std.mem.findScalar(check.BindingId, old_bindings.items, predicate.value.identity.decl) orelse return null;
        predicate.value.identity = .{ .unit = 0, .decl = @intCast(target + 1) };
    };
    var local_schemes: std.ArrayList(LocalScheme) = .empty;
    defer local_schemes.deinit(a);
    var local_requirement_budget: usize = 4096;
    for (old_bindings.items, 0..) |id, index| {
        const old = checked.bindings[id];
        if (old.kind != .local or (old.scheme.variables.len == 0 and old.scheme.row_variables.len == 0 and old.scheme.closed_rows.len == 0 and old.scheme.obligations.len == 0 and old.scheme.generative.len == 0)) continue;
        if (old.scheme.obligations.len > 4096 - predicates.items.len) return null;
        if (old.scheme.obligations.len != 0) {
            needs_selection = true;
            var member_budget: usize = 64;
            if (!try appendSchemeMembers(a, &members, old.scheme, checked.obligations, catalog, &member_budget, &implementation_selection)) return null;
        }
        var local = old.scheme;
        local.obligations = .{ .start = @intCast(predicates.items.len), .len = old.scheme.obligations.len };
        for (checked.obligations[old.scheme.obligations.start..][0..old.scheme.obligations.len]) |predicate| {
            // Local requirements own flat roots or a completed callee read.
            // Written clauses retain declaration-relative origins.
            if ((!supportedPredicate(predicate) and !declaredPredicate(predicate) and !sharedPredicate(predicate, checked.unit) and !contractPredicate(predicate, catalog) and !operationPredicate(predicate, catalog)) or local_requirement_budget == 0) return null;
            const synthetic_contract = predicate.kind == .contract and predicate.qualification_span == null and predicate.qualification_unit == 0;
            if (predicate.explicit and !synthetic_contract) {
                const origin = predicate.qualification_span orelse return null;
                const root_span = tree.span(root);
                if (predicate.qualification_unit != checked.unit or origin.start < root_span.start or origin.end > root_span.end or origin.start > origin.end) return null;
            }
            local_requirement_budget -= 1;
            const source_position = position(shape.ids, predicate.source) orelse return null;
            var proof: std.crypto.hash.Blake3 = .init(.{});
            for ([_]T.Id{ predicate.ty, predicate.other, predicate.result, predicate.signature }) |part| if (!typeHash(.{ .store = &checked.types }, part, &proof, &local_requirement_budget, 0, true, &.{}, &.{}, catalog)) return null;
            var identity = predicate.identity;
            if (predicate.kind == .callee_use) {
                const target = std.mem.findScalar(check.BindingId, old_bindings.items, predicate.identity.decl) orelse return null;
                if (bindings.items[target].kind != .global and bindings.items[target].kind != .external) return null;
                // This is an owned binding slot, not a nominal identity.
                identity = .{ .unit = 0, .decl = @intCast(target + 1) };
            }
            try predicates.ensureUnusedCapacity(a, 1);
            const name = try a.dupe(u8, pool.get(predicate.name));
            var value = predicate;
            value.identity = identity;
            value.name = 0;
            value.source = 0;
            if (value.qualification_span) |*origin| {
                origin.start -= tree.span(root).start;
                origin.end -= tree.span(root).start;
                value.qualification_unit = 0;
            }
            predicates.appendAssumeCapacity(.{ .value = value, .position = source_position, .name = name, .local = true });
        }
        try local_schemes.append(a, .{ .binding = @intCast(index + 1), .principal = local });
    }
    var selection_digest: ?Digest = null;
    if (implementation_selection) {
        needs_selection = true;
        for ([_][]const T.Obligation{ checked.contract_predicates, checked.implementation_predicates }) |requirements| for (requirements) |predicate| {
            if (predicate.kind == .dispatch or predicate.kind == .result_dispatch) try appendMember(a, &members, pool.get(predicate.name));
        };
    }
    if (needs_selection) selection_digest = associatedDigest(.{ .store = &checked.types }, catalog, tree, checked.associated, checked.bindings, checked.obligations, names, members.items) orelse return null;
    if (implementation_selection) selection_digest = implementationDigest(.{ .store = &checked.types }, catalog, selection_digest.?) orelse return null;
    const name = try a.dupe(u8, pool.get(tree.valueDecl(root).name));
    errdefer a.free(name);
    const source = try a.dupe(u8, text[span.start..span.end]);
    errdefer a.free(source);
    const owned_facts = try facts.toOwnedSlice(a);
    errdefer a.free(owned_facts);
    const body_row_start: u32 = @intCast(closed_rows.items.len);
    for (checked.body_closed_rows) |row| if (row.owner == global) {
        try closed_rows.append(a, row.variable);
    };
    const body_rows: T.List = .{ .start = body_row_start, .len = @intCast(closed_rows.items.len - body_row_start) };
    const owned_rows = try closed_rows.toOwnedSlice(a);
    errdefer a.free(owned_rows);
    const owned_reads = try type_reads.toOwnedSlice(a);
    errdefer a.free(owned_reads);
    const owned_projections = try projections.toOwnedSlice(a);
    errdefer a.free(owned_projections);
    const owned_signatures = try signatures.toOwnedSlice(a);
    errdefer a.free(owned_signatures);
    const owned_members = try members.toOwnedSlice(a);
    errdefer {
        for (owned_members) |member| a.free(member);
        a.free(owned_members);
    }
    const owned_accesses = try accesses.toOwnedSlice(a);
    errdefer a.free(owned_accesses);
    const owned_fields = try fields.toOwnedSlice(a);
    errdefer a.free(owned_fields);
    const owned_field_tags = try field_tags.toOwnedSlice(a);
    errdefer a.free(owned_field_tags);
    const owned_local_schemes = try local_schemes.toOwnedSlice(a);
    errdefer a.free(owned_local_schemes);
    const owned_constructors = try constructors.toOwnedSlice(a);
    errdefer a.free(owned_constructors);
    const owned_merges = try merges.toOwnedSlice(a);
    errdefer a.free(owned_merges);
    const owned_rebindings = try rebindings.toOwnedSlice(a);
    errdefer a.free(owned_rebindings);
    const owned_predicates = try predicates.toOwnedSlice(a);
    errdefer {
        for (owned_predicates) |predicate| a.free(predicate.name);
        a.free(owned_predicates);
    }
    const loops: ?*Loops = blk: {
        if (loop_carries.items.len == 0 and loop_exits.items.len == 0 and exit_bindings.items.len == 0) break :blk null;
        const owned = try a.create(Loops);
        owned.* = .{};
        errdefer owned.deinit(a);
        owned.carries = try loop_carries.toOwnedSlice(a);
        owned.exits = try loop_exits.toOwnedSlice(a);
        owned.bindings = try exit_bindings.toOwnedSlice(a);
        break :blk owned;
    };
    errdefer if (loops) |owned| owned.deinit(a);
    const owned_bindings = try bindings.toOwnedSlice(a);
    auxiliary_transferred = true;
    return .{ .auxiliary = auxiliary_owner, .owner = undefined, .name = name, .source = source, .syntax = shape.digest, .facts = owned_facts, .bindings = owned_bindings, .closed_rows = owned_rows, .body_closed_rows = body_rows, .type_work = type_work, .type_reads = owned_reads, .predicates = owned_predicates, .signatures = owned_signatures, .projections = owned_projections, .merges = owned_merges, .loops = loops, .rebindings = owned_rebindings, .constructors = owned_constructors, .local_schemes = owned_local_schemes, .fields = owned_fields, .accesses = owned_accesses, .field_tags = owned_field_tags, .members = owned_members, .selection_digest = selection_digest, .implementation_selection = implementation_selection };
}

// First source use can visit synthetic loop successors in a different order
// from their creation. Replay allocates in receipt order, so retain creation
// order and relocate every captured binding slot before publishing the recipe.
fn orderBindings(a: A, bindings: []Binding, origins: []check.BindingId, facts: []Fact, merges: []Merge, carries: []LoopCarry, exits: []u32, rebindings: []Rebinding) A.Error!void {
    var ordered = true;
    var previous: check.BindingId = 0;
    for (origins, bindings) |origin, binding| {
        if (binding.kind != .local and binding.kind != .parameter) continue;
        if (previous > origin) ordered = false;
        previous = origin;
    }
    if (ordered) return;
    const Entry = struct {
        binding: Binding,
        origin: check.BindingId,
        slot: u32,
        fn less(_: void, left: @This(), right: @This()) bool {
            return left.origin < right.origin;
        }
    };
    const entries = try a.alloc(Entry, bindings.len);
    defer a.free(entries);
    for (entries, bindings, origins, 0..) |*entry, binding, origin, index| entry.* = .{ .binding = binding, .origin = origin, .slot = @intCast(index) };
    std.mem.sort(Entry, entries, {}, Entry.less);
    // Original IDs are scratch at this point; use their existing storage for
    // the old-slot to new-slot permutation, then restore the sorted origins.
    for (entries, 0..) |entry, index| origins[entry.slot] = @intCast(index + 1);
    for (facts) |*fact| if (fact.binding != 0) {
        fact.binding = origins[fact.binding - 1];
    };
    for (merges) |*merge| {
        merge.result = origins[merge.result - 1];
        merge.yes = origins[merge.yes - 1];
        merge.no = origins[merge.no - 1];
    }
    for (carries) |*carry| {
        carry.incoming = origins[carry.incoming - 1];
        carry.iteration = origins[carry.iteration - 1];
        carry.backedge = origins[carry.backedge - 1];
        carry.outgoing = origins[carry.outgoing - 1];
    }
    for (exits) |*binding| binding.* = origins[binding.* - 1];
    for (rebindings) |*binding| {
        binding.root = origins[binding.root - 1];
        binding.self_binding = origins[binding.self_binding - 1];
    }
    for (entries, bindings, origins) |entry, *binding, *origin| {
        binding.* = entry.binding;
        origin.* = entry.origin;
    }
}

/// Qualified references instantiate their current principal during replay;
/// copying requirements forwarded through them would duplicate predicates.
fn instantiatedReference(tree: *const ast.Tree, checked: *const check.Checked, predicate: T.Obligation) check.BindingId {
    const tag = tree.node(predicate.source).tag;
    if (tag != .name and tag != .binary) return 0;
    const target = checked.resolved[predicate.source];
    if (target == 0 or checked.bindings[target].scheme.obligations.len == 0) return 0;
    // A dotted use creates its own field requirements as well as forwarding
    // the root's principal. Only the actual path steps need copying: replay
    // instantiates the root's current requirements, including written clauses.
    if (tag == .name and directPathField(checked, predicate)) return 0;
    return target;
}
fn directPathField(checked: *const check.Checked, predicate: T.Obligation) bool {
    if (predicate.kind != .field or predicate.explicit or predicate.name == 0 or predicate.result == 0) return false;
    const path = checked.types.list(checked.access_paths[predicate.source]);
    const types = checked.types.list(checked.access_types[predicate.source]);
    if (path.len == 0 or types.len != path.len + 1) return false;
    for (path, 0..) |projection, index| {
        if (projection >= checked.projection_catalog.len) return false;
        const step = checked.projection_catalog[projection];
        if (step.field == predicate.name and checked.types.head(predicate.ty, 0) == checked.types.head(types[index], 0) and checked.types.head(predicate.result, 0) == checked.types.head(types[index + 1], 0)) return true;
    }
    return false;
}
// Forwarded source requirements may name a transitive callee rather than the
// direct lexical reference. The completed principal must actually reach it.
fn forwardsShared(checked: anytype, target: check.BindingId, identity_: T.NominalIdentity) bool {
    if (identity_.unit != checked.unit or identity_.decl == 0 or identity_.decl >= checked.bindings.len or target == 0 or target >= checked.bindings.len) return false;
    var pending: [64]check.BindingId = undefined;
    var len: usize = 1;
    var next: usize = 0;
    var budget: usize = 4096;
    pending[0] = target;
    while (next < len) : (next += 1) {
        const id = pending[next];
        if (id == identity_.decl) return true;
        if (id == 0 or id >= checked.bindings.len) return false;
        const scheme = checked.bindings[id].scheme;
        if (scheme.obligations.start > checked.obligations.len or scheme.obligations.len > checked.obligations.len - scheme.obligations.start) return false;
        for (checked.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |predicate| {
            if (budget == 0) return false;
            budget -= 1;
            if (!sharedPredicate(predicate, checked.unit)) continue;
            const callee = predicate.identity.decl;
            if (std.mem.findScalar(check.BindingId, pending[0..len], callee) != null) continue;
            if (len == pending.len) return false;
            pending[len] = callee;
            len += 1;
        }
    }
    return false;
}

// The same auxiliary schema drives read-frontier capture, graph projection,
// and final relocation. No source numeric identifier is retained as authority.
const AuxiliaryGraph = struct {
    tree: *const ast.Tree,
    allocator: A = undefined,
    checked: *const check.Checked,
    bodies: []const Body,
    scopes: std.ArrayList(struct { old: u32, current: u32 }) = .empty,
    fn physical(raw: *anyopaque, identity_: T.NominalIdentity, selection: bool) snapshot.Error!T.NominalIdentity {
        const self: *AuxiliaryGraph = @ptrCast(@alignCast(raw));
        for (self.bodies, 0..) |body, index| {
            const owner = body.auxiliary orelse continue;
            const proof: PrivateFacts = .{ .tree = self.tree, .checked = self.checked, .ids = owner.origins };
            if (proof.physical(identity_, selection)) |slot| return .{ .unit = @intCast(index + 1), .decl = slot };
        }
        return error.DependencyLimit;
    }
    fn version(raw: *anyopaque, id: T.Id) snapshot.Error!T.NominalIdentity {
        const self: *AuxiliaryGraph = @ptrCast(@alignCast(raw));
        for (self.bodies, 0..) |body, index| {
            const owner = body.auxiliary orelse continue;
            const proof: PrivateFacts = .{ .tree = self.tree, .checked = self.checked, .ids = owner.origins };
            const origin = proof.version(id) orelse continue;
            const namespace = std.math.cast(u31, index + 1) orelse return error.DependencyLimit;
            if (origin.kind == .source) return .{ .unit = namespace, .decl = origin.operand };
            const binding = std.mem.findScalar(u32, owner.binding_origins, origin.operand) orelse return error.DependencyLimit;
            return .{ .unit = @as(u32, namespace) | 0x80000000, .decl = @intCast(binding + 1) };
        }
        return error.DependencyLimit;
    }
    fn rigid(raw: *anyopaque, scope: u32) snapshot.Error!u32 {
        const self: *AuxiliaryGraph = @ptrCast(@alignCast(raw));
        for (self.scopes.items) |entry| if (entry.old == scope) return entry.current;
        for (self.bodies) |body| {
            const owner = body.auxiliary orelse continue;
            const proof: PrivateFacts = .{ .tree = self.tree, .checked = self.checked, .ids = owner.origins };
            if (!proof.rigid(scope)) continue;
            const current: u32 = @intCast(self.scopes.items.len + 1);
            try self.scopes.append(self.allocator, .{ .old = scope, .current = current });
            return current;
        }
        return error.DependencyLimit;
    }
};
const AuxiliaryBindings = struct {
    allocator: A,
    checked: *const check.Checked,
    pool: *const symbols.Pool,
    catalog: Catalog,
    shape: Syntax,
    bindings: *std.ArrayList(Binding),
    origins: *std.ArrayList(check.BindingId),
    pub fn map(self: *AuxiliaryBindings, comptime role: auxiliary.Route, value: anytype) !@TypeOf(value) {
        if (comptime role == .scope) {
            if (value != 0 and !self.catalog.private.?.rigid(value)) return error.DependencyLimit;
        }
        if (comptime role == .instance) {
            if ((value.unit != 0 or value.decl != 0) and self.catalog.private.?.physical(value, false) == null) return error.DependencyLimit;
        }
        if (comptime role == .callee_identity) {
            if (value.unit != self.checked.unit or value.decl == 0) return error.DependencyLimit;
            _ = try captureRead(self.allocator, self.checked, self.pool, self.catalog, self.shape, value.decl, self.bindings, self.origins) orelse return error.DependencyLimit;
        }
        if (comptime role == .binding) {
            if (value != 0) _ = try captureRead(self.allocator, self.checked, self.pool, self.catalog, self.shape, value, self.bindings, self.origins) orelse return error.DependencyLimit;
        }
        if (comptime role == .ty) {
            var hash: std.crypto.hash.Blake3 = .init(.{});
            var budget: usize = 4096;
            if (!typeHash(.{ .store = &self.checked.types }, value, &hash, &budget, 0, true, &.{}, &.{}, self.catalog)) return error.DependencyLimit;
        }
        return value;
    }
};
const AuxiliaryBindingSlots = struct {
    origins: []const check.BindingId,
    pub fn map(self: *AuxiliaryBindingSlots, comptime role: auxiliary.Route, value: anytype) !@TypeOf(value) {
        if (comptime role == .callee_identity) return .{ .unit = 0, .decl = @intCast((std.mem.findScalar(check.BindingId, self.origins, value.decl) orelse return error.DependencyLimit) + 1) };
        if (comptime role == .binding) {
            if (value != 0) return @intCast((std.mem.findScalar(check.BindingId, self.origins, value) orelse return error.DependencyLimit) + 1);
        }
        return value;
    }
};
const AuxiliaryRoots = struct {
    allocator: A,
    types: *std.ArrayList(T.Id),
    rows: *std.ArrayList(u32),
    labels: *std.ArrayList(u32),
    pub fn map(self: *AuxiliaryRoots, comptime role: auxiliary.Route, value: anytype) !@TypeOf(value) {
        switch (comptime role) {
            .ty => try self.types.append(self.allocator, value),
            .row => try self.rows.append(self.allocator, value),
            .label => try self.labels.append(self.allocator, value),
            else => {},
        }
        return value;
    }
};
const AuxiliaryFreeze = struct {
    allocator: A,
    catalog: Catalog,
    source: F.Source,
    nominals: *std.ArrayList(IdentityRead),
    fields: *std.ArrayList([]u8),
    dependencies: *std.ArrayList(u32),
    constructors: *std.ArrayList(auxiliary.Owner.Constructor),
    roots: []const T.Id,
    rows: []const u32,
    labels: []const u32,
    next_type: *usize,
    next_row: *usize,
    next_label: *usize,
    private: snapshot.PrivateOwner,
    fn depend(self: *AuxiliaryFreeze, slot: u32) !void {
        if (std.mem.findScalar(u32, self.dependencies.items, slot) == null) try self.dependencies.append(self.allocator, slot);
    }
    pub fn map(self: *AuxiliaryFreeze, comptime role: auxiliary.Route, value: anytype) !@TypeOf(value) {
        switch (comptime role) {
            .contract_identity => {
                const slot = try ownIdentityRead(self.allocator, self.catalog, self.source, self.nominals, value, true);
                try self.depend(slot);
                return .{ .unit = slot + 1, .decl = 0 };
            },
            .operation_identity => {
                const slot = try ownOperationRead(self.allocator, self.catalog, self.source, self.nominals, value);
                try self.depend(slot);
                return .{ .unit = slot + 1, .decl = 0 };
            },
            .scope => {
                if (value == 0) return 0;
                return self.private.rigid(self.private.context, value);
            },
            .instance => {
                if (value.unit == 0 and value.decl == 0) return value;
                return self.private.physical(self.private.context, value, false);
            },
            .ty => {
                const mapped = self.roots[self.next_type.*];
                self.next_type.* += 1;
                return mapped;
            },
            .row => {
                const mapped = self.rows[self.next_row.*];
                self.next_row.* += 1;
                return mapped;
            },
            .label => {
                const mapped = self.labels[self.next_label.*];
                self.next_label.* += 1;
                return mapped;
            },
            .name => {
                if (value == 0) return 0;
                return 1 + try ownFieldName(self.allocator, self.fields, self.catalog.pool.get(value));
            },
            .template => {
                if (value >= self.catalog.effect_templates.len) return error.DependencyLimit;
                const slot = try ownOperationRead(self.allocator, self.catalog, self.source, self.nominals, self.catalog.effect_templates[value].identity);
                try self.depend(slot);
                return slot + 1;
            },
            .constructor => {
                if (value == 0) return 0;
                if (value >= self.catalog.constructors.len) return error.DependencyLimit;
                const constructor = self.catalog.constructors[value];
                if (constructor.nominal >= self.catalog.nominals.len) return error.DependencyLimit;
                const identity = self.catalog.nominals[constructor.nominal].identity;
                const slot = try ownIdentityRead(self.allocator, self.catalog, self.source, self.nominals, identity, false);
                try self.depend(slot);
                try self.constructors.append(self.allocator, .{ .nominal = .{ .unit = slot + 1, .decl = 0 }, .tag = constructor.tag });
                return @intCast(self.constructors.items.len);
            },
            else => return value,
        }
    }
};
const AuxiliaryReads = struct {
    allocator: A,
    source: F.Source,
    pending: *std.ArrayList(T.Id),
    reads: *std.ArrayList(u32),
    nominals: []const IdentityRead,
    bytes: usize = 0,
    fn label(self: *AuxiliaryReads, id: u32) !void {
        if (id == 0 or id == T.foreign_operation) return;
        if (id >= self.source.operationCount()) return error.DependencyLimit;
        const operation_ = self.source.operation(id);
        if (operation_.identity.unit == 0 or operation_.identity.unit > self.nominals.len) return error.DependencyLimit;
        const index = operation_.identity.unit - 1;
        if (self.nominals[index].kind != .operation) return error.DependencyLimit;
        if (std.mem.findScalar(u32, self.reads.items, index) == null) {
            try self.reads.append(self.allocator, index);
            self.bytes += @sizeOf(IdentityRead) + self.nominals[index].name.len;
        }
        self.bytes += @sizeOf(T.Operation) + operation_.arguments.len * 4;
        try self.pending.appendSlice(self.allocator, self.source.list(operation_.arguments));
        if (operation_.instance.unit == 0 and operation_.instance.decl != 0) try self.pending.append(self.allocator, operation_.instance.decl);
    }
    pub fn map(self: *AuxiliaryReads, comptime role: auxiliary.Route, value: anytype) !@TypeOf(value) {
        switch (comptime role) {
            .ty => try self.pending.append(self.allocator, value),
            .label => try self.label(value),
            .row => {
                const row = self.source.row(value);
                self.bytes += @sizeOf(T.Effects.Row) + row.labels.len * 4;
                for (self.source.rowLabels(row.labels)) |operation_| try self.label(operation_);
            },
            else => {},
        }
        return value;
    }
};

fn captureRead(a: A, checked: *const check.Checked, pool: *const symbols.Pool, catalog: Catalog, shape: Syntax, id: check.BindingId, bindings: *std.ArrayList(Binding), old_bindings: *std.ArrayList(check.BindingId)) !?u32 {
    if (std.mem.findScalar(check.BindingId, old_bindings.items, id)) |index| return @intCast(index + 1);
    if (id == 0 or id >= checked.bindings.len) return null;
    if (bindings.items.len >= 4096) return null;
    const old = checked.bindings[id];
    if (old.scheme.generative.len != 0 and old.kind != .local and old.kind != .parameter) return null;
    const local = old.kind == .local or old.kind == .parameter;
    const declaration = position(shape.ids, old.declaration);
    const owner = position(shape.ids, old.owner);
    if (local and (declaration == null or owner == null)) return null;
    const values = catalog.values orelse return null;
    var digest: Digest = @splat(0);
    var ty: T.Id = 0;
    if (local) {
        // Reference facts already proved the ordinary type graph. The local
        // raw type can retain a covariance row outside the public principal.
        ty = old.ty;
    } else digest = readDigest(.{ .store = &checked.types }, old, checked.obligations, values.names, catalog) orelse return null;
    try bindings.ensureUnusedCapacity(a, 1);
    try old_bindings.ensureUnusedCapacity(a, 1);
    const name = try a.dupe(u8, pool.get(old.name));
    bindings.appendAssumeCapacity(.{ .name = name, .kind = old.kind, .private = old.private, .declaration = declaration orelse 0, .owner = owner orelse 0, .ty = ty, .scheme = old.scheme.root != 0, .named_function = old.named_function, .capability_flow = old.capability_flow, .capability_parameters = old.capability_parameters, .runtime = runtimeBinding(values.tree, old), .external = old.external, .interface = digest });
    old_bindings.appendAssumeCapacity(id);
    return @intCast(old_bindings.items.len);
}

// Branch joins can define a binding that no source reference uses. Preserve
// those complete local facts too, so lowering sees the ordinary scope graph.
fn captureLocal(a: A, checked: *const check.Checked, pool: *const symbols.Pool, catalog: Catalog, shape: Syntax, id: check.BindingId, bindings: *std.ArrayList(Binding), old_bindings: *std.ArrayList(check.BindingId)) !?u32 {
    if (std.mem.findScalar(check.BindingId, old_bindings.items, id)) |index| return @intCast(index + 1);
    if (id == 0 or id >= checked.bindings.len) return null;
    const old = checked.bindings[id];
    if (old.kind != .local and old.kind != .parameter) return null;
    const declaration = position(shape.ids, old.declaration) orelse return null;
    const owner = position(shape.ids, old.owner) orelse return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    var budget: usize = 4096;
    if (!typeHash(.{ .store = &checked.types }, old.ty, &hash, &budget, 0, true, &.{}, &.{}, catalog)) return null;
    try bindings.ensureUnusedCapacity(a, 1);
    try old_bindings.ensureUnusedCapacity(a, 1);
    const name = try a.dupe(u8, pool.get(old.name));
    bindings.appendAssumeCapacity(.{ .name = name, .kind = old.kind, .private = old.private, .declaration = declaration, .owner = owner, .ty = old.ty, .scheme = old.scheme.root != 0, .named_function = old.named_function, .capability_flow = old.capability_flow, .capability_parameters = old.capability_parameters, .runtime = false, .external = null, .interface = @splat(0) });
    old_bindings.appendAssumeCapacity(id);
    return @intCast(old_bindings.items.len);
}

test "body check cache recipe memo preserves exact depth budget and exhaustion guards" {
    const allocator = std.testing.allocator;
    const text = "type Token is data = #Token U32\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try @import("../parse/lexer.zig").lex(allocator, text);
    defer tokens.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var memo: RecipeMemo = .{};
    var catalog: Catalog = .{ .unit = 1, .pool = &pool, .nominals = checked.nominals, .constructors = checked.constructors, .patterns = .{ .store = &checked.parameter_patterns }, .recipes = &memo };
    const index = catalog.named(1, "Token").?;
    const source: F.Source = .{ .store = &checked.types };
    var complete: usize = 4096;
    const digest = nominalDigestAt(source, catalog, index, 0, &complete).?;
    const cost = 4096 - complete;
    try std.testing.expect(cost > 0);
    var exact = cost;
    try std.testing.expectEqual(digest, nominalDigestAt(source, catalog, index, 0, &exact).?);
    try std.testing.expectEqual(@as(usize, 0), exact);
    var short = cost - 1;
    try std.testing.expect(nominalDigestAt(source, catalog, index, 0, &short) == null);
    var different_depth: usize = 4096;
    try std.testing.expectEqual(digest, nominalDigestAt(source, catalog, index, 1, &different_depth).?);
    try std.testing.expectEqual(@as(usize, 2), memo.len);
    var exhausted: usize = 4096;
    try std.testing.expect(nominalDigestAt(source, catalog, index, 128, &exhausted) == null);
    catalog.recipes = null;
    var bare: usize = 4096;
    try std.testing.expectEqual(digest, nominalDigestAt(source, catalog, index, 0, &bare).?);
    try std.testing.expectEqual(complete, bare);
    var bare_short = cost - 1;
    try std.testing.expect(nominalDigestAt(source, catalog, index, 0, &bare_short) == null);
    catalog.recipes = &memo;
    for (2..64) |depth| {
        var remaining: usize = 4096;
        try std.testing.expectEqual(digest, nominalDigestAt(source, catalog, index, depth, &remaining).?);
    }
    try std.testing.expectEqual(memo.entries.len, memo.len);
    var overflow: usize = 4096;
    try std.testing.expectEqual(digest, nominalDigestAt(source, catalog, index, 64, &overflow).?);
    try std.testing.expectEqual(memo.entries.len, memo.len);
}

test "body check cache forwarded shared principals require an exact bounded transitive edge" {
    const edge = T.Obligation{ .kind = .callee_use, .ty = 0, .source = 0, .identity = .{ .unit = 1, .decl = 2 } };
    var obligations: [65]T.Obligation = @splat(edge);
    const binding = check.Binding{ .name = 0, .declaration = 0, .owner = 0, .kind = .global, .ty = 0 };
    var bindings: [66]check.Binding = @splat(binding);
    for (1..65) |index| {
        bindings[index].scheme.obligations = .{ .start = @intCast(index - 1), .len = 1 };
        obligations[index - 1].identity.decl = @intCast(index + 1);
    }
    const checked = .{ .unit = @as(u32, 1), .bindings = &bindings, .obligations = &obligations };
    try std.testing.expect(forwardsShared(checked, 1, .{ .unit = 1, .decl = 3 }));
    try std.testing.expect(!forwardsShared(checked, 1, .{ .unit = 2, .decl = 3 }));
    try std.testing.expect(!forwardsShared(checked, 1, .{ .unit = 1, .decl = 65 }));
    try std.testing.expect(!forwardsShared(checked, 1, .{ .unit = 1, .decl = 66 }));
    obligations[1].identity.decl = 1;
    try std.testing.expect(!forwardsShared(checked, 1, .{ .unit = 1, .decl = 3 }));
    obligations[1].identity.decl = 4;
    try std.testing.expect(!forwardsShared(checked, 1, .{ .unit = 1, .decl = 3 }));
    try std.testing.expect(forwardsShared(checked, 1, .{ .unit = 1, .decl = 4 }));
}
