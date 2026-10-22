const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const identity = @import("../backend/runtime_identity.zig");
const archive = @import("../backend/backend_checkpoint.zig");
const principal = @import("principal_archive.zig");
const a = std.testing.allocator;
const compiler: [32]u8 = @splat(17);
const source =
    \\type Box is data = #Box U32
    \\const extract = fn (box: Box) -> U32 => case box of
    \\  #Box value => value
    \\entry const answer: U32 where { type_rep U32 } = @u32.div 8 (extract (#Box 2))
;
const Fixture = struct {
    units: [1]core.Module,
    names: identity.Metadata,
    fn init(text: []const u8) !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var module = try core.lower(a, &tree, &pool, &checked);
        errdefer module.deinit(a);
        return .{ .units = .{module}, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/checkpoint/main.blot" }}, 1) };
    }
    fn emit(self: *const Fixture, allocator: std.mem.Allocator, cache: ?*const archive.Checkpoint) !backend.Result {
        return backend.compileWithOptions(allocator, &self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .checkpoint = cache });
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        self.names.deinit(a);
    }
};
fn makeCheckpoint() ![]u8 {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var compiled = try fixture.emit(a, null);
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    return archive.encode(a, compiler, &compiled.capture.?);
}
fn importScenario(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8) !void {
    var loaded = try archive.decode(allocator, compiler, bytes);
    defer loaded.deinit();
    var compiled = try fixture.emit(allocator, &loaded);
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.principal.persisted_hits > 0);
    try std.testing.expect(compiled.principal.persisted_call_proofs > 0);
    try std.testing.expect(compiled.query_tables.portable_principal.records > 0);
    try std.testing.expect(compiled.query_tables.portable_principal.inspected_positions > 0);
    try std.testing.expectEqualSlices(u8, expected, compiled.bytes);
}

// Decoding rejects a second record per target; the Reader still keeps the
// oldest valid candidate first when an owner supplies such duplicates.
fn appendInvalidDuplicate(loaded: *archive.Checkpoint) !void {
    const original = loaded.principal.snapshot.queries.records;
    try std.testing.expect(original.len > 0);
    const first = original[0];
    try std.testing.expect(first.dependencies.call_publications.len > 0);
    const records = try a.alloc(principal.Record, original.len + 1);
    errdefer a.free(records);
    var observed = try first.dependencies.clone(a);
    errdefer observed.deinit(a);
    const mappings = try a.dupe(@TypeOf(first.result.types[0]), first.result.types);
    errdefer a.free(mappings);
    const rows = try a.dupe(@TypeOf(first.result.rows[0]), first.result.rows);
    @memcpy(records[0..original.len], original);
    records[original.len] = .{ .key = first.key, .dependencies = observed, .result = .{ .types = mappings, .rows = rows } };
    records[original.len].dependencies.call_publications[0].evidence = std.math.maxInt(u32);
    a.free(original);
    loaded.principal.snapshot.queries.records = records;
}
test "portable principal query duplicates retain oldest valid proof priority" {
    const bytes = try makeCheckpoint();
    defer a.free(bytes);
    var loaded = try archive.decode(a, compiler, bytes);
    defer loaded.deinit();
    try appendInvalidDuplicate(&loaded);
    const expected_calls = loaded.principal.snapshot.queries.records[0].dependencies.call_publications.len;
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.emit(a, null);
    defer fresh.deinit(a);
    var compiled = try fixture.emit(a, &loaded);
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.principal.persisted_hits > 0);
    try std.testing.expectEqual(@as(usize, 0), compiled.principal.persisted_declines);
    try std.testing.expectEqual(expected_calls, compiled.principal.persisted_call_proofs);
    try std.testing.expectEqualSlices(u8, fresh.bytes, compiled.bytes);
}

test "portable principal query saturation declines optional archive reuse" {
    const bytes = try makeCheckpoint();
    defer a.free(bytes);
    var loaded = try archive.decode(a, compiler, bytes);
    defer loaded.deinit();
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var session = try @import("../eval/core_eval.zig").Session.init(a, &fixture.units);
    defer session.deinit();
    var reader: principal.Reader = .{ .allocator = a, .archive = &loaded.principal, .units = &fixture.units, .names = fixture.names.view() };
    defer reader.deinit();
    reader.query_table.limits.records = 0;
    const record = loaded.principal.snapshot.queries.records[0];
    try std.testing.expect((try reader.lookup(&session, record.key.target, record.key.options)) == null);
    try std.testing.expectEqual(@as(usize, 0), reader.stats.hits);
    try std.testing.expectEqual(@as(usize, 0), reader.storage().records);
    try std.testing.expectEqual(@as(usize, 1), reader.storage().saturated);
    try std.testing.expectEqual(@as(usize, 0), session.specializations.validated_calls.count());
    try std.testing.expectEqual(@as(usize, 0), session.specializations.plain_nominals.count());
}
test "portable semantic checkpoints outlive source owners and preserve inference through allocation failures" {
    const bytes = try makeCheckpoint();
    defer a.free(bytes);
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.emit(a, null);
    defer fresh.deinit(a);
    try importScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importScenario, .{ &fixture, bytes, fresh.bytes });
}
test "portable semantic checkpoints reject source settings and malformed semantic graph candidates" {
    const bytes = try makeCheckpoint();
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, archive.decode(a, @splat(18), bytes));
    var loaded = try archive.decode(a, compiler, bytes);
    defer loaded.deinit();
    const changed = try std.mem.replaceOwned(u8, a, source, "Box 2", "Box 0");
    defer a.free(changed);
    var fixture = try Fixture.init(changed);
    defer fixture.deinit();
    var fresh = try fixture.emit(a, null);
    defer fresh.deinit(a);
    var attempted = try fixture.emit(a, &loaded);
    defer attempted.deinit(a);
    try std.testing.expect(fresh.diagnostic != null);
    try std.testing.expectEqualDeep(fresh.diagnostic, attempted.diagnostic);
    try std.testing.expectEqual(@as(usize, 0), attempted.principal.persisted_hits);
    var matching = try Fixture.init(source);
    defer matching.deinit();
    const call = loaded.principal.snapshot.queries.records[0].dependencies.call_publications[0];
    loaded.principal.snapshot.evidence.nodes[call.evidence].a = std.math.maxInt(u32);
    var declined = try matching.emit(a, &loaded);
    defer declined.deinit(a);
    try std.testing.expect(declined.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), declined.principal.persisted_hits);
    try std.testing.expect(declined.principal.persisted_declines > 0);
}

fn nonemptyImport(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8, steps: usize) !void {
    var loaded = try archive.decode(allocator, compiler, bytes);
    defer loaded.deinit();
    var compiled = try fixture.emit(allocator, &loaded);
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.principal.persisted_nonempty_hits > 0);
    try std.testing.expectEqualSlices(u8, expected, compiled.bytes);
    try std.testing.expectEqual(steps, compiled.constant_steps);
}

test "portable principal results own inferred types and effect rows through restarts invalid inputs and allocation failures" {
    const row_source =
        \\entry const builder: U32 where { type_rep U32 } = do:
        \\  let local = fn value => value
        \\  break local 42
    ;
    const type_source =
        \\const from = fn value => @type.result "from" value
        \\const U32.from = fn value => @f32.to_u32 value
        \\const F32.from = fn value => @u32.to_f32 value
        \\const U32.add = fn left => fn right => @u32.add left right
        \\const F32.add = fn left => fn right => @f32.add left right
        \\const add = fn left => fn right => @type.call "add" left right
        \\const count = 10000
        \\entry const builder = add (from (@f32.ceil (@f32.sqrt (from count)))) 2
    ;
    for ([_][]const u8{ row_source, type_source }, 0..) |text, index| {
        const bytes = blk: {
            var initial = try Fixture.init(text);
            defer initial.deinit();
            var compiled = try initial.emit(a, null);
            defer compiled.deinit(a);
            try std.testing.expect(compiled.diagnostic == null);
            break :blk try archive.encode(a, compiler, &compiled.capture.?);
        };
        defer a.free(bytes);
        var fixture = try Fixture.init(text);
        defer fixture.deinit();
        var fresh = try fixture.emit(a, null);
        defer fresh.deinit(a);
        try nonemptyImport(a, &fixture, bytes, fresh.bytes, fresh.constant_steps);
        if (index == 0) try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nonemptyImport, .{ &fixture, bytes, fresh.bytes, fresh.constant_steps });
        var loaded = try archive.decode(a, compiler, bytes);
        defer loaded.deinit();
        for (loaded.principal.snapshot.queries.records) |*record| {
            if (index == 0 and record.result.rows.len != 0) @constCast(record.result.rows)[0].variable = std.math.maxInt(u32);
            if (index == 1 and record.result.types.len != 0) @constCast(record.result.types)[0].variable = std.math.maxInt(u32);
        }
        var declined = try fixture.emit(a, &loaded);
        defer declined.deinit(a);
        try std.testing.expect(declined.diagnostic == null);
        try std.testing.expectEqual(@as(usize, 0), declined.principal.persisted_nonempty_hits);
        try std.testing.expect(declined.principal.persisted_declines > 0);
        try std.testing.expectEqualSlices(u8, fresh.bytes, declined.bytes);
    }
}

const format = @import("dependency_format.zig");
fn implementationRestart(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8) !void {
    var loaded = try archive.decode(allocator, compiler, bytes);
    defer loaded.deinit();
    const before = @import("code_artifacts.zig").stamp(loaded.principal.snapshot);
    var actual = try fixture.emit(allocator, &loaded);
    defer actual.deinit(allocator);
    try std.testing.expect(actual.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, actual.bytes);
    try std.testing.expectEqualSlices(u8, &before, &@import("code_artifacts.zig").stamp(loaded.principal.snapshot));
}
test "implementation checkpoints reconstruct selected proofs after source owners die and equations change" {
    const original = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = U32, const first = fn value => value }\nimpl ArraySource a : Source (Array a) where { Source a } = { type Item = Source.Item a, const first = fn values => Source.first (@array.get values 0) }\nentry const answer: U32 = Source.first #[42]\n";
    const bytes = blk: {
        var initial = try Fixture.init(original);
        defer initial.deinit();
        var compiled = try initial.emit(a, null);
        defer compiled.deinit(a);
        try std.testing.expect(compiled.diagnostic == null);
        break :blk try archive.encode(a, compiler, &compiled.capture.?);
    };
    defer a.free(bytes);
    for ([_][]const u8{ original, "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = F32, const first = fn value => @u32.to_f32 value }\nimpl ArraySource a : Source (Array a) where { Source a } = { type Item = Source.Item a, const first = fn values => Source.first (@array.get values 0) }\nentry const answer: F32 = Source.first #[42]\n" }) |text| {
        var fixture = try Fixture.init(text);
        defer fixture.deinit();
        var fresh = try fixture.emit(a, null);
        defer fresh.deinit(a);
        try std.testing.expect(fresh.diagnostic == null);
        try implementationRestart(a, &fixture, bytes, fresh.bytes);
        if (std.mem.eql(u8, text, original)) try @import("../allocation_failures.zig").checkAllAllocationFailures(a, implementationRestart, .{ &fixture, bytes, fresh.bytes });
    }
}
const portable = @import("portable_query.zig");
const inputs = @import("principal_inputs.zig");
const evidence = @import("../eval/type_evidence.zig");
fn principalRejects(expected: anyerror, snapshot: principal.Snapshot) !void {
    const bytes = try format.encode(a, principal.wireKey(compiler), snapshot);
    defer a.free(bytes);
    try std.testing.expectError(expected, principal.decode(a, compiler, bytes));
}
fn principalAccepts(snapshot: principal.Snapshot) !void {
    const bytes = try format.encode(a, principal.wireKey(compiler), snapshot);
    defer a.free(bytes);
    var accepted = try principal.decode(a, compiler, bytes);
    accepted.deinit();
}
test "portable principal archives validate envelopes typed sections ordinals and graphs before exposure" {
    const checkpoint = try makeCheckpoint();
    defer a.free(checkpoint);
    var loaded = try archive.decode(a, compiler, checkpoint);
    defer loaded.deinit();
    const owner = loaded.principal.snapshot;
    try std.testing.expect(owner.queries.records.len > 0);
    const first = owner.queries.records[0];
    try std.testing.expect(first.dependencies.call_publications.len > 0);
    const bytes = try format.encode(a, principal.wireKey(compiler), owner);
    defer a.free(bytes);
    try principalAccepts(owner);
    try std.testing.expectError(error.StaleArtifact, principal.decode(a, @splat(18), bytes));
    {
        const older = try format.encode(a, .{ .compiler = compiler, .settings = format.digest("blot-principal-archive-v2"), .source = @splat(0), .dependencies = @splat(0) }, owner);
        defer a.free(older);
        try std.testing.expectError(error.StaleArtifact, principal.decode(a, compiler, older));
    }
    try std.testing.expectError(error.InvalidArtifact, principal.decode(a, compiler, bytes[0 .. bytes.len - 1]));
    {
        const copy = try a.dupe(u8, bytes);
        defer a.free(copy);
        copy[8] +%= 1; // envelope version
        try std.testing.expectError(error.UnsupportedVersion, principal.decode(a, compiler, copy));
        copy[8] -%= 1;
        copy[172] +%= 1; // payload length
        try std.testing.expectError(error.InvalidArtifact, principal.decode(a, compiler, copy));
        copy[172] -%= 1;
        copy[copy.len - 1] ^= 1; // integrity
        try std.testing.expectError(error.InvalidArtifact, principal.decode(a, compiler, copy));
    }
    {
        var copy = owner;
        copy.queries.header.version += 1;
        try principalRejects(error.UnsupportedVersion, copy);
        copy.queries.header = portable.header(.optimizer_output);
        try principalRejects(error.SchemaMismatch, copy);
        copy.queries.header = portable.header(.principal_complete_proof);
        copy.queries.header.schema += 1;
        try principalRejects(error.SchemaMismatch, copy);
        copy.queries.header = portable.header(.principal_complete_proof);
        copy.queries.header.kind = .refinement;
        try principalRejects(error.SchemaMismatch, copy);
    }
    var shape = [_]principal.Record{first};
    var copy = owner;
    copy.queries.records = &shape;
    try principalAccepts(copy);
    const nodes: u32 = @intCast(owner.evidence.nodes.len);
    const units: u32 = @intCast(owner.modules.len);
    const target = first.key.target;
    for ([_]core.BindingRef{ .{ .unit = 0, .binding = target.binding }, .{ .unit = units + 1, .binding = target.binding }, .{ .unit = target.unit, .binding = 0 } }) |forged| {
        shape[0] = first;
        shape[0].key.target = forged;
        try principalRejects(error.InvalidArtifact, copy);
    }
    shape[0] = first;
    {
        var mappings = [_]evidence.Mapping{ .{ .variable = 1, .evidence = 3 }, .{ .variable = 2, .evidence = 3 } };
        shape[0].result.types = &mappings;
        try principalAccepts(copy);
        mappings[1].variable = 1;
        try principalRejects(error.InvalidArtifact, copy);
        mappings[1] = .{ .variable = 0, .evidence = 3 };
        try principalRejects(error.InvalidArtifact, copy);
        mappings[1] = .{ .variable = 2, .evidence = nodes };
        try principalRejects(error.InvalidArtifact, copy);
        mappings[1] = .{ .variable = 2, .evidence = 0 };
        try principalRejects(error.InvalidArtifact, copy);
        shape[0] = first;
        const row_mappings = [_]evidence.RowMapping{.{ .variable = 0, .evidence = @intCast(owner.evidence.effects.rows.len) }};
        shape[0].result.rows = &row_mappings;
        try principalRejects(error.InvalidArtifact, copy);
        shape[0] = first;
    }
    {
        var reads = [_]inputs.ScalarRead{ .{ .target = target, .evidence = 3 }, .{ .target = target, .evidence = 3 } };
        shape[0].dependencies.scalar_reads = &reads;
        try principalRejects(error.InvalidArtifact, copy);
        shape[0].dependencies.scalar_reads = reads[0..1];
        try principalAccepts(copy);
        reads[0].evidence = @import("../check/types.zig").never + 1;
        try principalRejects(error.InvalidArtifact, copy);
        shape[0] = first;
    }
    {
        const key = (@as(u64, target.unit) << 32) | 1;
        var plain_reads = [_]inputs.PlainRead{.{ .key = key, .value = null }};
        const plain_publications = [_]inputs.PlainPublication{.{ .key = key, .value = true }};
        shape[0].dependencies.plain_publications = &plain_publications;
        shape[0].dependencies.plain_reads = &.{};
        // A publication without its observed prior state is missing a dependency.
        try principalRejects(error.InvalidArtifact, copy);
        shape[0].dependencies.plain_reads = &plain_reads;
        try principalAccepts(copy);
        const doubled = [_]inputs.PlainRead{ plain_reads[0], plain_reads[0] };
        shape[0].dependencies.plain_reads = &doubled;
        try principalRejects(error.InvalidArtifact, copy);
        // Builtin nominal keys lie outside the source image and stay admissible.
        const builtin = (@as(u64, std.math.maxInt(u32)) << 32) | 5;
        plain_reads[0].key = builtin;
        const builtin_publications = [_]inputs.PlainPublication{.{ .key = builtin, .value = true }};
        shape[0].dependencies.plain_reads = &plain_reads;
        shape[0].dependencies.plain_publications = &builtin_publications;
        try principalAccepts(copy);
        shape[0] = first;
    }
    {
        const original = first.dependencies.call_publications[0];
        var calls = [_]inputs.CallPublication{ original, original };
        shape[0].dependencies.call_publications = &calls;
        try principalRejects(error.InvalidArtifact, copy);
        shape[0].dependencies.call_publications = calls[0..1];
        for ([_]inputs.CallPublication{ .{ .target = original.target, .evidence = nodes }, .{ .target = original.target, .evidence = 0 }, .{ .target = .{ .unit = units + 1, .binding = 1 }, .evidence = original.evidence } }) |forged| {
            calls[0] = forged;
            try principalRejects(error.InvalidArtifact, copy);
        }
        shape[0] = first;
    }
    {
        const repeated = [_]principal.Record{ first, first };
        copy.queries.records = @constCast(&repeated);
        try principalRejects(error.InvalidArtifact, copy);
        copy.queries.records = &shape;
    }
    // Evidence edges point backward and stay in bounds; primitives are fixed.
    {
        const function = first.dependencies.call_publications[0].evidence;
        try std.testing.expectEqual(evidence.Tag.function, owner.evidence.nodes[function].tag);
        const forged = try a.dupe(evidence.Node, owner.evidence.nodes);
        defer a.free(forged);
        copy.evidence.nodes = forged;
        try principalAccepts(copy);
        forged[function].a = function;
        try principalRejects(error.InvalidArtifact, copy);
        forged[function] = owner.evidence.nodes[function];
        forged[function].c = @intCast(owner.evidence.effects.rows.len);
        try principalRejects(error.InvalidArtifact, copy);
        forged[function] = owner.evidence.nodes[function];
        forged[1].tag = .u32;
        try principalRejects(error.InvalidArtifact, copy);
        forged[1] = owner.evidence.nodes[1];
        copy.evidence.nodes = owner.evidence.nodes;
    }
    // Builtin nominal and operation identities use the reserved unit.
    {
        const builtin_unit = std.math.maxInt(u32);
        const grown_nodes = try a.alloc(evidence.Node, owner.evidence.nodes.len + 1);
        defer a.free(grown_nodes);
        @memcpy(grown_nodes[0..owner.evidence.nodes.len], owner.evidence.nodes);
        grown_nodes[owner.evidence.nodes.len] = .{ .tag = .nominal, .a = builtin_unit, .b = 5, .c = @intCast(owner.evidence.extra.len) };
        const extra = try a.alloc(u32, owner.evidence.extra.len + 1);
        defer a.free(extra);
        @memcpy(extra[0..owner.evidence.extra.len], owner.evidence.extra);
        extra[owner.evidence.extra.len] = 0;
        const Operation = @TypeOf(owner.evidence.effects.operations[0]);
        const operations = try a.alloc(Operation, owner.evidence.effects.operations.len + 1);
        defer a.free(operations);
        @memcpy(operations[0..owner.evidence.effects.operations.len], owner.evidence.effects.operations);
        operations[owner.evidence.effects.operations.len] = .{ .identity = .{ .unit = builtin_unit, .decl = 9000 }, .arguments = .{} };
        copy.evidence.nodes = grown_nodes;
        copy.evidence.extra = extra;
        copy.evidence.effects.operations = operations;
        try principalAccepts(copy);
        copy.evidence = owner.evidence;
    }
    {
        const rows = try a.dupe(@TypeOf(owner.evidence.effects.rows[0]), owner.evidence.effects.rows);
        defer a.free(rows);
        copy.evidence.effects.rows = rows;
        rows[0].len = 1;
        try principalRejects(error.InvalidArtifact, copy);
    }
}
