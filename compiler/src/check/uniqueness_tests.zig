const std = @import("std");
const ast = @import("../parse/ast.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;

// Each `:=` marked `// aliased` must be rejected, and every other accepted.
const source =
    \\type Box is data = $Box (Array U32)
    \\type World is data = $World { counts: Array U32, other: Array U32 }
    \\const keep = func (values: Array U32) => return values[0]
    \\const fresh = func (n: U32) => return do:
    \\  let rows = #[1, 2, 3]
    \\  rows[0] := n
    \\  rows[1] := @u32.add self n
    \\  break rows[0]
    \\const named = func (n: U32) => return do:
    \\  let rows = #[1, 2, 3]
    \\  let before = rows
    \\  rows[0] := n // aliased
    \\  break before[0]
    \\const captured = func (n: U32) => return do:
    \\  let rows = #[1, 2]
    \\  let read = func (i: U32) => return rows[i]
    \\  rows[0] := n // aliased
    \\  break read 0
    \\const passed = func (n: U32) => return do:
    \\  let rows = #[1, 2]
    \\  let first = keep rows
    \\  rows[0] := n // aliased
    \\  break first
    \\const constructed = func (n: U32) => return do:
    \\  let rows = #[1, 2]
    \\  let box = $Box rows
    \\  rows[0] := n // aliased
    \\  break box
    \\const parameter = func (rows: Array U32) => return do:
    \\  rows[0] := 1 // aliased
    \\  break rows
    \\const returned_early = func (flag: Bool) => return do:
    \\  let rows = #[1, 2]
    \\  if flag:
    \\    return rows
    \\  rows[0] := 3
    \\  break rows
    \\const sibling = func (flag: Bool) => return do:
    \\  let rows = #[1, 2]
    \\  let first = 0
    \\  if flag:
    \\    first := keep rows
    \\  else:
    \\    rows[0] := 3
    \\  break rows[0]
    \\const looped = func (n: U32) => return do:
    \\  let rows = #[0, 0, 0]
    \\  for i in 0..3:
    \\    rows[i] := n
    \\  break rows
    \\const looped_alias = func (n: U32) => return do:
    \\  let rows = #[0, 0, 0]
    \\  let total = 0
    \\  for i in 0..3:
    \\    rows[i] := n // aliased
    \\    total := keep rows
    \\  break total
    \\const iterated = func (n: U32) => return do:
    \\  let rows = #[1, 2, 3]
    \\  let total = 0
    \\  for value in rows:
    \\    total := @u32.add total value
    \\    rows[0] := n // aliased
    \\  break rows
    \\const element = func (n: U32) => return do:
    \\  let grid = #[#[1, 2], #[3, 4]]
    \\  grid[1][0] := n
    \\  let row = grid[0]
    \\  grid[0][1] := n // aliased
    \\  break row
    \\const shared_rows = func (n: U32) => return do:
    \\  let grid = @array.fill 2 #[0, 0]
    \\  grid[0][0] := n // aliased
    \\  grid[1] := #[n, n]
    \\  break grid
    \\const record_root = func (n: U32) => return do:
    \\  let counts = #[0, 0]
    \\  let world = { counts: counts, other: #[1] }
    \\  world.other[0] := n
    \\  world.counts[0] := n // aliased
    \\  break counts
    \\const nominal_root = func (n: U32) => return do:
    \\  let world = $World { counts: #[0, 0], other: #[1] }
    \\  world.counts[1] := n
    \\  break world
    \\const copied = func (n: U32) => return do:
    \\  let rows = #[1, 2]
    \\  let saved = rows
    \\  let edited = @storage.copy saved
    \\  edited[0] := n
    \\  break edited
    \\const stored = func (n: U32) => return do:
    \\  let rows = #[1, 2]
    \\  let saved = rows
    \\  rows[0] = n
    \\  break saved
;

const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    checked: check.Checked,
    fn init() !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &pool);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |item| std.debug.print("uniqueness {d}: {s}\n", .{ item.span.start, item.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .tree = tree, .pool = pool, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
};

fn lineOf(offset: u32) usize {
    return std.mem.countScalar(u8, source[0..offset], '\n');
}

fn verify(module: *const core.Module) !void {
    var expected: std.ArrayList(usize) = .empty;
    defer expected.deinit(a);
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line: usize = 0;
    while (lines.next()) |text| : (line += 1) {
        if (std.mem.endsWith(u8, text, "// aliased")) try expected.append(a, line);
    }
    var found: std.ArrayList(usize) = .empty;
    defer found.deinit(a);
    for (module.diagnostics) |item| {
        try std.testing.expectEqual(core.Code.aliased_update, item.code);
        try found.append(a, lineOf(item.span.start));
    }
    std.mem.sortUnstable(usize, found.items, {}, std.sort.asc(usize));
    try std.testing.expectEqualSlices(usize, expected.items, found.items);
}

fn lowered(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try core.lower(allocator, &fixture.tree, &fixture.pool, &fixture.checked);
    defer module.deinit(allocator);
    try verify(&module);
}

test "uniqueness accepts updates of fresh unique roots and rejects every aliased one" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try lowered(a, &fixture);
}

test "uniqueness allocation failures release every fact, trail and record table" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowered, .{&fixture});
}
