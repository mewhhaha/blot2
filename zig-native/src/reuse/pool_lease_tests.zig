const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const identity = @import("../backend/runtime_identity.zig");
const pool_leases = @import("../eval/pool_leases.zig");
const memory = @import("../runtime/memory.zig");
const a = std.testing.allocator;

const source =
    \\type Box is data = #Box U32
    \\const open = func (box: Box) : U32 => return case box of
    \\  #Box value => value
    \\const factory = func number => return func extra => return @u32.add number (open (#Box extra))
    \\const callback = factory 42
    \\entry const schema: U32 = 7
    \\entry const answer = func (extra: U32) : U32 => return callback (@u32.add extra 1)
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
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/leases/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const @import("artifact_capture.zig").Capture) !backend.Result {
        var result = try backend.compileWithOptions(allocator, self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous });
        errdefer result.deinit(allocator);
        if (result.diagnostic) |issue| std.debug.print("lease fixture {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expect(result.diagnostic == null);
        return result;
    }
};
fn pools(result: *const backend.Result) *const @import("code_artifacts.zig").Pools {
    return &result.capture.?.metadata.pools.?;
}

test "artifact pools lease unchanged fields from the previous revision and copy changed ones" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var second: backend.Result = undefined;
    var spelling: []u8 = undefined;
    {
        var first = try fixture.compile(a, null);
        defer first.deinit(a);
        try std.testing.expectEqual(@as(u64, 0), first.counters.metadata_shared_fields);
        try std.testing.expect(first.counters.metadata_copied_fields > 0);
        second = try fixture.compile(a, &first.capture.?);
        errdefer second.deinit(a);
        try std.testing.expect(second.counters.metadata_shared_fields > 0);
        try std.testing.expectEqualSlices(u8, first.bytes, second.bytes);
        const old = pools(&first);
        const new = pools(&second);
        try expectSharedExactlyWhenEqual(old, new);
        try std.testing.expectEqual(old.identity.?.bytes.ptr, new.identity.?.bytes.ptr);
        try std.testing.expectEqual(@as(usize, 2), old.leases.get(.identity_bytes).?.references);
        spelling = try a.dupe(u8, new.identity.?.bytes);
    }
    defer second.deinit(a);
    defer a.free(spelling);
    // The earlier revision was released first; the shared blocks survive.
    const new = pools(&second);
    try std.testing.expectEqual(@as(usize, 1), new.leases.get(.identity_bytes).?.references);
    try std.testing.expectEqualSlices(u8, spelling, new.identity.?.bytes);
}
fn field(owner: *const @import("code_artifacts.zig").Pools, comptime which: pool_leases.Field) []const u8 {
    const value = switch (which) {
        .identity_bytes => owner.identity.?.bytes,
        .identity_symbols => std.mem.sliceAsBytes(owner.identity.?.symbols),
        .identity_owners => std.mem.sliceAsBytes(owner.identity.?.owners),
        .layout_nodes => std.mem.sliceAsBytes(owner.layouts.nodes),
        .layout_extra => std.mem.sliceAsBytes(owner.layouts.extra),
        .layout_operations => std.mem.sliceAsBytes(owner.layouts.effects.operations),
        .layout_arguments => std.mem.sliceAsBytes(owner.layouts.effects.arguments),
        .layout_rows => std.mem.sliceAsBytes(owner.layouts.effects.rows),
        .layout_labels => std.mem.sliceAsBytes(owner.layouts.effects.labels),
        .layout_universal_dictionaries => std.mem.sliceAsBytes(owner.layouts.universal_dictionaries),
        .evidence_nodes => std.mem.sliceAsBytes(owner.evaluator.evidence.nodes),
        .evidence_extra => std.mem.sliceAsBytes(owner.evaluator.evidence.extra),
        .evidence_operations => std.mem.sliceAsBytes(owner.evaluator.evidence.effects.operations),
        .evidence_arguments => std.mem.sliceAsBytes(owner.evaluator.evidence.effects.arguments),
        .evidence_rows => std.mem.sliceAsBytes(owner.evaluator.evidence.effects.rows),
        .evidence_labels => std.mem.sliceAsBytes(owner.evaluator.evidence.effects.labels),
        .evidence_quantifier_goals => std.mem.sliceAsBytes(owner.evaluator.evidence.quantifier_goals),
        .evidence_quantifier_obligations => std.mem.sliceAsBytes(owner.evaluator.evidence.quantifier_obligations),
        .implementation_proofs => std.mem.sliceAsBytes(owner.evaluator.implementation_proofs.proofs),
        .implementation_arguments => std.mem.sliceAsBytes(owner.evaluator.implementation_proofs.arguments),
        .implementation_members => std.mem.sliceAsBytes(owner.evaluator.implementation_proofs.members),
        .implementation_edges => std.mem.sliceAsBytes(owner.evaluator.implementation_proofs.edges),
        .code_origins, .values, .children, .closures, .value_evidence, .type_mappings, .row_mappings, .value_records, .record_layouts, .field_names, .demands => std.mem.sliceAsBytes(@field(owner.evaluator, @tagName(which))),
        else => std.mem.sliceAsBytes(@field(owner, @tagName(which))),
    };
    return value;
}
/// Every nonempty leased field is shared exactly when its content is equal.
/// Byte equality suffices here: both owners were filled field by field.
fn expectSharedExactlyWhenEqual(old: *const @import("code_artifacts.zig").Pools, new: *const @import("code_artifacts.zig").Pools) !void {
    inline for (@typeInfo(pool_leases.Field).@"enum".field_names) |name| {
        const which = @field(pool_leases.Field, name);
        const before = field(old, which);
        const after = field(new, which);
        if (before.len != 0 and after.len != 0) {
            const same = before.ptr == after.ptr;
            if (same != std.mem.eql(u8, before, after)) {
                std.debug.print("lease field {s}: shared {any}\n", .{ name, same });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "artifact pools copy fields whose content changes and keep unchanged leases" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var first = try fixture.compile(a, null);
    defer first.deinit(a);
    const edited_source = try std.mem.replaceOwned(u8, a, source, "factory 42", "factory 43");
    defer a.free(edited_source);
    var edited = try Fixture.init(edited_source);
    defer edited.deinit();
    var second = try edited.compile(a, &first.capture.?);
    defer second.deinit(a);
    var fresh = try edited.compile(a, null);
    defer fresh.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, second.bytes);
    const old = pools(&first);
    const new = pools(&second);
    try expectSharedExactlyWhenEqual(old, new);
    // The captured constant changes; the namespace does not.
    try std.testing.expect(!@import("../structural.zig").equal(old.evaluator.values, new.evaluator.values));
    try std.testing.expect(old.evaluator.values.ptr != new.evaluator.values.ptr);
    try std.testing.expectEqual(old.identity.?.symbols.ptr, new.identity.?.symbols.ptr);
    try std.testing.expect(second.counters.metadata_copied_fields > 0);
    // Shared and copied content equals a fresh capture of the same source.
    try std.testing.expect(@import("../structural.zig").equal(pools(&fresh).evaluator.values, new.evaluator.values));
    try std.testing.expect(@import("../structural.zig").equal(pools(&fresh).slots, new.slots));
    try std.testing.expect(@import("../structural.zig").equal(pools(&fresh).functions, new.functions));
}

fn leasedCapture(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result) !void {
    var second = try fixture.compile(allocator, &previous.capture.?);
    defer second.deinit(allocator);
    try std.testing.expect(second.counters.metadata_shared_fields > 0);
}
test "failed captures release every lease they took and leave the previous counts unchanged" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var first = try fixture.compile(a, null);
    defer first.deinit(a);
    const old = pools(&first);
    try leasedCapture(a, &fixture, &first);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, leasedCapture, .{ &fixture, &first });
    for (old.leases.values) |lease| if (lease) |owned| try std.testing.expectEqual(@as(usize, 1), owned.references);
}

test "repeated edits keep leased pool storage bounded" {
    var tracked: memory.TrackedAllocator = .{ .backing = a };
    const allocator = tracked.allocator();
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    const edited_source = try std.mem.replaceOwned(u8, a, source, "factory 42", "factory 43");
    defer a.free(edited_source);
    var edited = try Fixture.init(edited_source);
    defer edited.deinit();
    {
        var current = try fixture.compile(allocator, null);
        defer current.deinit(allocator);
        var plateau: ?usize = null;
        for (0..12) |round| {
            const chosen = if (round % 2 == 0) &edited else &fixture;
            const next = try chosen.compile(allocator, &current.capture.?);
            current.deinit(allocator);
            current = next;
            if (round == 3) plateau = tracked.counts.live_bytes;
            if (round > 3 and round % 2 == 1) try std.testing.expectEqual(plateau.?, tracked.counts.live_bytes);
        }
    }
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

test "lease builders count shared and copied fields" {
    var first: pool_leases.Builder = .{ .allocator = a, .previous = null };
    defer first.abort();
    _ = try first.dupe(.break_values, u32, &.{ 1, 2 }, null);
    try std.testing.expectEqual(@as(usize, 8), first.stats.copied_bytes);
}
