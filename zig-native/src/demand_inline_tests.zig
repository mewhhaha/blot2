const std = @import("std");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const demand = @import("demand_inline.zig");

fn lower(a: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try @import("lexer.zig").lex(a, source);
    defer lexed.deinit(a);
    var names: @import("symbols.zig").Pool = .{};
    defer names.deinit(a);
    var tree = try @import("parser.zig").parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    var checked = try @import("check.zig").check(a, &tree, &names);
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

test "known callback type and row specialization releases every allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const read = fn ~value => do:
        \\  let identity = fn item => item
        \\  let callback = fn () => identity (@demand value)
        \\  use first <- callback ()
        \\  use callback ()
        \\  return first
        \\entry const integer = fn (value: U32) => read value
        \\entry const floating = fn (value: F32) => read value
    );
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "known local callbacks preserve one creation memo through aliases and loops" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const repeat = fn (count: U32) => fn ~(value: U32) => do:
        \\  let read = fn (extra: U32) => @u32.add (@demand value) extra
        \\  let alias = read
        \\  let second = fn (extra: U32) => @u32.add (@demand value) extra
        \\  let total = 0
        \\  for i in 0..count:
        \\    use left <- alias i
        \\    use right <- second i
        \\    total := @u32.add self (@u32.add left right)
        \\  return total
        \\entry const run = fn (count: U32) => repeat count 21
    );
    defer module.deinit(a);
    var admitted = false;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body)) |plan| {
        admitted = true;
        try std.testing.expect(plan.local_callbacks);
        try std.testing.expectEqual(@as(u8, 2), plan.uses[1]);
    };
    try std.testing.expect(admitted);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "local memo proof admits structured loops and aliases without mutating Core" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const sum = fn (count: U32) => fn ~(value: U32) => do:
        \\  let first = value
        \\  let second = first
        \\  let total = 0
        \\  for i in 0..count:
        \\    if @u32.eq i 1:
        \\      total := @u32.add self (@demand second)
        \\    else:
        \\      total := @u32.add self (@demand first)
        \\  return total
        \\entry const run = fn (count: U32) => sum count 21
    );
    defer module.deinit(a);
    var admitted = false;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body)) |plan| {
        admitted = true;
        try std.testing.expectEqual(@as(u8, 2), plan.uses[1]);
    };
    try std.testing.expect(admitted);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "local memo structured proof retains conservative escape and provider fallback" {
    const a = std.testing.allocator;
    for ([_][]const u8{
        "const delay = fn ~(value: U32) => do:\n  return value\nentry const run = 42\n",
        "const keep = fn ~(value: U32) => { callback: fn () => @demand value }\nentry const run = 42\n",
        "type Tick is effect = { read: Unit -> U32 }\nconst scoped = fn ~(value: U32) => do (@effect.provider Tick.read (fn () => 1)):\n  return @demand value\nentry const run = 42\n",
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
    try text.appendSlice(a, "const many = fn ~(value: U32) => do:\n  let total = @demand value\n");
    for (0..100) |_| try text.appendSlice(a, "  total := @u32.add self 1\n");
    try text.appendSlice(a, "  return total\nentry const run = fn (value: U32) => many value\n");
    var module = try lower(a, text.items);
    defer module.deinit(a);
    for (module.bodies) |*body| try std.testing.expect(demand.Plan.init(&module, body) == null);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "local memo List cleanup snapshots and managed loop roots release every allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const walk = fn (rows: List U32) => fn ~(value: U32) => do:
        \\  let total = 0
        \\  for row in rows:
        \\    total := @u32.add self (@u32.add row (@demand value))
        \\  return total
        \\const cache = fn (count: U32) => fn ~(value: Array U32) => do:
        \\  let i = 0
        \\  for ever:
        \\    let pressure = @array.fill 1024 i
        \\    let cached = @demand value
        \\    i := @u32.add (@array.get pressure 0) 1
        \\    if @u32.eq i count:
        \\      return cached
        \\entry const lists = fn (count: U32) => walk (@list.fill count 42) 21
        \\entry const arrays = fn (count: U32) => cache count #[21, 22, 23]
    );
    defer module.deinit(a);
    var admitted: usize = 0;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body) != null) {
        admitted += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), admitted);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "demand forwarding bounds nested proofs and preserves immutable Core under allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
        \\const forward = fn ~(value: U32) => twice (@demand value)
        \\const many = fn ~(value: U32) => @u32.add (forward (@demand value)) (twice (@demand value))
        \\const ignore = fn ~(value: U32) => 42
        \\const discard = fn ~(value: U32) => ignore (@demand value)
        \\entry const run = fn (value: U32) => many value
        \\entry const skip = fn (value: U32) => discard (@u32.div 1 value)
    );
    defer module.deinit(a);
    var forwarded: usize = 0;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body)) |plan| {
        if (plan.call_count != 0) forwarded += 1;
        for (plan.uses) |uses| try std.testing.expect(uses <= 2);
    };
    try std.testing.expect(forwarded >= 3);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "recursive demand forwarding declines its bounded inline proof" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const recursive: ~U32 -> U32 = fn ~(value: U32) => recursive (@demand value)
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
        "const recursive = fn ~(value: U32) => recursive (@demand value)\nentry const unused = 42\n",
        "const recursive = fn ~value => recursive (@demand value)\nentry const unused = 42\n",
        "const recursive = fn (count: U32) => fn ~(value: U32) => if @u32.eq count 0 then @demand value else recursive (@u32.sub count 1) (@demand value)\nentry const run = fn (count: U32) => recursive count 42\n",
        "const even = fn (count: U32) => fn ~value => if @u32.eq count 0 then @demand value else odd (@u32.sub count 1) (@demand value)\nconst odd = fn (count: U32) => fn ~value => if @u32.eq count 0 then @demand value else even (@u32.sub count 1) (@demand value)\nentry const run = fn (count: U32) => even count 42\n",
        "const even: U32 -> ~U32 -> U32 = fn count => fn ~value => if @u32.eq count 0 then @demand value else odd (@u32.sub count 1) (@demand value)\nconst odd: U32 -> ~U32 -> U32 = fn count => fn ~value => if @u32.eq count 0 then @demand value else even (@u32.sub count 1) (@demand value)\nentry const run = fn (count: U32) => even count 42\n",
    }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try emit(a, &module);
    }
}

fn recursiveHeaderOwnership(a: std.mem.Allocator) !void {
    var module = try lower(a,
        \\const recursive = fn ~value => recursive (@demand value)
        \\entry const unused = 42
    );
    defer module.deinit(a);
}

test "recursive demand provisional headers release every allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, recursiveHeaderOwnership, .{});
}
