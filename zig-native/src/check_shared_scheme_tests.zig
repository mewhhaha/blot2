//! Schemes with many obligations are used by reference. These tests pin the
//! work bounds and the cases that must keep ordinary flat instantiation.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const a = std.testing.allocator;

const header =
    \\infixl 60 (+) = _fixity_add
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
    \\
;
/// A nominal counter whose `+` resolves through an associated member.
const counter =
    \\type N is data = #N U32
    \\const N.add = fn left => fn right => case left, right of
    \\  #N a, #N b => #N (@u32.add a b)
    \\
;
const box =
    \\type Box a is data = #Box a
    \\const Box.add = fn left => fn right => case left, right of
    \\  #Box a, #Box b => #Box (a + b)
    \\
;
const Fixture = struct {
    pool: symbols.Pool = .{},
    tree: ast.Tree,
    checked: check.Checked,
    fn init(text: []const u8) !Fixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const checked = try check.check(a, &tree, &pool);
        return .{ .pool = pool, .tree = tree, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn valid(self: *const Fixture) !void {
        for (self.checked.diagnostics) |d| std.debug.print("{s}:{d}\n", .{ @tagName(d.code), d.span.start });
        try std.testing.expectEqual(@as(usize, 0), self.checked.diagnostics.len);
    }
    fn binding(self: *const Fixture, name: []const u8) ?check.Binding {
        for (self.checked.bindings[1..]) |value| if (value.kind == .global and std.mem.eql(u8, self.pool.get(value.name), name)) return value;
        return null;
    }
};
/// `v + v + ... + v` with enough additions to exceed the sharing threshold.
fn wideSum(out: *std.ArrayList(u8), operand: []const u8, terms: usize) !void {
    try out.appendSlice(a, operand);
    for (1..terms) |_| {
        try out.appendSlice(a, " + ");
        try out.appendSlice(a, operand);
    }
}
fn diamond(depth: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, header);
    try out.appendSlice(a, counter);
    try out.appendSlice(a, "const f_0 = fn x => x + (#N 1)\n");
    for (1..depth + 1) |i| try out.print(a, "const f_{d} = fn x => f_{d} (f_{d} x)\n", .{ i, i - 1, i - 1 });
    try out.print(a, "entry const main = fn (x: N) -> N => f_{d} x\n", .{depth});
    return out.toOwnedSlice(a);
}
fn chain(depth: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, header);
    try out.appendSlice(a, counter);
    try out.appendSlice(a, "const f_0 = fn x => x + (#N 1)\n");
    for (1..depth + 1) |i| try out.print(a, "const f_{d} = fn x => f_{d} x + (#N 1)\n", .{ i, i - 1 });
    try out.print(a, "entry const main = fn (x: N) -> N => f_{d} x\n", .{depth});
    return out.toOwnedSlice(a);
}
fn appended(source: []const u8) !u64 {
    var f = try Fixture.init(source);
    defer f.deinit();
    try f.valid();
    return f.checked.counters.obligations_appended;
}

test "a deep diamond of unannotated generic functions checks with bounded obligations" {
    const source = try diamond(24);
    defer a.free(source);
    var f = try Fixture.init(source);
    defer f.deinit();
    try f.valid();
    const counters = f.checked.counters;
    // Flat instantiation would append 2^24 obligations.
    try std.testing.expect(counters.obligations_appended < 4096);
    try std.testing.expect(counters.pending_peak < 4096);
    try std.testing.expect(counters.shared_uses > 0);
    try std.testing.expect(counters.memo_hits > 0);
    try std.testing.expectEqual(@as(u64, 0), counters.memo_declined);
    // The deep generic functions keep two shared uses, not their expansion.
    const deep = f.binding("f_24").?;
    try std.testing.expect(deep.scheme.obligations.len <= 2);
    try std.testing.expect(deep.summary.flat_size > 1 << 20);
}

test "a generic chain appends obligations linearly" {
    const small = try chain(128);
    defer a.free(small);
    const large = try chain(256);
    defer a.free(large);
    const first = try appended(small);
    const second = try appended(large);
    // Doubling the depth must not square the work.
    try std.testing.expect(second < first * 3);
    try std.testing.expect(second < 8192);
}

test "left operand dispatch wins through a shared callee" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, header);
    try source.appendSlice(a, box);
    try source.appendSlice(a, "const wide = fn value => ");
    try wideSum(&source, "value", 40);
    try source.appendSlice(a,
        \\
        \\entry const answer = fn (value: F32) => case wide (#Box value) of
        \\  #Box result => result
        \\
    );
    var f = try Fixture.init(source.items);
    defer f.deinit();
    try f.valid();
    try std.testing.expect(f.checked.counters.shared_uses > 0);
}

test "a conflicting operand reports the same outcome through a shared callee" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, header);
    try source.appendSlice(a, box);
    try source.appendSlice(a, "const wide = fn left => fn right => ");
    try wideSum(&source, "left", 20);
    try source.appendSlice(a, " + ");
    try wideSum(&source, "right", 20);
    try source.appendSlice(a,
        \\
        \\entry const answer = fn (value: F32) => case wide (#Box value) 1 of
        \\  #Box result => result
        \\
    );
    var f = try Fixture.init(source.items);
    defer f.deinit();
    // Left operand selection precedes any right fallback, exactly as in flat
    // instantiation, so the written program is still accepted.
    try std.testing.expectEqual(@as(usize, 0), f.checked.diagnostics.len);
    try std.testing.expect(f.checked.counters.shared_uses > 0);
}

test "return type polymorphism keeps flat instantiation" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, header);
    try source.appendSlice(a,
        \\type Box value is data = #Box value
        \\const Box.from = fn value => #Box value
        \\const from = fn value => @type.result "from" value
        \\
    );
    try source.appendSlice(a, "const wide = fn value => from (");
    try wideSum(&source, "value", 40);
    try source.appendSlice(a,
        \\)
        \\entry const integer = fn () => do:
        \\  let #Box value:Box U32 = wide 21
        \\  return value
        \\
    );
    var f = try Fixture.init(source.items);
    defer f.deinit();
    try f.valid();
    try std.testing.expectEqual(@as(u64, 0), f.checked.counters.shared_uses);
    try std.testing.expect(!f.binding("wide").?.summary.shareable);
}

test "mutually recursive generic functions keep flat obligations" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, header);
    try source.appendSlice(a, counter);
    try source.appendSlice(a, "const left = fn value => (");
    try wideSum(&source, "value", 40);
    try source.appendSlice(a, ") + right value\nconst right = fn value => left (value + (#N 1))\n");
    try source.appendSlice(a, "entry const main = fn (value: N) -> N => left value\n");
    var f = try Fixture.init(source.items);
    defer f.deinit();
    try f.valid();
    for ([_][]const u8{ "left", "right" }) |name| {
        const member = f.binding(name).?;
        for (f.checked.obligations[member.scheme.obligations.start..][0..member.scheme.obligations.len]) |predicate| {
            try std.testing.expect(predicate.kind != .callee_use);
        }
    }
}

test "higher order callees are solved at their use" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, header);
    try source.appendSlice(a, counter);
    try source.appendSlice(a, "const apply = fn run => fn value => run (");
    try wideSum(&source, "value", 40);
    try source.appendSlice(a,
        \\)
        \\entry const main = fn (value: N) -> N => apply (fn total => total + (#N 1)) value
        \\
    );
    var f = try Fixture.init(source.items);
    defer f.deinit();
    try f.valid();
    try std.testing.expect(f.checked.counters.shared_uses > 0);
    // Nothing is left unresolved in the entry's scheme.
    const entry = f.binding("main").?;
    for (f.checked.obligations[entry.scheme.obligations.start..][0..entry.scheme.obligations.len]) |predicate| {
        try std.testing.expect(predicate.kind != .callee_use);
    }
}

test "allocation failures during shared use resolution release every owner" {
    const source = try diamond(12);
    defer a.free(source);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = fail_index });
        const allocator = failing.allocator();
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = parser.parse(allocator, source, tokens.tokens.items, &pool) catch continue;
        defer tree.deinit(allocator);
        var checked = check.check(allocator, &tree, &pool) catch |err| switch (err) {
            error.OutOfMemory => continue,
            else => return err,
        };
        defer checked.deinit(allocator);
        try std.testing.expect(checked.counters.shared_uses > 0);
        break;
    }
}

test "a lexical closure over outer variables expands its shared callee in place" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, header);
    try source.appendSlice(a, counter);
    try source.appendSlice(a, "const wide = fn value => ");
    try wideSum(&source, "value", 40);
    try source.appendSlice(a,
        \\
        \\entry const main = fn (outer: N) -> N => do:
        \\  let inner = fn value => wide (value + outer)
        \\  return inner (#N 1)
        \\
    );
    var f = try Fixture.init(source.items);
    defer f.deinit();
    try f.valid();
    try std.testing.expect(f.checked.counters.shared_uses > 0);
}
