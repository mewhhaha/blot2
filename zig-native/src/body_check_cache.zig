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
    closed_rows: ?*const fn (*const anyopaque, check.ExternalTarget) ?Digest = null,
};
pub const Catalog = struct {
    unit: u32,
    pool: *const symbols.Pool,
    nominals: []const check.Nominal,
    constructors: []const check.Constructor,
    fn identity(self: Catalog, value: T.NominalIdentity) ?usize {
        for (self.nominals, 0..) |nominal, index| if (std.meta.eql(nominal.identity, value)) return index;
        return null;
    }
    pub fn named(self: Catalog, unit: u32, name: []const u8) ?usize {
        for (self.nominals, 0..) |nominal, index| if (nominal.identity.unit == unit and std.mem.eql(u8, self.pool.get(nominal.name), name)) return index;
        return null;
    }
};
pub const NominalRead = struct { unit: u32, name: []u8, digest: Digest };
pub const TypeRead = struct { position: u32, digest: Digest };
pub fn nominalDigest(source: F.Source, catalog: Catalog, index: usize) ?Digest {
    var budget: usize = 4096;
    return nominalDigestAt(source, catalog, index, 0, &budget);
}
fn nominalDigestAt(source: F.Source, catalog: Catalog, index: usize, depth: usize, budget: *usize) ?Digest {
    if (depth >= 128 or budget.* == 0) return null;
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
    hashWord(&hash, nominal.identity.unit);
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
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
pub fn annotationDigest(source: F.Source, catalog: Catalog, name: []const u8) ?Digest {
    // Namespaced and imported aliases need their own owned name-resolution
    // receipt. Local monomorphic annotations have a complete current catalog.
    const index = catalog.named(catalog.unit, name) orelse return null;
    const nominal = catalog.nominals[index];
    if (nominal.parameters.len != 0) return null;
    if (nominal.alias != 0) {
        const expansion = typeDigest(source, nominal.alias, catalog) orelse return null;
        var alias_hash: std.crypto.hash.Blake3 = .init(.{});
        hashWord(&alias_hash, @backingInt(ast.Tag.type_alias_decl));
        hashWord(&alias_hash, nominal.identity.unit);
        alias_hash.update(name);
        hashWord(&alias_hash, @intFromBool(nominal.private));
        alias_hash.update(&expansion);
        var digest: Digest = undefined;
        alias_hash.final(&digest);
        return digest;
    }
    const digest = nominalDigest(source, catalog, index) orelse return null;
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
    runtime: bool,
    external: ?check.ExternalTarget,
    interface: Digest,
};
pub const Projection = struct { position: u32, index: u32 };
pub const Signature = struct { position: u32, ty: T.Id };
pub const Predicate = struct { value: T.Obligation, position: u32, name: []u8 };
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
    members: [][]u8 = &.{},
    selection_digest: ?Digest = null,
    pub fn bytes(self: *const Body) usize {
        var total = @sizeOf(Body) + self.name.len + self.source.len + self.facts.len * @sizeOf(Fact) + self.bindings.len * @sizeOf(Binding) + self.closed_rows.len * 4 + self.nominals.len * 4 + self.type_reads.len * @sizeOf(TypeRead);
        for (self.bindings) |binding| total += binding.name.len;
        total += self.predicates.len * @sizeOf(Predicate);
        for (self.predicates) |predicate| total += predicate.name.len;
        total += self.projections.len * @sizeOf(Projection) + self.signatures.len * @sizeOf(Signature) + self.members.len * @sizeOf([]u8);
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
    const principal = binding.scheme;
    if (principal.root == 0) return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    var budget: usize = 4096;
    const variables = source.list(principal.variables);
    hashWord(&hash, @intCast(variables.len));
    hashWord(&hash, principal.row_variables.len);
    const certificates = closedRowsDigest(source, binding.ty, principal, catalog.pool) orelse return null;
    hash.update(&certificates);
    if (!typeHash(source, principal.root, &hash, &budget, 0, false, variables, source.list(principal.row_variables), catalog)) return null;
    hashWord(&hash, principal.obligations.len);
    for (obligations[principal.obligations.start..][0..principal.obligations.len]) |predicate| {
        if (!supportedPredicate(predicate)) return null;
        hashWord(&hash, @backingInt(predicate.kind));
        hashWord(&hash, @backingInt(predicate.operator));
        const name = catalog.pool.get(predicate.name);
        hashWord(&hash, @intCast(name.len));
        hash.update(name);
        for ([_]T.Id{ predicate.ty, predicate.other, predicate.result, predicate.signature }) |part| {
            if (!typeHash(source, part, &hash, &budget, 0, false, variables, source.list(principal.row_variables), catalog)) return null;
        }
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}
fn supportedPredicate(value: T.Obligation) bool {
    return (value.kind == .dispatch or value.kind == .result_dispatch) and !value.explicit and value.identity.unit == 0 and value.identity.decl == 0 and value.qualification_span == null and value.qualification_unit == 0;
}

pub fn readDigest(source: F.Source, binding: check.Binding, obligations: []const T.Obligation, names: ?ExternalNames, catalog: Catalog) ?Digest {
    var principal_binding = binding;
    var certificates: ?Digest = null;
    if (binding.kind == .external and binding.scheme.closed_rows.len != 0) {
        const dictionary = names orelse return null;
        const lookup = dictionary.closed_rows orelse return null;
        certificates = lookup(dictionary.context, binding.external orelse return null) orelse return null;
        // This receipt was canonicalized in the producer's raw type namespace.
        principal_binding.scheme.closed_rows = .{};
    }
    const digest = interfaceDigest(source, principal_binding, obligations, catalog) orelse return null;
    if (binding.kind != .external) return digest;
    const dictionary = names orelse return null;
    const name = dictionary.lookup(dictionary.context, binding.external orelse return null) orelse return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    hash.update(&digest);
    if (certificates) |certificate| hash.update(&certificate);
    hash.update(name);
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
        hashWord(&hash, entry.identity.unit);
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
        hashWord(&hash, @intFromBool(binding.kind == .global and tree.valueDecl(binding.declaration).runtime));
        if (binding.external) |target| {
            hashWord(&hash, target.unit);
            hashWord(&hash, target.binding);
        }
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

const Walker = struct {
    a: A,
    tree: *const ast.Tree,
    pool: *const symbols.Pool,
    ids: std.ArrayList(ast.Id) = .empty,
    hash: std.crypto.hash.Blake3 = .init(.{}),
    start: u32,
    count: usize = 0,
    materialize: bool = true,
    fn word(self: *Walker, value: u32) void {
        if (self.materialize) hashWord(&self.hash, value);
    }
    fn text(self: *Walker, value: []const u8) void {
        if (self.materialize) self.hash.update(value);
    }
    fn visit(self: *Walker, id: ast.Id, depth: usize) A.Error!bool {
        if (id == 0) return true;
        if (depth >= 128 or self.count >= 4096) return false;
        const node = self.tree.node(id);
        const span = self.tree.span(id);
        if (span.start < self.start) return false;
        self.count += 1;
        if (self.materialize) try self.ids.append(self.a, id);
        self.word(@backingInt(node.tag));
        self.word(span.start - self.start);
        self.word(span.end - self.start);
        switch (node.tag) {
            .value_decl => {
                const decl = self.tree.valueDecl(id);
                if (decl.attributes.len != 0 or decl.where_node != 0) return false;
                self.word(@intFromBool(decl.runtime));
                self.word(@intFromBool(decl.exported));
                const traits = self.tree.declarationTraits(id);
                self.word(@intFromBool(traits.private));
                self.word(@intFromBool(traits.is_opaque));
                if (!try self.visit(decl.annotation, depth + 1)) return false;
                return self.visit(decl.body, depth + 1);
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
            .apply, .type_function => {
                if (node.tag == .type_function and node.c != 0) return false;
                if (!try self.visit(node.a, depth + 1)) return false;
                return self.visit(node.b, depth + 1);
            },
            .binary => {
                self.text(self.pool.get(node.a));
                if (!try self.visit(node.b, depth + 1)) return false;
                return self.visit(node.c, depth + 1);
            },
            .group => return self.visit(node.a, depth + 1),
            .if_expr => {
                if (!try self.visit(node.a, depth + 1)) return false;
                if (!try self.visit(node.b, depth + 1)) return false;
                return self.visit(node.c, depth + 1);
            },
            .record => {
                if (node.a != 0) return false;
                for (self.tree.children(id)) |child| if (!try self.visit(child, depth + 1)) return false;
            },
            .field, .type_field => {
                if (node.b == 0) return false;
                self.text(self.pool.get(node.a));
                return self.visit(node.b, depth + 1);
            },
            .product, .array, .type_product, .type_record => for (self.tree.children(id)) |child| {
                if (!try self.visit(child, depth + 1)) return false;
            },
            .name => self.text(self.pool.get(node.a)),
            .type_name => {
                const name = self.pool.get(node.a);
                self.text(name);
            },
            .intrinsic => {
                const name = self.pool.get(node.a);
                if (!std.mem.startsWith(u8, name, "@u32.") and !std.mem.startsWith(u8, name, "@f32.") and !std.mem.eql(u8, name, "@type.call") and !std.mem.eql(u8, name, "@type.result")) return false;
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
        if (try captureBody(a, tree, pool, text, checked, root, shape, names)) |body| {
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
        for (body.predicates) |predicate| try roots.appendSlice(a, &.{ predicate.value.ty, predicate.value.other, predicate.value.result, predicate.value.signature });
        try rows.appendSlice(a, body.closed_rows);
    }
    const owner = freezeChunk(a, tree, pool, checked, &bodies, roots.items, rows.items) catch |err| {
        if (err == error.OutOfMemory) return err;
        return;
    } orelse return;
    try publishChunk(a, cache, owner);
}
fn freezeChunk(a: A, tree: *const ast.Tree, checked_pool: *const symbols.Pool, checked: *const check.Checked, bodies: *std.ArrayList(Body), roots: []T.Id, rows: []u32) !?*Chunk {
    const catalog: Catalog = .{ .unit = checked.unit, .pool = checked_pool, .nominals = checked.nominals, .constructors = checked.constructors };
    var graph = snapshot.freezeRoots(a, tree, checked, roots, rows) catch |err| {
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
            const name = catalog.pool.get(graph.extra[position_]);
            var slot: ?usize = null;
            for (field_names.items, 0..) |known, i| if (std.mem.eql(u8, known, name)) {
                slot = i;
                break;
            };
            if (slot == null) {
                try field_names.ensureUnusedCapacity(a, 1);
                const owned_name = try a.dupe(u8, name);
                slot = field_names.items.len;
                field_names.appendAssumeCapacity(owned_name);
            }
            graph.extra[position_] = @intCast(slot.?);
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
            const owned_name = try a.dupe(u8, name);
            slot = nominals.items.len;
            nominals.appendAssumeCapacity(.{ .unit = nominal.identity.unit, .name = owned_name, .digest = digest });
        }
        // This graph's nominal namespace is chunk-local. AST and symbol IDs
        // become current identities only through the independently owned reads.
        node.a = @intCast(slot.? + 1);
        node.b = 0;
    };
    var next_type: usize = 0;
    var next_row: usize = 0;
    for (bodies.items) |*body| {
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
        for (body.predicates) |*predicate| {
            predicate.value.ty = roots[next_type];
            predicate.value.other = roots[next_type + 1];
            predicate.value.result = roots[next_type + 2];
            predicate.value.signature = roots[next_type + 3];
            next_type += 4;
        }
        @memcpy(body.closed_rows, rows[next_row..][0..body.closed_rows.len]);
        next_row += body.closed_rows.len;
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
fn bodyReads(a: A, graph: *const F.Graph, body: *const Body, names: []const []const u8, nominals: []const NominalRead) !struct { nominals: []u32, bytes: usize } {
    var seen: std.AutoHashMapUnmanaged(T.Id, void) = .empty;
    defer seen.deinit(a);
    var pending: std.ArrayList(T.Id) = .empty;
    defer pending.deinit(a);
    var result: std.ArrayList(u32) = .empty;
    defer result.deinit(a);
    for (body.facts) |fact| try pending.append(a, fact.ty);
    for (body.bindings) |binding| try pending.append(a, binding.ty);
    for (body.signatures) |signature| try pending.append(a, signature.ty);
    for (body.predicates) |predicate| try pending.appendSlice(a, &.{ predicate.value.ty, predicate.value.other, predicate.value.result, predicate.value.signature });
    const source: F.Source = .{ .frozen = graph };
    var bytes: usize = 0;
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
    return .{ .nominals = try result.toOwnedSlice(a), .bytes = bytes };
}

fn publishChunk(a: A, cache: *Cache, owner: *Chunk) !void {
    defer owner.release();
    for (owner.bodies) |*body| try cache.retain(a, body);
}

fn captureBody(a: A, tree: *const ast.Tree, pool: *const symbols.Pool, text: []const u8, checked: *const check.Checked, root: ast.Id, shape: Syntax, names: ?ExternalNames) !?Body {
    const catalog: Catalog = .{ .unit = checked.unit, .pool = pool, .nominals = checked.nominals, .constructors = checked.constructors };
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
        if (!supportedPredicate(predicate)) return null;
        // Qualified references instantiate their current principal below;
        // copying their forwarded requirements too would duplicate predicates.
        if (tree.node(predicate.source).tag == .name) {
            const target = checked.resolved[predicate.source];
            if (target == 0 or checked.bindings[target].scheme.obligations.len == 0) return null;
            continue;
        }
        if (tree.node(predicate.source).tag != .apply) return null;
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
    var needs_selection = false;
    var type_work: usize = 0;
    for (shape.ids, 0..) |id, position_| {
        if (checked.constructor_resolved[id] != 0) return null;
        if (tree.node(id).tag == .string) try appendMember(a, &members, pool.get(tree.node(id).a));
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
            if (!variable and !std.mem.eql(u8, name, "U32") and !std.mem.eql(u8, name, "F32") and !std.mem.eql(u8, name, "Bool") and !std.mem.eql(u8, name, "Unit")) {
                const digest = annotationDigest(.{ .store = &checked.types }, catalog, name) orelse return null;
                try type_reads.append(a, .{ .position = @intCast(position_), .digest = digest });
            }
        }
        if (checked.projections[id] != std.math.maxInt(u32)) try projections.append(a, .{ .position = @intCast(position_), .index = checked.projections[id] });
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
                const local = old.kind == .parameter;
                if (old.kind == .local) return null;
                if (!local and old.scheme.obligations.len != 0) {
                    needs_selection = true;
                    for (checked.obligations[old.scheme.obligations.start..][0..old.scheme.obligations.len]) |predicate| {
                        if (!supportedPredicate(predicate)) return null;
                        try appendMember(a, &members, pool.get(predicate.name));
                    }
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
                bindings.appendAssumeCapacity(.{ .name = name, .kind = old.kind, .private = old.private, .declaration = declaration orelse 0, .owner = owner orelse 0, .ty = old.ty, .scheme = old.scheme.root != 0, .named_function = old.named_function, .runtime = old.kind == .global and tree.valueDecl(old.declaration).runtime, .external = old.external, .interface = digest.? });
                old_bindings.appendAssumeCapacity(old_id);
            }
            fact.binding = @intCast(index.? + 1);
        } else if (old_id == global and id != root) return null;
        try facts.append(a, fact);
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
    const owned_predicates = try predicates.toOwnedSlice(a);
    errdefer {
        for (owned_predicates) |predicate| a.free(predicate.name);
        a.free(owned_predicates);
    }
    const owned_bindings = try bindings.toOwnedSlice(a);
    return .{ .owner = undefined, .name = name, .source = source, .syntax = shape.digest, .facts = owned_facts, .bindings = owned_bindings, .closed_rows = owned_rows, .type_work = type_work, .type_reads = owned_reads, .predicates = owned_predicates, .signatures = owned_signatures, .projections = owned_projections, .members = owned_members, .selection_digest = selection_digest };
}
