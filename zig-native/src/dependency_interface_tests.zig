const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const snapshot = @import("dependency_snapshot.zig");
const bundle = @import("dependency_bundle.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const relink = @import("dependency_relink.zig");
const validation = @import("dependency_interface_validation.zig");
const admission = @import("dependency_admission.zig");
const consumer_api = @import("dependency_consumer.zig");
const slots_api = @import("dependency_symbol_slots.zig");

const producer_source =
    \\data Box a = #Box { value: a }
    \\const Box.get = fn receiver => receiver.value
    \\type Cell a is effect = { get: Unit -> a, set: a -> Unit }
    \\const identity = fn value => value
    \\const qualified: a -> a where { type_rep a } = fn value => value
    \\const reader = @effect.provider (Cell.get U32) (fn () => 41)
;
const consumer_source =
    \\entry const answer: Unit -> U32 = fn () => do reader:
    \\  use value <- Cell.get U32 ()
    \\  return @u32.add (qualified (identity (#Box { value: value }).get)) 1
;

test "frozen principal imports share exact ordinary scheme and catalog rules" {
    const a = std.testing.allocator;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, producer_source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, producer_source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    for (tree.diagnostics.items) |item| std.debug.print("producer syntax {s} {d}\n", .{ @tagName(item.code), item.start });
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModule(a, &tree, &pool, &.{}, &.{}, 2);
    defer checked.deinit(a);
    for (checked.diagnostics) |item| std.debug.print("producer {s} {d}\n", .{ @tagName(item.code), item.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try snapshot.freeze(a, &tree, &checked);
    defer snapshot.deinit(a, &frozen);
    try validation.validate(&frozen, pool.entries.items.len + 1, 2);
    var producer_core = try core.lower(a, &tree, &pool, &checked);
    defer producer_core.deinit(a);
    producer_core.unit = 2;
    var consumer_tokens = try lexer.lex(a, consumer_source);
    defer consumer_tokens.deinit(a);
    var consumer_tree = try parser.parse(a, consumer_source, consumer_tokens.tokens.items, &pool);
    defer consumer_tree.deinit(a);
    for (consumer_tree.diagnostics.items) |item| std.debug.print("consumer syntax {s} {d}\n", .{ @tagName(item.code), item.start });
    try std.testing.expectEqual(@as(usize, 0), consumer_tree.diagnostics.items.len);
    var imports: std.ArrayList(check.ImportedBinding) = .empty;
    defer imports.deinit(a);
    for (frozen.bindings, 0..) |binding, index| if (binding.kind == .global) {
        try imports.append(a, .{ .name = binding.name, .target = .{ .unit = 2, .binding = @intCast(index) }, .origin = 0, .interface = .{ .types = .{ .frozen = &frozen.graph }, .scheme = binding.scheme, .obligations = frozen.obligations, .named_function = binding.named_function } });
    };
    var consumer = try check.checkModule(a, &consumer_tree, &pool, imports.items, &.{
        .{ .frozen = &frozen, .kind = .catalog, .index = 0, .origin = 0 },
        .{ .frozen = &frozen, .kind = .constructor, .index = 1, .name = pool.lookup("Box").?, .origin = 0 },
        .{ .frozen = &frozen, .kind = .effect_family, .index = 1, .name = pool.lookup("Cell").?, .origin = 0 },
    }, 1);
    defer consumer.deinit(a);
    for (consumer.diagnostics) |item| std.debug.print("consumer {s} {d}\n", .{ @tagName(item.code), item.span.start });
    try std.testing.expectEqual(@as(usize, 0), consumer.diagnostics.len);
    var consumer_core = try core.lower(a, &consumer_tree, &pool, &consumer);
    defer consumer_core.deinit(a);
    consumer_core.unit = 1;
    var result = try backend.compile(a, &.{ consumer_core, producer_core }, 1);
    defer result.deinit(a);
    if (result.diagnostic) |item| std.debug.print("backend {s} {d}\n", .{ @tagName(item.code), item.span.start });
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

const prelude_source = @embedFile("dependency-fixtures/prelude.blot");
const key: format.Key = .{ .compiler = @as([32]u8, @splat(1)), .settings = @as([32]u8, @splat(2)), .source = @as([32]u8, @splat(3)), .dependencies = @as([32]u8, @splat(4)) };

fn artifact(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try bundle.freeze(allocator, "std/prelude.blot", source, &pool, &tree, &checked, true);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, source, "std/prelude.blot");
    return format.encode(allocator, key, frozen);
}

fn consume(allocator: std.mem.Allocator, bytes: []const u8, source: []const u8) !consumer_api.Result {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try validation.validate(&frozen.modules[0].interface, frozen.symbols.len, frozen.modules.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    try relink.relink(allocator, &frozen, &pool, &.{2});
    return consumer_api.compile(allocator, source, &pool, &frozen.modules[0]);
}

test "compiled generic prelude imports after every frontend owner is released" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, prelude_source);
    defer a.free(bytes);
    for ([_][]const u8{
        "entry const answer: Unit -> U32 = fn () => 40 + 2\n",
        "entry const answer: Unit -> F32 = fn () => 40.0 + 2.5\n",
        "entry const answer: Unit -> U32 = fn () => (fn value => value) 42\n",
    }) |source| {
        var compiled = try consume(a, bytes, source);
        defer compiled.deinit(a);
        try std.testing.expect(compiled.diagnostic == null);
        try std.testing.expect(compiled.compiled.diagnostic == null);
        try std.testing.expectEqual(@as(usize, 1), compiled.stats.body_elaborations);
        try std.testing.expectEqual(@as(usize, 1), compiled.stats.body_lowerings);
    }
}

test "duplicate dictionary admission leaves caller symbols and artifact unchanged" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, "const alpha=fn value=>value\nconst zebra=fn value=>value\n");
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    for (frozen.symbols[1..]) |*symbol| if (std.mem.eql(u8, symbol.text, "alpha")) {
        a.free(symbol.text);
        symbol.text = try a.dupe(u8, "zebra");
        break;
    };
    const before = try format.encode(a, key, frozen);
    defer a.free(before);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    const zebra = try pool.intern(a, "zebra");
    try std.testing.expectError(error.InvalidArtifact, relink.relink(a, &frozen, &pool, &.{2}));
    try std.testing.expectEqual(@as(usize, 1), pool.entries.items.len);
    try std.testing.expectEqual(zebra, pool.lookup("zebra").?);
    try std.testing.expect(pool.lookup("alpha") == null);
    const after = try format.encode(a, key, frozen);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    try std.testing.expectError(error.InvalidArtifact, relink.relink(a, &frozen, &pool, &.{0}));
    try std.testing.expectError(error.InvalidArtifact, relink.relink(a, &frozen, &pool, &.{std.math.maxInt(u32)}));
}

fn freezeScenario(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, "const identity=fn value=>value\nconst qualified: a -> a where {type_rep a}=fn value=>value\n");
    defer allocator.free(bytes);
}

test "principal freeze and owned bundle allocation failures release every owner" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, freezeScenario, .{});
}

fn relinkScenario(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    _ = try pool.intern(allocator, "prior-symbol");
    const count = pool.entries.items.len;
    relink.relink(allocator, &frozen, &pool, &.{2}) catch |err| {
        try std.testing.expectEqual(count, pool.entries.items.len);
        try std.testing.expectEqualStrings("prior-symbol", pool.get(1));
        try std.testing.expectEqual(@as(u32, 1), frozen.modules[0].core.unit);
        try std.testing.expectEqual(@as(u32, 1), frozen.modules[0].interface.unit);
        return err;
    };
    try std.testing.expectEqual(@as(u32, 2), frozen.modules[0].core.unit);
    try std.testing.expectEqual(@as(u32, 2), frozen.modules[0].interface.unit);
}

test "relink publication is atomic through every allocation failure" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, "const identity=fn value=>value\n");
    defer a.free(bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, relinkScenario, .{bytes});
}

test "frozen import preserves closed explicit obligations instead of erasing proof" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, "const qualified: a -> a where {type_rep a, associated \"missing\" Bool Bool Bool}=fn value=>value\n");
    defer a.free(bytes);
    var compiled = try consume(a, bytes, "entry const answer: Unit -> U32=fn()=>qualified 42\n");
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.diagnostic != null);
    try std.testing.expectEqual(backend.Code.missing_associated, compiled.compiled.diagnostic.?.code);
}

test "loaded dependency principal Core and rows remain immutable across distinct specializations" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, prelude_source);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    try relink.relink(a, &frozen, &pool, &.{2});
    const before = try format.encode(a, key, frozen);
    defer a.free(before);
    for ([_][]const u8{
        "entry const answer: Unit -> U32 = fn () => identity (40 + 2)\n",
        "entry const answer: Unit -> F32 = fn () => identity (40.0 + 2.5)\n",
        "entry const answer: Unit -> U32 = fn () => do:\n  let #Some value = #Some 42 else:\n    return 0\n  return value\n",
    }) |source| {
        var compiled = try consumer_api.compile(a, source, &pool, &frozen.modules[0]);
        defer compiled.deinit(a);
        try std.testing.expect(compiled.diagnostic == null);
        try std.testing.expect(compiled.compiled.diagnostic == null);
    }
    const after = try format.encode(a, key, frozen);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

test "shared symbol slots relocate once and conflicting type roles are rejected" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, "data Pair = #Pair {x: U32,y: U32}\nconst identity=fn value=>value\n");
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const owner = &frozen.modules[0];
    const source = for (owner.interface.graph.nodes, 0..) |node, index| {
        if (node.tag == .record and node.b == 2) break index;
    } else return error.TestUnexpectedResult;
    const record = owner.interface.graph.nodes[source];
    const enlarged = try a.alloc(@import("types.zig").Node, owner.interface.graph.nodes.len + 1);
    @memcpy(enlarged[0..owner.interface.graph.nodes.len], owner.interface.graph.nodes);
    enlarged[owner.interface.graph.nodes.len] = record;
    a.free(owner.interface.graph.nodes);
    owner.interface.graph.nodes = enlarged;
    var roles = try slots_api.collect(a, owner);
    roles.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    _ = try pool.intern(a, "prior-symbol");
    const old_name = owner.interface.graph.extra[record.a];
    try relink.relink(a, &frozen, &pool, &.{2});
    try std.testing.expectEqual(old_name + 1, owner.interface.graph.extra[record.a]);
    owner.interface.graph.nodes[owner.interface.graph.nodes.len - 1] = .{ .tag = .product, .a = record.a, .b = 1 };
    try std.testing.expectError(error.InvalidArtifact, slots_api.collect(a, owner));
}

test "artifact provenance and dictionary failures stay explicit" {
    const a = std.testing.allocator;
    const source = "const identity=fn value=>value\n";
    const bytes = try artifact(a, source);
    defer a.free(bytes);
    var changed = key;
    inline for (@typeInfo(format.Key).@"struct".field_names) |name| {
        changed = key;
        @field(changed, name)[0] ^= 1;
        try std.testing.expectError(error.StaleArtifact, format.decode(D.FrozenDependency, a, bytes, changed));
    }
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, "const identity=fn value=>42\n", "std/prelude.blot"));
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, source, "different/prelude.blot"));
    frozen.modules[0].interface.bindings[1].scheme.variables = .{ .start = std.math.maxInt(u32), .len = 1 };
    try std.testing.expectError(error.InvalidArtifact, validation.validate(&frozen.modules[0].interface, frozen.symbols.len, 1));
}

test "empty and Unicode dictionary values remain exact while builtin and source units stay distinct" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, "const empty=fn()=>@panic \"\"\nconst unicode=fn()=>@panic \"π😀\"\nconst identity=fn value=>value\n");
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    try relink.relink(a, &frozen, &pool, &.{2});
    const empty = pool.lookup("").?;
    try std.testing.expect(empty != 0);
    try std.testing.expectEqualStrings("π😀", pool.get(pool.lookup("π😀").?));
    try std.testing.expectEqual(@as(u32, 0), frozen.modules[0].interface.graph.operations[1].identity.unit);
    try std.testing.expectEqual(@as(u32, 0), frozen.modules[0].core.types.operations[1].identity.unit);
    try std.testing.expectEqual(@as(u32, 2), frozen.modules[0].core.unit);
    var compiled = try consumer_api.compile(a, "entry const answer:Unit->U32=fn()=>identity 42\n", &pool, &frozen.modules[0]);
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null and compiled.compiled.diagnostic == null);
}

test "principal type operation and pattern cycles decline before import" {
    const a = std.testing.allocator;
    const source = "data Box a=#Box {value:a}\ntype Named {input, output} is effect = input -> output\nconst identity=fn value=>value\n";
    const bytes = try artifact(a, source);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const owner = &frozen.modules[0].interface;
    const index = for (owner.graph.nodes, 0..) |node, i| {
        if (node.tag == .function) break i;
    } else return error.TestUnexpectedResult;
    const previous = owner.graph.nodes[index];
    owner.graph.nodes[index].a = @intCast(index);
    try validation.validate(owner, frozen.symbols.len, 1);
    try std.testing.expectError(error.InvalidArtifact, validation.validateGraph(a, owner));
    owner.graph.nodes[index] = previous;
    const pattern = for (owner.patterns.nodes, 0..) |node, i| {
        if (node.kind == .record and node.b != 0) break i;
    } else return error.TestUnexpectedResult;
    const slot = owner.patterns.nodes[pattern].a + 1;
    const old = owner.patterns.extra[slot];
    owner.patterns.extra[slot] = @intCast(pattern);
    try validation.validate(owner, frozen.symbols.len, 1);
    try std.testing.expectError(error.InvalidArtifact, validation.validateGraph(a, owner));
    owner.patterns.extra[slot] = old;
    try validation.validateGraph(a, owner);
}

fn consumerScenario(allocator: std.mem.Allocator, bytes: []const u8, source: []const u8) !void {
    var result = try consume(allocator, bytes, source);
    defer result.deinit(allocator);
}

test "fresh cached consumers release every owner on success rejection and allocation failure" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, producer_source);
    defer a.free(bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, consumerScenario, .{ bytes, consumer_source });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, consumerScenario, .{ bytes, "entry const answer:Unit->U32=fn()=>missing\n" });
}

test "decoded malformed Core declines before symbols or interface are published" {
    const a = std.testing.allocator;
    const source = "const identity=fn value=>value\n";
    const bytes = try artifact(a, source);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    const owner = &frozen.modules[0].core;
    const old = owner.nodes[1].ty;
    owner.nodes[1].ty = @intCast(owner.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, source, "std/prelude.blot"));
    try std.testing.expectEqual(@as(usize, 0), pool.entries.items.len);
    owner.nodes[1].ty = old;
    try admission.validatePrelude(a, &frozen, source, "std/prelude.blot");
}
