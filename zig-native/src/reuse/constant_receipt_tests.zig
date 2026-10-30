const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const identity = @import("../backend/runtime_identity.zig");
const a = std.testing.allocator;

fn callableConstantSource(sibling: []const u8, changed: bool, cursor: bool) ![]u8 {
    var expression = try a.dupe(u8, "1");
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    var output: []const u8 = "func (value: U32) => return @u32.add value cost";
    var entry: []const u8 = "entry const run = func (value: U32) => return expensive value";
    if (changed) output = "func (value: U32) => return @u32.sub value cost";
    if (cursor) {
        output = "@array.cursor #[cost, 2]";
        entry = "entry const run = func (value: U32) => return @u32.add value (@cursor.value expensive)";
    }
    return a.print("const seed = {s}\nconst expensive = do:\n  let cost = {s}\n  break {s}\n{s}\nentry const unrelated = seed\n", .{ sibling, expression, output, entry });
}

test "constant receipts retain standalone callable and cursor values with exact changed source and OOM" {
    for ([_]bool{ false, true }) |cursor| {
        const source = try callableConstantSource("2", false, cursor);
        defer a.free(source);
        var before = try Fixture.init(source);
        defer before.deinit();
        var initial = try before.compile(a, null, true);
        defer initial.deinit(a);
        try std.testing.expect(initial.diagnostic == null);
        try std.testing.expectEqual(@as(usize, 1), initial.capture.?.metadata.pools.?.constant_records.len);
        const edited = try callableConstantSource("3", false, cursor);
        defer a.free(edited);
        var after = try Fixture.init(edited);
        defer after.deinit();
        var fresh = try after.compile(a, null, false);
        defer fresh.deinit(a);
        try replayGraphs(a, &after, &initial, &fresh, 1);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &fresh, @as(usize, 1) });
        if (!cursor) {
            const changed = try callableConstantSource("3", true, false);
            defer a.free(changed);
            var altered = try Fixture.init(changed);
            defer altered.deinit();
            var expected = try altered.compile(a, null, false);
            defer expected.deinit(a);
            try replayGraphs(a, &altered, &initial, &expected, 0);
        }
    }
}

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
    return a.print("const seed = {s}\nconst expensive = {s}\nentry const run = func (value: U32) => return @u32.add value (@u32.add expensive seed)\n", .{ seed, expression });
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replay, .{ &after, &initial, &fresh, @as(usize, 1) });
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

fn appendType(fixture: *Fixture, node: @import("../check/types.zig").Node) !void {
    const old = fixture.units[0].types.nodes;
    const nodes = try a.alloc(@import("../check/types.zig").Node, old.len + 1);
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
        \\entry const run = func () => return @u32.add seed (@u32.add (@array.get first 0) (@u32.add (@array.get middle 0) (@array.get last 0)))
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
    if (hits != result.constant_receipts.reused) std.debug.print("COMPOUND_RECEIPT_DECLINE {any}\n", .{result.constant_receipts});
    try std.testing.expectEqual(hits, result.constant_receipts.reused);
    try std.testing.expectEqual(@as(usize, 0), result.constant_receipts.scalar_reused);
    if (hits != 0) try std.testing.expect(result.constant_receipts.graph_index_bytes > 0);
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
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &fresh, hits });
        // Failure sweeps leave the immutable producer available for retry.
        try replayGraphs(a, &after, &initial, &fresh, hits);
    }
}

fn growingSource(sibling: []const u8) ![]u8 {
    return a.print(
        \\const grown: List U32 = do:
        \\  let values = []
        \\  for index in 0..32:
        \\    values := if @u32.lt index 16 then @list.append values index else @list.prepend values index
        \\  break values
        \\const later = @list.prepend (@list.append grown 99) 100
        \\entry const first = func () => return @array.from_list grown
        \\entry const following = func () => return @array.from_list later
        \\entry const sibling = {s}
        \\
    , .{sibling});
}
test "constant receipts restore the recorded growth frontier before later ordinary extensions" {
    const source = try growingSource("1");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), initial.constant_receipts.recorded);
    const record = initial.capture.?.metadata.pools.?.constant_records[0];
    const growth = record.events[record.events.len - 1].growth;
    try std.testing.expectEqual(@as(u64, 32), growth.mutations);
    try std.testing.expect(growth.frontier != null);
    const edited = try growingSource("2");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var fresh = try after.compile(a, null, false);
    defer fresh.deinit(a);
    try replayGraphs(a, &after, &initial, &fresh, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &fresh, @as(usize, 1) });
    try replayGraphs(a, &after, &initial, &fresh, 1);
}

test "constant receipts preserve growth capacity and temporary debt at tight child limits" {
    const original = try growingSource("1");
    defer a.free(original);
    const edited = try growingSource("2");
    defer a.free(edited);
    var before = try Fixture.init(original);
    defer before.deinit();
    var after = try Fixture.init(edited);
    defer after.deinit();
    var admitted: usize = 0;
    for ([_]usize{ 64, 80, 96, 112, 128, 144, 160, 192, 256 }) |children| {
        const limits: @FieldType(backend.CompileOptions, "constant_limits") = .{ .children = children };
        var initial = try before.compileLimited(a, null, true, limits);
        defer initial.deinit(a);
        if (initial.diagnostic != null) continue;
        var fresh = try after.compileLimited(a, null, false, limits);
        defer fresh.deinit(a);
        var retained = try after.compileLimited(a, &initial, true, limits);
        defer retained.deinit(a);
        try std.testing.expectEqualDeep(fresh.diagnostic, retained.diagnostic);
        try std.testing.expectEqualSlices(u8, fresh.bytes, retained.bytes);
        try std.testing.expectEqual(fresh.constant_steps, retained.constant_steps);
        try std.testing.expectEqual(@as(usize, 1), retained.constant_receipts.reused);
        admitted += 1;
    }
    try std.testing.expect(admitted >= 3);
}

test "constant receipts omit inaccessible growth frontiers from old versions and scalar results" {
    var expression = try a.dupe(u8, "1");
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    for ([_]bool{ false, true }) |scalar| {
        var outcome: []const u8 = "first";
        var use: []const u8 = "@array.from_list following";
        var following: []const u8 = "@list.append value 9";
        if (scalar) {
            outcome = "@list.length later";
            use = "following";
            following = "@u32.add value 9";
        }
        const text = try a.print(
            \\const value = do:
            \\  let first = @list.append [] ({s})
            \\  let later = @list.append first 7
            \\  break {s}
            \\const following = {s}
            \\entry const run = func () => return {s}
            \\entry const sibling = 1
            \\
        , .{ expression, outcome, following, use });
        defer a.free(text);
        var before = try Fixture.init(text);
        defer before.deinit();
        var initial = try before.compile(a, null, true);
        defer initial.deinit(a);
        try std.testing.expect(initial.diagnostic == null);
        try std.testing.expectEqual(@as(usize, 1), initial.constant_receipts.recorded);
        const record = initial.capture.?.metadata.pools.?.constant_records[0];
        const growth = record.events[record.events.len - 1].growth;
        try std.testing.expectEqual(@as(u64, 2), growth.mutations);
        try std.testing.expect(growth.frontier == null);
        text[text.len - 2] = '2';
        var after = try Fixture.init(text);
        defer after.deinit();
        var fresh = try after.compile(a, null, false);
        defer fresh.deinit(a);
        if (scalar) {
            try replay(a, &after, &initial, &fresh, 1);
        } else try replayGraphs(a, &after, &initial, &fresh, 1);
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
        var node = before.units[0].types.nodes[@import("../check/types.zig").u32_type];
        if (variant == 1) node = .{ .tag = .array, .a = @import("../check/types.zig").u32_type };
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
    const conditional = try a.print("const flag = 0\n{s}\nconst seed = if @u32.eq flag 0 then 3 else {s}\nentry const run = func (value: U32) => return @u32.add value (@u32.add expensive seed)\n", .{ initializer, seed });
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
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, resourceParity, .{ &after, &initial, &expected, limits });
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
    const source = try a.print("const seed = 2\nconst helper: U32 -> U32 = func (value: U32) => return {s}\nconst expensive = helper 1\nentry const run = func (value: U32) => return @u32.add value (@u32.add expensive seed)\n", .{expression_source[start..end]});
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
    // A called helper's scalar output cannot authorize missing invocation
    // ownership. Keep both source pins equal so declaration matching alone
    // admits the body; the receipt's callable-source guard must reject it.
    const pools = &initial.capture.?.metadata.pools.?;
    const record = &pools.constant_records[0];
    var helper: u32 = 0;
    for (record.sources) |source_read| if (source_read == .named and source_read.named.binding != record.target.binding) {
        if (pools.modules[0].module.body(source_read.named.binding).?.is_function) helper = source_read.named.binding;
    };
    try std.testing.expect(helper != 0);
    const old_module = @constCast(pools.modules[0].module);
    const new_module = &same.units[0];
    for ([_]bool{ false, true }) |binding_scheme| {
        var old_scheme = &old_module.bodies[old_module.bindings[helper].body_id].scheme;
        var new_scheme = &new_module.bodies[new_module.bindings[helper].body_id].scheme;
        if (binding_scheme) {
            old_scheme = &old_module.bindings[helper].scheme;
            new_scheme = &new_module.bindings[helper].scheme;
        }
        const before_old = old_scheme.generative;
        const before_new = new_scheme.generative;
        defer old_scheme.generative = before_old;
        defer new_scheme.generative = before_new;
        old_scheme.generative = .{ .len = 2 };
        new_scheme.generative = .{ .len = 2 };
        try replay(a, &same, &initial, &fresh, 0);
    }
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
    const qualified = try std.mem.replaceOwned(u8, a, plain, "const expensive =", "const expensive: U32 where { type_rep U32 } = do:\n  let local = func value => return value\n  break");
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replay, .{ &after, &initial, &expected, @as(usize, 1) });
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
    return a.print("const Array.count = func values => return {s}\nentry const warm: U32 = #[].count\nentry const result: U32 = #[].count\nentry const sibling = {s}\n", .{ expression, sibling });
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, memberReplay, .{ &after, &initial, &expected });
    var changed = try Fixture.init("const Array.count = func values => return @u32.add 1 (@array.length values)\nentry const warm: U32 = #[].count\nentry const result: U32 = #[].count\nentry const sibling = 2\n");
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
    return a.print("const compound = #[{{ value: {s} }}]\nentry const owned = func () => return @array.length compound\nentry const sibling = {s}\n", .{ expression, sibling });
}
test "constant receipts replay compound graphs with exact fuel and allocation ownership" {
    const original = try compoundSource("1");
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), initial.capture.?.metadata.pools.?.constant_records.len);
    const edit = try compoundSource("2");
    defer a.free(edit);
    var after = try Fixture.init(edit);
    defer after.deinit();
    var ordinary = try after.compile(a, null, false);
    defer ordinary.deinit(a);
    try replayGraphs(a, &after, &initial, &ordinary, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &ordinary, @as(usize, 1) });
    // The reachable graph may not exceed its tape's cumulative storage owner.
    for ([_]bool{ false, true }) |children| {
        const record = &initial.capture.?.metadata.pools.?.constant_records[0];
        for (record.events) |*event| if (event.* == .work) {
            const before_work = event.work;
            defer event.work = before_work;
            if (children) event.work.children = 0 else event.work.values = 0;
            var rejected = try after.compile(a, &initial, true);
            defer rejected.deinit(a);
            try std.testing.expectEqualSlices(u8, ordinary.bytes, rejected.bytes);
            try std.testing.expectEqual(ordinary.constant_steps, rejected.constant_steps);
            try std.testing.expectEqual(@as(usize, 0), rejected.constant_receipts.reused);
            break;
        };
    }
    try replayGraphs(a, &after, &initial, &ordinary, 1);
}

fn smallScalarSource(sibling: []const u8) ![]u8 {
    var expression = try a.dupe(u8, "1");
    defer a.free(expression);
    for (0..52) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const small = {s}\nentry const run = func () => return small\nentry const sibling = {s}\n", .{ expression, sibling });
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, smallScalarReplay, .{ &after, &initial, &ordinary });
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
    const loop_method = try a.print("do:\n  let total = ({s})\n  for index in 0..128:\n    total := @u32.add self 1\n  break total", .{method});
    a.free(method);
    method = loop_method;
    if (second) {
        const next = try a.print("@u32.add (#[].count) ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const seed = {s}\nconst Array.count = func values => return {s}\nentry const warm: U32 = #[].count\nentry const enclosing: U32 = {s}\nentry const sibling = {s}\n", .{ seed, method, expression, sibling });
}
fn enclosingReplay(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expect(result.constant_receipts.queries_replayed != 0);
}

fn enclosingFresh(allocator: std.mem.Allocator, fixture: *const Fixture, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, null, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expect(result.constant_receipts.queries_recorded != 0);
}

test "enclosing constant member judgment owns fresh and retained authority with OOM rollback" {
    const original = try enclosingSource("1", "2", "0", "#[]", false);
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.constant_receipts.queries_recorded != 0);
    const edited = try enclosingSource("2", "2", "0", "#[]", false);
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var ordinary = try after.compile(a, null, false);
    defer ordinary.deinit(a);
    try enclosingFresh(a, &after, &ordinary);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, enclosingFresh, .{ &after, &ordinary });
    try enclosingReplay(a, &after, &initial, &ordinary);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, enclosingReplay, .{ &after, &initial, &ordinary });
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
    }
}

fn enclosingParity(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, limits: @FieldType(backend.CompileOptions, "constant_limits")) !void {
    var actual = try fixture.compileLimited(allocator, previous, true, limits);
    defer actual.deinit(allocator);
    try std.testing.expectEqualDeep(expected.diagnostic, actual.diagnostic);
    try std.testing.expectEqual(expected.constant_steps, actual.constant_steps);
    try std.testing.expectEqualSlices(u8, expected.bytes, actual.bytes);
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

test "enclosing constant query barriers preserve typed warm aliases and value quotas" {
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
    try std.testing.expectEqual(@as(usize, 0), actual.constant_receipts.owned_payload_bytes);
}

test "enclosing constant member judgment cannot absorb prior unowned inference" {
    const text = try enclosingSource("1", "2", "0", "#[]", false);
    defer a.free(text);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var session = try @import("../eval/core_eval.zig").Session.init(a, fixture.units);
    defer session.deinit();
    session.retain_specialization_receipts = true;
    session.options.trace_runtime_dependencies = true;
    session.options.retain_source_suspensions = true;
    _ = try session.richValue(.{ .unit = 1, .binding = 3 });
    _ = try session.richValue(.{ .unit = 1, .binding = 2 });
    _ = try session.specializations.body_recipes.get(a, session.units, .{ .owner = 0, .body = session.units[0].body(2).?.root, .callables = true }, session.options.max_values);
    try std.testing.expect(session.memberReceiptEligible(.{ .unit = 1, .binding = 2 }));
    var parent = @import("constant_receipt.zig").Recorder.init(&session);
    defer parent.deinit(a);
    // A child frame runs while its enclosing recorder is suspended. Its real
    // inference observation cannot be reassigned to a later member callback.
    const value = try session.richValue(.{ .unit = 1, .binding = 4 });
    try std.testing.expect(session.constant_inference_serial > parent.inference_serial);
    try std.testing.expect(session.retained.specialization_receipts.items.len != 0);
    const complete = session.retained.specialization_receipts.items.len - 1;
    try std.testing.expect(session.retained.specialization_receipts.items[complete].complete);
    try parent.beforeRead(a, &session);
    try std.testing.expect(!parent.eligible);
    try std.testing.expect(try parent.finish(a, &session, .{ .unit = 1, .binding = 4 }, value, .{}) == null);
    session.constant_inference_serial = std.math.maxInt(u64);
    var saturated = @import("constant_receipt.zig").Recorder.init(&session);
    defer saturated.deinit(a);
    try saturated.beforeRead(a, &session);
    try std.testing.expect(!saturated.eligible);
    try std.testing.expect(try saturated.finish(a, &session, .{ .unit = 1, .binding = 4 }, value, .{}) == null);
}

fn compoundAliasesSource(sibling: []const u8, seed: []const u8, delta: []const u8) ![]u8 {
    var expression = try a.dupe(u8, "1");
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print(
        \\data Box = #Box {{ value: U32 }}
        \\const seed = {s}
        \\const ready = #Box {{ value: seed }}
        \\entry const warmed = func () => return ready.value
        \\const compound = do:
        \\  let cost = {s}
        \\  break {{ first: ready, second: ready, values: #[ready, ready], answer: cost, callback: func (value: U32) => return @u32.add value (@u32.add cost {s}) }}
        \\entry const run = func (value: U32) => return compound.callback value
        \\entry const answer = func () => return compound.first.value
        \\entry const count = func () => return @array.length compound.values
        \\entry const sibling = {s}
        \\
    , .{ seed, expression, delta, sibling });
}
test "constant receipts own ready nominal aliases and captured closure graphs" {
    const original = try compoundAliasesSource("1", "2", "0");
    defer a.free(original);
    var before = try Fixture.init(original);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), initial.capture.?.metadata.pools.?.constant_records.len);
    for ([_][]const u8{ "2", "3", "2" }, [_][]const u8{ "0", "0", "1" }, [_]usize{ 1, 0, 0 }) |seed, delta, hits| {
        const source = try compoundAliasesSource("2", seed, delta);
        defer a.free(source);
        var after = try Fixture.init(source);
        defer after.deinit();
        var fresh = try after.compile(a, null, false);
        defer fresh.deinit(a);
        try replayGraphs(a, &after, &initial, &fresh, hits);
        if (hits != 0) {
            try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &fresh, hits });
            const record = &initial.capture.?.metadata.pools.?.constant_records[0];
            for (record.events) |*event| if (event.* == .read) {
                const dependency = event.read.target;
                defer event.read.target = dependency;
                // An evaluating slot is never a ready dependency anchor.
                event.read.target = record.target;
                var unfinished = try after.compile(a, &initial, true);
                defer unfinished.deinit(a);
                try std.testing.expectEqualSlices(u8, fresh.bytes, unfinished.bytes);
                try std.testing.expectEqual(fresh.constant_steps, unfinished.constant_steps);
                try std.testing.expectEqual(@as(usize, 0), unfinished.constant_receipts.reused);
                try std.testing.expectEqual(@as(usize, 1), unfinished.constant_receipts.retries);
                break;
            };
        }
    }
    const warm_prefix = "entry const warmed";
    const offset = std.mem.find(u8, original, warm_prefix).?;
    const cold_source = try a.print("{s}const warmed{s}", .{ original[0..offset], original[offset + warm_prefix.len ..] });
    defer a.free(cold_source);
    var cold = try Fixture.init(cold_source);
    defer cold.deinit();
    var cold_initial = try cold.compile(a, null, true);
    defer cold_initial.deinit(a);
    var ordinary = try cold.compile(a, null, false);
    defer ordinary.deinit(a);
    var retained = try cold.compile(a, &initial, true);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, ordinary.bytes, retained.bytes);
    try std.testing.expectEqual(ordinary.constant_steps, retained.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), retained.constant_receipts.reused);
    var demand_replay = try cold.compile(a, &cold_initial, true);
    defer demand_replay.deinit(a);
    try std.testing.expectEqualSlices(u8, ordinary.bytes, demand_replay.bytes);
    try std.testing.expectEqual(ordinary.constant_steps, demand_replay.constant_steps);
    try std.testing.expectEqual(@as(usize, 1), demand_replay.constant_receipts.reused);
    try std.testing.expectEqual(@as(usize, 0), demand_replay.constant_receipts.retries);
}

fn compoundGrowthSource(sibling: []const u8, seed: []const u8) ![]u8 {
    return a.print(
        \\data Bundle = #Bundle {{ earlier: List U32, current: List U32, alias: List U32, other: List U32, answer: U32 }}
        \\const seed = {s}
        \\const grown = do:
        \\  let values: List U32 = []
        \\  let earlier: List U32 = []
        \\  let other: List U32 = []
        \\  for index in 0..32:
        \\    values := if @u32.lt index 16 then @list.append values index else @list.prepend values index
        \\    other := @list.append other (@u32.add index 100)
        \\    earlier := if @u32.eq index 30 then values else earlier
        \\  break #Bundle {{ earlier: earlier, current: values, alias: values, other: other, answer: seed }}
        \\const later = @list.prepend (@list.append grown.current 99) 100
        \\const branched = @list.append grown.earlier 200
        \\entry const first = func () => return @array.from_list grown.current
        \\entry const old = func () => return @array.from_list grown.earlier
        \\entry const following = func () => return @array.from_list later
        \\entry const branch = func () => return @array.from_list branched
        \\entry const answer = func () => return grown.answer
        \\entry const sibling = {s}
        \\
    , .{ seed, sibling });
}
fn replayCompoundGrowth(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, hits: usize, retries: usize) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expectEqualDeep(expected.diagnostic, result.diagnostic);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    if (result.constant_receipts.reused != hits) std.debug.print("BUFFER_RECEIPT {any}\n", .{result.constant_receipts});
    try std.testing.expectEqual(hits, result.constant_receipts.reused);
    try std.testing.expectEqual(retries, result.constant_receipts.retries);
}

test "constant receipts own compound latest buffers with aliases older spans and ordinary demand" {
    const source = try compoundGrowthSource("1", "2");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), initial.constant_receipts.recorded);
    const records = initial.capture.?.metadata.pools.?.constant_records;
    try std.testing.expectEqual(@as(usize, 2), records[0].buffers.len);
    const edited = try compoundGrowthSource("2", "2");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var fresh = try after.compile(a, null, false);
    defer fresh.deinit(a);
    try replayCompoundGrowth(a, &after, &initial, &fresh, 1, 0);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayCompoundGrowth, .{ &after, &initial, &fresh, @as(usize, 1), @as(usize, 0) });
    var retained = try after.compile(a, &initial, true);
    defer retained.deinit(a);
    try replayCompoundGrowth(a, &before, &retained, &initial, 1, 0);
    const changed = try compoundGrowthSource("2", "3");
    defer a.free(changed);
    var changed_fixture = try Fixture.init(changed);
    defer changed_fixture.deinit();
    var changed_fresh = try changed_fixture.compile(a, null, false);
    defer changed_fresh.deinit(a);
    try replayCompoundGrowth(a, &changed_fixture, &initial, &changed_fresh, 0, 1);
    // An attempted mismatch cannot corrupt the immutable prior revision.
    try replayCompoundGrowth(a, &after, &initial, &fresh, 1, 0);
    const effects = @constCast(records[0].buffers);
    const original = effects[0];
    const other = effects[1];
    effects[0].frontier.offset = std.math.maxInt(u32);
    try replayCompoundGrowth(a, &after, &initial, &fresh, 0, 0);
    effects[0] = original;
    effects[1] = original;
    try replayCompoundGrowth(a, &after, &initial, &fresh, 0, 1);
    effects[1] = other;
    {
        const original_events = try a.dupe(@import("constant_receipt.zig").Event, records[0].events);
        defer a.free(original_events);
        defer @memcpy(records[0].events, original_events);
        for (records[0].events) |*event| if (event.* == .work) {
            event.work.children = 0;
        };
        try replayCompoundGrowth(a, &after, &initial, &fresh, 0, 1);
    }
    for (records[0].events) |*event| if (event.* == .read) {
        const depth = event.read.depth;
        event.read.depth = std.math.maxInt(usize);
        try replayCompoundGrowth(a, &after, &initial, &fresh, 0, 1);
        event.read.depth = depth;
        break;
    };
    try replayCompoundGrowth(a, &after, &initial, &fresh, 1, 0);
}

fn compoundLimitedParity(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, limits: @FieldType(backend.CompileOptions, "constant_limits")) !void {
    var result = try fixture.compileLimited(allocator, previous, true, limits);
    defer result.deinit(allocator);
    try std.testing.expectEqualDeep(expected.diagnostic, result.diagnostic);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
}

test "compound demand receipts retain cumulative limits retry rollback and source failures" {
    const text = try compoundGrowthSource("1", "2");
    defer a.free(text);
    var before = try Fixture.init(text);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    const changed = try compoundGrowthSource("2", "3");
    defer a.free(changed);
    var after = try Fixture.init(changed);
    defer after.deinit();
    var fresh = try after.compile(a, null, false);
    defer fresh.deinit(a);
    try replayCompoundGrowth(a, &after, &initial, &fresh, 0, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayCompoundGrowth, .{ &after, &initial, &fresh, @as(usize, 0), @as(usize, 1) });
    // The successful retry records ordinary receipts for the next revision.
    var retry = try after.compile(a, &initial, true);
    defer retry.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), retry.constant_receipts.recorded);
    try replayCompoundGrowth(a, &after, &retry, &fresh, 1, 0);
    const Limits = @FieldType(backend.CompileOptions, "constant_limits");
    const limits = [_]Limits{ .{ .steps = 64 }, .{ .steps = initial.constant_steps }, .{ .values = 64 }, .{ .values = 256 }, .{ .children = 64 }, .{ .children = 256 }, .{ .children = 384 }, .{ .depth = 2 }, .{ .depth = 32 }, .{ .calls = 0 }, .{ .calls = 16 } };
    for (limits) |limit| {
        var limited_initial = try before.compileLimited(a, null, true, limit);
        defer limited_initial.deinit(a);
        var ordinary = try after.compileLimited(a, null, false, limit);
        defer ordinary.deinit(a);
        var previous = &initial;
        if (limited_initial.capture != null) previous = &limited_initial;
        try compoundLimitedParity(a, &after, previous, &ordinary, limit);
    }
    const panic_source = try compoundGrowthSource("2", "@panic \"failed dependency\"");
    defer a.free(panic_source);
    var failed = try Fixture.init(panic_source);
    defer failed.deinit();
    var failed_fresh = try failed.compile(a, null, false);
    defer failed_fresh.deinit(a);
    try std.testing.expect(failed_fresh.diagnostic != null);
    try compoundLimitedParity(a, &failed, &initial, &failed_fresh, .{});
    try replayCompoundGrowth(a, &before, &retry, &initial, 0, 1);
    try replayCompoundGrowth(a, &after, &retry, &fresh, 1, 0);
}

fn queryBarrierSource(seed: []const u8, increment: []const u8) ![]u8 {
    return a.print("const Array.count = func values => return @u32.add (@array.length values) {s}\nconst seed = {s}\nconst bundle = do:\n  let first = #[].count\n  let second = #[].count\n  let cost = 1\n  for index in 0..256:\n    cost := @u32.add self 1\n  break {{first, second, cost}}\nentry const run = func () => return @u32.add bundle.first (@u32.add bundle.second bundle.cost)\nentry const unrelated = seed\n", .{ increment, seed });
}
fn replayQueryBarriers(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expect(result.constant_receipts.reused != 0);
    try std.testing.expect(result.constant_receipts.queries_replayed >= 2);
}
test "constant receipts replay multiple ordinary inference barriers before compound data through OOM" {
    const source = try queryBarrierSource("2", "0");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    if (initial.diagnostic) |issue| std.debug.print("query initial {s}\n", .{issue.message()});
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.constant_receipts.queries_recorded >= 2);
    const edited = try queryBarrierSource("3", "0");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var expected = try after.compile(a, null, false);
    defer expected.deinit(a);
    try replayQueryBarriers(a, &after, &initial, &expected);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayQueryBarriers, .{ &after, &initial, &expected });

    const changed_source = try queryBarrierSource("3", "1");
    defer a.free(changed_source);
    var changed = try Fixture.init(changed_source);
    defer changed.deinit();
    var changed_expected = try changed.compile(a, null, false);
    defer changed_expected.deinit(a);
    try replayGraphs(a, &changed, &initial, &changed_expected, 0);

    const record = &initial.capture.?.metadata.pools.?.constant_records[0];
    const query = for (@constCast(record.events)) |*event| {
        if (event.* == .query) break event.query;
    } else return error.TestUnexpectedResult;
    const old_expected = query.expected;
    defer query.expected = old_expected;
    query.expected = @import("../check/types.zig").f32_type;
    try queryBarrierRecovery(a, &after, &initial, &expected);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, queryBarrierRecovery, .{ &after, &initial, &expected });
}
fn queryBarrierRecovery(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expectEqual(@as(usize, 1), result.constant_receipts.retries);
}

fn frameJudgmentSource(seed: []const u8, value: []const u8) ![]u8 {
    return a.print(
        \\const seed = {s}
        \\const identity = func value => return value
        \\const answer = do:
        \\  let callback = func () => return {s}
        \\  let generic = identity
        \\  let nested = {{callback, value: generic 7}}
        \\  let selected: U32 where {{ type_rep U32 }} = nested.callback ()
        \\  let cost = 0
        \\  for index in 0..256:
        \\    cost := @u32.add self 1
        \\  break {{selected, cost, value: nested.value}}
        \\entry const run = func () => return @u32.add answer.selected (@u32.add answer.cost answer.value)
        \\entry const unrelated = seed
        \\
    , .{ seed, value });
}
fn replayFrameJudgments(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    try std.testing.expect(result.constant_receipts.reused != 0);
    try std.testing.expect(result.constant_receipts.queries_replayed != 0);
}
test "constant receipts reconstruct current solver judgments and mapped frame outputs through OOM" {
    const source = try frameJudgmentSource("2", "35");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    var judgments: usize = 0;
    for (initial.capture.?.metadata.pools.?.constant_records) |record| {
        for (record.events) |event| if (event == .query and event.query.kind == .judgment) {
            judgments += 1;
        };
    }
    try std.testing.expect(judgments != 0);
    const record = &initial.capture.?.metadata.pools.?.constant_records[0];
    try std.testing.expect(record.inputs.rows.len != 0);
    try std.testing.expect(record.outputs == null);
    const changed_source = try frameJudgmentSource("3", "35");
    defer a.free(changed_source);
    var after = try Fixture.init(changed_source);
    defer after.deinit();
    var expected = try after.compile(a, null, false);
    defer expected.deinit(a);
    try replayFrameJudgments(a, &after, &initial, &expected);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayFrameJudgments, .{ &after, &initial, &expected });
    {
        // Principal solving makes this source frame stable. Exercise the same
        // owned output representation used when an inner judgment extends it,
        // using its actual current solved rows rather than synthetic IDs.
        const outputs = try a.create(@import("constant_receipt.zig").Inputs);
        defer a.destroy(outputs);
        outputs.* = try record.inputs.clone(a);
        defer outputs.deinit(a);
        record.outputs = outputs;
        defer record.outputs = null;
        try replayFrameJudgments(a, &after, &initial, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayFrameJudgments, .{ &after, &initial, &expected });
        const rows = @constCast(outputs.rows);
        const saved = rows[0];
        defer rows[0] = saved;
        rows[0].variable = std.math.maxInt(u32);
        try replayGraphs(a, &after, &initial, &expected, 0);
    }

    // The current ordinary query must reproduce the complete output, including
    // failure, rather than accepting a retained successful boolean as proof.
    const judgment = for (record.events) |event| {
        if (event == .query and event.query.kind == .judgment) break event.query.judgment.?;
    } else return error.TestUnexpectedResult;
    {
        const saved = judgment.matched;
        defer judgment.matched = saved;
        judgment.matched = !saved;
        try queryBarrierRecovery(a, &after, &initial, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, queryBarrierRecovery, .{ &after, &initial, &expected });
    }
    {
        const saved = judgment.unit;
        defer judgment.unit = saved;
        judgment.unit = std.math.maxInt(u32);
        try queryBarrierRecovery(a, &after, &initial, &expected);
    }
    {
        const saved = judgment.source;
        defer judgment.source = saved;
        judgment.source = std.math.maxInt(u32);
        try queryBarrierRecovery(a, &after, &initial, &expected);
    }
    {
        const rows = @constCast(record.inputs.rows);
        const saved = rows[0];
        defer rows[0] = saved;
        rows[0].variable = std.math.maxInt(u32);
        try replayGraphs(a, &after, &initial, &expected, 0);
    }
    // A different selected callable body invalidates the source owner, while
    // returning to the last successful revision can still use the old owner.
    const callable_edit = try frameJudgmentSource("3", "36");
    defer a.free(callable_edit);
    var changed = try Fixture.init(callable_edit);
    defer changed.deinit();
    var changed_expected = try changed.compile(a, null, false);
    defer changed_expected.deinit(a);
    try replayGraphs(a, &changed, &initial, &changed_expected, 0);
    try replayFrameJudgments(a, &after, &initial, &expected);

    const Limits = @FieldType(backend.CompileOptions, "constant_limits");
    for ([_]Limits{ .{ .steps = 64 }, .{ .steps = initial.constant_steps }, .{ .values = 32 }, .{ .children = 8 }, .{ .depth = 3 }, .{ .calls = 0 } }) |limits| {
        var limited = try after.compileLimited(a, null, false, limits);
        defer limited.deinit(a);
        try compoundLimitedParity(a, &after, &initial, &limited, limits);
    }
}

fn immutableTemporarySource(seed: []const u8, bound: []const u8) ![]u8 {
    var cost = try a.dupe(u8, "1");
    defer a.free(cost);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{cost});
        a.free(cost);
        cost = next;
    }
    return a.print(
        \\type Item = exists [a] => a
        \\const seed = {s}
        \\const limit = {s}
        \\const answer = do:
        \\  let item = pack [U32] 35 as Item
        \\  let resealed = unpack item as [a] value in pack [a] value as Item
        \\  let selected = unpack resealed as [b] value in 7
        \\  let valid = @proof.lt 0 limit
        \\  let cost = {s}
        \\  break @u32.add cost selected
        \\entry const run = func () => return answer
        \\entry const unrelated = seed
        \\
    , .{ seed, bound, cost });
}
test "constant receipts retain immutable package and proof temporaries while preserving guard failures through OOM" {
    const source = try immutableTemporarySource("2", "1");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.constant_receipts.recorded != 0);
    const edited = try immutableTemporarySource("3", "1");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var expected = try after.compile(a, null, false);
    defer expected.deinit(a);
    try replayGraphs(a, &after, &initial, &expected, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &expected, @as(usize, 1) });
    const trapped = try immutableTemporarySource("3", "0");
    defer a.free(trapped);
    var failed = try Fixture.init(trapped);
    defer failed.deinit();
    var fresh = try failed.compile(a, null, false);
    defer fresh.deinit(a);
    try std.testing.expect(fresh.diagnostic != null);
    try compoundLimitedParity(a, &failed, &initial, &fresh, .{});
    try replayGraphs(a, &after, &initial, &expected, 1);
}

fn retainedPackageSource(seed: []const u8, payload: []const u8) ![]u8 {
    var cost = try a.dupe(u8, payload);
    defer a.free(cost);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{cost});
        a.free(cost);
        cost = next;
    }
    return a.print(
        \\type Render a is contract = {{ const show: a -> U32 }}
        \\impl Number : Render U32 = {{ const show = func value => return value }}
        \\type Item = exists [a] where {{ Render a }} => a
        \\const seed = {s}
        \\const packet = pack [U32] ({s}) as Item
        \\entry const run = func () => return unpack packet as [a] value in Render.show value
        \\entry const unrelated = seed
        \\
    , .{ seed, cost });
}
test "constant receipts retain closed existential data and selected dictionary closures through OOM" {
    const source = try retainedPackageSource("2", "35");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.constant_receipts.recorded != 0);
    const edited = try retainedPackageSource("3", "35");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var expected = try after.compile(a, null, false);
    defer expected.deinit(a);
    try replayGraphs(a, &after, &initial, &expected, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &expected, @as(usize, 1) });
    const pools = &initial.capture.?.metadata.pools.?;
    const record = &pools.constant_records[0];
    const package = &pools.evaluator.values[record.value];
    try std.testing.expect(package.kind == .package);
    {
        const saved = package.nominal;
        defer package.nominal = saved;
        package.nominal = std.math.maxInt(u64);
        try replayGraphs(a, &after, &initial, &expected, 0);
    }
    {
        const saved = package.bits;
        defer package.bits = saved;
        package.bits = std.math.maxInt(u32);
        try replayGraphs(a, &after, &initial, &expected, 0);
    }
    {
        const dictionary = &pools.evaluator.evidence.nodes[@intCast(package.nominal)];
        const saved = dictionary.*;
        defer dictionary.* = saved;
        dictionary.b += 1;
        try replayGraphs(a, &after, &initial, &expected, 0);
    }
    {
        const recipe = pools.evaluator.evidence.nodes[package.bits];
        const binder = &pools.evaluator.evidence.nodes[pools.evaluator.evidence.extra[recipe.c]];
        const saved = binder.*;
        defer binder.* = saved;
        binder.c = 1;
        try replayGraphs(a, &after, &initial, &expected, 0);
    }
    const payload = pools.evaluator.children[package.start];
    {
        const saved = pools.evaluator.values[payload].kind;
        defer pools.evaluator.values[payload].kind = saved;
        pools.evaluator.values[payload].kind = .capability;
        try replayGraphs(a, &after, &initial, &expected, 0);
    }
    {
        const old_nodes = pools.evaluator.evidence.nodes;
        const nodes = try a.alloc(@import("../eval/type_evidence.zig").Node, old_nodes.len + 1);
        defer a.free(nodes);
        @memcpy(nodes[0..old_nodes.len], old_nodes);
        nodes[old_nodes.len] = .{ .tag = .usage, .a = @import("../check/types.zig").u32_type, .b = @backingInt(@import("../check/types.zig").UsageKind.unique) };
        pools.evaluator.evidence.nodes = nodes;
        defer pools.evaluator.evidence.nodes = old_nodes;
        const saved = pools.evaluator.value_evidence[payload];
        defer pools.evaluator.value_evidence[payload] = saved;
        pools.evaluator.value_evidence[payload] = @intCast(old_nodes.len);
        try replayGraphs(a, &after, &initial, &expected, 0);
    }
    var guarded_staging = false;
    for (pools.evaluator.children[package.start..][0..package.len]) |child| {
        const info = pools.evaluator.values[child];
        if (info.kind != .closure) continue;
        const closure = &pools.evaluator.closures[info.bits];
        const saved = closure.staged;
        defer closure.staged = saved;
        closure.staged = record.value;
        guarded_staging = true;
        try replayGraphs(a, &after, &initial, &expected, 0);
        break;
    }
    try std.testing.expect(guarded_staging);
    const changed_text = try retainedPackageSource("3", "36");
    defer a.free(changed_text);
    var changed = try Fixture.init(changed_text);
    defer changed.deinit();
    var fresh = try changed.compile(a, null, false);
    defer fresh.deinit(a);
    try replayGraphs(a, &changed, &initial, &fresh, 0);
    const changed_method = try std.mem.replaceOwned(u8, a, edited, "func value => return value", "func value => return @u32.add value 1");
    defer a.free(changed_method);
    var method = try Fixture.init(changed_method);
    defer method.deinit();
    var method_fresh = try method.compile(a, null, false);
    defer method_fresh.deinit(a);
    try replayGraphs(a, &method, &initial, &method_fresh, 0);
    try replayGraphs(a, &after, &initial, &expected, 1);
}

fn retainedQuantifierSource(seed: []const u8) ![]u8 {
    var cost = try a.dupe(u8, "35");
    defer a.free(cost);
    for (0..80) |_| {
        const next = try a.print("@u32.add 1 ({s})", .{cost});
        a.free(cost);
        cost = next;
    }
    return a.print(
        \\const choose: forall [a] => a -> a = func value => return value
        \\const concrete = func (value: U32) => return @u32.add value 1
        \\const seed = {s}
        \\const packet = {{choose, cost: {s}}}
        \\entry const run = func () => return packet.choose packet.cost
        \\entry const unrelated = seed
        \\
    , .{ seed, cost });
}
test "constant receipts preserve explicit quantified callable data without erasing binder owners through OOM" {
    const source = try retainedQuantifierSource("2");
    defer a.free(source);
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null, true);
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.constant_receipts.recorded != 0);
    const edited = try retainedQuantifierSource("3");
    defer a.free(edited);
    var after = try Fixture.init(edited);
    defer after.deinit();
    var expected = try after.compile(a, null, false);
    defer expected.deinit(a);
    try replayGraphs(a, &after, &initial, &expected, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayGraphs, .{ &after, &initial, &expected, @as(usize, 1) });
    const offset = std.mem.find(u8, source, "const concrete =").?;
    const concrete: u32 = for (before.units[0].bindings, 0..) |binding, ordinal| {
        if (binding.span.start == offset) break @intCast(ordinal);
    } else return error.TestUnexpectedResult;
    const pools = &initial.capture.?.metadata.pools.?;
    const graph = pools.evaluator.values[pools.constant_records[0].value];
    var guarded = false;
    for (pools.evaluator.children[graph.start..][0..graph.len]) |child| {
        const info = pools.evaluator.values[child];
        if (info.kind != .closure) continue;
        const closure = &pools.evaluator.closures[info.bits];
        if (closure.origin != .named) continue;
        const saved = closure.identity;
        closure.identity = concrete;
        defer closure.identity = saved;
        guarded = true;
        try replayGraphs(a, &after, &initial, &expected, 0);
        break;
    }
    try std.testing.expect(guarded);
}

fn quantifiedFieldSource(seed: []const u8) ![]u8 {
    return a.print(
        \\type Maybe a is data = #Some a | #None
        \\type Render a is contract = {{ const show: a -> U32 }}
        \\impl Number : Render U32 = {{ const show = func value => return @u32.add value 1 }}
        \\impl Flag : Render Bool = {{ const show = func value => return if value then 7 else 9 }}
        \\const choose: forall [a] => a -> a = func value => return value
        \\const make: U32 -> (forall [a] => a -> a) = func captured => return func item => return do:
        \\  let ignored = @u32.add captured 1
        \\  break item
        \\const show: forall [a] where {{ Render a }} => a -> U32 = func value => return Render.show value
        \\const wrap: forall [a] => a -> Maybe a = #Some
        \\const apply: forall [a, row e] => ((a -> a ! {{|e}}), a) -> a ! {{|e}} = func pair => return (@product.get pair 0) (@product.get pair 1)
        \\const concrete = func (value: U32) => return @u32.add value 1
        \\const seed = {s}
        \\const packet = do:
        \\  let cost = 35
        \\  for index in 0..256:
        \\    cost := @u32.add self 1
        \\  break {{choose, other: make 35, show, wrap, apply, cost}}
        \\entry const run = func () => return packet.choose packet.cost
        \\entry const fraction = func () => return packet.other 3.5
        \\entry const shown = func () => return @u32.add (packet.show 35) (packet.show true)
        \\entry const wrapped = func () => return case packet.wrap packet.cost of
        \\  #Some value => value
        \\  #None => 0
        \\entry const host = func (callback: U32 -> U32 ! {{Foreign}}) => return packet.apply (callback, packet.cost)
        \\entry const unrelated = seed
        \\
    , .{seed});
}
fn compileQuantifiedFields(allocator: std.mem.Allocator, fixture: *const Fixture, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, null, false);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
}
test "constant quantified fields preserve constructor captured dictionary and effect carrier owners through OOM" {
    const source = try quantifiedFieldSource("2");
    defer a.free(source);
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var expected = try fixture.compile(a, null, false);
    defer expected.deinit(a);
    try std.testing.expect(expected.diagnostic == null);
    try compileQuantifiedFields(a, &fixture, &expected);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compileQuantifiedFields, .{ &fixture, &expected });
}

const temporary_programs = [_]struct { body: []const u8, hits: usize, changed_hits: usize = 0 }{
    .{ .body =
    \\  let metadata = @effect.of described
    \\  let cost = @effect.count metadata
    , .hits = 1, .changed_hits = 1 },
    .{ .body =
    \\  let provider = @effect.provider Read (func () => return base)
    \\  let cost = base
    , .hits = 1 },
    .{ .body =
    \\  let cost = do (@effect.provider Read (func () => return base)):
    \\    break base
    , .hits = 1 },
    .{ .body =
    \\  let cost = base
    \\  for request in @requests (@computation (func () => return base)):
    \\    case request of
    \\      effect Read () =>
    \\        yield base
    \\      complete result =>
    \\        cost := result
    \\        break
    , .hits = 1 },
    .{ .body =
    \\  let wrapped = do (@do.monad Box):
    \\    break base
    \\  let cost = case wrapped of
    \\    #Box value => value
    , .hits = 1 },
    .{ .body =
    \\  let (_, cost) = @state.run base (func () => return base)
    , .hits = 0 },
    .{ .body =
    \\  let cost = do (@effect.provider Read (func () => return base)):
    \\    use result <- Read ()
    \\    break result
    , .hits = 0 },
    .{ .body =
    \\  let pending = delayed base
    \\  let cost = @force pending
    \\  let again = @force pending
    , .hits = 0 },
    .{ .body =
    \\  let cost = @effect.scope (func (state: State U32) => return base)
    , .hits = 0 },
    .{ .body =
    \\  let cost = @code.run (@code.quote (@code.lift base))
    , .hits = 0 },
};
fn temporarySource(seed: []const u8, base: []const u8, body: []const u8) ![]u8 {
    return a.print(
        \\effect Read: Unit -> U32
        \\type State a is effect = {{get: Unit -> a, set: a -> Unit}}
        \\const described: Unit -> U32 ! {{Read}} = func () => return Read ()
        \\type Box a is data = #Box a
        \\const Box.pure = func (value: U32) => return #Box value
        \\const delayed = func ~value => return value
        \\const base = {s}
        \\const expensive = do:
        \\{s}
        \\  for index in 0..256:
        \\    cost := @u32.add self 1
        \\  break cost
        \\entry const answer = func () => return expensive
        \\entry const sibling = {s}
        \\
    , .{ base, body, seed });
}
fn replayTemporaries(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result, hits: usize) !void {
    var result = try fixture.compile(allocator, previous, true);
    defer result.deinit(allocator);
    try std.testing.expectEqualDeep(expected.diagnostic, result.diagnostic);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.constant_steps, result.constant_steps);
    if (result.constant_receipts.reused != hits) std.debug.print("TEMPORARY_RECEIPT {any}\n", .{result.constant_receipts});
    try std.testing.expectEqual(hits, result.constant_receipts.reused);
    if (hits != 0) try std.testing.expect(result.constant_receipts.source_steps_replayed > 1700);
}
test "constant receipts use actual execution boundaries for dead immutable temporaries through OOM" {
    for (temporary_programs) |program| {
        const original = try temporarySource("2", "1", program.body);
        defer a.free(original);
        var before = try Fixture.init(original);
        defer before.deinit();
        var initial = try before.compile(a, null, true);
        defer initial.deinit(a);
        try std.testing.expect(initial.diagnostic == null);
        const edited = try temporarySource("3", "1", program.body);
        defer a.free(edited);
        var after = try Fixture.init(edited);
        defer after.deinit();
        var expected = try after.compile(a, null, false);
        defer expected.deinit(a);
        try replayTemporaries(a, &after, &initial, &expected, program.hits);
        if (program.hits != 0) {
            const Limits = @FieldType(backend.CompileOptions, "constant_limits");
            for ([_]Limits{ .{ .steps = 1700 }, .{ .values = 100 }, .{ .children = 0 }, .{ .depth = 2 }, .{ .calls = 0 } }) |limit| {
                var limited = try after.compileLimited(a, null, false, limit);
                defer limited.deinit(a);
                try enclosingParity(a, &after, &initial, &limited, limit);
            }
        }
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayTemporaries, .{ &after, &initial, &expected, program.hits });
        const changed = try temporarySource("3", "2", program.body);
        defer a.free(changed);
        var altered = try Fixture.init(changed);
        defer altered.deinit();
        var fresh = try altered.compile(a, null, false);
        defer fresh.deinit(a);
        try replayTemporaries(a, &altered, &initial, &fresh, program.changed_hits);
    }
}
