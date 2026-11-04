const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const identity = @import("../backend/runtime_identity.zig");
const a = std.testing.allocator;

const source =
    \\const twice = func f => return func x => return f (f x)
    \\const helper = func (x: U32) : U32 => return @u32.add x 1
    \\entry const apply = func (x: U32) : U32 => return twice helper x
    \\entry const adder = func (x: U32) : U32 => return do:
    \\  let add = func (y: U32) => return @u32.add y x
    \\  break twice add 3
    \\entry const edited = func (x: U32) : U32 => return @u32.add x 2
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
        for (checked.diagnostics) |issue| std.debug.print("cutoff fixture {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/cutoff/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const @import("artifact_capture.zig").Capture) !backend.Result {
        var result = try backend.compileWithOptions(allocator, self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous });
        errdefer result.deinit(allocator);
        if (result.diagnostic) |issue| std.debug.print("cutoff backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expect(result.diagnostic == null);
        return result;
    }
};

fn edited(from: []const u8, to: []const u8) ![]u8 {
    const text = try std.mem.replaceOwned(u8, a, source, from, to);
    try std.testing.expect(!std.mem.eql(u8, text, source));
    return text;
}
fn replayScenario(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: []const u8, hits: usize) !void {
    var result = try fixture.compile(allocator, &previous.capture.?);
    defer result.deinit(allocator);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expectEqual(hits, result.refinements.hits);
}

test "unchanged declarations in an edited module replay refinement receipts through allocation failures" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    // Exercise refinement replay when the optional whole-function fragment
    // index is unavailable; successful fragment reuse otherwise skips solving.
    initial.capture.?.executable_queries_complete = false;
    // A same-size body edit makes the module non-structural. Receipts rooted
    // in exactly equal declarations and their closures still replay.
    const text = try edited("@u32.add x 2", "@u32.add 2 x");
    defer a.free(text);
    var after = try Fixture.init(text);
    defer after.deinit();
    var fresh = try after.compile(a, null);
    defer fresh.deinit(a);
    var result = try after.compile(a, &initial.capture.?);
    defer result.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, result.bytes);
    try std.testing.expect(result.refinements.hits > 0);
    try std.testing.expect(result.refinements.body_cutoff_hits > 0);
    try std.testing.expect(result.refinements.collected_removed > 0);
    // Only the edited declaration's own receipt declines at its root.
    try std.testing.expect(result.refinements.reasons[@backingInt(@import("refinement_receipt.zig").Reason.root)] <= 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayScenario, .{ &after, &initial, fresh.bytes, result.refinements.hits });
}

test "a callee body edit with an unchanged interface keeps consumer receipts while executable callers rebuild" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    const text = try edited("@u32.add x 1", "@u32.add x 4");
    defer a.free(text);
    var after = try Fixture.init(text);
    defer after.deinit();
    var fresh = try after.compile(a, null);
    defer fresh.deinit(a);
    var result = try after.compile(a, &initial.capture.?);
    defer result.deinit(a);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, fresh.bytes));
    try std.testing.expectEqualSlices(u8, fresh.bytes, result.bytes);
    // Consumers of `helper` read only its unchanged interface and replay; a
    // region that collected its changed source declines, and every executable
    // caller of the changed body is regenerated.
    try std.testing.expect(result.refinements.hits > 0);
    try std.testing.expect(result.refinements.reasons[@backingInt(@import("refinement_receipt.zig").Reason.source)] > 0);
    // Both replay and fresh emission finish a metadata job as .complete;
    // prove executable invalidation through the actual target admission gate.
    var gate = try @import("code_body_validity.zig").Gate.init(a, &initial.capture.?.metadata.pools.?, after.units, after.names.view(), null);
    defer gate.deinit();
    try std.testing.expect(gate.semantic.enabled);
    var helper_declined = false;
    var apply_declined = false;
    var edited_reused = false;
    for (fresh.capture.?.metadata.jobs.items) |job| {
        if (job.request != .named) continue;
        const target = job.request.named.target;
        const body = after.units[target.unit - 1].body(target.binding).?;
        const spelling = text[body.span.start..body.span.end];
        if (std.mem.find(u8, spelling, "@u32.add x 4") != null) {
            try std.testing.expect(!gate.body(target));
            helper_declined = true;
        } else if (std.mem.find(u8, spelling, "twice helper x") != null) {
            try std.testing.expect(!gate.body(target));
            apply_declined = true;
        } else if (std.mem.find(u8, spelling, "@u32.add x 2") != null) {
            try std.testing.expect(gate.body(target));
            edited_reused = true;
        }
    }
    try std.testing.expect(helper_declined and apply_declined and edited_reused);
}
