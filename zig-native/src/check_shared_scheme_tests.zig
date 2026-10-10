//! Schemes with many obligations are used by reference. These tests pin the
//! work bounds and the cases that must keep ordinary flat instantiation.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const a = std.testing.allocator;

test "recursive frontend scheduling keeps forward chains independent of native and syntax depth" {
    for ([_]usize{ 300, 1000 }) |depth| {
        for ([_]bool{ false, true }) |annotated| {
            var source: std.ArrayList(u8) = .empty;
            defer source.deinit(a);
            try source.appendSlice(a, "entry const run = fn value => f_0 value\n");
            for (0..depth) |index| try source.print(a, "const f_{d}{s} = fn value => f_{d} value\n", .{ index, if (annotated) ": U32 -> U32" else "", index + 1 });
            try source.print(a, "const f_{d}{s} = fn value => value\n", .{ depth, if (annotated) ": U32 -> U32" else "" });
            var fixture = try Fixture.init(source.items);
            defer fixture.deinit();
            try fixture.valid();
            try std.testing.expect(fixture.binding("run").?.scheme.root != 0);
        }
    }
}

test "recursive frontend dependency discovery preserves local and pattern shadowing" {
    var fixture = try Fixture.init(
        \\const global = fn value => value
        \\const run = fn global => global 1
        \\const local = fn value => do:
        \\  let global = fn item => item
        \\  return global value
        \\const pattern = fn value => case value of
        \\  (global, ignored) => global ignored
        \\entry const result = local (run (fn value => pattern ((fn item => item), value)))
    );
    defer fixture.deinit();
    try fixture.valid();
}

test "recursive frontend discovery restores names after a forever suite" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a,
        \\entry const run = fn value => do:
        \\  for ever:
        \\    let f_0 = fn item => item
        \\    break
        \\  return f_0 value
        \\
    );
    for (0..1000) |index| try source.print(a, "const f_{d} = fn value => f_{d} value\n", .{ index, index + 1 });
    try source.appendSlice(a, "const f_1000 = fn value => value\n");
    var fixture = try Fixture.init(source.items);
    defer fixture.deinit();
    try fixture.valid();
}

const scheduled_diagnostic_source =
    \\const parent: U32 -> U32 = fn value => do:
    \\  let first: U32 = 1.5
    \\  let second = broken value
    \\  let last: U32 = 1.5
    \\  return value
    \\const broken: U32 -> F32 = fn value => value
;

fn scheduledFailureScenario(allocator: std.mem.Allocator) !void {
    for ([_][]const u8{
        scheduled_diagnostic_source,
        late_recursive_source,
    }, 0..) |source, index| {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        if (index == 0) {
            try std.testing.expect(checked.diagnostics.len >= 3);
        } else try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    }
}

test "recursive frontend scheduled allocation failures release frames and staged diagnostics" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scheduledFailureScenario, .{});
}

test "recursive frontend scheduled child diagnostics keep their original reference order" {
    for ([_][]const u8{
        scheduled_diagnostic_source,
        \\type Box is data = #Box U32
        \\const parent: U32 -> U32 = fn value => do:
        \\  let first: U32 = 1.5
        \\  let selected = (#Box 1).read
        \\  let last: U32 = 1.5
        \\  return value
        \\const Box.read: Box -> U32 = fn box => do:
        \\  let inner: U32 = 1.5
        \\  return 42
    }) |source| {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var ordinary = try check.checkPrivateExecution(a, &tree, &pool, .{ .schedule_globals = false });
        defer ordinary.deinit(a);
        var scheduled = try check.check(a, &tree, &pool);
        defer scheduled.deinit(a);
        try std.testing.expect(ordinary.diagnostics.len >= 3);
        try std.testing.expectEqual(ordinary.diagnostics.len, scheduled.diagnostics.len);
        for (ordinary.diagnostics, scheduled.diagnostics) |expected, actual| {
            try std.testing.expectEqual(expected.code, actual.code);
            try std.testing.expectEqualDeep(expected.span, actual.span);
        }
    }
}

test "recursive frontend waits for the preferred left dispatch before right fallback" {
    var fixture = try Fixture.init(
        \\type L is data = #L U32
        \\type R is data = #R U32
        \\type X is data = #X U32
        \\const prime = @type.call "merge" (#X 1) (#R 2)
        \\entry const answer: U32 = @type.call "merge" (#L 1) (#R 2)
        \\const L.merge: L -> R -> U32 = fn left => fn right => 1
        \\const R.merge: a -> R -> F32 = fn left => fn right => 1.0
    );
    defer fixture.deinit();
    try fixture.valid();
    const wanted = fixture.binding("L.merge").?;
    const answer = fixture.binding("answer").?;
    const selected = fixture.checked.resolved[fixture.tree.valueDecl(answer.declaration).body];
    try std.testing.expect(selected != 0);
    try std.testing.expectEqual(wanted.declaration, fixture.checked.bindings[selected].declaration);
}

test "recursive frontend retries publish only owned final scheme predicates" {
    var fixture = try Fixture.init(
        \\type Box is data = #Box U32
        \\const choose: a -> Box where { associated "merge" Box Box Box } = fn value => @type.call "merge" value value
        \\const Box.merge: Box -> Box -> Box = fn left => fn right => left
        \\entry const answer: Box = choose (#Box 1)
    );
    defer fixture.deinit();
    try fixture.valid();
    try std.testing.expect(fixture.checked.obligations.len != 0);
    for (fixture.checked.obligations, 0..) |_, index| {
        var owned = false;
        for (fixture.checked.bindings) |binding| if (index >= binding.scheme.obligations.start and index - binding.scheme.obligations.start < binding.scheme.obligations.len) {
            owned = true;
        };
        try std.testing.expect(owned);
    }
}

test "recursive frontend queued method preserves declaration and call diagnostics" {
    const prefix =
        \\type Seed is data = #Seed
        \\type Box a is data = #Box a
        \\const Seed.build: a -> Seed -> Box a = fn value => fn seed => #Box value
        \\const wrap = fn value => @type.call "build" value #Seed
        \\const parent: U32 -> U32 = fn value => if @u32.eq value 0 then 1.5 else (wrap value).read
        \\const Box.read: Box U32 -> U32 = fn box => case box of
    ;
    const bodies = [_][]const u8{
        "  #Box value => parent (@u32.sub value 1)\n",
        "  #Box value => do:\n    let next = @u32.sub value 1\n    return parent next\n",
        "  #Box value => do:\n    let next = fn arg => parent arg\n    return next (@u32.sub value 1)\n",
    };
    for (bodies) |body| {
        const source = try std.mem.concat(a, u8, &.{ prefix, "\n", body, "entry const run: U32 -> U32 = fn value => parent value\n" });
        defer a.free(source);
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var ordinary = try check.checkPrivateExecution(a, &tree, &pool, .{ .schedule_globals = false });
        defer ordinary.deinit(a);
        var scheduled = try check.check(a, &tree, &pool);
        defer scheduled.deinit(a);
        try std.testing.expectEqual(@as(usize, 2), ordinary.diagnostics.len);
        try std.testing.expectEqual(ordinary.diagnostics.len, scheduled.diagnostics.len);
        for (ordinary.diagnostics, scheduled.diagnostics) |expected, actual| {
            try std.testing.expectEqual(expected.code, actual.code);
            try std.testing.expectEqualDeep(expected.span, actual.span);
        }
    }
}

const late_recursive_source =
    \\type Seed is data = #Seed
    \\type Box a is data = #Box a
    \\const Seed.build: a -> Seed -> Box a = fn value => fn seed => #Box value
    \\const f_0 = fn value => @type.call "build" value #Seed
    \\const parent: a -> a = fn value => (f_0 value).read
    \\const Box.read: Box a -> a = fn box => case box of
    \\  #Box value => parent value
    \\entry const generic = fn value => parent value
;

test "late selected recursive components keep their placeholder until all schemes publish" {
    var fixture = try Fixture.init(late_recursive_source);
    defer fixture.deinit();
    try fixture.valid();
    for ([_][]const u8{ "Seed.build", "f_0", "parent", "Box.read", "generic" }) |name| {
        const binding = fixture.binding(name).?;
        try std.testing.expect(binding.scheme.root != 0);
        try std.testing.expectEqual(check.Kind.global, binding.kind);
    }
}

test "frontend recursive component transition limit bounds unresolved selected work" {
    var tokens = try lexer.lex(a, late_recursive_source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, late_recursive_source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectError(error.TypeLimit, check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .max_inference_transitions = 0 }));
}

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

test "inferred operation wrappers retain their written callee latent rows" {
    var fixture = try Fixture.init(
        \\type Signal a is effect = { get: Unit -> a }
        \\const operation_0: a -> a ! {| e} where { operation Signal.get a } = fn token => Signal.get a ()
        \\const operation_1 = fn token => do:
        \\  use result <- operation_0 token
        \\  return result
    );
    defer fixture.deinit();
    try fixture.valid();
    for ([_][]const u8{ "operation_0", "operation_1" }) |name| {
        const binding = fixture.binding(name).?;
        const arrow = fixture.checked.types.node(binding.scheme.root);
        try std.testing.expectEqual(@import("types.zig").Effects.Tail.variable, std.meta.activeTag(fixture.checked.types.row(arrow.c).tail));
        try std.testing.expect(binding.summary.has_explicit);
    }
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

test "shared written predicates keep computed operands monomorphic and unrelated parameters fresh" {
    var f = try Fixture.init(
        \\const keep: a -> b -> b where { associated "add" a a a } = fn value => fn other => do:
        \\  let ignored = @type.call "add" value value
        \\  return other
        \\entry const answer = fn () => do:
        \\  let selected = case #True of
        \\    #True => keep
        \\    #False => keep
        \\  let integer = selected 21 7
        \\  return @f32.add (@u32.to_f32 integer) (selected 21 1.5)
    );
    defer f.deinit();
    try f.valid();
    const keep = f.binding("keep").?;
    try std.testing.expect(keep.summary.has_explicit and keep.summary.shareable);
    const flags = f.checked.types.list(keep.summary.requirement_variables);
    try std.testing.expectEqual(@as(usize, 2), flags.len);
    const public = f.checked.types.list(keep.summary.public_variables);
    const arrow = f.checked.types.node(keep.scheme.root);
    const other = f.checked.types.node(arrow.b);
    try std.testing.expectEqual(@as(u32, 1), flags[std.mem.findScalar(u32, public, arrow.a).?]);
    try std.testing.expectEqual(@as(u32, 0), flags[std.mem.findScalar(u32, public, other.a).?]);
}

test "shared written requirements retain the local computation reference origin" {
    var f = try Fixture.init(@embedFile("retained-state-fixtures/unmet-qualifier.blot"));
    defer f.deinit();
    try f.valid();
    const answer = f.binding("answer").?;
    try std.testing.expectEqual(@as(u32, 1), answer.scheme.obligations.len);
    const requirement = f.checked.obligations[answer.scheme.obligations.start];
    try std.testing.expectEqual(@import("types.zig").ObligationKind.callee_use, requirement.kind);
    try std.testing.expectEqualDeep(ast.Span{ .start = 594, .end = 605 }, f.tree.span(requirement.source));
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

test "return type polymorphism preserves independent expected results through shared uses" {
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
        \\entry const floating = fn () => do:
        \\  let #Box value:Box F32 = wide 1.5
        \\  return value
        \\
    );
    var f = try Fixture.init(source.items);
    defer f.deinit();
    try f.valid();
    try std.testing.expect(f.binding("from").?.summary.shareable);
    try std.testing.expect(f.binding("wide").?.summary.shareable);
    try std.testing.expect(f.checked.counters.shared_uses > 0);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const entry = f.binding(name).?;
        for (f.checked.obligations[entry.scheme.obligations.start..][0..entry.scheme.obligations.len]) |predicate|
            try std.testing.expect(predicate.kind != .callee_use);
    }
}

test "result directed principal diamonds keep frontend work bounded by distinct bodies" {
    for ([_]usize{ 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "const f_0 = fn value => @type.result \"from\" value\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const generic = fn value => f_{d} value\n", .{depth});
        var f = try Fixture.init(text.items);
        defer f.deinit();
        try f.valid();
        try std.testing.expect(f.binding("f_0").?.summary.shareable);
        try std.testing.expect(f.checked.counters.obligations_appended < depth * 16 + 64);
        try std.testing.expect(f.checked.counters.pending_peak < depth * 16 + 64);
        try std.testing.expect(f.binding("generic").?.scheme.obligations.len <= 2);
    }
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
        try std.testing.expect(!member.summary.shareable);
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
