//! Portable candidates for empty-result principal queries. The full ordered
//! source/catalog image and symbol/producer namespace must match before dynamic
//! observations are checked. Runtime values are always evaluated afresh.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const types = @import("type_evidence.zig");
const inputs = @import("principal_inputs.zig");
const identity = @import("runtime_identity.zig");
const metadata = @import("code_artifacts.zig");
const format = @import("dependency_format.zig");
const A = std.mem.Allocator;
const Proof = struct { target: core.BindingRef, options: eval.Options, inputs: inputs.Key };
const Snapshot = struct {
    modules: []format.Digest,
    namespace: format.Digest,
    proofs: []Proof,
    evidence: types.Snapshot,
};
fn key(compiler: format.Digest) format.Key {
    return .{ .compiler = compiler, .settings = format.digest("blot-principal-archive-v1"), .source = @splat(0), .dependencies = @splat(0) };
}
pub fn encode(a: A, compiler: format.Digest, context: *const metadata.Context) format.Error![]u8 {
    const pools = &(context.pools orelse return error.InvalidArtifact);
    const names = if (pools.identity) |*owned| owned.view() else return error.InvalidArtifact;
    const modules = try a.alloc(format.Digest, pools.modules.len);
    defer a.free(modules);
    for (pools.modules, modules) |pin, *stamp| stamp.* = metadata.stamp(pin.module.*);
    var proofs: std.ArrayList(Proof) = .empty;
    defer proofs.deinit(a);
    for (context.principal_proofs.items) |proof| {
        if (proof.types.len != 0 or proof.rows.len != 0) continue;
        if (proof.inputs) |observed| try proofs.append(a, .{ .target = proof.target, .options = proof.options, .inputs = observed });
    }
    return format.encode(a, key(compiler), Snapshot{ .modules = modules, .namespace = metadata.stamp(names), .proofs = proofs.items, .evidence = pools.evaluator.evidence });
}
pub const Archive = struct {
    allocator: A,
    snapshot: Snapshot,
    pub fn deinit(self: *Archive) void {
        format.deinit(self.allocator, &self.snapshot);
        self.* = undefined;
    }
};
pub fn decode(a: A, compiler: format.Digest, bytes: []const u8) format.Error!Archive {
    return .{ .allocator = a, .snapshot = try format.decode(Snapshot, a, bytes, key(compiler)) };
}
pub const Stats = struct { requests: usize = 0, hits: usize = 0, image_checks: usize = 0, declined: usize = 0, call_proofs: usize = 0 };
pub const Reader = struct {
    allocator: A,
    archive: *const Archive,
    units: []const core.Module,
    names: ?identity.View,
    image_matches: ?bool = null,
    last_inputs: ?inputs.Key = null,
    stats: Stats = .{},

    pub fn deinit(self: *Reader) void {
        self.clearInputs();
        self.* = undefined;
    }
    pub fn clearInputs(self: *Reader) void {
        if (self.last_inputs) |*observed| observed.deinit(self.allocator);
        self.last_inputs = null;
    }
    fn matchesImage(self: *Reader) bool {
        if (self.image_matches) |known| return known;
        self.stats.image_checks += 1;
        self.image_matches = false;
        const names = self.names orelse return false;
        const image = &self.archive.snapshot;
        if (image.modules.len != self.units.len or !std.mem.eql(u8, &image.namespace, &metadata.stamp(names))) return false;
        for (image.modules, self.units) |stamp, module| if (!std.mem.eql(u8, &stamp, &metadata.stamp(module))) return false;
        self.image_matches = true;
        return true;
    }
    pub fn lookup(self: *Reader, session: *eval.Session, target: core.BindingRef, options: eval.Options) A.Error!?eval.SolvedEvidence {
        self.clearInputs();
        self.stats.requests += 1;
        if (session.units.ptr != self.units.ptr or session.units.len != self.units.len or !self.matchesImage()) return null;
        for (self.archive.snapshot.proofs) |proof| {
            if (!std.meta.eql(proof.target, target) or !std.meta.eql(proof.options, options) or !proof.inputs.matches(session)) continue;
            if (!validTarget(self.units, target)) continue;
            var translated = try proof.inputs.clone(self.allocator);
            var owned = true;
            defer if (owned) translated.deinit(self.allocator);
            var importer: Import = .{ .allocator = self.allocator, .source = self.archive.snapshot.evidence.view(), .target = &session.evidence, .units = self.units, .names = self.names.? };
            defer importer.deinit();
            var valid = true;
            for (translated.call_publications) |*call| {
                if (!validTarget(self.units, call.target)) {
                    valid = false;
                    break;
                }
                const actual = importer.typeId(call.evidence, 0) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidEvidence => {
                        valid = false;
                        break;
                    },
                };
                if (session.evidence.node(actual).tag != .function) {
                    valid = false;
                    break;
                }
                call.evidence = actual;
            }
            if (!valid) {
                self.stats.declined += 1;
                continue;
            }
            // Validate every nominal memo key before any memo publication. Its
            // absence/value was already checked by the dynamic input contract.
            for (translated.plain_publications) |publication| if (!validNominal(self.units, .{ .unit = @intCast(publication.key >> 32), .decl = @truncate(publication.key) })) {
                valid = false;
                break;
            };
            if (!valid) {
                self.stats.declined += 1;
                continue;
            }
            try translated.publish(session);
            self.stats.hits += 1;
            self.stats.call_proofs += translated.call_publications.len;
            self.last_inputs = translated;
            owned = false;
            return .{ .types = &.{}, .rows = &.{} };
        }
        return null;
    }
};
fn validTarget(units: []const core.Module, target: core.BindingRef) bool {
    if (target.unit == 0 or target.unit > units.len) return false;
    const module = &units[target.unit - 1];
    return target.binding != 0 and target.binding < module.bindings.len and module.binding(target.binding).kind == .global and module.body(target.binding) != null;
}
fn validNominal(units: []const core.Module, nominal: @import("types.zig").NominalIdentity) bool {
    if (nominal.unit == 0 or nominal.unit > units.len or nominal.decl == 0) return false;
    const module = &units[nominal.unit - 1];
    for (module.nominals) |item| if (item.identity.decl == nominal.decl and (item.identity.unit == 0 or item.identity.unit == nominal.unit)) return true;
    return false;
}
// Deliberately admits the same closed family as retained principal call proofs.
// Providers, generative identities, resolvers and type constructors are absent.
// Importing a graph alone never publishes a callable validation certificate.
const Import = struct {
    allocator: A,
    source: types.View,
    target: *types.Store,
    units: []const core.Module,
    names: identity.View,
    mapped: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    remaining: usize = 1_000_000,
    const Error = A.Error || error{InvalidEvidence};
    fn deinit(self: *Import) void {
        self.mapped.deinit(self.allocator);
    }
    fn span(values: []const u32, start: u32, len: usize) Error![]const u32 {
        if (start > values.len or len > values.len - start) return error.InvalidEvidence;
        return values[start..][0..len];
    }
    fn typeId(self: *Import, id: u32, depth: usize) Error!u32 {
        if (depth >= 256 or self.remaining == 0 or id == 0 or id >= self.source.nodes.len) return error.InvalidEvidence;
        self.remaining -= 1;
        if (self.mapped.get(id)) |prior| return prior;
        const node = self.source.node(id);
        var left = node.a;
        var right = node.b;
        var effects: u32 = 0;
        var values: std.ArrayList(u32) = .empty;
        defer values.deinit(self.allocator);
        switch (node.tag) {
            .absent, .provider, .state_provider, .resolver, .type_constructor => return error.InvalidEvidence,
            .unit, .boolean, .u32, .f32, .never => if (node.a != 0 or node.b != 0 or node.c != 0) return error.InvalidEvidence,
            .array, .list, .cursor, .demand => {
                if (right != 0 or (node.tag != .demand and node.c != 0)) return error.InvalidEvidence;
                left = try self.typeId(left, depth + 1);
                if (node.tag == .demand) effects = try self.row(node.c, depth + 1);
            },
            .function => {
                left = try self.typeId(left, depth + 1);
                right = try self.typeId(right, depth + 1);
                effects = try self.row(node.c, depth + 1);
            },
            .product, .record, .nominal => {
                var children: []const u32 = undefined;
                if (node.tag == .nominal) {
                    if (!validNominal(self.units, .{ .unit = node.a, .decl = node.b }) or node.c >= self.source.extra.len) return error.InvalidEvidence;
                    children = try span(self.source.extra, node.c + 1, self.source.extra[node.c]);
                } else {
                    if (node.c != 0) return error.InvalidEvidence;
                    children = try span(self.source.extra, node.a, std.math.mul(usize, node.b, if (node.tag == .record) 2 else 1) catch return error.InvalidEvidence);
                    left = 0;
                    right = 0;
                }
                for (children, 0..) |child, index| {
                    if (node.tag == .record and index % 2 == 0) {
                        if (self.names.symbol(child) == null) return error.InvalidEvidence;
                        try values.append(self.allocator, child);
                    } else try values.append(self.allocator, try self.typeId(child, depth + 1));
                }
            },
        }
        const result = self.target.internWithEffects(node.tag, left, right, effects, values.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEvidence;
        try self.mapped.put(self.allocator, id, result);
        return result;
    }
    fn row(self: *Import, id: u32, depth: usize) Error!u32 {
        const source = self.source.effects;
        if (depth >= 256 or self.remaining == 0 or id >= source.rows.len) return error.InvalidEvidence;
        self.remaining -= 1;
        const item = source.rows[id];
        const labels = try span(source.labels, item.start, item.len);
        if (id == 0 and labels.len != 0) return error.InvalidEvidence;
        var translated: std.ArrayList(u32) = .empty;
        defer translated.deinit(self.allocator);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(self.allocator);
        for (labels) |label| {
            if (label == 0 or label >= source.operations.len) return error.InvalidEvidence;
            const operation = source.operations[label];
            const original = try span(source.arguments, operation.arguments.start, operation.arguments.len);
            if (operation.identity.unit == 0) {
                if (operation.identity.decl != 1 or original.len != 0) return error.InvalidEvidence;
            } else if (!validNominal(self.units, operation.identity)) return error.InvalidEvidence;
            arguments.clearRetainingCapacity();
            for (original) |argument| try arguments.append(self.allocator, try self.typeId(argument, depth + 1));
            const actual = self.target.effects.internOperation(operation.identity, arguments.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEvidence;
            try translated.append(self.allocator, actual);
        }
        return self.target.effects.internRow(translated.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEvidence;
    }
};
