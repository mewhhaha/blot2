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
    @import("frozen_core_validation.zig").validate(allocator, &module, .{}) catch |err| {
        std.debug.print("task validation source: {s}\n", .{source});
        return err;
    };
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try format.encode(allocator, key, module);
    defer allocator.free(bytes);
    var decoded = try format.decode(@import("core.zig").Module, allocator, bytes, key);
    defer decoded.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &decoded, .{});
}
const siblings =
    \\entry const answer = func () => return @task.scope (func group => return do:
    \\  let left = @task.spawn group (func () => return 20)
    \\  let right = @task.spawn group (func () => return 22)
    \\  break @u32.add (@task.join left) (@task.join right))
;
test "spawn wrappers validate each actual action and preserve explicit group identity" {
    try law(std.testing.allocator,
        \\const launch = func group => return func action => return @task.spawn group action
        \\const alias = launch
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let pending = alias group (func () => return 42)
        \\  break |pending|)
    , null);
    try law(std.testing.allocator,
        \\const launch = func group => return func action => return @task.spawn group action
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let partial = launch group
        \\  let alias = partial
        \\  let pending = alias (func () => return 42)
        \\  break |pending|)
    , null);
    try law(std.testing.allocator,
        \\const launch = func group => return func action => return @task.spawn group action
        \\entry const answer = func () => return @task.scope (func outer => return @task.scope (func inner => return do:
        \\  let pending = launch outer (func () => return @task.join (@task.spawn inner (func () => return 42)))
        \\  break |pending|))
    , .task_capture_transfer);
    try law(std.testing.allocator,
        \\const launch = func group => return func action => return @task.spawn group action
        \\const identity = func value => return value
        \\const escaping = identity launch
    , .task_capture_transfer);
}
test "structured task checking admits once siblings and closed immutable captures" {
    try law(std.testing.allocator, siblings, null);
    try law(std.testing.allocator,
        \\entry const answer = func (value: U32) => return @task.scope (func group => return do:
        \\  let task = @task.spawn group (func () => return value)
        \\  break @task.join task)
    , null);
    try law(std.testing.allocator,
        \\const nested = func () => return @task.scope (func inner => return @task.join (@task.spawn inner (func () => return 42)))
        \\entry const answer = func () => return @task.scope (func group => return @task.join (@task.spawn group (func () => return nested ())))
    , null);
}
test "spark and receive use the checked explicit task scope" {
    try law(std.testing.allocator,
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  return 42)
    , null);
    try law(std.testing.allocator,
        \\const add22 = func value => return @u32.add value 22
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let pending = *(add22 20)
        \\  return |pending|)
    , null);
    try law(std.testing.allocator,
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let pending = @task.spawn group (func () => return 42)
        \\  let first = |pending|
        \\  return |pending|)
    , .task_handle_consumed);
}

test "task collection checks stored receiver tuples and preserves tuple payloads" {
    try law(std.testing.allocator,
        \\const await = func source => return |source|
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let left = @task.spawn group (func () => return 20)
        \\  let right = @task.spawn group (func () => return 22)
        \\  let receivers = (left, right)
        \\  let (first, second) = await receivers
        \\  break @u32.add first second)
    , null);
    try law(std.testing.allocator,
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let left = @task.spawn group (func () => return 20)
        \\  let right = @task.spawn group (func () => return 22)
        \\  let receivers = (left, right)
        \\  let (first, second) = |receivers|
        \\  break @u32.add first second)
    , null);
    try law(std.testing.allocator,
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let pending = @task.spawn group (func () => return (20, 22))
        \\  let (first, second) = |pending|
        \\  break @u32.add first second)
    , null);
    try law(std.testing.allocator,
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let pending = @task.spawn group (func () => return 42)
        \\  break |(pending, pending)|)
    , .task_handle_consumed);
    try law(std.testing.allocator,
        \\const duplicate = func source => return (|source|, |source|)
    , .task_host_contract);
}

fn inferredSparkRegion(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const identity = func value => return value
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let group = 100
        \\  let pending = *(identity 42)
        \\  break @u32.add group (|pending|))
    , null);
    try law(allocator,
        \\const identity = func value => return value
        \\entry const answer = func () => return *(identity 42)
    , .task_escape);
    try law(allocator,
        \\const identity = func value => return value
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let delayed = func () => return *(identity 42)
        \\  break ())
    , .task_escape);
}

test "spark region checking preserves exact scope owners under shadowing through OOM" {
    try inferredSparkRegion(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, inferredSparkRegion, .{});
}

fn wrappedTaskScope(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const identity = func value => return value
        \\const wrap = func () => return func body => return scope body
        \\const relay = identity (wrap ())
        \\entry const answer = func () => return relay (func group => return @task.join (@task.spawn group (func () => return 42)))
    , null);
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const relay = func body => return scope body
        \\const identity = func value => return value
        \\entry const answer = func () => return relay (func group => return do:
        \\  let pending = *(identity 42)
        \\  break |pending|)
    , null);
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const renamed = scope
        \\const identity = func value => return value
        \\entry const answer = func () => return renamed (func group => return do:
        \\  let pending = *(identity 42)
        \\  break |pending|)
    , null);
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const identity = func value => return value
        \\entry const answer = func () => return scope (func outer => return do:
        \\  let first = *(identity 20)
        \\  let second = scope (func inner => return do:
        \\    let pending = *(identity 22)
        \\    break |pending|)
        \\  break @u32.add (|first|) second)
    , null);
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\entry const escaped = func () => return scope (func group => return group)
    , .task_escape);
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const identity = func value => return value
        \\entry const escaped = func () => return scope (func group => return *(identity 42))
    , .task_escape);
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const relay = func body => return scope body
        \\entry const escaped = func () => return relay (func group => return func () => return @task.join (@task.spawn group (func () => return 42)))
    , .task_escape);
}

test "ordinary task scope wrappers preserve fresh regions and reject escaping results through OOM" {
    try wrappedTaskScope(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, wrappedTaskScope, .{});
}
test "structured task checking rejects escaped groups and consumed handles" {
    try law(std.testing.allocator, "entry const answer = func () => return @task.scope (func group => return group)", .task_escape);
    try law(std.testing.allocator,
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let task = @task.spawn group (func () => return 42)
        \\  let first = @task.join task
        \\  break @task.join task)
    , .task_handle_consumed);
    try law(std.testing.allocator, "entry const answer = func () => return @task.scope (func group => return @task.spawn group (func () => return 42))", .task_escape);
}

fn scopedTaskResults(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const bad = func () => return @task.scope (func group => return do:
        \\  let child = @task.spawn group (func () => return func () => return @task.join (@task.spawn group (func () => return 42)))
        \\  break @task.join child)
    , .task_escape);
    try law(allocator,
        \\type Package = exists [a] => {value: a, apply: a -> U32}
        \\const bad = func () => return @task.scope (func group => return do:
        \\  let child = @task.spawn group (func () => return pack [U32] {value: 0, apply: func (value: U32) => return @task.join (@task.spawn group (func () => return value))} as Package)
        \\  break @task.join child)
    , .task_escape);
}
test "structured tasks reject children returning group scoped callbacks and packages through OOM" {
    try scopedTaskResults(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedTaskResults, .{});
}
test "structured task checking transfers unique captures and rejects ordinary Foreign contracts" {
    try law(std.testing.allocator,
        \\const take = func (value: unique U32) => return @task.scope (func group => return do:
        \\  let task = @task.spawn group (func () => return value)
        \\  break @task.join task)
    , null);
    try law(std.testing.allocator,
        \\const take = func (value: unique U32) => return @task.scope (func group => return do:
        \\  let task = @task.spawn group (func () => return value)
        \\  let moved = @task.join task
        \\  break value)
    , .use_after_move);
    try law(std.testing.allocator,
        \\entry const answer = func (host: Unit -> U32 ! {Foreign}) => return @task.scope (func group => return do:
        \\  let task = @task.spawn group (func () => return host ())
        \\  break @task.join task)
    , .task_host_contract);
}
test "structured task checking preserves every failed source allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, law, .{ siblings, null });
}
const partitioned =
    \\const partition = func (owner: unique (Array U32)) => return @task.split owner ((0, 2), (2, 4)) (func views => return do:
    \\  let (left, right) = views
    \\  let before = @task.read left 0
    \\  let written = @task.write left 0 (@u32.add before 1)
    \\  break @task.scope (func group => return do:
    \\    let first = @task.spawn group (func () => return @task.read left 0)
    \\    let second = @task.spawn group (func () => return @task.read right 0)
    \\    break @u32.add (@task.join first) (@task.join second)))
;
test "structured task checking proves one owner version and disjoint affine view captures" {
    try law(std.testing.allocator, partitioned, null);
}
test "structured task checking rejects overlapping unknown forged and escaping views" {
    try law(std.testing.allocator,
        \\const partition = func (owner: unique (Array U32)) => return @task.split owner ((0, 3), (2, 4)) (func views => return ())
    , .task_regions_overlap);
    try law(std.testing.allocator,
        \\const partition = func (owner: unique (Array U32)) => return func (index: U32) => return @task.split owner ((0, index), (2, 4)) (func views => return ())
    , .task_regions_overlap);
    try law(std.testing.allocator,
        \\const partition = func (owner: Array U32) => return @task.split owner ((0, 2), (2, 4)) (func views => return ())
    , .task_regions_overlap);
    try law(std.testing.allocator,
        \\const partition = func (owner: unique (Array U32)) => return @task.split owner ((0, 2), (2, 4)) (func views => return views)
    , .task_escape);
    try law(std.testing.allocator,
        \\const partition = func (owner: unique (Array U32)) => return @task.split owner ((0, 2), (2, 4)) (func views => return do:
        \\  let (left, right) = views
        \\  break @task.scope (func group => return do:
        \\    let first = @task.spawn group (func () => return @task.read left 0)
        \\    let second = @task.spawn group (func () => return @task.read left 1)
        \\    break @u32.add (@task.join first) (@task.join second)))
    , .use_after_move);
}
test "structured task checking rejects shared pending demand forcing and accepts ready immutable values" {
    try law(std.testing.allocator,
        \\const shared = func ~(value: U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return @demand value)))
    , .task_demand_shared);
    try law(std.testing.allocator,
        \\const ready = func ~(value: U32) => return do:
        \\  let computed = @demand value
        \\  break @task.scope (func group => return @task.join (@task.spawn group (func () => return computed)))
    , null);
}

test "structured tasks retain read loans whose enclosing borrow owns the group" {
    try law(std.testing.allocator,
        \\const inspect = func (owner: unique U32) => return @usage.borrow owner (func loan => return @task.scope (func group => return do:
        \\  let first = @task.spawn group (func () => return @usage.read loan)
        \\  let second = @task.spawn group (func () => return @usage.read loan)
        \\  break @u32.add (@task.join first) (@task.join second)))
    , null);
    try law(std.testing.allocator,
        \\const inspect = func (owner: unique U32) => return @usage.borrow_mut owner (func loan => return @task.scope (func group => return @task.join (@task.spawn group (func () => return @usage.read loan))))
    , .task_capability_shared);
    try law(std.testing.allocator,
        \\entry const bad = func (host: concurrent (U32 -> U32)) => return host 1
    , .task_host_contract);
}

test "structured tasks move one affine demand and reject its parent reuse" {
    try law(std.testing.allocator,
        \\const take = func ~(value: unique U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return @demand value)))
    , null);
    try law(std.testing.allocator,
        \\const take = func ~(value: unique U32) => return @task.scope (func group => return do:
        \\  let task = @task.spawn group (func () => return @demand value)
        \\  let result = @task.join task
        \\  break @demand value)
    , .use_after_move);
}

test "structured task thunks preserve checked local once aliases" {
    try law(std.testing.allocator,
        \\const take = func (owner: unique U32) => return @task.scope (func group => return do:
        \\  let thunk: once (Unit -> unique U32) = func () => return owner
        \\  let alias = thunk
        \\  break @task.join (@task.spawn group alias))
    , null);
}

test "task captures must enclose their actual destination group" {
    try law(std.testing.allocator,
        \\const bad = func () => return @task.scope (func outer => return @task.scope (func inner => return do:
        \\  let task = @task.spawn outer (func () => return @task.join (@task.spawn inner (func () => return 42)))
        \\  break 7))
    , .task_capture_transfer);
    try law(std.testing.allocator,
        \\const bad = func (owner: unique (Array U32)) => return @task.scope (func outer => return do:
        \\  let (owner, result) = @task.split owner ((0, 1), (1, 2)) (func views => return do:
        \\    let (left, right) = views
        \\    let task = @task.spawn outer (func () => return @task.read left 0)
        \\    break 7)
        \\  break result)
    , .task_capture_transfer);
    try law(std.testing.allocator,
        \\const bad = func (owner: unique U32) => return @task.scope (func outer => return @usage.borrow owner (func loan => return do:
        \\  let task = @task.spawn outer (func () => return @usage.read loan)
        \\  break 7))
    , .task_capability_shared);
    try law(std.testing.allocator,
        \\const good = func () => return @task.scope (func group => return do:
        \\  let task = @task.spawn group (func () => return @task.join (@task.spawn group (func () => return 42)))
        \\  break 7)
    , null);
}

test "task owner payload does not erase scoped resource cleanup authority" {
    try law(std.testing.allocator,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\const bad = func () => return @effect.scope (func (state: State U32) => return do:
        \\  use owner <- @resource.acquire (func () => return #[20, 22]) (func resource => return do:
        \\    let retained = state
        \\    break ())
        \\  let (owner, result) = @task.split owner ((0, 1), (1, 2)) (func views => return do:
        \\    let (left, right) = views
        \\    break @task.scope (func group => return @task.join (@task.spawn group (func () => return @task.read left 0))))
        \\  break result)
    , .cleanup_not_safe);
}

test "structured task scope and capture proof accepts more than 64 direct children" {
    var buffer: [16_384]u8 = undefined;
    var source = std.Io.Writer.fixed(&buffer);
    try source.writeAll("entry const answer = func (value: U32) => return @task.scope (func group => return do:\n");
    for (0..96) |index| try source.print("  let outer_{d} = {d}\n", .{ index, index });
    try source.writeAll("  let child = @task.spawn group (func () => return do:\n");
    for (0..96) |index| try source.print("    let inner_{d} = {d}\n", .{ index, index });
    try source.writeAll("    break @u32.add value 22)\n  break @task.join child)\n");
    try law(std.testing.allocator, source.buffered(), null);
}

test "structured tasks preserve generic helper group view loan and recursive pure calls" {
    try law(std.testing.allocator,
        \\const identity = func value => return value
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let alias = identity group
        \\  break @task.join (@task.spawn alias (func () => return 42)))
    , null);
    try law(std.testing.allocator,
        \\const changed = func (values: Array U32) => return @array.set values 0 42
        \\entry const answer = func (values: Array U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return @array.get (changed values) 0)))
    , null);
    try law(std.testing.allocator,
        \\const identity = func (value: unique a) => return value
        \\const partition = func (owner: unique (Array U32)) => return @task.split owner ((0, 1), (1, 2)) (func views => return do:
        \\  let (left, right) = views
        \\  let alias = identity left
        \\  break @task.scope (func group => return @task.join (@task.spawn group (func () => return @task.read alias 0))))
    , null);
    try law(std.testing.allocator,
        \\const read: forall [region r] => (borrow r U32) -> U32 = func loan => return @usage.read loan
        \\const inspect = func (owner: unique U32) => return @usage.borrow owner (func loan => return @task.scope (func group => return @task.join (@task.spawn group (func () => return read loan))))
    , null);
    try law(std.testing.allocator,
        \\const apply = func (f: U32 -> U32) => return func (value: U32) => return f value
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let offset: U32 -> U32 = func (value: U32) => return @u32.add value 22
        \\  break @task.join (@task.spawn group (func () => return apply offset 20)))
    , null);
    try law(std.testing.allocator,
        \\const identity = func value => return value
        \\entry const answer = func (host: concurrent (U32 -> U32 ! {Foreign})) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return do:
        \\  let alias = identity host
        \\  use value <- alias 20
        \\  break value)))
    , null);
    try law(std.testing.allocator,
        \\const recur = func (value: U32) : U32 => return if @u32.eq value 0 then 42 else recur (@u32.sub value 1)
        \\entry const answer = func () => return @task.scope (func group => return @task.join (@task.spawn group (func () => return recur 3)))
    , null);
}

fn namedRegionHelper(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const read: forall [region r] => (borrow r U32) -> U32 = func loan => return @usage.read loan
        \\const inspect = func (owner: unique U32) => return @usage.borrow owner (func loan => return @task.scope (func group => return @task.join (@task.spawn group (func () => return read loan))))
    , null);
}
test "structured task named region helper preserves every failed allocation" {
    try namedRegionHelper(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, namedRegionHelper, .{});
}

fn dollarTaskScope(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const identity = func value => return value
        \\entry const control = func () => return scope (func outer => return do:
        \\  let first = *(identity 20)
        \\  let second = scope (func inner => return do:
        \\    let pending = *(identity 22)
        \\    break |pending|)
        \\  break @u32.add (|first|) second)
    , null);
    try law(allocator,
        \\const identity = func value => return value
        \\entry const answer = func () => return @task.scope $ func group => return do:
        \\  let first = @task.spawn group $ func () => return 20
        \\  let second = *(identity 22)
        \\  let (a, b) = |(first, second)|
        \\  break @u32.add a b
    , null);
    try law(allocator,
        \\const scope = func body => return @task.scope body
        \\const identity = func value => return value
        \\entry const answer = func () => return scope $ func outer => return do:
        \\  let first = *(identity 20)
        \\  let second = scope $ func inner => return do:
        \\    let pending = *(identity 22)
        \\    break |pending|
        \\  break @u32.add (|first|) second
    , null);
    try law(allocator, "entry const escaped = func () => return @task.scope $ func group => return group", .task_escape);
    try law(allocator,
        \\const identity = func value => return value
        \\entry const escaped = func () => return @task.scope $ func group => return *(identity 42)
    , .task_escape);
    try law(allocator,
        \\entry const doubled = func () => return @task.scope $ func group => return do:
        \\  let pending = @task.spawn group $ func () => return 42
        \\  let first = |pending|
        \\  break @u32.add first (|pending|)
    , .task_handle_consumed);
}

test "dollar application preserves task scope and ownership through OOM" {
    try dollarTaskScope(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, dollarTaskScope, .{});
}
