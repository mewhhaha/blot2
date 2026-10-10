const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const checkpoint = @import("backend_checkpoint.zig");
const archive = @import("semantic_archive.zig");
const format = @import("dependency_format.zig");
const portable = @import("portable_query.zig");
const a = std.testing.allocator;
const compiler: [32]u8 = @splat(23);

// A captured callback specialized at a typed entry, a nominal payload and a
// recursive helper: the selected receipt replays the closure graph.
const source =
    \\type Box is data = #Box U32
    \\const open = fn (box: Box) -> U32 => case box of
    \\  #Box value => value
    \\const factory = fn number => fn extra => @u32.add number (open (#Box extra))
    \\const callback = factory 42
    \\const count = fn (n: U32) -> U32 => if @u32.eq n 0 then 0 else @u32.add 1 (count (@u32.sub n 1))
    \\entry const schema: U32 = 7
    \\entry const answer = fn (extra: U32) -> U32 => callback (@u32.add extra (count 3))
;
const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,
    fn init(text: []const u8) !Fixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| std.debug.print("semantic archive fixture {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/semantic/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, loaded: ?*const checkpoint.Checkpoint) !backend.Result {
        return backend.compileWithOptions(allocator, self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .checkpoint = loaded });
    }
};
fn successful(result: *const backend.Result) !void {
    if (result.diagnostic) |issue| std.debug.print("semantic archive backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
    try std.testing.expect(result.diagnostic == null);
}
/// The producer and its Core are released before decoding, as at restart.
fn produce(text: []const u8) ![]u8 {
    var before = try Fixture.init(text);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    try successful(&initial);
    try std.testing.expect(initial.capture.?.metadata.specialization_queries.records.items.len > 0);
    return checkpoint.encode(a, compiler, &initial.capture.?);
}
fn restartScenario(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8) !void {
    var loaded = try checkpoint.decode(allocator, compiler, bytes);
    defer loaded.deinit();
    try std.testing.expect(loaded.semantic != null);
    var restarted = try fixture.compile(allocator, &loaded);
    defer restarted.deinit(allocator);
    try successful(&restarted);
    try std.testing.expect(restarted.completed_queries.reused > 0);
    try std.testing.expectEqualSlices(u8, expected, restarted.bytes);
}

test "persisted semantic owners replay selected receipts after restart and match fresh output through allocation failures" {
    const bytes = try produce(source);
    defer a.free(bytes);
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
}

test "persisted semantic owners follow edited bodies and failed sources like fresh compilation" {
    const bytes = try produce(source);
    defer a.free(bytes);
    var loaded = try checkpoint.decode(a, compiler, bytes);
    defer loaded.deinit();
    for ([_][]const u8{ "#Box value => @u32.add value 1", "factory 43", "@u32.eq n 1" }) |replacement| {
        const anchor = if (std.mem.startsWith(u8, replacement, "#Box")) "#Box value => value" else if (std.mem.startsWith(u8, replacement, "factory")) "factory 42" else "@u32.eq n 0";
        const edited = try std.mem.replaceOwned(u8, a, source, anchor, replacement);
        defer a.free(edited);
        var fixture = try Fixture.init(edited);
        defer fixture.deinit();
        var fresh = try fixture.compile(a, null);
        defer fresh.deinit(a);
        try successful(&fresh);
        var restarted = try fixture.compile(a, &loaded);
        defer restarted.deinit(a);
        try successful(&restarted);
        try std.testing.expectEqualSlices(u8, fresh.bytes, restarted.bytes);
    }
    // A source that fails to compile reports the fresh diagnostic.
    const broken = try std.mem.replaceOwned(u8, a, source, "entry const schema: U32 = 7", "entry const schema: U32 = @u32.div 8 0");
    defer a.free(broken);
    var fixture = try Fixture.init(broken);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    var restarted = try fixture.compile(a, &loaded);
    defer restarted.deinit(a);
    try std.testing.expect(fresh.diagnostic != null);
    try std.testing.expectEqualDeep(fresh.diagnostic, restarted.diagnostic);
}

fn rejects(expected: anyerror, snapshot: archive.Snapshot) !void {
    const bytes = try format.encodeWithLimits(a, archive.wireKey(compiler), snapshot, archive.limits);
    defer a.free(bytes);
    try std.testing.expectError(expected, archive.decode(a, compiler, bytes));
}
fn accepts(snapshot: archive.Snapshot) !void {
    const bytes = try format.encodeWithLimits(a, archive.wireKey(compiler), snapshot, archive.limits);
    defer a.free(bytes);
    var owner = try archive.decode(a, compiler, bytes);
    owner.deinit();
}

test "persisted semantic owners reject forged namespaces graphs ordinals and receipts before exposure" {
    const bytes = blk: {
        var before = try Fixture.init(source);
        defer before.deinit();
        var initial = try before.compile(a, null);
        defer initial.deinit(a);
        try successful(&initial);
        break :blk (try archive.encode(a, compiler, &initial.capture.?)).?;
    };
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, archive.decode(a, @splat(24), bytes));
    try std.testing.expectError(error.InvalidArtifact, archive.decode(a, compiler, bytes[0 .. bytes.len - 1]));
    var owner = try format.decodeWithLimits(archive.Snapshot, a, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &owner);
    try accepts(owner);
    {
        var copy = owner;
        copy.queries.header.version += 1;
        try rejects(error.UnsupportedVersion, copy);
        copy.queries.header = portable.header(.principal_complete_proof);
        try rejects(error.SchemaMismatch, copy);
    }
    const unit = owner.units[0];
    var units = [_]archive.Unit{unit};
    var copy = owner;
    copy.units = &units;
    {
        var path = "/semantic/other.blot".*;
        units[0].canonical_path = &path;
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
        units[0].unit = 2;
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
        var short = [_]u32{1};
        units[0].certificates = &short;
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
        units[0].core.bindings = &.{};
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
    }
    const evaluator = owner.evaluator;
    {
        const children = try a.dupe(u32, evaluator.children);
        defer a.free(children);
        try std.testing.expect(children.len != 0);
        copy.evaluator.children = children;
        children[0] = @intCast(evaluator.values.len);
        try rejects(error.InvalidArtifact, copy);
        copy.evaluator = evaluator;
        const values = try a.dupe(@TypeOf(evaluator.values[0]), evaluator.values);
        defer a.free(values);
        copy.evaluator.values = values;
        for (values) |*value| if (value.kind == .closure) {
            value.bits = @intCast(evaluator.closures.len);
            break;
        };
        try rejects(error.InvalidArtifact, copy);
        copy.evaluator = evaluator;
    }
    {
        try std.testing.expect(owner.slots.len > 1);
        copy.slots = owner.slots[0 .. owner.slots.len - 1];
        try rejects(error.InvalidArtifact, copy);
        const slots = try a.dupe(@TypeOf(owner.slots[0]), owner.slots);
        defer a.free(slots);
        slots[0].value = @intCast(evaluator.values.len);
        copy.slots = slots;
        try rejects(error.InvalidArtifact, copy);
        copy.slots = owner.slots;
    }
    {
        try std.testing.expect(owner.queries.records.len > 0);
        const first = owner.queries.records[0];
        var records = [_]archive.Record{first};
        copy.queries.records = &records;
        try accepts(copy);
        records[0].key.input = 0;
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        records[0].key.expected = 1;
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        records[0].result.selected = @intCast(evaluator.values.len);
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        const forged = [_]core.BindingRef{.{ .unit = 2, .binding = 1 }};
        records[0].dependencies.sources = @constCast(&forged);
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        records[0].dependencies.values_added = evaluator.values.len + 1;
        try rejects(error.InvalidArtifact, copy);
        copy.queries.records = owner.queries.records;
    }
    if (owner.field_locations.len != 0) {
        const fields = try a.dupe(@TypeOf(owner.field_locations[0]), owner.field_locations);
        defer a.free(fields);
        fields[0].name = @intCast(owner.identity.symbols.len);
        copy.field_locations = fields;
        try rejects(error.InvalidArtifact, copy);
        copy.field_locations = owner.field_locations;
    }
}

test "persisted semantic owners with a forged stamp decode but admit no receipt" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    try successful(&initial);
    const bytes = (try archive.encode(a, compiler, &initial.capture.?)).?;
    defer a.free(bytes);
    var owner = try format.decodeWithLimits(archive.Snapshot, a, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &owner);
    owner.units[0].stamp[0] ^= 1;
    const forged = try format.encodeWithLimits(a, archive.wireKey(compiler), owner, archive.limits);
    defer a.free(forged);
    var semantic = try archive.decode(a, compiler, forged);
    var loaded: checkpoint.Checkpoint = .{ .principal = .{ .allocator = a, .snapshot = .{ .modules = &.{}, .namespace = @splat(0), .queries = .{ .header = portable.header(.principal_complete_proof), .records = &.{} }, .evidence = emptyEvidence() } }, .optimizer = null, .semantic = semantic };
    semantic = undefined;
    defer loaded.semantic.?.deinit();
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    var restarted = try fixture.compile(a, &loaded);
    defer restarted.deinit(a);
    try successful(&restarted);
    try std.testing.expectEqual(@as(usize, 0), restarted.completed_queries.reused);
    try std.testing.expectEqualSlices(u8, fresh.bytes, restarted.bytes);
}
fn emptyEvidence() @import("type_evidence.zig").Snapshot {
    return .{ .nodes = &.{}, .extra = &.{}, .effects = .{ .operations = &.{}, .arguments = &.{}, .rows = &.{}, .labels = &.{} } };
}

test "semantic archives omit owners without a complete project namespace or a replayable receipt" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var anonymous = try backend.compileWithOptions(a, fixture.units, 1, .{ .retain_artifacts = true });
    defer anonymous.deinit(a);
    try successful(&anonymous);
    try std.testing.expect((try archive.encode(a, compiler, &anonymous.capture.?)) == null);
    var plain = try Fixture.init("entry const answer = fn (x: U32) -> U32 => @u32.add x 1");
    defer plain.deinit();
    var compiled = try plain.compile(a, null);
    defer compiled.deinit(a);
    try successful(&compiled);
    try std.testing.expectEqual(@as(usize, 0), compiled.capture.?.metadata.specialization_queries.records.items.len);
    try std.testing.expect((try archive.encode(a, compiler, &compiled.capture.?)) == null);
    const bytes = try checkpoint.encode(a, compiler, &compiled.capture.?);
    defer a.free(bytes);
    var loaded = try checkpoint.decode(a, compiler, bytes);
    defer loaded.deinit();
    try std.testing.expect(loaded.semantic == null);
}
