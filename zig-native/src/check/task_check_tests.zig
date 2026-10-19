const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
fn law(allocator: std.mem.Allocator, source: []const u8, expected: ?checker.Code) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    if (syntax.diagnostics.items.len != 0) std.debug.print("task parse source: {s}\n", .{source});
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &syntax, &names, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    if (expected) |code| {
        for (checked.diagnostics) |diagnostic| if (diagnostic.code == code) return;
        for (checked.diagnostics) |diagnostic| std.debug.print("task fixture: {s}\n", .{@tagName(diagnostic.code)});
        return error.ExpectedTaskDiagnostic;
    }
    for (checked.diagnostics) |diagnostic| std.debug.print("task fixture: {s} at {}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    if (checked.diagnostics.len != 0) std.debug.print("task source: {s}\n", .{source});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(allocator, &syntax, &names, &checked);
    defer module.deinit(allocator);
    if (module.diagnostics.len != 0) std.debug.print("task lower source: {s}\n", .{source});
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try format.encode(allocator, key, module);
    defer allocator.free(bytes);
    var decoded = try format.decode(@import("core.zig").Module, allocator, bytes, key);
    defer decoded.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &decoded, .{});
}
const siblings =
    \\entry const answer = fn () => @task.scope (fn group => do:
    \\  let left = @task.spawn group (fn () => 20)
    \\  let right = @task.spawn group (fn () => 22)
    \\  return @u32.add (@task.join left) (@task.join right))
;
test "structured task checking admits once siblings and closed immutable captures" {
    try law(std.testing.allocator, siblings, null);
    try law(std.testing.allocator,
        \\entry const answer = fn (value: U32) => @task.scope (fn group => do:
        \\  let task = @task.spawn group (fn () => value)
        \\  return @task.join task)
    , null);
    try law(std.testing.allocator,
        \\const nested = fn () => @task.scope (fn inner => @task.join (@task.spawn inner (fn () => 42)))
        \\entry const answer = fn () => @task.scope (fn group => @task.join (@task.spawn group (fn () => nested ())))
    , null);
}
test "structured task checking rejects escaped groups and consumed handles" {
    try law(std.testing.allocator, "entry const answer = fn () => @task.scope (fn group => group)", .task_escape);
    try law(std.testing.allocator,
        \\entry const answer = fn () => @task.scope (fn group => do:
        \\  let task = @task.spawn group (fn () => 42)
        \\  let first = @task.join task
        \\  return @task.join task)
    , .task_handle_consumed);
    try law(std.testing.allocator, "entry const answer = fn () => @task.scope (fn group => @task.spawn group (fn () => 42))", .task_escape);
}

fn scopedTaskResults(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const bad = fn () => @task.scope (fn group => do:
        \\  let child = @task.spawn group (fn () => fn () => @task.join (@task.spawn group (fn () => 42)))
        \\  return @task.join child)
    , .task_escape);
    try law(allocator,
        \\type Package = exists [a] => {value: a, apply: a -> U32}
        \\const bad = fn () => @task.scope (fn group => do:
        \\  let child = @task.spawn group (fn () => pack [U32] {value: 0, apply: fn (value: U32) => @task.join (@task.spawn group (fn () => value))} as Package)
        \\  return @task.join child)
    , .task_escape);
}
test "structured tasks reject children returning group scoped callbacks and packages through OOM" {
    try scopedTaskResults(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedTaskResults, .{});
}
test "structured task checking transfers unique captures and rejects ordinary Foreign contracts" {
    try law(std.testing.allocator,
        \\const take = fn (value: unique U32) => @task.scope (fn group => do:
        \\  let task = @task.spawn group (fn () => value)
        \\  return @task.join task)
    , null);
    try law(std.testing.allocator,
        \\const take = fn (value: unique U32) => @task.scope (fn group => do:
        \\  let task = @task.spawn group (fn () => value)
        \\  let moved = @task.join task
        \\  return value)
    , .use_after_move);
    try law(std.testing.allocator,
        \\entry const answer = fn (host: Unit -> U32 ! {Foreign}) => @task.scope (fn group => do:
        \\  let task = @task.spawn group (fn () => host ())
        \\  return @task.join task)
    , .task_host_contract);
}
test "structured task checking preserves every failed source allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, law, .{ siblings, null });
}
const partitioned =
    \\const partition = fn (owner: unique (Array U32)) => @task.split owner ((0, 2), (2, 4)) (fn views => do:
    \\  let (left, right) = views
    \\  let before = @task.read left 0
    \\  let written = @task.write left 0 (@u32.add before 1)
    \\  return @task.scope (fn group => do:
    \\    let first = @task.spawn group (fn () => @task.read left 0)
    \\    let second = @task.spawn group (fn () => @task.read right 0)
    \\    return @u32.add (@task.join first) (@task.join second)))
;
test "structured task checking proves one owner version and disjoint affine view captures" {
    try law(std.testing.allocator, partitioned, null);
}
test "structured task checking rejects overlapping unknown forged and escaping views" {
    try law(std.testing.allocator,
        \\const partition = fn (owner: unique (Array U32)) => @task.split owner ((0, 3), (2, 4)) (fn views => ())
    , .task_regions_overlap);
    try law(std.testing.allocator,
        \\const partition = fn (owner: unique (Array U32)) => fn (index: U32) => @task.split owner ((0, index), (2, 4)) (fn views => ())
    , .task_regions_overlap);
    try law(std.testing.allocator,
        \\const partition = fn (owner: Array U32) => @task.split owner ((0, 2), (2, 4)) (fn views => ())
    , .task_regions_overlap);
    try law(std.testing.allocator,
        \\const partition = fn (owner: unique (Array U32)) => @task.split owner ((0, 2), (2, 4)) (fn views => views)
    , .task_escape);
    try law(std.testing.allocator,
        \\const partition = fn (owner: unique (Array U32)) => @task.split owner ((0, 2), (2, 4)) (fn views => do:
        \\  let (left, right) = views
        \\  return @task.scope (fn group => do:
        \\    let first = @task.spawn group (fn () => @task.read left 0)
        \\    let second = @task.spawn group (fn () => @task.read left 1)
        \\    return @u32.add (@task.join first) (@task.join second)))
    , .use_after_move);
}
test "structured task checking rejects shared pending demand forcing and accepts ready immutable values" {
    try law(std.testing.allocator,
        \\const shared = fn ~(value: U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => @demand value)))
    , .task_demand_shared);
    try law(std.testing.allocator,
        \\const ready = fn ~(value: U32) => do:
        \\  let computed = @demand value
        \\  return @task.scope (fn group => @task.join (@task.spawn group (fn () => computed)))
    , null);
}

test "structured tasks retain read loans whose enclosing borrow owns the group" {
    try law(std.testing.allocator,
        \\const inspect = fn (owner: unique U32) => @usage.borrow owner (fn loan => @task.scope (fn group => do:
        \\  let first = @task.spawn group (fn () => @usage.read loan)
        \\  let second = @task.spawn group (fn () => @usage.read loan)
        \\  return @u32.add (@task.join first) (@task.join second)))
    , null);
    try law(std.testing.allocator,
        \\const inspect = fn (owner: unique U32) => @usage.borrow_mut owner (fn loan => @task.scope (fn group => @task.join (@task.spawn group (fn () => @usage.read loan))))
    , .task_capability_shared);
    try law(std.testing.allocator,
        \\entry const bad = fn (host: concurrent (U32 -> U32)) => host 1
    , .task_host_contract);
}

test "structured tasks move one affine demand and reject its parent reuse" {
    try law(std.testing.allocator,
        \\const take = fn ~(value: unique U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => @demand value)))
    , null);
    try law(std.testing.allocator,
        \\const take = fn ~(value: unique U32) => @task.scope (fn group => do:
        \\  let task = @task.spawn group (fn () => @demand value)
        \\  let result = @task.join task
        \\  return @demand value)
    , .use_after_move);
}

test "structured task thunks preserve checked local once aliases" {
    try law(std.testing.allocator,
        \\const take = fn (owner: unique U32) => @task.scope (fn group => do:
        \\  let thunk: once (Unit -> unique U32) = fn () => owner
        \\  let alias = thunk
        \\  return @task.join (@task.spawn group alias))
    , null);
}

test "task captures must enclose their actual destination group" {
    try law(std.testing.allocator,
        \\const bad = fn () => @task.scope (fn outer => @task.scope (fn inner => do:
        \\  let task = @task.spawn outer (fn () => @task.join (@task.spawn inner (fn () => 42)))
        \\  return 7))
    , .task_capture_transfer);
    try law(std.testing.allocator,
        \\const bad = fn (owner: unique (Array U32)) => @task.scope (fn outer => do:
        \\  let (owner, result) = @task.split owner ((0, 1), (1, 2)) (fn views => do:
        \\    let (left, right) = views
        \\    let task = @task.spawn outer (fn () => @task.read left 0)
        \\    return 7)
        \\  return result)
    , .task_capture_transfer);
    try law(std.testing.allocator,
        \\const bad = fn (owner: unique U32) => @task.scope (fn outer => @usage.borrow owner (fn loan => do:
        \\  let task = @task.spawn outer (fn () => @usage.read loan)
        \\  return 7))
    , .task_capability_shared);
    try law(std.testing.allocator,
        \\const good = fn () => @task.scope (fn group => do:
        \\  let task = @task.spawn group (fn () => @task.join (@task.spawn group (fn () => 42)))
        \\  return 7)
    , null);
}

test "task owner payload does not erase scoped resource cleanup authority" {
    try law(std.testing.allocator,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\const bad = fn () => @effect.scope (fn (state: State U32) => do:
        \\  use owner <- @resource.acquire (fn () => #[20, 22]) (fn resource => do:
        \\    let retained = state
        \\    return ())
        \\  let (owner, result) = @task.split owner ((0, 1), (1, 2)) (fn views => do:
        \\    let (left, right) = views
        \\    return @task.scope (fn group => @task.join (@task.spawn group (fn () => @task.read left 0))))
        \\  return result)
    , .cleanup_not_safe);
}

test "structured task scope and capture proof accepts more than 64 direct children" {
    var buffer: [16_384]u8 = undefined;
    var source = std.Io.Writer.fixed(&buffer);
    try source.writeAll("entry const answer = fn (value: U32) => @task.scope (fn group => do:\n");
    for (0..96) |index| try source.print("  let outer_{d} = {d}\n", .{ index, index });
    try source.writeAll("  let child = @task.spawn group (fn () => do:\n");
    for (0..96) |index| try source.print("    let inner_{d} = {d}\n", .{ index, index });
    try source.writeAll("    return @u32.add value 22)\n  return @task.join child)\n");
    try law(std.testing.allocator, source.buffered(), null);
}

test "structured tasks preserve generic helper group view loan and recursive pure calls" {
    try law(std.testing.allocator,
        \\const identity = fn value => value
        \\entry const answer = fn () => @task.scope (fn group => do:
        \\  let alias = identity group
        \\  return @task.join (@task.spawn alias (fn () => 42)))
    , null);
    try law(std.testing.allocator,
        \\const changed = fn (values: Array U32) => @array.set values 0 42
        \\entry const answer = fn (values: Array U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => @array.get (changed values) 0)))
    , null);
    try law(std.testing.allocator,
        \\const identity = fn (value: unique a) => value
        \\const partition = fn (owner: unique (Array U32)) => @task.split owner ((0, 1), (1, 2)) (fn views => do:
        \\  let (left, right) = views
        \\  let alias = identity left
        \\  return @task.scope (fn group => @task.join (@task.spawn group (fn () => @task.read alias 0))))
    , null);
    try law(std.testing.allocator,
        \\const read: forall [region r] => (borrow r U32) -> U32 = fn loan => @usage.read loan
        \\const inspect = fn (owner: unique U32) => @usage.borrow owner (fn loan => @task.scope (fn group => @task.join (@task.spawn group (fn () => read loan))))
    , null);
    try law(std.testing.allocator,
        \\const apply = fn (f: U32 -> U32) => fn (value: U32) => f value
        \\entry const answer = fn () => @task.scope (fn group => do:
        \\  let offset: U32 -> U32 = fn (value: U32) => @u32.add value 22
        \\  return @task.join (@task.spawn group (fn () => apply offset 20)))
    , null);
    try law(std.testing.allocator,
        \\const identity = fn value => value
        \\entry const answer = fn (host: concurrent (U32 -> U32 ! {Foreign})) => @task.scope (fn group => @task.join (@task.spawn group (fn () => do:
        \\  let alias = identity host
        \\  use value <- alias 20
        \\  return value)))
    , null);
    try law(std.testing.allocator,
        \\const recur = fn (value: U32) -> U32 => if @u32.eq value 0 then 42 else recur (@u32.sub value 1)
        \\entry const answer = fn () => @task.scope (fn group => @task.join (@task.spawn group (fn () => recur 3)))
    , null);
}

fn namedRegionHelper(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const read: forall [region r] => (borrow r U32) -> U32 = fn loan => @usage.read loan
        \\const inspect = fn (owner: unique U32) => @usage.borrow owner (fn loan => @task.scope (fn group => @task.join (@task.spawn group (fn () => read loan))))
    , null);
}
test "structured task named region helper preserves every failed allocation" {
    try namedRegionHelper(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, namedRegionHelper, .{});
}
