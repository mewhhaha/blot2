const std = @import("std");
const core = @import("../check/core.zig");
const demand = @import("demand_summary.zig");
const backend = @import("core_backend.zig");
const A = std.mem.Allocator;
fn lower(a: A, source: []const u8) !core.Module {
    return lowerNames(a, source, null);
}
fn lowerNames(a: A, source: []const u8, metadata: ?*@import("runtime_identity.zig").Metadata) !core.Module {
    var lexed = try @import("../parse/lexer.zig").lex(a, source);
    defer lexed.deinit(a);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(a);
    var tree = try @import("../parse/parser.zig").parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    var checked = try @import("../check/check.zig").check(a, &tree, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    module.unit = 1;
    errdefer module.deinit(a);
    if (metadata) |out| out.* = try @import("runtime_identity.zig").Metadata.capture(a, &names, &.{.{ .unit = 1, .path = "/demand/main.blot" }}, 1);
    return module;
}
fn classify(a: A, module: *const core.Module, target: u32, limits: demand.Limits) !demand.Outcome {
    var counters: @import("../work_counters.zig").Counters = .{};
    var result = try demand.analyze(a, &.{module.*}, .{ .unit = 1, .binding = target }, limits, &counters);
    defer result.deinit(a);
    return result.summary.parameter(0).outcome();
}
test "demand summary exclusive branches join dynamically and forwarding records every body" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const choose = fn ~(value: U32) => if @u32.eq (@demand value) 0 then 1 else 2
        \\const exclusive = fn ~(value: U32) => if #True then @demand value else @demand value
        \\const both = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
        \\const escape = fn ~(value: U32) => if #True then fn () => @demand value else fn () => @demand value
        \\const ignore = fn ~(value: U32) => 42
        \\const forward = fn ~(value: U32) => both (@demand value)
        \\entry const run = fn (x: U32) => exclusive x
    );
    defer module.deinit(a);
    const expected = [_]demand.Outcome{ .once, .once, .repeated, .escaping, .never, .repeated };
    var index: usize = 0;
    for (module.bodies) |body| {
        if (!body.is_function or body.parameters.len == 0) continue;
        if (module.types.node(module.bodyParameters(&body)[0].ty).tag != .demand) continue;
        try std.testing.expectEqual(expected[index], try classify(a, &module, body.binding, .{}));
        index += 1;
    }
    try std.testing.expectEqual(expected.len, index);
    var result = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.demand_summary_builds > 0);
    try std.testing.expect(result.capture.?.metadata.demand_summaries.records.items.len > 0);
}
fn ownership(a: A, module: *const core.Module, target: u32) !void {
    var counters: @import("../work_counters.zig").Counters = .{};
    const result = try demand.analyze(a, &.{module.*}, .{ .unit = 1, .binding = target }, .{}, &counters);
    // insert returns a position; its prepared pointer token stays operation-local.
    var table: demand.Table = .{};
    defer table.deinit(a);
    // zig-analyzer: disable-next-line local-storage-escape
    _ = try demand.insert(a, &table, demand.keyFor(&.{module.*}, .{ .unit = 1, .binding = target }, .{}), result.dependencies, result.summary);
}
test "demand summary ownership survives every allocation failure and budget exhaustion" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
        \\entry const run = fn (x: U32) => twice x
    );
    defer module.deinit(a);
    const body = module.bodies[1];
    try ownership(a, &module, body.binding);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, ownership, .{ &module, body.binding });
    try std.testing.expectEqual(demand.Outcome.unknown, try classify(a, &module, body.binding, .{ .nodes = 1 }));
}

test "demand summary aliases preserve identity and an outside creation repeats in a loop" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const alias = fn ~(value: U32) => do:
        \\  let second = value
        \\  break @demand second
        \\const looped = fn ~(value: U32) => do:
        \\  for index in 0..3:
        \\    use @demand value
        \\  break 42
        \\entry const run = fn (x: U32) => alias x
    );
    defer module.deinit(a);
    try std.testing.expectEqual(demand.Outcome.once, try classify(a, &module, module.bodies[1].binding, .{}));
    try std.testing.expectEqual(demand.Outcome.repeated, try classify(a, &module, module.bodies[2].binding, .{}));
    var counters: @import("../work_counters.zig").Counters = .{};
    var analysis = try demand.analyze(a, &.{module}, .{ .unit = 1, .binding = module.bodies[1].binding }, .{}, &counters);
    defer analysis.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), analysis.summary.aliases.len);
    try std.testing.expectEqual(analysis.summary.demands[0].binding, module.bodyParameters(&module.bodies[1])[0].binding);
}

test "demand summary recursive checked graphs converge and bounded components decline" {
    const a = std.testing.allocator;
    for ([_][]const u8{
        "const once = fn ~(value: U32) => if #True then @demand value else once (@demand value)\nentry const run = fn (x: U32) => once x\n",
        "const even = fn ~(value: U32) => if #True then @demand value else odd (@demand value)\nconst odd = fn ~(value: U32) => even (@demand value)\nentry const run = fn (x: U32) => even x\n",
    }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const body = module.bodies[1];
        try std.testing.expectEqual(demand.Outcome.once, try classify(a, &module, body.binding, .{}));
        try std.testing.expectEqual(demand.Outcome.unknown, try classify(a, &module, body.binding, .{ .iterations = 1 }));
    }
}

const Fixture = struct {
    units: [1]core.Module,
    names: @import("runtime_identity.zig").Metadata,
    fn init(source: []const u8) !Fixture {
        // lowerNames fills this output. deinit releases it through self.names.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        var names: @import("runtime_identity.zig").Metadata = undefined;
        const module = try lowerNames(std.testing.allocator, source, &names);
        return .{ .units = .{module}, .names = names };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(std.testing.allocator);
        self.names.deinit(std.testing.allocator);
    }
    fn compile(self: *const Fixture, a: A, previous: ?*const @import("../reuse/artifact_capture.zig").Capture) !backend.Result {
        return backend.compileWithOptions(a, &self.units, 1, .{ .retain_artifacts = true, .identity = self.names.view(), .previous = previous });
    }
};
const retained_before =
    \\const leaf = fn ~(value: U32) => if #True then @demand value else 42
    \\const forward = fn ~(value: U32) => leaf (@demand value)
    \\entry const run = fn (x: U32) => forward x
;
const retained_after =
    \\const leaf = fn ~(value: U32) => if #True then 42 else @demand value
    \\const forward = fn ~(value: U32) => leaf (@demand value)
    \\entry const run = fn (x: U32) => forward x
;
test "demand summary retained exact bodies reject stable type edits and survive no op generations" {
    const a = std.testing.allocator;
    var before = try Fixture.init(retained_before);
    defer before.deinit();
    var after = try Fixture.init(retained_after);
    defer after.deinit();
    var first = try before.compile(a, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try std.testing.expect(first.counters.demand_summary_builds > 0);
    var second = try before.compile(a, &first.capture.?);
    defer second.deinit(a);
    try std.testing.expect(second.diagnostic == null);
    try std.testing.expect(second.counters.demand_summary_imports > 0);
    try std.testing.expectEqual(@as(u64, 0), second.counters.demand_summary_builds);
    var third = try before.compile(a, &second.capture.?);
    defer third.deinit(a);
    try std.testing.expect(third.counters.demand_summary_imports > 0);
    try std.testing.expectEqualSlices(u8, first.bytes, third.bytes);
    var edited = try after.compile(a, &third.capture.?);
    defer edited.deinit(a);
    var fresh = try after.compile(a, null);
    defer fresh.deinit(a);
    try std.testing.expect(edited.diagnostic == null and fresh.diagnostic == null);
    try std.testing.expect(edited.counters.demand_summary_builds > 0);
    try std.testing.expectEqualSlices(u8, fresh.bytes, edited.bytes);
    try std.testing.expect(!std.mem.eql(u8, first.bytes, edited.bytes));
}
fn failedRevision(a: A, fixture: *const Fixture, previous: *const @import("../reuse/artifact_capture.zig").Capture) !void {
    const old_count = previous.metadata.demand_summaries.records.items.len;
    var result = try fixture.compile(a, previous);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(old_count, previous.metadata.demand_summaries.records.items.len);
}
test "demand summary failed revision allocation recovery keeps last good queries intact" {
    const a = std.testing.allocator;
    var before = try Fixture.init(retained_before);
    defer before.deinit();
    var after = try Fixture.init(retained_after);
    defer after.deinit();
    var first = try before.compile(a, null);
    defer first.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, failedRevision, .{ &after, &first.capture.? });
    var recovered = try before.compile(a, &first.capture.?);
    defer recovered.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, recovered.bytes);
    try std.testing.expect(recovered.counters.demand_summary_imports > 0);
}

test "demand summary forwarding growth visits retained nodes and edges linearly" {
    const a = std.testing.allocator;
    var previous: u64 = 0;
    for ([_]usize{ 8, 16, 32, 64, 128 }) |count| {
        var source: std.ArrayList(u8) = .empty;
        defer source.deinit(a);
        try source.appendSlice(a, "const f0 = fn ~(value: U32) => @demand value\n");
        for (1..count) |index| {
            const line = try a.print("const f{d} = fn ~(value: U32) => f{d} (@demand value)\n", .{ index, index - 1 });
            defer a.free(line);
            try source.appendSlice(a, line);
        }
        const entry = try a.print("entry const run = fn (x: U32) => f{d} x\n", .{count - 1});
        defer a.free(entry);
        try source.appendSlice(a, entry);
        var module = try lower(a, source.items);
        defer module.deinit(a);
        var counters: @import("../work_counters.zig").Counters = .{};
        var table: demand.Table = .{};
        defer table.deinit(a);
        const target: core.BindingRef = .{ .unit = 1, .binding = module.bodies[count].binding };
        var analysis = try demand.analyzeCached(a, &.{module}, target, .{}, &counters, &table);
        defer analysis.deinit(a);
        try std.testing.expectEqual(demand.Outcome.once, analysis.summary.parameter(0).outcome());
        try std.testing.expect(counters.demand_summary_nodes <= count * 16);
        try std.testing.expect(counters.demand_summary_edges <= count * 3);
        if (previous != 0) try std.testing.expect(counters.demand_summary_nodes <= previous * 2 + 8);
        previous = counters.demand_summary_nodes;
        _ = try analysis.publish(a, &table, demand.keyFor(&.{module}, target, .{}));
        try std.testing.expectEqual(count, table.records.items.len);
        // Each component record owns a lease of the same immutable read set.
        const lease = table.records.items[0].dependencies.lease;
        for (table.records.items) |record| try std.testing.expectEqual(lease, record.dependencies.lease);
        std.debug.print("demand growth bodies={d} nodes={d} edges={d} iterations={d} records={d}\n", .{ count, counters.demand_summary_nodes, counters.demand_summary_edges, counters.demand_summary_iterations, table.records.items.len });
    }
}

test "demand summary aggregate escape unknown callbacks and provider barriers stay conservative" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\type Tick is effect = { read: Unit -> U32 }
        \\const stored = fn ~(value: U32) => { item: value }
        \\const callback = fn ~(value: U32) => fn (next: ~U32 -> U32) => next (@demand value)
        \\const guarded = fn ~(value: U32) => do (@effect.provider Tick.read (fn () => 42)):
        \\  break @demand value
        \\entry const run = fn () => guarded (Tick.read ())
    );
    defer module.deinit(a);
    try std.testing.expectEqual(demand.Outcome.escaping, try classify(a, &module, module.bodies[1].binding, .{}));
    try std.testing.expectEqual(demand.Outcome.unknown, try classify(a, &module, module.bodies[2].binding, .{}));
    try std.testing.expectEqual(demand.Outcome.unknown, try classify(a, &module, module.bodies[3].binding, .{}));
}

test "demand summary loop fresh creation has one use per dynamic instance" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const looped = fn ~(value: U32) => do:
        \\  for index in 0..3:
        \\    let pending = value
        \\    use @demand pending
        \\  break 42
        \\entry const run = fn (x: U32) => looped x
    );
    defer module.deinit(a);
    // Source suspension creation currently occurs at argument applications.
    // Install that typed creation as a local loop seed to isolate the lifetime law.
    var suspension: core.Id = 0;
    var seed: core.Id = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag == .suspend_) suspension = @intCast(index);
        if (node.tag == .bind and module.node(node.b).tag == .reference) seed = @intCast(index);
    }
    const original = module.nodes[seed].b;
    defer module.nodes[seed].b = original;
    module.nodes[seed].b = suspension;
    var counters: @import("../work_counters.zig").Counters = .{};
    var analysis = try demand.analyze(a, &.{module}, .{ .unit = 1, .binding = module.bodies[1].binding }, .{}, &counters);
    defer analysis.deinit(a);
    try std.testing.expectEqual(demand.Outcome.never, analysis.summary.parameter(0).outcome());
    var fresh = false;
    for (analysis.summary.demands) |item| if (item.creation == suspension) {
        fresh = true;
        try std.testing.expect(item.scope.loop != 0);
        try std.testing.expectEqual(demand.Outcome.once, item.fact.outcome());
    };
    try std.testing.expect(fresh);
}
