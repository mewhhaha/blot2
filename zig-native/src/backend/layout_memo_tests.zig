const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const layout = @import("layout.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

const shapes =
    \\type Pair [a, b] is data = $Pair { left: a, right: b }
    \\type Shape is data = $Circle F32 | $Box { width: F32, height: F32 }
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\const area = func (shape: Shape) => return case shape of
    \\  $Circle radius => @f32.mul radius radius
    \\  $Box { width, height } => @f32.mul width height
    \\const swap = func pair => return do:
    \\  let $Pair { left, right } = pair
    \\  break $Pair { left: right, right: left }
    \\const total = func (values: Array (Pair [U32, F32])) => return @array.length values
    \\const counter = func () => return do:
    \\  use value <- State.get ()
    \\  State.set (@u32.add value 1)
    \\  break value
    \\entry const run = func (x: U32) => return do:
    \\  let shapes = #[$Circle 1.0, $Box { width: 2.0, height: 3.0 }]
    \\  let pair = swap ($Pair { left: 2.5, right: x })
    \\  break @u32.add (total #[pair]) (@array.length shapes)
;

/// Derives every type of `units[0]` twice, unsubstituted and with its first
/// variable taken as U32, into `store`, recording each outcome.
fn deriveAll(store: *layout.Store, units: []const core.Module, outcomes: *std.ArrayList(u64), allocator: std.mem.Allocator) !void {
    const module = &units[0];
    var first: ?u32 = null;
    for (module.types.nodes, 0..) |node, id| if (node.tag == .variable) {
        first = @intCast(id);
        break;
    };
    const mapped = [_]layout.Mapping{.{ .variable = first orelse 0, .layout = @import("../check/types.zig").u32_type }};
    for (0..2) |round| for (0..module.types.nodes.len) |id| {
        const mappings: []const layout.Mapping = if (round == 1 and first != null) &mapped else &.{};
        for ([_]bool{ false, true }) |partial| {
            const outcome: u64 = if (store.fromTypeWithRows(module, @intCast(id), mappings, &.{}, partial)) |value| value else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnresolvedType => 1 << 40,
                error.LayoutLimit => 2 << 40,
                error.TypeMismatch => 3 << 40,
            };
            try outcomes.append(allocator, outcome);
        }
    };
}

fn memoScenario(allocator: std.mem.Allocator, units: []const core.Module, expected: []const u64) !void {
    var store = try layout.Store.init(allocator);
    defer store.deinit();
    store.closed.units = units;
    var outcomes: std.ArrayList(u64) = .empty;
    defer outcomes.deinit(allocator);
    try deriveAll(&store, units, &outcomes, allocator);
    try std.testing.expectEqualSlices(u64, expected, outcomes.items);
}

test "closed type layouts memoized per unit equal fresh derivations under substitutions and allocation failure" {
    var module = try lower(a, shapes);
    defer module.deinit(a);
    const units = [_]core.Module{module};
    var fresh = try layout.Store.init(a);
    defer fresh.deinit();
    var expected: std.ArrayList(u64) = .empty;
    defer expected.deinit(a);
    try deriveAll(&fresh, &units, &expected, a);
    try std.testing.expectEqual(@as(usize, 0), fresh.closed.layouts.count());
    var memoized = try layout.Store.init(a);
    defer memoized.deinit();
    memoized.closed.units = &units;
    var actual: std.ArrayList(u64) = .empty;
    defer actual.deinit(a);
    try deriveAll(&memoized, &units, &actual, a);
    // The memo returns exactly what a fresh derivation interns.
    try std.testing.expectEqualSlices(u64, expected.items, actual.items);
    try std.testing.expectEqual(fresh.nodes.items.len, memoized.nodes.items.len);
    try std.testing.expect(memoized.closed.layouts.count() != 0);
    // A module outside the memoized units is derived without the memo.
    var copy = module;
    var outside: std.ArrayList(u64) = .empty;
    defer outside.deinit(a);
    const before = memoized.closed.layouts.count();
    try deriveAll(&memoized, (&copy)[0..1], &outside, a);
    try std.testing.expectEqualSlices(u64, expected.items, outside.items);
    try std.testing.expectEqual(before, memoized.closed.layouts.count());
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, memoScenario, .{ &units, expected.items });
}
