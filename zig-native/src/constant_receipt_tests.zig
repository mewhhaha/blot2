const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const a = std.testing.allocator;

const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,
    fn init(source: []const u8) !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/constant-receipts/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const backend.Result, enabled: bool) !backend.Result {
        return self.compileLimited(allocator, previous, enabled, .{});
    }
    fn compileLimited(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const backend.Result, enabled: bool, limits: @FieldType(backend.CompileOptions, "constant_limits")) !backend.Result {
        var options: backend.CompileOptions = .{ .identity = self.names.view(), .retain_artifacts = true, .constant_receipts = enabled, .constant_limits = limits };
        if (previous) |old| options.previous = &old.capture.?;
        return backend.compileWithOptions(allocator, self.units, 1, options);
    }
};
fn makeSource(seed: []const u8, input: []const u8) ![]u8 {
    var expression = try a.dupe(u8, input);
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const seed = {s}\nconst expensive = {s}\nentry const run = fn (value: U32) => @u32.add value (@u32.add expensive seed)\n", .{ seed, expression });
}
fn replay(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, hits: usize) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    if (hits != result.constant_receipts.reused) std.debug.print("CONSTANT_RECEIPT_DECLINE {any} records={d} steps={d}\n", .{ result.constant_receipts, previous.capture.?.metadata.pools.?.constant_records.len, result.constant_steps });
    try std.testing.expectEqual(hits, result.constant_receipts.reused);
    try std.testing.expectEqual(hits, result.constant_receipts.scalar_reused);
}

test "constant receipts publish unchanged expensive scalars with exact fuel and OOM ownership" {
    const original = try makeSource("2", "1");
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.capture.?.metadata.pools.?.constant_records.len != 0);
    const edited = try makeSource("3", "1");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var fresh = try after.compile(a, null, false);
    defer fresh.deinit(a);
    try std.testing.expect(fresh.diagnostic == null);
    try replay(a, &after, &initial, &fresh, 1);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, replay, .{ &after, &initial, &fresh, @as(usize, 1) });
    const changed_read = try makeSource("3", "seed");
    defer a.free(changed_read);
    var changed = try Fixture.init(changed_read);
    defer changed.deinit();
    var expected = try changed.compile(a, null, false);
    defer expected.deinit(a);
    try replay(a, &changed, &initial, &expected, 0);
    const input_source = try makeSource("2", "seed");
    defer a.free(input_source);
    var input_before = try Fixture.init(input_source);
    defer input_before.deinit();
    var input_initial = try input_before.compile(a, null, true);
    defer input_initial.deinit(a);
    try std.testing.expect(input_initial.capture.?.metadata.pools.?.constant_records.len != 0);
    // This initializer is unchanged: its actual scalar read alone changed.
    try replay(a, &changed, &input_initial, &expected, 0);
    try replay(a, &after, &initial, &fresh, 1);
}

fn appendType(fixture: *Fixture, node: @import("types.zig").Node) !void {
    const old = fixture.units[0].types.nodes;
    const nodes = try a.alloc(@import("types.zig").Node, old.len + 1);
    @memcpy(nodes[0..old.len], old);
    nodes[old.len] = node;
    a.free(old);
    fixture.units[0].types.nodes = nodes;
}

fn graphSource(seed: []const u8, sibling: []const u8) ![]u8 {
    var expression = try a.dupe(u8, "1");
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print(
        \\entry const seed = {s}
        \\const first = #[{s}, 11]
        \\const middle = #[@u32.add seed ({s}), seed]
        \\const last = #[{s}, 12]
        \\entry const run = fn () => @u32.add seed (@u32.add (@array.get first 0) (@u32.add (@array.get middle 0) (@array.get last 0)))
        \\entry const sibling = {s}
        \\
    , .{ seed, expression, expression, expression, sibling });
}
fn replayGraphs(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, hits: usize) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expectEqual(hits, result.constant_receipts.reused);
    try std.testing.expectEqual(@as(usize, 0), result.constant_receipts.scalar_reused);
    try std.testing.expect(result.constant_receipts.graph_index_bytes > 0);
}
test "constant receipts reset shared graph scratch after hits misses and allocation failure" {
    const original = try graphSource("2", "1");
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    for ([_][]const u8{ "2", "3" }, [_]usize{ 3, 2 }) |seed, hits| {
        const source = try graphSource(seed, "2");
        defer a.free(source);
        var after = try Fixture.init(source);
        defer after.deinit();
        var fresh = try after.compile(a, null, false);
        defer fresh.deinit(a);
        try replayGraphs(a, &after, &initial, &fresh, hits);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &fresh, hits });
        // Failure sweeps leave the immutable producer available for retry.
        try replayGraphs(a, &after, &initial, &fresh, hits);
    }
}

test "constant receipts prove duplicate closed type tails and reject forged tails" {
    const original = try makeSource("2", "1");
    defer a.free(original);
    const edited = try makeSource("3", "1");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var fresh = try after.compile(a, null, false);
    defer fresh.deinit(a);
    for (0..3) |variant| {
        var before = try Fixture.init(original);
        defer before.deinit();
        var node = before.units[0].types.nodes[@import("types.zig").u32_type];
        if (variant == 1) node = .{ .tag = .array, .a = @import("types.zig").u32_type };
        if (variant == 2) node = .{ .tag = .u32, .a = 99 };
        try appendType(&before, node);
        var initial = try before.compile(a, null, true);
        defer initial.deinit(a);
        // A malformed old graph may decline capture, but it cannot gain an
        // initializer, slot or portable type authority on the next revision.
        if (initial.capture == null) {
            try std.testing.expectEqual(@as(usize, 2), variant);
            try std.testing.expect(initial.diagnostic != null);
            continue;
        }
        var hits: usize = 0;
        if (variant == 0) hits = 1;
        try replay(a, &after, &initial, &fresh, hits);
    }
}

fn resourceParity(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, limits: @FieldType(backend.CompileOptions, "constant_limits")) !void {
    var result = try fixture.compileLimited(allocator, previous, true, limits);
    defer result.deinit(allocator);
    try std.testing.expectEqualDeep(expected.diagnostic, result.diagnostic);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    if (limits.steps == 220 or limits.values == 200) try std.testing.expect(result.constant_receipts.reused != 0);
}

test "constant receipts preserve tight source and allocation limits after a hit" {
    const original = try makeSource("2", "1");
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var seed = try a.dupe(u8, "3");
    defer a.free(seed);
    for (0..40) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{seed});
        a.free(seed);
        seed = next;
    }
    const start = std.mem.find(u8, original, "const expensive = ").?;
    const end = std.mem.find(u8, original[start..], "\n").? + start;
    const initializer = original[start..end];
    const conditional = try a.print("const flag = 0\n{s}\nconst seed = if @u32.eq flag 0 then 3 else {s}\nentry const run = fn (value: U32) => @u32.add value (@u32.add expensive seed)\n", .{ initializer, seed });
    defer a.free(conditional);
    const edited = try a.dupe(u8, conditional);
    defer a.free(edited);
    edited["const flag = ".len] = '1';
    var limit_before = try Fixture.init(conditional);
    defer limit_before.deinit();
    var after = try Fixture.init(edited);
    defer after.deinit();
    const Limits = @FieldType(backend.CompileOptions, "constant_limits");
    for ([_]Limits{ .{ .steps = 220 }, .{ .values = 200 } }) |limits| {
        var initial = try limit_before.compileLimited(a, null, true, limits);
        defer initial.deinit(a);
        try std.testing.expect(initial.diagnostic == null);
        var expected = try after.compileLimited(a, null, false, limits);
        defer expected.deinit(a);
        try std.testing.expect(expected.diagnostic != null);
        try resourceParity(a, &after, &initial, &expected, limits);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, resourceParity, .{ &after, &initial, &expected, limits });
    }
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    for ([_]Limits{ .{ .steps = 80 }, .{ .values = 80 }, .{ .depth = 40 } }) |limits| {
        var expected = try before.compileLimited(a, null, false, limits);
        defer expected.deinit(a);
        try std.testing.expect(expected.diagnostic != null);
        try resourceParity(a, &before, &initial, &expected, limits);
    }
}

test "constant receipts invalidate executed closed callees and retain ordinary call depth" {
    const expression_source = try makeSource("2", "value");
    defer a.free(expression_source);
    const start = std.mem.find(u8, expression_source, "const expensive = ").? + "const expensive = ".len;
    const end = std.mem.find(u8, expression_source[start..], "\n").? + start;
    const source = try a.print("const seed = 2\nconst helper: U32 -> U32 = fn (value: U32) => {s}\nconst expensive = helper 1\nentry const run = fn (value: U32) => @u32.add value (@u32.add expensive seed)\n", .{expression_source[start..end]});
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.constant_receipts.recorded != 0);
    const sibling = try a.dupe(u8, source);
    defer a.free(sibling);
    sibling["const seed = ".len] = '3';
    var same = try Fixture.init(sibling);
    defer same.deinit();
    var fresh = try same.compile(a, null, false);
    defer fresh.deinit(a);
    try replay(a, &same, &initial, &fresh, 1);
    const called = try a.dupe(u8, sibling);
    defer a.free(called);
    const operation = std.mem.find(u8, called, "@u32.add 1").?;
    called[operation + "@u32.add ".len] = '2';
    var changed = try Fixture.init(called);
    defer changed.deinit();
    var expected = try changed.compile(a, null, false);
    defer expected.deinit(a);
    try replay(a, &changed, &initial, &expected, 0);
    const limits: @FieldType(backend.CompileOptions, "constant_limits") = .{ .calls = 0 };
    var limited = try before.compileLimited(a, null, false, limits);
    defer limited.deinit(a);
    try std.testing.expect(limited.diagnostic != null);
    try resourceParity(a, &before, &initial, &limited, limits);
}

test "constant receipts retain value work after the ordinary principal prepass" {
    const plain = try makeSource("2", "1");
    defer a.free(plain);
    const qualified = try std.mem.replaceOwned(u8, a, plain, "const expensive =", "const expensive: U32 where { type_rep U32 } = do:\n  let local = fn value => value\n  return");
    defer a.free(qualified);
    var before = try Fixture.init(qualified);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.principal.requests != 0);
    try std.testing.expect(initial.constant_receipts.recorded != 0);
    const captured = &initial.capture.?.metadata.pools.?.constant_records[0];
    try std.testing.expect(captured.inputs.types.len != 0 or captured.inputs.rows.len != 0);
    const edited = try a.dupe(u8, qualified);
    defer a.free(edited);
    edited["const seed = ".len] = '3';
    var after = try Fixture.init(edited);
    defer after.deinit();
    var expected = try after.compile(a, null, false);
    defer expected.deinit(a);
    try replay(a, &after, &initial, &expected, 1);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, replay, .{ &after, &initial, &expected, @as(usize, 1) });
    var retained = try after.compile(a, &initial, true);
    defer retained.deinit(a);
    try std.testing.expect(retained.principal.requests != 0);
    try std.testing.expectEqual(retained.principal.requests, expected.principal.requests);
    var ordinary_retained = try after.compile(a, &initial, false);
    defer ordinary_retained.deinit(a);
    try std.testing.expectEqual(retained.principal.fresh_regions, ordinary_retained.principal.fresh_regions);
    // These are owned solved inputs, not authority to name arbitrary old
    // solver variables. A forged binder must take ordinary value evaluation.
    if (captured.inputs.types.len != 0) {
        const mappings = @constCast(captured.inputs.types);
        const saved = mappings[0];
        defer mappings[0] = saved;
        mappings[0].variable = 0;
        try replay(a, &after, &initial, &expected, 0);
    } else {
        const mappings = @constCast(captured.inputs.rows);
        const saved = mappings[0];
        defer mappings[0] = saved;
        mappings[0].variable = std.math.maxInt(u32);
        try replay(a, &after, &initial, &expected, 0);
    }
}

fn memberReplay(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expect(result.completed_queries.reused != 0);
}

fn memberSource(sibling: []const u8) ![]u8 {
    var expression = try a.dupe(u8, "@array.length values");
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 0 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const Array.count = fn values => {s}\nentry const warm: U32 = #[].count\nentry const result: U32 = #[].count\nentry const sibling = {s}\n", .{ expression, sibling });
}

test "constant receipt array member judgments own ready methods and publications" {
    const original_source = try memberSource("1");
    defer a.free(original_source);
    var before = try Fixture.init(original_source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), initial.capture.?.metadata.specialization_queries.records.items.len);
    const edited_source = try memberSource("2");
    defer a.free(edited_source);
    var after = try Fixture.init(edited_source);
    defer after.deinit();
    var expected = try after.compile(a, null, false);
    defer expected.deinit(a);
    try memberReplay(a, &after, &initial, &expected);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, memberReplay, .{ &after, &initial, &expected });
    var changed = try Fixture.init("const Array.count = fn values => @u32.add 1 (@array.length values)\nentry const warm: U32 = #[].count\nentry const result: U32 = #[].count\nentry const sibling = 2\n");
    defer changed.deinit();
    var ordinary = try changed.compile(a, null, false);
    defer ordinary.deinit(a);
    var retained = try changed.compile(a, &initial, true);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, ordinary.bytes, retained.bytes);
    try std.testing.expectEqual(ordinary.constant_steps, retained.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), retained.completed_queries.reused);
    const member = initial.capture.?.metadata.specialization_queries.records.items[0].dependencies.member.?;
    {
        const before_budget = member.query_budgets[0];
        defer member.query_budgets[0] = before_budget;
        member.query_budgets[0] +|= 1;
        var budget_decline = try after.compile(a, &initial, true);
        defer budget_decline.deinit(a);
        try std.testing.expectEqualSlices(u8, expected.bytes, budget_decline.bytes);
        try std.testing.expectEqual(expected.constant_steps, budget_decline.constant_steps);
        try std.testing.expectEqual(@as(usize, 0), budget_decline.completed_queries.member_reused);
    }
}

fn compoundSource(sibling: []const u8) ![]u8 {
    var expression = try a.dupe(u8, "1");
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const compound = #[{{ value: {s} }}]\nentry const owned = fn () => @array.length compound\nentry const sibling = {s}\n", .{ expression, sibling });
}
test "constant receipts decline compound graph results with ordinary bytes and fuel" {
    const original = try compoundSource("1");
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), initial.capture.?.metadata.pools.?.constant_records.len);
    const edit = try compoundSource("2");
    defer a.free(edit);
    var after = try Fixture.init(edit);
    defer after.deinit();
    var ordinary = try after.compile(a, null, false);
    defer ordinary.deinit(a);
    try replay(a, &after, &initial, &ordinary, 0);
}

fn smallScalarSource(sibling: []const u8) ![]u8 {
    var expression = try a.dupe(u8, "1");
    defer a.free(expression);
    for (0..52) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const small = {s}\nentry const run = fn () => small\nentry const sibling = {s}\n", .{ expression, sibling });
}
fn smallScalarReplay(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), result.constant_receipts.lookups);
    try std.testing.expectEqual(@as(usize, 0), result.constant_receipts.recorded);
    try std.testing.expectEqual(@as(usize, 0), result.constant_receipts.owned_payload_bytes);
}
test "constant receipts keep 105-step scalars ordinary without provider bookkeeping and OOM" {
    const source = try smallScalarSource("1");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), initial.capture.?.metadata.pools.?.constant_records.len);
    const edited = try smallScalarSource("2");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var ordinary = try after.compile(a, null, false);
    defer ordinary.deinit(a);
    try smallScalarReplay(a, &after, &initial, &ordinary);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, smallScalarReplay, .{ &after, &initial, &ordinary });
    const receipt = @import("constant_receipt.zig");
    const work = [_]receipt.Event{.{ .work = .{ .steps = 105 } }};
    const old = [_]receipt.Record{.{ .target = .{ .unit = 1, .binding = 1 }, .value = 0, .options = .{}, .events = @constCast(&work), .sources = &.{} }};
    try std.testing.expect(!receipt.hasProductiveRecord(&old, receipt.minimum_steps));
}

fn enclosingSource(sibling: []const u8, seed: []const u8, delta: []const u8, receiver: []const u8, second: bool) ![]u8 {
    var method = try a.dupe(u8, "@u32.add seed (@array.length values)");
    defer a.free(method);
    var expression = try a.print("{s}.count", .{receiver});
    defer a.free(expression);
    for (0..80) |_| {
        const next_method = try a.print("@u32.add {s} ({s})", .{ delta, method });
        a.free(method);
        method = next_method;
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    const loop_method = try a.print("do:\n  let total = ({s})\n  for index in 0..128:\n    total := @u32.add self 1\n  return total", .{method});
    a.free(method);
    method = loop_method;
    if (second) {
        const next = try a.print("@u32.add (#[].count) ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const seed = {s}\nconst Array.count = fn values => {s}\nentry const warm: U32 = #[].count\nentry const enclosing: U32 = {s}\nentry const sibling = {s}\n", .{ seed, method, expression, sibling });
}
fn enclosingReplay(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expectEqual(@as(usize, 1), result.constant_receipts.member_replayed);
}

fn enclosingFresh(allocator: std.mem.Allocator, fixture: *const Fixture, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, null, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expectEqual(@as(usize, 1), result.constant_receipts.member_recorded);
}

test "enclosing constant member judgment owns fresh and retained authority with OOM rollback" {
    const original = try enclosingSource("1", "2", "0", "#[]", false);
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), initial.constant_receipts.member_recorded);
    const edited = try enclosingSource("2", "2", "0", "#[]", false);
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var ordinary = try after.compile(a, null, false);
    defer ordinary.deinit(a);
    try enclosingFresh(a, &after, &ordinary);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, enclosingFresh, .{ &after, &ordinary });
    try enclosingReplay(a, &after, &initial, &ordinary);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, enclosingReplay, .{ &after, &initial, &ordinary });
    var retained = try after.compile(a, &initial, true);
    defer retained.deinit(a);
    try enclosingReplay(a, &after, &retained, &ordinary);
    inline for (.{
        .{ "2", "3", "0", "#[]", false },
        .{ "2", "2", "1", "#[]", false },
        .{ "2", "2", "0", "#[1]", false },
        .{ "2", "2", "0", "#[]", true },
    }) |change| {
        const text = try enclosingSource(change[0], change[1], change[2], change[3], change[4]);
        defer a.free(text);
        var fixture = try Fixture.init(text);
        defer fixture.deinit();
        var fresh = try fixture.compile(a, null, false);
        defer fresh.deinit(a);
        var result = try fixture.compile(a, &initial, true);
        defer result.deinit(a);
        try std.testing.expectEqualSlices(u8, fresh.bytes, result.bytes);
        try std.testing.expectEqual(fresh.constant_steps, result.constant_steps);
        try std.testing.expectEqual(@as(usize, 0), result.constant_receipts.member_replayed);
    }
}

fn enclosingParity(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, limits: @FieldType(backend.CompileOptions, "constant_limits")) !void {
    var actual = try fixture.compileLimited(allocator, previous, true, limits);
    defer actual.deinit(allocator);
    try std.testing.expectEqualDeep(expected.diagnostic, actual.diagnostic);
    try std.testing.expectEqual(expected.constant_steps, actual.constant_steps);
    try std.testing.expectEqualSlices(u8, expected.bytes, actual.bytes);
    try std.testing.expectEqual(@as(usize, 0), actual.constant_receipts.member_replayed);
}

test "enclosing constant member judgment preserves failed edits limits and owned lookup outcomes" {
    const text = try enclosingSource("1", "2", "0", "#[]", false);
    defer a.free(text);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var initial = try fixture.compile(a, null, true);
    defer initial.deinit(a);
    var ordinary = try fixture.compile(a, null, false);
    defer ordinary.deinit(a);
    const Limits = @FieldType(backend.CompileOptions, "constant_limits");
    for ([_]Limits{ .{ .steps = 80 }, .{ .values = 80 }, .{ .children = 0 }, .{ .depth = 40 }, .{ .calls = 0 }, .{ .steps = 1000 }, .{ .values = 1000 } }) |limits| {
        var fresh = try fixture.compileLimited(a, null, false, limits);
        defer fresh.deinit(a);
        try enclosingParity(a, &fixture, &initial, &fresh, limits);
    }
    // A changed observed principal-cache outcome declines before graph
    // publication. The private receiver/fuel rollback permits ordinary work.
    const query = &initial.capture.?.metadata.specialization_queries.records.items[0];
    const member = query.dependencies.member.?;
    const reads = member.principals;
    const forged = try a.alloc(@import("specialization_receipt.zig").PrincipalRead, 1);
    defer a.free(forged);
    forged[0] = .{ .target = member.target, .open = false, .source_interface = false, .deferred_member = false, .outcome = .declined };
    member.principals = forged;
    try enclosingParity(a, &fixture, &initial, &ordinary, .{});
    member.principals = reads;
    // Failed publication never replaces the previous immutable Capture.
    const trapping = try enclosingSource("@panic \"failed\"", "2", "0", "#[]", false);
    defer a.free(trapping);
    var broken = try Fixture.init(trapping);
    defer broken.deinit();
    var fresh_failure = try broken.compile(a, null, false);
    defer fresh_failure.deinit(a);
    try std.testing.expect(fresh_failure.diagnostic != null);
    try enclosingParity(a, &broken, &initial, &fresh_failure, .{});
    try enclosingReplay(a, &fixture, &initial, &ordinary);
    // Replacing the enclosing explicit context retains ordinary validation.
    const marker = "entry const enclosing: U32";
    const index = std.mem.find(u8, text, marker).?;
    const changed = try a.print("{s}entry const enclosing{s}", .{ text[0..index], text[index + marker.len ..] });
    defer a.free(changed);
    var inferred = try Fixture.init(changed);
    defer inferred.deinit();
    var fresh_inferred = try inferred.compile(a, null, false);
    defer fresh_inferred.deinit(a);
    try enclosingParity(a, &inferred, &initial, &fresh_inferred, .{});
}

test "enclosing constant member judgment leaves typed warm aliases and value quotas ordinary" {
    const base = try enclosingSource("1", "2", "0", "alias", false);
    defer a.free(base);
    const text = try a.print("const alias: Array U32 = #[]\n{s}", .{base});
    defer a.free(text);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var initial = try fixture.compile(a, null, true);
    defer initial.deinit(a);
    var fresh = try fixture.compile(a, null, false);
    defer fresh.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), initial.constant_receipts.member_recorded);
    try enclosingParity(a, &fixture, &initial, &fresh, .{});
    // Ordinary typed alias cache publication remains authoritative even when
    // quota leaves room for one use but not an extra reconstructed alias.
    for ([_]usize{ 160, 250, 1000 }) |limit| {
        const limits: @FieldType(backend.CompileOptions, "constant_limits") = .{ .values = limit };
        var limited = try fixture.compileLimited(a, null, false, limits);
        defer limited.deinit(a);
        try enclosingParity(a, &fixture, &initial, &limited, limits);
    }
}

test "enclosing constant member judgment subfloor keeps ordinary selected reuse without an outer owner" {
    const text = try memberSource("1");
    defer a.free(text);
    var before = try Fixture.init(text);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), initial.constant_receipts.recorded);
    try std.testing.expectEqual(@as(usize, 0), initial.constant_receipts.owned_payload_bytes);
    const edited = try memberSource("2");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var fresh = try after.compile(a, null, false);
    defer fresh.deinit(a);
    var actual = try after.compile(a, &initial, true);
    defer actual.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, actual.bytes);
    try std.testing.expectEqual(fresh.constant_steps, actual.constant_steps);
    try std.testing.expect(actual.completed_queries.member_reused != 0);
    try std.testing.expectEqual(@as(usize, 0), actual.constant_receipts.lookups);
    try std.testing.expectEqual(@as(usize, 0), actual.constant_receipts.member_replayed);
    try std.testing.expectEqual(@as(usize, 0), actual.constant_receipts.owned_payload_bytes);
}

test "enclosing constant member judgment cannot absorb prior unowned inference" {
    const text = try enclosingSource("1", "2", "0", "#[]", false);
    defer a.free(text);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var session = try @import("core_eval.zig").Session.init(a, fixture.units);
    defer session.deinit();
    session.retain_specialization_receipts = true;
    session.options.trace_runtime_dependencies = true;
    session.options.retain_source_suspensions = true;
    _ = try session.richValue(.{ .unit = 1, .binding = 3 });
    _ = try session.richValue(.{ .unit = 1, .binding = 2 });
    _ = try session.body_recipes.get(a, session.units, .{ .owner = 0, .body = session.units[0].body(2).?.root, .callables = true }, session.options.max_values);
    try std.testing.expect(session.memberReceiptEligible(.{ .unit = 1, .binding = 2 }));
    var parent = @import("constant_receipt.zig").Recorder.init(&session);
    defer parent.deinit(a);
    // A child frame runs while its enclosing recorder is suspended. Its real
    // inference observation cannot be reassigned to a later member callback.
    const value = try session.richValue(.{ .unit = 1, .binding = 4 });
    try std.testing.expect(session.constant_inference_serial > parent.inference_serial);
    try std.testing.expect(session.specialization_receipts.items.len != 0);
    const complete = session.specialization_receipts.items.len - 1;
    try std.testing.expect(session.specialization_receipts.items[complete].complete);
    try std.testing.expect(!try parent.member(a, &session, complete, session.constant_inference_serial));
    try std.testing.expect(try parent.finish(a, &session, .{ .unit = 1, .binding = 4 }, value) == null);
    session.constant_inference_serial = std.math.maxInt(u64);
    var saturated = @import("constant_receipt.zig").Recorder.init(&session);
    defer saturated.deinit(a);
    try std.testing.expect(!try saturated.member(a, &session, complete, session.constant_inference_serial));
    try std.testing.expect(try saturated.finish(a, &session, .{ .unit = 1, .binding = 4 }, value) == null);
}
