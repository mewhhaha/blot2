const std = @import("std");
const core = @import("../check/core.zig");
const backend = @import("core_backend.zig");
const demand = @import("demand_inline.zig");

fn lower(a: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try @import("../parse/lexer.zig").lex(a, source);
    defer lexed.deinit(a);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(a);
    var tree = try @import("../parse/parser.zig").parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    var checked = try @import("../check/check.zig").check(a, &tree, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &tree, &names, &checked);
    result.unit = 1;
    return result;
}

fn emit(a: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(a, &.{module.*}, 1);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

fn explainedEmission(a: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(a, &.{module.*}, 1, .{ .explain_demands = true });
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    const snapshot = result.demand_lowering orelse return error.MissingExplanation;
    var kinds: [4]bool = @splat(false);
    for (snapshot.sites) |site| {
        kinds[@backingInt(site.lowering)] = true;
        try std.testing.expect(site.span.end >= site.span.start);
        try std.testing.expectEqual(@as(u32, 1), site.unit);
    }
    try std.testing.expectEqualSlices(bool, &@as([4]bool, @splat(true)), &kinds);
    try std.testing.expect(result.counters.demand_eliminated > 0);
    try std.testing.expect(result.counters.demand_direct > 0);
    try std.testing.expect(result.counters.demand_local_memo_slots >= 2);
    try std.testing.expect(result.counters.demand_allocations > 0);
    try std.testing.expect(result.counters.demand_indirect_calls > 0);
}

test "demand decisions report actual storage and preserve output through OOM" {
    const allocator = std.testing.allocator;
    var module = try lower(allocator,
        \\const ignore = func ~(value: U32) => return 42
        \\const once = func ~(value: U32) => return @demand value
        \\const twice = func ~(value: U32) => return @u32.add (@demand value) (@demand value)
        \\const stored = func ~(value: U32) => return func () => return @demand value
        \\const unknown = func (next: ~U32 -> U32) => return func ~(value: U32) => return next (@demand value)
        \\entry const eliminated = func (value: U32) => return ignore value
        \\entry const direct = func (value: U32) => return once value
        \\entry const memo = func (value: U32) => return twice value
        \\entry const escape = func (value: U32) => return (stored value) ()
        \\entry const indirect = func (value: U32) => return unknown once value
    );
    defer module.deinit(allocator);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    var ordinary = try backend.compile(allocator, &.{module}, 1);
    defer ordinary.deinit(allocator);
    var explained = try backend.compileWithOptions(allocator, &.{module}, 1, .{ .explain_demands = true });
    defer explained.deinit(allocator);
    try std.testing.expectEqualSlices(u8, ordinary.bytes, explained.bytes);
    try std.testing.expect(ordinary.demand_lowering == null);
    try explainedEmission(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, explainedEmission, .{&module});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "known callback type and row specialization releases every allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const read = func ~value => return do:
        \\  let identity = func item => return item
        \\  let callback = func () => return identity (@demand value)
        \\  use first <- callback ()
        \\  use callback ()
        \\  break first
        \\entry const integer = func (value: U32) => return read value
        \\entry const floating = func (value: F32) => return read value
    );
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "known local callbacks preserve one creation memo through aliases and loops" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const repeat = func (count: U32) => return func ~(value: U32) => return do:
        \\  let read = func (extra: U32) => return @u32.add (@demand value) extra
        \\  let alias = read
        \\  let second = func (extra: U32) => return @u32.add (@demand value) extra
        \\  let total = 0
        \\  for i in 0..count:
        \\    use left <- alias i
        \\    use right <- second i
        \\    total := @u32.add self (@u32.add left right)
        \\  break total
        \\entry const run = func (count: U32) => return repeat count 21
    );
    defer module.deinit(a);
    var admitted = false;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body)) |plan| {
        admitted = true;
        try std.testing.expect(plan.local_callbacks);
        try std.testing.expectEqual(@as(u8, 2), plan.uses[1]);
    };
    try std.testing.expect(admitted);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "local memo proof admits structured loops and aliases without mutating Core" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const sum = func (count: U32) => return func ~(value: U32) => return do:
        \\  let first = value
        \\  let second = first
        \\  let total = 0
        \\  for i in 0..count:
        \\    if @u32.eq i 1:
        \\      total := @u32.add self (@demand second)
        \\    else:
        \\      total := @u32.add self (@demand first)
        \\  break total
        \\entry const run = func (count: U32) => return sum count 21
    );
    defer module.deinit(a);
    var admitted = false;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body)) |plan| {
        admitted = true;
        try std.testing.expectEqual(@as(u8, 2), plan.uses[1]);
    };
    try std.testing.expect(admitted);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "local memo structured proof retains conservative escape and provider fallback" {
    const a = std.testing.allocator;
    for ([_][]const u8{
        "const delay = func ~(value: U32) => return do:\n  break value\nentry const run = 42\n",
        "const keep = func ~(value: U32) => return { callback: func () => return @demand value }\nentry const run = 42\n",
        "type Tick is effect = { read: Unit -> U32 }\nconst scoped = func ~(value: U32) => return do (@effect.provider Tick.read (func () => return 1)):\n  break @demand value\nentry const run = 42\n",
    }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        for (module.bodies) |*body| {
            if (body.parameters.len == 0) continue;
            try std.testing.expect(demand.Plan.init(&module, body) == null);
        }
    }
}

test "local memo structured proof exhaustion preserves ordinary emission" {
    const a = std.testing.allocator;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a, "const many = func ~(value: U32) => return do:\n  let total = @demand value\n");
    for (0..100) |_| try text.appendSlice(a, "  total := @u32.add self 1\n");
    try text.appendSlice(a, "  break total\nentry const run = func (value: U32) => return many value\n");
    var module = try lower(a, text.items);
    defer module.deinit(a);
    for (module.bodies) |*body| try std.testing.expect(demand.Plan.init(&module, body) == null);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "local memo List cleanup snapshots and managed loop roots release every allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const walk = func (rows: List U32) => return func ~(value: U32) => return do:
        \\  let total = 0
        \\  for row in rows:
        \\    total := @u32.add self (@u32.add row (@demand value))
        \\  break total
        \\const cache = func (count: U32) => return func ~(value: Array U32) => return do:
        \\  let i = 0
        \\  for ever:
        \\    let pressure = @array.fill 1024 i
        \\    let cached = @demand value
        \\    i := @u32.add (@array.get pressure 0) 1
        \\    if @u32.eq i count:
        \\      break cached
        \\entry const lists = func (count: U32) => return walk (@list.fill count 42) 21
        \\entry const arrays = func (count: U32) => return cache count #[21, 22, 23]
    );
    defer module.deinit(a);
    var admitted: usize = 0;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body) != null) {
        admitted += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), admitted);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "demand forwarding bounds nested proofs and preserves immutable Core under allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const twice = func ~(value: U32) => return @u32.add (@demand value) (@demand value)
        \\const forward = func ~(value: U32) => return twice (@demand value)
        \\const many = func ~(value: U32) => return @u32.add (forward (@demand value)) (twice (@demand value))
        \\const ignore = func ~(value: U32) => return 42
        \\const discard = func ~(value: U32) => return ignore (@demand value)
        \\entry const run = func (value: U32) => return many value
        \\entry const skip = func (value: U32) => return discard (@u32.div 1 value)
    );
    defer module.deinit(a);
    var forwarded: usize = 0;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body)) |plan| {
        if (plan.call_count != 0) forwarded += 1;
        for (plan.uses) |uses| try std.testing.expect(uses <= 2);
    };
    try std.testing.expect(forwarded >= 3);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "recursive demand forwarding declines its bounded inline proof" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const recursive: ~U32 -> U32 = func ~(value: U32) => return recursive (@demand value)
        \\entry const unused = 42
    );
    defer module.deinit(a);
    for (module.bodies) |*body| {
        if (body.parameters.len == 0) continue;
        try std.testing.expect(demand.Plan.init(&module, body) == null);
    }
}

test "recursive demand headers preserve inferred curried and mutual forwarding" {
    const a = std.testing.allocator;
    for ([_][]const u8{
        "const recursive = func ~(value: U32) => return recursive (@demand value)\nentry const unused = 42\n",
        "const recursive = func ~value => return recursive (@demand value)\nentry const unused = 42\n",
        "const recursive = func (count: U32) => return func ~(value: U32) => return if @u32.eq count 0 then @demand value else recursive (@u32.sub count 1) (@demand value)\nentry const run = func (count: U32) => return recursive count 42\n",
        "const even = func (count: U32) => return func ~value => return if @u32.eq count 0 then @demand value else odd (@u32.sub count 1) (@demand value)\nconst odd = func (count: U32) => return func ~value => return if @u32.eq count 0 then @demand value else even (@u32.sub count 1) (@demand value)\nentry const run = func (count: U32) => return even count 42\n",
        "const even: U32 -> ~U32 -> U32 = func count => return func ~value => return if @u32.eq count 0 then @demand value else odd (@u32.sub count 1) (@demand value)\nconst odd: U32 -> ~U32 -> U32 = func count => return func ~value => return if @u32.eq count 0 then @demand value else even (@u32.sub count 1) (@demand value)\nentry const run = func (count: U32) => return even count 42\n",
    }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try emit(a, &module);
    }
}

fn recursiveHeaderOwnership(a: std.mem.Allocator) !void {
    var module = try lower(a,
        \\const recursive = func ~value => return recursive (@demand value)
        \\entry const unused = 42
    );
    defer module.deinit(a);
}

test "recursive demand provisional headers release every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, recursiveHeaderOwnership, .{});
}
