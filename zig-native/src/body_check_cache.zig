//! Owned, relocatable checked facts for a conservative body-elaboration cutoff.
//! Unsupported syntax/types keep ordinary checking; executable lowering is fresh.
const std = @import("std");
const ast = @import("ast.zig");
const check = @import("check.zig");
const symbols = @import("symbols.zig");
const T = @import("types.zig");
const F = @import("frozen_types.zig");
const snapshot = @import("dependency_snapshot.zig");
const A = std.mem.Allocator;
pub const Digest = [32]u8;
pub const ExternalNames = struct {
    context: *const anyopaque,
    lookup: *const fn (*const anyopaque, check.ExternalTarget) ?[]const u8,
    unit_origin: ?*const fn (*const anyopaque, u32) ?Digest = null,
    closed_rows: ?*const fn (*const anyopaque, check.ExternalTarget) ?Digest = null,
    qualification: ?*const fn (*const anyopaque, u32, ast.Span) ?Digest = null,
};
pub const AnnotationLookup = struct {
    context: *const anyopaque,
    lookup: *const fn (*const anyopaque, []const u8) ?usize,
};
pub const Values = struct {
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
pub const Catalog = struct {
    recipes: ?*RecipeMemo = null,
    unit: u32,
    pool: *const symbols.Pool,
    nominals: []const check.Nominal,
    constructors: []const check.Constructor,
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
};
pub const NominalRead = struct { unit: u32, origin: Digest, name: []u8, digest: Digest };
pub const TypeRead = struct { position: u32, digest: Digest };
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
        storage = @import("opaque_storage.zig").infer(source, catalog.nominals, catalog.constructors, @intCast(index), &storage_budget);
    }
    if (nominal.is_opaque and storage.kind == .unknown) return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hashWord(&hash, @backingInt(ast.Tag.data_decl));
    const origin = catalog.unitOrigin(nominal.identity.unit) orelse return null;
    hash.update(&origin);
    hash.update(catalog.pool.get(nominal.name));
    hashWord(&hash, @intFromBool(nominal.private));
    hashWord(&hash, @intFromBool(nominal.is_opaque));
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
pub fn annotationDigest(source: F.Source, catalog: Catalog, name: []const u8) ?Digest {
    var index: ?usize = null;
    if (catalog.values) |values| if (values.annotations) |annotations| {
        index = annotations.lookup(annotations.context, name);
        if (index == null) return null;
    };
    if (index == null) index = catalog.named(catalog.unit, name);
    const resolved = index orelse return null;
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
pub const Projection = struct { position: u32, index: u32, owner: u32 = 0 };
pub const Signature = struct { position: u32, ty: T.Id };
pub const Predicate = struct { value: T.Obligation, position: u32, local: bool = false, name: []u8 };
pub const Body = struct {
    owner: *Chunk,
    name: []u8,
    source: []u8,
    syntax: Digest,
    facts: []Fact,
    bindings: []Binding,
    closed_rows: []u32,
    type_work: usize,
    nominals: []u32 = &.{},
    type_reads: []TypeRead = &.{},
    predicates: []Predicate = &.{},
    signatures: []Signature = &.{},
    projections: []Projection = &.{},
    merges: []Merge = &.{},
    constructors: []Constructor = &.{},
    local_schemes: []LocalScheme = &.{},
    fields: []FieldProjection = &.{},
    accesses: []Access = &.{},
    field_tags: []u32 = &.{},
    members: [][]u8 = &.{},
    selection_digest: ?Digest = null,
    pub fn bytes(self: *const Body) usize {
        var total = @sizeOf(Body) + self.name.len + self.source.len + self.facts.len * @sizeOf(Fact) + self.bindings.len * @sizeOf(Binding) + self.closed_rows.len * 4 + self.nominals.len * 4 + self.type_reads.len * @sizeOf(TypeRead);
        for (self.bindings) |binding| total += binding.name.len;
        total += self.predicates.len * @sizeOf(Predicate);
        for (self.predicates) |predicate| total += predicate.name.len;
        total += self.fields.len * @sizeOf(FieldProjection) + self.field_tags.len * 4 + self.local_schemes.len * @sizeOf(LocalScheme) + self.constructors.len * @sizeOf(Constructor) + self.merges.len * @sizeOf(Merge) + self.projections.len * @sizeOf(Projection) + self.signatures.len * @sizeOf(Signature) + self.members.len * @sizeOf([]u8);
        total += self.accesses.len * @sizeOf(Access);
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
pub const Chunk = struct {
    allocator: A,
    references: usize = 1,
    graph: F.Graph,
    nominals: []NominalRead,
    field_names: [][]u8,
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
            total += @sizeOf(Chunk) + owner.body_bytes + graph.nodes.len * @sizeOf(T.Node) + graph.extra.len * 4 + graph.rows.len * @sizeOf(T.Effects.Row) + graph.labels.len * 4 + graph.operations.len * @sizeOf(T.Operation);
            total += owner.nominals.len * @sizeOf(NominalRead);
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
fn typeHash(source: F.Source, ty: T.Id, hash: *std.crypto.hash.Blake3, budget: *usize, depth: usize, allow_open_rows: bool, variables: []const T.Id, row_variables: []const u32, catalog: Catalog) bool {
    if (budget.* == 0 or depth >= 128) return false;
    budget.* -= 1;
    const node = source.node(source.head(ty, 0));
    hashWord(hash, @backingInt(node.tag));
    switch (node.tag) {
        .absent, .unit, .boolean, .u32, .f32, .never => {},
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
        .function => {
            const row = source.row(node.c);
            hashWord(hash, row.labels.len);
            for (source.rowLabels(row.labels)) |label| {
                // Other operation identities need a current-catalog relocation
                // receipt; the built-in Foreign identity is globally stable.
                if (label != T.foreign_operation) return false;
                hashWord(hash, T.foreign_operation);
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
                .parameter => return false,
            }
            if (!typeHash(source, node.a, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
            if (!typeHash(source, node.b, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false;
        },
        .nominal => {
            const index = catalog.identity(.{ .unit = node.a, .decl = node.b }) orelse return false;
            const digest = nominalDigestAt(source, catalog, index, depth + 1, budget) orelse return false;
            hash.update(&digest);
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
        .array, .list => if (!typeHash(source, node.a, hash, budget, depth + 1, allow_open_rows, variables, row_variables, catalog)) return false,
        else => return false,
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
        .function => {
            const tail = source.row(node.c).tail;
            if (tail == .variable and tail.variable == target) {
                if (count.* == paths.len) return false;
                paths[count.*] = closedPath(path, node.tag, 2, "");
                count.* += 1;
            }
            if (!closedPaths(source, node.a, target, pool, closedPath(path, node.tag, 0, ""), paths, count, budget, depth + 1)) return false;
            return closedPaths(source, node.b, target, pool, closedPath(path, node.tag, 1, ""), paths, count, budget, depth + 1);
        },
        .product => for (source.list(.{ .start = node.a, .len = node.b }), 0..) |child, index| {
            if (!closedPaths(source, child, target, pool, closedPath(path, node.tag, @intCast(index), ""), paths, count, budget, depth + 1)) return false;
        },
        .nominal => for (source.nominalArguments(node), 0..) |child, index| {
            if (!closedPaths(source, child, target, pool, closedPath(path, node.tag, @intCast(index), ""), paths, count, budget, depth + 1)) return false;
        },
        .record => for (0..node.b) |index| {
            const field = source.recordField(node, index);
            if (field.name == 0) return false;
            if (!closedPaths(source, field.ty, target, pool, closedPath(path, node.tag, 0, pool.get(field.name)), paths, count, budget, depth + 1)) return false;
        },
        .array, .list => return closedPaths(source, node.a, target, pool, closedPath(path, node.tag, 0, ""), paths, count, budget, depth + 1),
        .absent, .unit, .boolean, .u32, .f32, .never, .variable => {},
        else => return false,
    }
    return true;
}

pub fn interfaceDigest(source: F.Source, binding: check.Binding, obligations: []const T.Obligation, catalog: Catalog) ?Digest {
    var proof: InterfaceProof = .{ .source = source, .catalog = catalog };
    return proof.interface(binding, obligations);
}
fn supportedPredicate(value: T.Obligation) bool {
    return (value.kind == .dispatch or value.kind == .result_dispatch or (value.kind == .field and value.other == 0)) and !value.explicit and value.identity.unit == 0 and value.identity.decl == 0 and value.qualification_span == null and value.qualification_unit == 0;
}
fn declaredPredicate(value: T.Obligation) bool {
    return (value.kind == .dispatch or value.kind == .result_dispatch or value.kind == .type_rep) and value.explicit and value.identity.unit == 0 and value.identity.decl == 0 and value.qualification_span != null and value.qualification_unit != 0;
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
        if (principal.root == 0) return null;
        var hash: std.crypto.hash.Blake3 = .init(.{});
        const variables = self.source.list(principal.variables);
        const rows = self.source.list(principal.row_variables);
        hashWord(&hash, @intCast(variables.len));
        hashWord(&hash, principal.row_variables.len);
        const certificates = closedRowsDigest(self.source, binding.ty, principal, self.catalog.pool) orelse return null;
        hash.update(&certificates);
        if (!typeHash(self.source, principal.root, &hash, &self.budget, 0, false, variables, rows, self.catalog)) return null;
        hashWord(&hash, principal.obligations.len);
        for (obligations[principal.obligations.start..][0..principal.obligations.len]) |predicate| {
            if (self.budget == 0) return null;
            self.budget -= 1;
            if (!supportedPredicate(predicate) and !declaredPredicate(predicate) and !sharedPredicate(predicate, self.catalog.unit)) return null;
            hashWord(&hash, @backingInt(predicate.kind));
            hashWord(&hash, @backingInt(predicate.operator));
            hashWord(&hash, @intFromBool(predicate.explicit));
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
    fn qualificationOrigin(self: *InterfaceProof, binding: check.Binding, predicate: T.Obligation) ?Digest {
        const values = self.catalog.values orelse return null;
        if (predicate.qualification_unit != self.catalog.unit) {
            const dictionary = values.names orelse return null;
            const lookup = dictionary.qualification orelse return null;
            return lookup(dictionary.context, predicate.qualification_unit, predicate.qualification_span orelse return null);
        }
        const span = predicate.qualification_span orelse return null;
        if (self.qualificationOwner(binding, span)) |digest| return digest;
        if (values.bindings.len > 4096) return null;
        for (values.bindings) |owner| if (self.qualificationOwner(owner, span)) |digest| return digest;
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
        hashWord(&hash, @intFromBool(binding.kind == .global and values.tree.valueDecl(binding.declaration).runtime));
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
        if (binding.capability_flow != .unknown) {
            var contract_hash: std.crypto.hash.Blake3 = .init(.{});
            contract_hash.update(&digest);
            hashWord(&contract_hash, @backingInt(binding.capability_flow));
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
    const declaration = tree.valueDecl(owner.declaration);
    const root = tree.span(owner.declaration);
    const name = pool.get(owner.name);
    if (declaration.where_node != 0 and std.meta.eql(span, tree.span(declaration.where_node))) return qualificationDigest(name, owner.private, declaration.runtime, root, span);
    if (span.start < root.start or span.end > root.end or span.start > span.end) return null;
    var walker: Walker = .{ .a = std.heap.page_allocator, .tree = tree, .pool = pool, .start = root.start, .materialize = false, .max_nodes = budget.*, .qualification = span };
    const complete = walker.visit(owner.declaration, 0) catch return null;
    budget.* -= walker.count;
    if (!complete or !walker.found_qualification) return null;
    return localQualificationDigest(name, owner.private, declaration.runtime, root, span);
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
        hashWord(&hash, @intFromBool(binding.kind == .global and tree.valueDecl(binding.declaration).runtime));
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

fn appendSchemeMembers(a: A, members: *std.ArrayList([]u8), scheme: T.Scheme, obligations: []const T.Obligation, catalog: Catalog, budget: *usize) !bool {
    if (budget.* == 0) return false;
    budget.* -= 1;
    for (obligations[scheme.obligations.start..][0..scheme.obligations.len]) |predicate| {
        if (supportedPredicate(predicate) or declaredPredicate(predicate)) {
            if (predicate.kind == .dispatch or predicate.kind == .result_dispatch or predicate.kind == .field) try appendMember(a, members, catalog.pool.get(predicate.name));
        } else if (sharedPredicate(predicate, catalog.unit)) {
            const values = catalog.values orelse return false;
            if (predicate.identity.decl >= values.bindings.len) return false;
            if (!try appendSchemeMembers(a, members, values.bindings[predicate.identity.decl].scheme, obligations, catalog, budget)) return false;
        } else return false;
    }
    return true;
}

const Walker = struct {
    a: A,
    tree: *const ast.Tree,
    pool: *const symbols.Pool,
    ids: std.ArrayList(ast.Id) = .empty,
    hash: std.crypto.hash.Blake3 = .init(.{}),
    start: u32,
    count: usize = 0,
    materialize: bool = true,
    max_nodes: usize = 4096,
    qualification: ?ast.Span = null,
    found_qualification: bool = false,
    fn word(self: *Walker, value: u32) void {
        if (self.materialize) hashWord(&self.hash, value);
    }
    fn text(self: *Walker, value: []const u8) void {
        if (self.materialize) self.hash.update(value);
    }
    fn visit(self: *Walker, id: ast.Id, depth: usize) A.Error!bool {
        if (id == 0 or self.found_qualification) return true;
        if (depth >= 128 or self.count >= self.max_nodes) return false;
        const node = self.tree.node(id);
        const span = self.tree.span(id);
        if (span.start < self.start) return false;
        self.count += 1;
        if (self.qualification) |requested| {
            if (span.start > requested.start or span.end < requested.end) return true;
            if (node.tag == .where_clause and std.meta.eql(span, requested)) {
                self.found_qualification = true;
                return true;
            }
        }
        if (self.materialize) try self.ids.append(self.a, id);
        self.word(@backingInt(node.tag));
        self.word(span.start - self.start);
        self.word(span.end - self.start);
        switch (node.tag) {
            .value_decl => {
                const decl = self.tree.valueDecl(id);
                if (decl.attributes.len != 0) return false;
                self.word(@intFromBool(decl.runtime));
                self.word(@intFromBool(decl.exported));
                const traits = self.tree.declarationTraits(id);
                self.word(@intFromBool(traits.private));
                self.word(@intFromBool(traits.is_opaque));
                if (!try self.visit(decl.annotation, depth + 1)) return false;
                if (!try self.visit(decl.where_node, depth + 1)) return false;
                return self.visit(decl.body, depth + 1);
            },
            .where_clause => {
                for (self.tree.list(.{ .start = node.a, .len = node.b })) |clause| if (!try self.visit(clause, depth + 1)) return false;
            },
            .constraint => {
                const kind = self.pool.get(node.a);
                if (!std.mem.eql(u8, kind, "associated") and !std.mem.eql(u8, kind, "type_rep")) return false;
                self.text(kind);
                self.text(self.pool.get(node.b));
                const details = self.tree.extra.items[node.c..][0..3];
                if (details[2] != 0) return false;
                for (self.tree.list(.{ .start = details[0], .len = details[1] })) |part| if (!try self.visit(part, depth + 1)) return false;
            },
            .lambda => {
                if (!try self.visit(node.a, depth + 1)) return false;
                if (!try self.visit(node.c, depth + 1)) return false;
                return self.visit(node.b, depth + 1);
            },
            .parameter => {
                const param = self.tree.parameter(id);
                if (param.demanded or param.where_node != 0) return false;
                self.text(self.pool.get(param.name));
                self.word(@intFromBool(param.is_unit));
                return self.visit(param.annotation, depth + 1);
            },
            .apply, .index_access, .type_apply, .type_function => {
                if (!try self.visit(node.a, depth + 1)) return false;
                if (!try self.visit(node.b, depth + 1)) return false;
                if (node.tag == .type_function) return self.visit(node.c, depth + 1);
            },
            .effect_row => {
                self.word(node.b);
                for (self.tree.list(.{ .start = node.a, .len = node.b })) |label| {
                    const item = self.tree.node(label);
                    const location = self.tree.span(label);
                    if (item.tag != .type_name or !std.mem.eql(u8, self.pool.get(item.a), "Foreign")) return false;
                    if (depth + 1 >= 128 or self.count >= self.max_nodes or location.start < self.start) return false;
                    self.count += 1;
                    // Foreign is sealed and globally stable. Its syntax belongs
                    // to the row, rather than a nominal annotation read.
                    self.word(@backingInt(item.tag));
                    self.word(location.start - self.start);
                    self.word(location.end - self.start);
                    self.text(self.pool.get(item.a));
                }
                return self.visit(node.c, depth + 1);
            },
            .binary => {
                self.text(self.pool.get(node.a));
                if (!try self.visit(node.b, depth + 1)) return false;
                return self.visit(node.c, depth + 1);
            },
            .unary => {
                if (!std.mem.eql(u8, self.pool.get(node.a), "-")) return false;
                self.text(self.pool.get(node.a));
                return self.visit(node.b, depth + 1);
            },
            .field_access => {
                self.text(self.pool.get(node.b));
                return self.visit(node.a, depth + 1);
            },
            .group => return self.visit(node.a, depth + 1),
            .block => {
                if (node.c != 0) return false;
                for (self.tree.children(id)) |child| if (!try self.visit(child, depth + 1)) return false;
            },
            .let_stmt => {
                const binding = self.tree.binding(id);
                if (binding.where_node != 0) {
                    const pattern = self.tree.node(binding.pattern);
                    if (pattern.tag != .pattern_name) return false;
                }
                if (!try self.visit(binding.where_node, depth + 1)) return false;
                if (!try self.visit(binding.annotation, depth + 1)) return false;
                if (!try self.visit(binding.value, depth + 1)) return false;
                if (!try self.visit(binding.pattern, depth + 1)) return false;
                return self.visit(binding.fallback, depth + 1);
            },
            .return_stmt => {
                if (node.b != 0) return false;
                return self.visit(node.a, depth + 1);
            },
            .rebind_stmt => {
                if (self.tree.node(node.a).tag != .name) return false;
                if (!try self.visit(node.a, depth + 1)) return false;
                return self.visit(node.b, depth + 1);
            },
            .case_expr => {
                const inputs = self.tree.extra.items[node.a..][0..2];
                for (self.tree.list(.{ .start = inputs[0], .len = inputs[1] })) |input| if (!try self.visit(input, depth + 1)) return false;
                for (self.tree.list(.{ .start = node.b, .len = node.c })) |arm| if (!try self.visit(arm, depth + 1)) return false;
            },
            .case_arm => {
                for (self.tree.list(.{ .start = node.a, .len = node.b })) |row| if (!try self.visit(row, depth + 1)) return false;
                const parts = self.tree.extra.items[node.c..][0..2];
                for (parts) |part| if (!try self.visit(part, depth + 1)) return false;
            },
            .pattern_row, .pattern_product, .pattern_record => for (self.tree.children(id)) |child| {
                if (!try self.visit(child, depth + 1)) return false;
            },
            .pattern_name, .pattern_value, .constructor_ref => self.text(self.pool.get(node.a)),
            .pattern_constructor => {
                self.text(self.pool.get(node.a));
                return self.visit(node.b, depth + 1);
            },
            .pattern_field => {
                self.text(self.pool.get(node.a));
                return self.visit(node.b, depth + 1);
            },
            .pattern_integer, .pattern_boolean => self.word(node.a),
            .if_expr, .if_stmt => {
                if (!try self.visit(node.a, depth + 1)) return false;
                if (!try self.visit(node.b, depth + 1)) return false;
                return self.visit(node.c, depth + 1);
            },
            .if_let_stmt => {
                if (!try self.visit(node.a, depth + 1)) return false;
                if (!try self.visit(node.b, depth + 1)) return false;
                for (self.tree.extra.items[node.c..][0..2]) |part| if (!try self.visit(part, depth + 1)) return false;
            },
            .record => {
                self.text(self.pool.get(node.a));
                for (self.tree.children(id)) |child| if (!try self.visit(child, depth + 1)) return false;
            },
            .field, .type_field => {
                if (node.b == 0) return false;
                self.text(self.pool.get(node.a));
                return self.visit(node.b, depth + 1);
            },
            .product, .array, .type_product, .type_array, .type_record => for (self.tree.children(id)) |child| {
                if (!try self.visit(child, depth + 1)) return false;
            },
            .name => self.text(self.pool.get(node.a)),
            .type_name => {
                const name = self.pool.get(node.a);
                self.text(name);
            },
            .intrinsic => {
                const name = self.pool.get(node.a);
                if (!std.mem.startsWith(u8, name, "@u32.") and !std.mem.startsWith(u8, name, "@f32.") and !std.mem.eql(u8, name, "@type.call") and !std.mem.eql(u8, name, "@type.result") and !std.mem.eql(u8, name, "@product.get")) {
                    const collection = @import("collection_ops.zig").lookup(name) orelse return false;
                    switch (collection.op) {
                        .cursor, .cursor_has, .cursor_value, .cursor_advance => return false,
                        else => {},
                    }
                }
                self.text(name);
            },
            .integer, .float, .boolean => self.word(node.a),
            .string => self.text(self.pool.get(node.a)),
            .unit => {},
            else => return false,
        }
        return true;
    }
};
pub const Syntax = struct { ids: []ast.Id, digest: Digest };
pub fn syntax(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, root: ast.Id) A.Error!?Syntax {
    var walker: Walker = .{ .a = a, .tree = tree, .pool = pool, .start = tree.span(root).start };
    defer walker.ids.deinit(a);
    if (!try walker.visit(root, 0)) return null;
    var digest: Digest = undefined;
    walker.hash.final(&digest);
    return .{ .ids = try walker.ids.toOwnedSlice(a), .digest = digest };
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
    // Selected implementation dependencies need their complete proof/read
    // owner. The ordinary body receipt has no implementation admission lane.
    if (checked.implementations.len != 0 or checked.member_templates.len != 0) return;
    if (checked.diagnostics.len != 0 or text.len == 0) return;
    try cache.compact(a);
    var bodies: std.ArrayList(Body) = .empty;
    defer {
        for (bodies.items) |*body| body.deinit(a);
        bodies.deinit(a);
    }
    for (tree.roots.items) |root| {
        if (tree.node(root).tag != .value_decl or cache.find(pool.get(tree.valueDecl(root).name)) != null) continue;
        if (cache.minimum_nodes != 0) {
            var counter: Walker = .{ .a = a, .tree = tree, .pool = pool, .start = tree.span(root).start, .materialize = false };
            if (!try counter.visit(root, 0) or counter.count < cache.minimum_nodes) continue;
        }
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
    for (bodies.items) |body| {
        for (body.facts) |fact| try roots.append(a, fact.ty);
        for (body.bindings) |binding| try roots.append(a, binding.ty);
        for (body.signatures) |signature| try roots.append(a, signature.ty);
        for (body.accesses) |access| try roots.append(a, access.ty);
        for (body.predicates) |predicate| try roots.appendSlice(a, &.{ predicate.value.ty, predicate.value.other, predicate.value.result, predicate.value.signature });
        try rows.appendSlice(a, body.closed_rows);
    }
    const owner = freezeChunk(a, tree, pool, checked, names, &bodies, roots.items, rows.items) catch |err| {
        if (err == error.OutOfMemory) return err;
        return;
    } orelse return;
    try publishChunk(a, cache, owner);
}
fn freezeChunk(a: A, tree: *const ast.Tree, checked_pool: *const symbols.Pool, checked: *const check.Checked, names: ?ExternalNames, bodies: *std.ArrayList(Body), roots: []T.Id, rows: []u32) !?*Chunk {
    const catalog: Catalog = .{ .unit = checked.unit, .pool = checked_pool, .nominals = checked.nominals, .constructors = checked.constructors, .patterns = .{ .store = &checked.parameter_patterns }, .values = .{ .bindings = checked.bindings, .tree = tree, .names = names } };
    var schemes: std.ArrayList(T.Scheme) = .empty;
    defer schemes.deinit(a);
    for (bodies.items) |body| for (body.local_schemes) |local| {
        var principal = local.principal;
        // Owned requirements are projected with the ordinary body roots. The
        // scheme projector owns only binders and covariance certificates.
        principal.obligations = .{};
        try schemes.append(a, principal);
    };
    var graph = snapshot.freezeRootsWithSchemes(a, tree, checked, roots, rows, schemes.items) catch |err| {
        if (err == error.OutOfMemory) return err;
        return null;
    };
    errdefer snapshot.deinitGraph(a, &graph);
    var nominals: std.ArrayList(NominalRead) = .empty;
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
    for (graph.nodes) |*node| if (node.tag == .nominal) {
        const index = catalog.identity(.{ .unit = node.a, .decl = node.b }) orelse return error.DependencyLimit;
        const nominal = catalog.nominals[index];
        const name = catalog.pool.get(nominal.name);
        var slot: ?usize = null;
        for (nominals.items, 0..) |read, position_| if (read.unit == nominal.identity.unit and std.mem.eql(u8, read.name, name)) {
            slot = position_;
            break;
        };
        if (slot == null) {
            try nominals.ensureUnusedCapacity(a, 1);
            const digest = nominalDigest(.{ .store = &checked.types }, catalog, index) orelse return error.DependencyLimit;
            const origin = catalog.unitOrigin(nominal.identity.unit) orelse return error.DependencyLimit;
            const owned_name = try a.dupe(u8, name);
            slot = nominals.items.len;
            nominals.appendAssumeCapacity(.{ .unit = nominal.identity.unit, .origin = origin, .name = owned_name, .digest = digest });
        }
        // This graph's nominal namespace is chunk-local. AST and symbol IDs
        // become current identities only through the independently owned reads.
        node.a = @intCast(slot.? + 1);
        node.b = 0;
    };
    var next_type: usize = 0;
    var next_row: usize = 0;
    var next_scheme: usize = 0;
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
    const owner = try a.create(Chunk);
    errdefer a.destroy(owner);
    const owned_bodies = try bodies.toOwnedSlice(a);
    owner.* = .{ .allocator = a, .graph = graph, .nominals = owned_nominals, .field_names = owned_fields, .bodies = owned_bodies, .body_bytes = 0, .type_work = 0 };
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
fn frozenNominal(catalog: Catalog, reads: []const NominalRead, identity: T.NominalIdentity) !T.NominalIdentity {
    if (identity.unit == 0) return identity;
    const index = catalog.identity(identity) orelse return error.DependencyLimit;
    const original = catalog.nominals[index];
    for (reads, 0..) |read, read_index| {
        if (read.unit == original.identity.unit and std.mem.eql(u8, read.name, catalog.pool.get(original.name))) return .{ .unit = @intCast(read_index + 1), .decl = 0 };
    }
    return error.DependencyLimit;
}

fn bodyReads(a: A, graph: *const F.Graph, body: *const Body, names: []const []const u8, nominals: []const NominalRead) !struct { nominals: []u32, bytes: usize } {
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
    }
    for (body.predicates) |predicate| try pending.appendSlice(a, &.{ predicate.value.ty, predicate.value.other, predicate.value.result, predicate.value.signature });
    var bytes: usize = 0;
    for (body.local_schemes) |local| bytes += (local.principal.variables.len + local.principal.row_variables.len + local.principal.closed_rows.len) * 4;
    while (pending.pop()) |id| {
        const entry = try seen.getOrPut(a, id);
        if (entry.found_existing) continue;
        const node = source.node(id);
        bytes += @sizeOf(T.Node);
        switch (node.tag) {
            .nominal => {
                if (std.mem.findScalar(u32, result.items, node.a - 1) == null) {
                    try result.append(a, node.a - 1);
                    bytes += @sizeOf(NominalRead) + nominals[node.a - 1].name.len;
                }
                bytes += (source.nominalArguments(node).len + 1) * 4;
                try pending.appendSlice(a, source.nominalArguments(node));
            },
            .function => {
                const row = source.row(node.c);
                bytes += @sizeOf(T.Effects.Row) + row.labels.len * 4;
                try pending.appendSlice(a, &.{ node.a, node.b });
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
            .array, .list => try pending.append(a, node.a),
            else => {},
        }
    }
    for (body.constructors) |constructor| {
        const index = constructor.nominal.unit - 1;
        if (std.mem.findScalar(u32, result.items, index) == null) {
            try result.append(a, index);
            bytes += @sizeOf(NominalRead) + nominals[index].name.len;
        }
    }
    for (body.fields) |field| if (field.nominal.unit != 0) {
        const index = field.nominal.unit - 1;
        if (std.mem.findScalar(u32, result.items, index) == null) {
            try result.append(a, index);
            bytes += @sizeOf(NominalRead) + nominals[index].name.len;
        }
    };
    return .{ .nominals = try result.toOwnedSlice(a), .bytes = bytes };
}

fn publishChunk(a: A, cache: *Cache, owner: *Chunk) !void {
    defer owner.release();
    for (owner.bodies) |*body| try cache.retain(a, body);
}

fn genericAccessRoot(checked: *const check.Checked, id: ast.Id) bool {
    const target = checked.resolved[id];
    if (target == 0) return false;
    const binding = checked.bindings[target];
    return (binding.kind == .parameter or binding.kind == .local) and binding.scheme.obligations.len == 0;
}

fn captureBody(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, text: []const u8, checked: *const check.Checked, root: ast.Id, shape: Syntax, names: ?ExternalNames, annotations: ?AnnotationLookup) !?Body {
    var recipes: RecipeMemo = .{};
    const catalog: Catalog = .{ .recipes = &recipes, .unit = checked.unit, .pool = pool, .nominals = checked.nominals, .constructors = checked.constructors, .patterns = .{ .store = &checked.parameter_patterns }, .values = .{ .bindings = checked.bindings, .tree = tree, .names = names, .annotations = annotations } };
    const global = checked.resolved[root];
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
        if (!supportedPredicate(predicate) and !declaredPredicate(predicate) and !sharedPredicate(predicate, checked.unit)) return null;
        // Top-level declared clauses were already recreated by beginGlobal.
        if (predicate.explicit and tree.node(predicate.source).tag == .constraint) {
            if (position(shape.ids, predicate.source) == null) return null;
            continue;
        }
        // Qualified references instantiate their current principal below;
        // copying their forwarded requirements too would duplicate predicates.
        const generic_path = predicate.kind == .field and tree.node(predicate.source).tag == .name and checked.access_paths[predicate.source].len != 0 and genericAccessRoot(checked, predicate.source);
        if (!generic_path and (tree.node(predicate.source).tag == .name or tree.node(predicate.source).tag == .binary)) {
            const target = checked.resolved[predicate.source];
            if (target == 0 or checked.bindings[target].scheme.obligations.len == 0 or (predicate.kind == .callee_use and checked.bindings[target].kind != .local and predicate.identity.decl != target)) return null;
            continue;
        }
        if (predicate.kind == .field) {
            if (tree.node(predicate.source).tag != .field_access and !generic_path) return null;
        } else if (predicate.kind == .callee_use or tree.node(predicate.source).tag != .apply) return null;
        const source_position = position(shape.ids, predicate.source) orelse return null;
        try predicates.ensureUnusedCapacity(a, 1);
        const name = try a.dupe(u8, pool.get(predicate.name));
        var value = predicate;
        value.name = 0;
        value.source = 0;
        predicates.appendAssumeCapacity(.{ .value = value, .position = source_position, .name = name });
    }
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
    var constructors: std.ArrayList(Constructor) = .empty;
    defer constructors.deinit(a);
    var accesses: std.ArrayList(Access) = .empty;
    defer accesses.deinit(a);
    var fields: std.ArrayList(FieldProjection) = .empty;
    defer fields.deinit(a);
    var field_tags: std.ArrayList(u32) = .empty;
    defer field_tags.deinit(a);
    var needs_selection = false;
    var type_work: usize = 0;
    for (shape.ids, 0..) |id, position_| {
        const path = checked.types.list(checked.access_paths[id]);
        if (path.len != 0) {
            // Concrete dotted references have no access-node side table. Method
            // paths need complete selection reads and remain ordinary.
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
                    const receiver = checked.types.node(checked.types.head(types[index], 0));
                    if (step.nominal.unit != 0 or step.nominal.decl != 0 or receiver.tag != .variable or !genericAccessRoot(checked, id)) return null;
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
                const receiver = checked.types.node(checked.types.head(checked.expr_types[tree.node(id).a], 0));
                if (field.nominal.unit != 0 or field.nominal.decl != 0 or receiver.tag != .variable or field.field != tree.node(id).b) return null;
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
        const ty = checked.expr_types[id];
        var proof: std.crypto.hash.Blake3 = .init(.{});
        var budget: usize = 4096;
        if (!typeHash(.{ .store = &checked.types }, ty, &proof, &budget, 0, true, &.{}, &.{}, catalog)) return null;
        type_work += 4096 - budget;
        if (tree.node(id).tag == .type_name) {
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
        if (tree.node(id).tag == .lambda) {
            const rows = checked.types.list(checked.lambda_closed_rows[id]);
            fact.closed_rows = .{ .start = @intCast(closed_rows.items.len), .len = @intCast(rows.len) };
            try closed_rows.appendSlice(a, rows);
        }
        const old_id = checked.resolved[id];
        if (old_id != 0 and old_id != global) {
            var index = std.mem.findScalar(check.BindingId, old_bindings.items, old_id);
            if (index == null) {
                const old = checked.bindings[old_id];
                const local = old.kind == .parameter or old.kind == .local;
                if (!local and old.scheme.obligations.len != 0) {
                    needs_selection = true;
                    var member_budget: usize = 64;
                    if (!try appendSchemeMembers(a, &members, old.scheme, checked.obligations, catalog, &member_budget)) return null;
                }
                var digest: ?Digest = null;
                if (local) {
                    digest = @as(Digest, @splat(0));
                } else {
                    digest = readDigest(.{ .store = &checked.types }, old, checked.obligations, names, catalog);
                }
                if (digest == null) return null;
                const declaration = position(shape.ids, old.declaration);
                const owner = position(shape.ids, old.owner);
                if (local and (declaration == null or owner == null)) return null;
                if (!local and old.kind == .global and old.declaration == root) return null;
                try bindings.ensureUnusedCapacity(a, 1);
                try old_bindings.ensureUnusedCapacity(a, 1);
                const name = try a.dupe(u8, pool.get(old.name));
                index = old_bindings.items.len;
                bindings.appendAssumeCapacity(.{ .name = name, .kind = old.kind, .private = old.private, .declaration = declaration orelse 0, .owner = owner orelse 0, .ty = old.ty, .scheme = old.scheme.root != 0, .named_function = old.named_function, .capability_flow = old.capability_flow, .runtime = old.kind == .global and tree.valueDecl(old.declaration).runtime, .external = old.external, .interface = digest.? });
                old_bindings.appendAssumeCapacity(old_id);
            }
            fact.binding = @intCast(index.? + 1);
        } else if (old_id == global and id != root) return null;
        try facts.append(a, fact);
    }
    for (checked.merges) |merge| if (position(shape.ids, merge.node)) |at| {
        const result = try captureLocal(a, checked, pool, catalog, shape, merge.result, &bindings, &old_bindings) orelse return null;
        const yes = try captureLocal(a, checked, pool, catalog, shape, merge.then_binding, &bindings, &old_bindings) orelse return null;
        const no = try captureLocal(a, checked, pool, catalog, shape, merge.else_binding, &bindings, &old_bindings) orelse return null;
        try merges.append(a, .{ .position = at, .result = result, .yes = yes, .no = no });
    };
    for (old_bindings.items, bindings.items) |old_id, *binding| {
        const predecessor = checked.bindings[old_id].predecessor;
        if (predecessor != 0) binding.predecessor = @intCast((std.mem.findScalar(check.BindingId, old_bindings.items, predecessor) orelse return null) + 1);
    }
    var local_schemes: std.ArrayList(LocalScheme) = .empty;
    defer local_schemes.deinit(a);
    var local_requirement_budget: usize = 4096;
    for (old_bindings.items, 0..) |id, index| {
        const old = checked.bindings[id];
        if (old.kind != .local or (old.scheme.variables.len == 0 and old.scheme.row_variables.len == 0 and old.scheme.closed_rows.len == 0 and old.scheme.obligations.len == 0)) continue;
        if (old.scheme.obligations.len > 4096 - predicates.items.len) return null;
        if (old.scheme.obligations.len != 0) {
            needs_selection = true;
            var member_budget: usize = 64;
            if (!try appendSchemeMembers(a, &members, old.scheme, checked.obligations, catalog, &member_budget)) return null;
        }
        var local = old.scheme;
        local.obligations = .{ .start = @intCast(predicates.items.len), .len = old.scheme.obligations.len };
        for (checked.obligations[old.scheme.obligations.start..][0..old.scheme.obligations.len]) |predicate| {
            // Local requirements own flat roots or a completed callee read.
            // Written clauses retain declaration-relative origins.
            if ((!supportedPredicate(predicate) and !declaredPredicate(predicate) and !sharedPredicate(predicate, checked.unit)) or local_requirement_budget == 0) return null;
            if (predicate.explicit) {
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
    if (needs_selection) selection_digest = associatedDigest(.{ .store = &checked.types }, catalog, tree, checked.associated, checked.bindings, checked.obligations, names, members.items) orelse return null;
    const name = try a.dupe(u8, pool.get(tree.valueDecl(root).name));
    errdefer a.free(name);
    const span = tree.span(root);
    const source = try a.dupe(u8, text[span.start..span.end]);
    errdefer a.free(source);
    const owned_facts = try facts.toOwnedSlice(a);
    errdefer a.free(owned_facts);
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
    const owned_predicates = try predicates.toOwnedSlice(a);
    errdefer {
        for (owned_predicates) |predicate| a.free(predicate.name);
        a.free(owned_predicates);
    }
    const owned_bindings = try bindings.toOwnedSlice(a);
    return .{ .owner = undefined, .name = name, .source = source, .syntax = shape.digest, .facts = owned_facts, .bindings = owned_bindings, .closed_rows = owned_rows, .type_work = type_work, .type_reads = owned_reads, .predicates = owned_predicates, .signatures = owned_signatures, .projections = owned_projections, .merges = owned_merges, .constructors = owned_constructors, .local_schemes = owned_local_schemes, .fields = owned_fields, .accesses = owned_accesses, .field_tags = owned_field_tags, .members = owned_members, .selection_digest = selection_digest };
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
    bindings.appendAssumeCapacity(.{ .name = name, .kind = old.kind, .private = old.private, .declaration = declaration, .owner = owner, .ty = old.ty, .scheme = old.scheme.root != 0, .named_function = old.named_function, .capability_flow = old.capability_flow, .runtime = false, .external = null, .interface = @splat(0) });
    old_bindings.appendAssumeCapacity(id);
    return @intCast(old_bindings.items.len);
}

test "body check cache recipe memo preserves exact depth budget and exhaustion guards" {
    const allocator = std.testing.allocator;
    const text = "type Token is data = #Token U32\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try @import("lexer.zig").lex(allocator, text);
    defer tokens.deinit(allocator);
    var tree = try @import("parser.zig").parse(allocator, text, tokens.tokens.items, &pool);
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
