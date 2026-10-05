const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const graph = @import("startup_graph.zig");
const a = std.testing.allocator;
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("check {s}: {s}\n", .{ @tagName(d.code), d.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &syntax, &names, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
const associated_cycle = "type Box is data = #Box U32\nconst Box.read = fn value => first\nconst pick = fn value => value.read\nlet first: U32 = pick (#Box 1)\nentry const answer: Unit -> U32 = fn () => first\n";
const separate_instances = "type Left is data = #Left U32\ntype Right is data = #Right U32\nconst Left.read = fn value => 0\nconst Right.read = fn value => first\nconst pick = fn value => value.read\nlet first: U32 = pick (#Left 1)\nlet second: U32 = pick (#Right 2)\nentry const answer: Unit -> U32 = fn () => @u32.add first second\n";
fn emit(allocator: std.mem.Allocator, module: *const core.Module, expected: ?backend.Code, point: ?u32) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |d| std.debug.print("backend {s} {d}..{d}: {s}\n", .{ @tagName(d.code), d.span.start, d.span.end, d.message() });
    try std.testing.expectEqual(expected, if (result.diagnostic) |d| d.code else null);
    if (point) |p| try std.testing.expectEqual(core.Span{ .start = p, .end = p }, result.diagnostic.?.span);
    if (expected == null) try std.testing.expect(result.bytes.len > 8) else try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}
test "selected startup projection target detects real cell cycle after frontend teardown" {
    var module = try lower(a, associated_cycle);
    defer module.deinit(a);
    try emit(a, &module, .initialization_cycle, 103);
}
test "selected startup projection edges stay separate across generic initializer instances" {
    var module = try lower(a, separate_instances);
    defer module.deinit(a);
    try emit(a, &module, null, null);
}
fn selectedDependencies(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try eval.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.options.trace_runtime_dependencies = true;
    const steps = session.steps;
    var count: usize = 0;
    for (module.bodies[1..]) |body| {
        if (!body.runtime or body.is_function) continue;
        var methods = try session.startupDependencies(.{ .unit = 1, .binding = body.binding });
        defer methods.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), methods.selected.len);
        const selected = module.body(methods.selected[0].binding).?;
        try std.testing.expect(selected.is_function);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(steps, session.steps);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
}
test "selected startup evidence owns numeric edges without executing or retaining values and releases OOM" {
    var module = try lower(a, separate_instances);
    defer module.deinit(a);
    try selectedDependencies(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, selectedDependencies, .{&module});
}
test "selected startup cyclic graph releases every backend allocation failure" {
    var module = try lower(a, associated_cycle);
    defer module.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, @as(?backend.Code, .initialization_cycle), @as(?u32, 103) });
}

const ready_demand = "const keep = fn ~(value: Unit -> U32) => value\nconst helper = fn () => first\nconst pending = keep helper\nconst cached = @force pending\nlet first: U32 = cached ()\nentry const answer: Unit -> U32 = fn () => first\n";
test "selected startup global allocation precedes recursive initializer helper emission" {
    var module = try lower(a, ready_demand);
    defer module.deinit(a);
    try emit(a, &module, null, null);
}
test "selected startup global emission preserves real direct cycles and legal function recursion" {
    const cases = [_]struct { source: []const u8, expected: ?backend.Code }{
        .{ .source = "let first: U32 = first\nentry const answer = fn () => first\n", .expected = .initialization_cycle },
        .{ .source = "const recurse: U32 -> U32 = fn value => if @u32.eq value 0 then 42 else recurse (@u32.sub value 1)\nentry const answer = fn () => recurse 3\n", .expected = null },
    };
    for (cases) |c| {
        var module = try lower(a, c.source);
        defer module.deinit(a);
        try emit(a, &module, c.expected, null);
    }
}

test "selected startup allocated slots and initializer emission release every allocation failure" {
    for ([_][]const u8{ ready_demand, separate_instances }) |text| {
        var module = try lower(a, text);
        defer module.deinit(a);
        const before = @import("core_snapshot_tests.zig").stamp(module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, @as(?backend.Code, null), @as(?u32, null) });
        try std.testing.expectEqualSlices(u8, &before, &@import("core_snapshot_tests.zig").stamp(module));
    }
}

const completeness_cases = [_]struct { source: []const u8, expected: ?backend.Code, point: ?u32 }{
    .{ .source = "type Box is data = #Box U32\nconst Box.add = fn left => fn right => first\nconst combine = fn left => fn right => @type.call \"add\" left right\nlet first: U32 = combine (#Box 1) (#Box 2)\nentry const answer: Unit -> U32 = fn () => first\n", .expected = .initialization_cycle, .point = 144 },
    .{ .source = "type Box is data = #Box U32\nconst Box.add = fn left => fn right => second\nconst combine = fn left => fn right => @type.call \"add\" left right\nlet first: U32 = combine (#Box 1) (#Box 2)\nlet second: U32 = first\nentry const answer: Unit -> U32 = fn () => first\n", .expected = .initialization_cycle, .point = 145 },
    .{ .source = "type Box is data = #Box U32\nconst Box.add = fn left => fn right => second\nconst combine = fn left => fn right => @type.call \"add\" left right\nlet first: U32 = combine (#Box 1) (#Box 2)\nlet second: U32 = 42\nentry const answer: Unit -> U32 = fn () => first\n", .expected = null, .point = null },
    .{ .source = "type Box is data = #Box U32\ntype Left is data = #Left U32\nconst Box.add = fn left => fn right => second\nconst Left.read = fn value => first\nconst combine = fn left => fn right => @type.call \"add\" left right\nconst pick = fn value => value.read\nlet first: U32 = combine (#Box 1) (#Box 2)\nlet second: U32 = pick (#Left 1)\nentry const answer: Unit -> U32 = fn () => first\n", .expected = .initialization_cycle, .point = 247 },
    .{ .source = "type Box value is data = #Box value\nconst Box.from = fn value => first\nconst from = fn value => @type.result \"from\" value\nlet first: Box U32 = from 42\nentry const answer = fn () => case first of\n  #Box value => value\n", .expected = .initialization_cycle, .point = 126 },
    .{ .source = "type Box value is data = #Box value\nconst Box.from = fn value => second\nconst from = fn value => @type.result \"from\" value\nlet first: Box U32 = from 0\nlet second: Box U32 = #Box 42\nentry const answer = fn () => case first of\n  #Box value => value\n", .expected = null, .point = null },
    .{ .source = "type Box value is data = #Box value\nconst Box.pure = fn value => first\nlet first: Box U32 = do (@do.monad Box):\n  return 42\nentry const answer = fn () => case first of\n  #Box value => value\n", .expected = .initialization_cycle, .point = 75 },
    .{ .source = "type Box value is data = #Box value\nconst Box.pure = fn value => second\nlet first: Box U32 = do (@do.monad Box):\n  return 0\nlet second: Box U32 = #Box 42\nentry const answer = fn () => case first of\n  #Box value => value\n", .expected = null, .point = null },
    .{ .source = "type Box value is data = #Box value\nconst Box.pure = fn value => #Box value\nconst Box.bind = fn candidate => fn next => first\nlet first: Box U32 = do (@do.monad Box):\n  use value <- #Box 1\n  return value\nentry const answer = fn () => case first of\n  #Box value => value\n", .expected = .initialization_cycle, .point = 130 },
    .{ .source = "const make = fn () => do:\n  let unused = fn value => value.read\n  return second\nlet first: U32 = make ()\nlet second: U32 = 42\nentry const answer: Unit -> U32 = fn () => first\n", .expected = null, .point = null },
    .{ .source = "type Box is data = #Box U32\nconst Box.add = fn left => fn right => cached\nconst cached = @u32.add 40 2\nconst combine = fn left => fn right => @type.call \"add\" left right\nlet first: U32 = combine (#Box 1) (#Box 2)\nentry const answer: Unit -> U32 = fn () => first\n", .expected = null, .point = null },
};

test "selected startup admitted binary result and resolver targets cover newly reached initializer cells" {
    for (completeness_cases) |c| {
        var module = try lower(a, c.source);
        defer module.deinit(a);
        try emit(a, &module, c.expected, c.point);
    }
}

test "selected startup deferred selector coverage cannot certify relaxed storage reads" {
    var module = try lower(a, completeness_cases[9].source);
    defer module.deinit(a);
    var session = try eval.Session.init(a, &.{module});
    defer session.deinit();
    session.options.trace_runtime_dependencies = true;
    var checked = false;
    for (module.bodies[1..]) |body| {
        if (!body.runtime or body.is_function) continue;
        var facts = try session.startupDependencies(.{ .unit = 1, .binding = body.binding });
        defer facts.deinit(a);
        if (!checked) {
            try std.testing.expect(!facts.complete);
            checked = true;
        }
    }
    try std.testing.expect(checked);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
}

test "selected startup complete and guarded fallback plans release every backend allocation failure" {
    for ([_]usize{ 2, 3, 5, 7, 9, 10 }) |index| {
        var module = try lower(a, completeness_cases[index].source);
        defer module.deinit(a);
        const c = completeness_cases[index];
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, c.expected, c.point });
    }
}

const pattern_cases = [_]struct { source: []const u8, expected: ?backend.Code, point: ?u32 }{
    .{ .source = "let selected: U32 = second\nconst pick = fn () => case 0 of\n  ^selected => 42\n  _ => 0\nlet first: U32 = pick ()\nlet second: U32 = 0\nentry const answer: Unit -> U32 = fn () => first\n", .expected = null, .point = null },
    .{ .source = "let selected: U32 = first\nconst pick = fn () => case 0 of\n  ^selected => 42\n  _ => 0\nlet first: U32 = pick ()\nentry const answer: Unit -> U32 = fn () => first\n", .expected = .initialization_cycle, .point = 89 },
    .{ .source = "type Carrier is data = #Carrier U32\nlet selected: U32 = second\nconst pick = fn () => case (#Carrier 0, 0) of\n  (#Carrier ^selected, _) => 42\n  _ => 0\nlet first: U32 = pick ()\nlet second: U32 = 0\nentry const answer: Unit -> U32 = fn () => first\n", .expected = null, .point = null },
    .{ .source = "type Carrier is data = #Carrier U32\nlet selected: U32 = first\nconst pick = fn () => case (#Carrier 0, 0) of\n  (#Carrier ^selected, _) => 42\n  _ => 0\nlet first: U32 = pick ()\nentry const answer: Unit -> U32 = fn () => first\n", .expected = .initialization_cycle, .point = 153 },
    .{ .source = "type Carrier is data = #Carrier {value: U32}\nlet selected: U32 = second\nconst pick = fn () => case #Carrier {value: 0} of\n  #Carrier {value: ^selected} => 42\n  _ => 0\nlet first: U32 = pick ()\nlet second: U32 = 0\nentry const answer: Unit -> U32 = fn () => first\n", .expected = null, .point = null },
    .{ .source = "type Carrier is data = #Carrier {value: U32}\nlet selected: U32 = first\nconst pick = fn () => case #Carrier {value: 0} of\n  #Carrier {value: ^selected} => 42\n  _ => 0\nlet first: U32 = pick ()\nentry const answer: Unit -> U32 = fn () => first\n", .expected = .initialization_cycle, .point = 170 },
    .{ .source = "let selected: U32 = second\nconst pick = fn () => do:\n  let ^selected = 0 else:\n    return 0\n  return 42\nlet first: U32 = pick ()\nlet second: U32 = 0\nentry const answer: Unit -> U32 = fn () => first\n", .expected = null, .point = null },
    .{ .source = "let selected: U32 = first\nconst pick = fn () => do:\n  let ^selected = 0 else:\n    return 0\n  return 42\nlet first: U32 = pick ()\nentry const answer: Unit -> U32 = fn () => first\n", .expected = .initialization_cycle, .point = 107 },
};

test "selected startup value pattern trees preserve exact source cycles and ordered valid values" {
    for (pattern_cases) |c| {
        var module = try lower(a, c.source);
        defer module.deinit(a);
        try emit(a, &module, c.expected, c.point);
    }
}

test "selected startup value patterns cannot certify relaxed storage in region or opaque coverage" {
    for ([_]usize{ 0, 2, 4, 6 }) |index| {
        var module = try lower(a, pattern_cases[index].source);
        defer module.deinit(a);
        var session = try eval.Session.init(a, &.{module});
        defer session.deinit();
        session.options.trace_runtime_dependencies = true;
        var saw_pattern = false;
        for (module.bodies[1..]) |body| {
            if (body.is_function and module.node(body.root).tag != .reference) {
                try std.testing.expect(!try session.startupSelectorFree(0, body.root));
                saw_pattern = true;
            }
            if (!body.runtime or body.is_function or module.node(body.root).tag != .call) continue;
            var facts = try session.startupDependencies(.{ .unit = 1, .binding = body.binding });
            defer facts.deinit(a);
            try std.testing.expect(!facts.complete);
        }
        try std.testing.expect(saw_pattern);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
        try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
    }
}

const pattern_adversary = "type Box is data = #Box U32\nconst Box.read = fn value => first\nconst box = #Box 1\nconst latent = fn () => box.read\nconst sentinel: U32 = 0\nconst pick = fn () => case 0 of\n  ^sentinel => 42\n  _ => 0\nlet first: U32 = pick ()\nentry const answer: Unit -> U32 = fn () => first\n";
fn patternAdversary(allocator: std.mem.Allocator, module: *const core.Module, target: core.BindingRef) !void {
    var session = try eval.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.options.trace_runtime_dependencies = true;
    var facts = try session.startupDependencies(target);
    defer facts.deinit(allocator);
    try std.testing.expect(!facts.complete);
    try std.testing.expectEqual(@as(usize, 1), facts.selected.len);
    try std.testing.expect(module.body(facts.selected[0].binding).?.is_function);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
}
test "selected startup same owner pattern projection cannot hide a method cycle and releases OOM" {
    var module = try lower(a, pattern_adversary);
    defer module.deinit(a);
    var projection: core.Id = 0;
    for (module.bodies[1..]) |body| if (module.node(body.root).tag == .project) {
        projection = body.root;
    };
    try std.testing.expect(projection != 0);
    var replaced = false;
    for (module.patterns) |*pattern| if (pattern.tag == .value) {
        // One valid, owned U32 project already in this module; no foreign IDs.
        pattern.a = projection;
        replaced = true;
    };
    try std.testing.expect(replaced);
    // Publish a coherent dependency recipe for the new owned Core, just as
    // lowering does. There are no stale source edges or foreign captures.
    a.free(module.declaration_dependencies);
    a.free(module.dependency_references);
    a.free(module.dependency_members);
    module.declaration_dependencies = &.{};
    module.dependency_references = &.{};
    module.dependency_members = &.{};
    try @import("declaration_dependencies.zig").capture(a, &module);
    var target: core.BindingRef = .{ .unit = 1, .binding = 0 };
    for (module.bodies[1..]) |body| if (body.runtime and !body.is_function) {
        target.binding = body.binding;
    };
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try patternAdversary(a, &module, target);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, patternAdversary, .{ &module, target });
    const point = module.runtimeNamePoint(target.binding);
    try emit(a, &module, .initialization_cycle, point);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, @as(?backend.Code, .initialization_cycle), @as(?u32, point) });
    try std.testing.expectEqualSlices(u8, &before, &@import("core_snapshot_tests.zig").stamp(module));
}

test "selected startup empty plan entry selection preserves guarded on demand cells" {
    {
        var module = try lower(a, "type Box is data = #Box U32\nconst Box.read = fn value => second\nconst pick = fn value => value.read\nlet second: U32 = 42\nentry const answer: Unit -> U32 = fn () => pick (#Box 1)\n");
        defer module.deinit(a);
        try emit(a, &module, null, null);
    }
    {
        var module = try lower(a, "const keep = fn ~(value: Unit -> U32) => value\nconst helper = fn () => first\nconst pending = keep helper\nconst cached = @force pending\nconst sentinel: U32 = 0\nconst make = fn () => fn (value: U32) -> U32 => case value of\n  ^sentinel => 42\n  _ => 0\nentry const extra: U32 -> U32 = make ()\nlet first: U32 = cached ()\nentry const answer: Unit -> U32 = fn () => first\n");
        defer module.deinit(a);
        try emit(a, &module, null, null);
    }
    {
        var module = try lower(a, "type Box is data = #Box U32\nconst Box.read = fn value => second\nconst pick = fn value => value.read\nlet second: U32 = second\nentry const answer: Unit -> U32 = fn () => pick (#Box 1)\n");
        defer module.deinit(a);
        try emit(a, &module, .initialization_cycle, 104);
    }
}
