const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");

fn law(allocator: std.mem.Allocator) !void {
    const source =
        \\type Read a is contract = { field "value" a U32 }
        \\type ReadAgain a is contract = { Read a }
        \\type Scalar = U32
        \\type Box is data = #Box { value: Scalar }
        \\type Different is data = #Different { value: U32, enabled: Bool }
        \\const read: a -> U32 where { ReadAgain a } = fn value => value.value
        \\entry const first = fn () => read (#Box { value: 42 })
        \\entry const second = fn () => read (#Different { value: 11, enabled: #True })
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("{s}: {s}\n", .{ @tagName(d.code), d.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), checked.contracts.len);
    try std.testing.expectEqual(@as(u32, 1), checked.contracts[1].predicates.len);
}
test "named contracts preserve independent evidence and release all allocation failures" {
    try law(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, law, .{});
}

test "contracts validate unused bodies, arity, parameter kinds and cycles" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        "type Loop a is contract = { Loop a }\nentry const answer = 42\n",
        "type A a is contract = { B a }\ntype B a is contract = { A a }\nentry const answer = 42\n",
        "type A a is contract = { field \"x\" a b }\nentry const answer = 42\n",
        "type A a is contract = { Unknown a }\nentry const answer = 42\n",
        "entry const answer: U32 where { Type_rep U32 } = 42\n",
        "type A a is contract = { field \"x\" a U32 }\nconst f: a -> U32 where { A } = fn x => x.x\nentry const answer = 42\n",
        "type A a is contract = { field \"x\" a U32 }\nconst f: a -> U32 where { A a U32 } = fn x => x.x\nentry const answer = 42\n",
        "type A a is contract = { field \"x\" a U32 }\ntype A = U32\nentry const answer = 42\n",
    }) |source| {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
    }
}

fn associatedMembersLaw(allocator: std.mem.Allocator) !void {
    const source =
        \\type Identity a is contract = { type Item = a }
        \\type Pair a is contract = { type Item = (Identity.Item a, a) }
        \\type View a = Pair.Item a
        \\type Curried a => type b is contract = { type First = a }
        \\type Named {a, b} is contract = { type First = a }
        \\type Fixed is contract = { type Value = U32 }
        \\type Signature s is contract = { type Run = s -> U32, const first: Signature.Run s }
        \\type Reader a is effect = Unit -> a
        \\type Effectful is contract = { type Run = Unit -> U32 ! {Reader (Identity.Item U32)} }
        \\const keep_effect: Effectful.Run -> (Unit -> U32 ! {Reader U32}) = fn action => action
        \\const shaped: (Named.First {b: F32, a: U32}) -> ((Curried.First U32) Bool) = fn value => value
        \\const fixed: Fixed.Value -> U32 = fn value => value
        \\const keep: a -> (Identity.Item a) where { Identity a, type_eq (Identity.Item a) a } = fn value => value
        \\const transitive: a -> U32 where { type_eq a b, type_eq b U32 } = fn value => value
        \\entry const answer: Unit -> U32 = fn () => keep (transitive 42)
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("ASSOC {s}: {s} at {d}\n", .{ @tagName(d.code), d.message(), d.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 8), checked.contract_members.len);
}
test "associated type members normalize defined nested and generic alias recipes" {
    try associatedMembersLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedMembersLaw, .{});
}

test "associated type members reject arity names binder leaks identity mismatches and all cycles" {
    const allocator = std.testing.allocator;
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "type Source s is contract = { type Item }\ntype Stored is data = #Stored (Source.Item U32)\n", .code = .missing_implementation },
        .{ .source = "type Source s is contract = { type Item }\nconst invalid: (Source.Item a) -> U32 where { Source b } = fn value => @panic \"unused\"\n", .code = .missing_predicate },
        .{ .source = "private type Hidden a is contract = { type Item = a }\nconst leaked: (Hidden.Item a) -> a = fn value => value\n", .code = .private_identity_escape },
        .{ .source = "type Source s is contract = { type Item }\ntype Box a is data = #Box (Source.Item a)\n", .code = .missing_predicate },
        .{ .source = "type Source s is contract = { type Item }\ntype Bad = Source.Missing U32\n", .code = .missing_type_member },
        .{ .source = "type Identity a is contract = { type Item = a }\ntype Bad = Identity.Item\n", .code = .associated_arity },
        .{ .source = "type Identity a is contract = { type Item = a }\ntype Bad = Identity.Item U32 F32\n", .code = .associated_arity },
        .{ .source = "type Identity a is contract = { type Item = b }\n", .code = .unsupported_type },
        .{ .source = "type Identity a is contract = { type Item = Unit -> a ! {| e} }\n", .code = .invalid_effect_annotation },
        .{ .source = "type Identity a is contract = { type Item = a, type Item }\n", .code = .duplicate_name },
        .{ .source = "type Identity a is contract = { type Item = a, const Item: a -> a }\n", .code = .duplicate_name },
        .{ .source = "type Identity a is contract = { const first: a }\n", .code = .annotation_kind_mismatch },
        .{ .source = "type Identity a is contract = { type Item = Identity.Item a }\n", .code = .recursive_associated_type },
        .{ .source = "type A a is contract = { type Item = B.Item a }\ntype B a is contract = { type Item = A.Item a }\n", .code = .recursive_associated_type },
        .{ .source = "type A a is contract = { type Item = A.Item (Array a) }\n", .code = .recursive_associated_type },
        .{ .source = "type Source s is contract = { type Item }\nconst invalid: (Source.Item s) -> U32 where { Source s } = fn value => value\n", .code = .type_mismatch },
        .{ .source = "type Source s is contract = { type Item }\ntype Other s is contract = { type Item }\nconst invalid: (Source.Item s) -> (Other.Item s) where { Source s, Other s } = fn value => value\n", .code = .type_mismatch },
    };
    for (cases) |case| {
        var tokens = try lexer.lex(allocator, case.source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, case.source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        const found = for (checked.diagnostics) |d| {
            if (d.code == case.code) break true;
        } else false;
        if (!found) for (checked.diagnostics) |d| std.debug.print("EXPECTED {s}: actual {s} for {s}\n", .{ @tagName(case.code), @tagName(d.code), case.source });
        try std.testing.expect(found);
    }
}

test "associated type members share projection DAG work and spend the enclosing budget" {
    const allocator = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    try source.appendSlice(allocator, "type P0 a is contract = { type Item = a }\n");
    for (1..33) |index| {
        const line = try allocator.print("type P{d} a is contract = {{ type Item = (P{d}.Item a, P{d}.Item a) }}\n", .{ index, index - 1, index - 1 });
        defer allocator.free(line);
        try source.appendSlice(allocator, line);
    }
    try source.appendSlice(allocator, "const keep: a -> (P32.Item a) = fn value => @panic \"unexecuted\"\nentry const answer = 42\n");
    var tokens = try lexer.lex(allocator, source.items);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source.items, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("DAG {s} at {d}\n", .{ @tagName(d.code), d.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(checked.counters.associated_steps < 100_000);
    try std.testing.expect(checked.counters.projection_memo_hits >= 32);
    try std.testing.expect(checked.types.nodes.items.len < 20_000);
    var remaining: usize = 10;
    var limited = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .associated_remaining = &remaining });
    defer limited.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), remaining);
    const rejected = for (limited.diagnostics) |d| {
        if (d.code == .associated_limit) break true;
    } else false;
    try std.testing.expect(rejected);
}

fn abstractAssociatedLaw(allocator: std.mem.Allocator) !void {
    const source =
        \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
        \\const keep: (Source.Item (Array a)) -> (Source.Item (Array a)) where { Source (Array a) } = fn value => value
        \\const equal_output: (Source.Item s) -> U32 where { Source s, type_eq (Source.Item s) U32 } = fn value => value
        \\type Callable f is contract = { type Run = f }
        \\const relay: (Unit -> a ! {| e}) -> (Callable.Run (Unit -> a ! {| e})) = fn value => value
        \\const congruent: (Source.Item a) -> U32 where { Source a, Source b, type_eq a b, type_eq (Source.Item b) U32 } = fn value => value
        \\entry const answer = 42
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("ABSTRACT {s} at {d}\n", .{ @tagName(d.code), d.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const keep = checked.bindings[1].scheme;
    const arrow = checked.types.node(keep.root);
    try std.testing.expectEqual(@import("types.zig").Tag.projection, checked.types.node(arrow.a).tag);
    try std.testing.expect(keep.obligations.len != 0);
    const relay = checked.types.node(checked.bindings[3].scheme.root);
    const parameter = checked.types.node(relay.a);
    const result = checked.types.node(relay.b);
    try std.testing.expectEqualSlices(u32, checked.types.rowLabels(parameter.c), checked.types.rowLabels(result.c));
    try std.testing.expectEqual(checked.types.row(parameter.c).tail.variable, checked.types.row(result.c).tail.variable);
}
test "associated type members retain congruent abstract projections logical equality and exact row aliases through OOM" {
    try abstractAssociatedLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, abstractAssociatedLaw, .{});
}

test "associated type members retain given structural evidence on symbolic output owners" {
    const source =
        \\type Source s is contract = { type Item }
        \\const read: (Source.Item s) -> U32 where { Source s, field "value" (Source.Item s) U32 } = fn value => value.value
        \\entry const answer = 42
    ;
    const allocator = std.testing.allocator;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("STRUCTURAL {s} at {d}\n", .{ @tagName(d.code), d.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}

// One instantiation of one shared equation keeps its row aliases. A later
// instantiation receives fresh latent rows, without expanding a shared DAG.
test "associated type members open callback projection DAGs by distinct node" {
    const allocator = std.testing.allocator;
    var store = try @import("types.zig").Store.init(allocator);
    defer store.deinit();
    _ = try store.projection(.{ .unit = 1, .decl = 1 }, 1, &.{});
    var root = try store.function(@import("types.zig").unit, @import("types.zig").u32_type);
    for (0..32) |_| root = try store.product(&.{ root, root });
    const before = store.nodes.items.len;
    const first = try store.openCovariant(root);
    const second = try store.openCovariant(root);
    try std.testing.expect(store.nodes.items.len - before < 100);
    try std.testing.expect(store.projection_steps < 1000);
    var a = first;
    var b = second;
    for (0..32) |_| {
        const node = store.node(a);
        const parts = store.extra.items[node.a..][0..node.b];
        try std.testing.expectEqual(parts[0], parts[1]);
        a = parts[0];
        b = store.extra.items[store.node(b).a];
    }
    try std.testing.expect(store.row(store.node(a).c).tail.variable != store.row(store.node(b).c).tail.variable);
}

test "associated contract coverage preserves distinct application binders" {
    const allocator = std.testing.allocator;
    const source =
        \\type Source s is contract = { type Item }
        \\const unrelated: (Source.Item a) -> (Source.Item b) where { Source a, Source b } = fn value => @panic "unused"
        \\entry const answer = 42
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(u32, 2), checked.bindings[1].scheme.variables.len);
}
