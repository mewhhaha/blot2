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

const abstraction_producer =
    \\opaque type Token = U32
    \\private const offset = 1
    \\const make: U32 -> Token = fn value => #Token (@u32.add value offset)
    \\const read: Token -> U32 = fn (#Token value) => value
;
const abstraction_consumer = "entry const answer = fn (value: U32) => read (make value)\n";

test "module abstraction compiled principal has no opaque representation or private binding" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, abstraction_producer);
    defer a.free(bytes);
    var owner = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &owner);
    const producer = &owner.modules[0];
    for (producer.interface.nominals) |nominal| if (nominal.is_opaque) {
        try std.testing.expectEqual(@as(u32, 0), nominal.constructors.len);
        try std.testing.expectEqual(@import("opaque_storage.zig").Storage{ .kind = .u32 }, nominal.storage);
    };
    for (producer.interface.constructors) |constructor| if (constructor.private) {
        try std.testing.expectEqual(@as(u32, 0), constructor.name);
        try std.testing.expectEqual(@as(u32, 0), constructor.payload);
    };
    for (producer.interface.bindings) |binding| if (binding.private) {
        try std.testing.expectEqual(@as(u32, 0), binding.name);
        try std.testing.expectEqual(@as(u32, 0), binding.scheme.root);
    };
    var result = try consume(a, bytes, abstraction_consumer);
    defer result.deinit(a);
    try std.testing.expect(result.compiled.bytes.len > 8);
    try std.testing.expectEqual(@as(?consumer_api.Diagnostic, null), result.diagnostic);
}

fn abstractionRoundTrip(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var owner = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &owner);
    try admission.validatePrelude(allocator, &owner, abstraction_producer, "std/prelude.blot");
    const encoded = try format.encode(allocator, key, owner);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, bytes, encoded);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    try relink.relink(allocator, &owner, &names, &.{2});
}

test "module abstraction allocation failure releases every unpublished compiled owner" {
    const bytes = try artifact(std.testing.allocator, abstraction_producer);
    defer std.testing.allocator.free(bytes);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, abstractionRoundTrip, .{bytes});
}

test "module abstraction forged identities ABI and private constructor promotion reject before publication" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, abstraction_producer);
    defer a.free(bytes);
    var owner = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &owner);
    const producer = &owner.modules[0];
    const nominal = for (producer.interface.nominals) |*definition| {
        if (definition.is_opaque) break definition;
    } else return error.TestUnexpectedResult;
    const saved = nominal.*;
    nominal.storage.kind = .f32;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &owner, abstraction_producer, "std/prelude.blot"));
    nominal.* = saved;
    nominal.identity.decl = @import("types.zig").opaque_name_bit | producer.interface.bindings[1].name;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &owner, abstraction_producer, "std/prelude.blot"));
    nominal.* = saved;
    const constructor = for (producer.interface.constructors) |*definition| {
        if (definition.private) break definition;
    } else return error.TestUnexpectedResult;
    const original = constructor.*;
    constructor.private = false;
    constructor.name = nominal.name;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &owner, abstraction_producer, "std/prelude.blot"));
    constructor.* = original;
    try admission.validatePrelude(a, &owner, abstraction_producer, "std/prelude.blot");
}

const associated_producer =
    \\type Identity a is contract = { type Item = a, type Pair = (Identity.Item a, a) }
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\type Callable f is contract = { type Run = f }
    \\type Signature s is contract = { const first: Callable.Run (s -> U32) }
    \\type Alias b = Identity.Item b
    \\const helper: b -> b = fn value => value
    \\const keep: a -> (Identity.Item a) where { Identity a, type_eq (Identity.Item a) a } = fn value => value
;
fn associatedAdmissionLaw(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, associated_producer, "std/prelude.blot");
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    _ = try pool.intern(allocator, "before");
    try relink.relink(allocator, &frozen, &pool, &.{2});
    try validation.validate(&frozen.modules[0].interface, pool.entries.items.len + 1, 2);
    try validation.validateGraph(allocator, &frozen.modules[0].interface);
    try @import("frozen_core_validation.zig").validate(allocator, &frozen.modules[0].core, .{ .symbol_count = pool.entries.items.len + 1 });
}
test "associated type member portable admission and relocation release every failed allocation" {
    const bytes = try artifact(std.testing.allocator, associated_producer);
    defer std.testing.allocator.free(bytes);
    try associatedAdmissionLaw(std.testing.allocator, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedAdmissionLaw, .{bytes});
}
test "associated type member admission rejects forged equations escaped binders cycles and incomplete tables" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, associated_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const owner = &frozen.modules[0].interface;
    try admission.validatePrelude(a, &frozen, associated_producer, "std/prelude.blot");
    var exhausted: usize = 0;
    try std.testing.expectError(error.InvalidArtifact, validation.validateGraphWithBudget(a, owner, &exhausted));
    try std.testing.expectEqual(@as(usize, 0), exhausted);
    const old = owner.contract_members[0];
    owner.contract_members[0].root = @import("types.zig").u32_type;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, associated_producer, "std/prelude.blot"));
    owner.contract_members[0] = old;
    const pair = owner.graph.nodes[owner.contract_members[1].root];
    const self_projection = owner.graph.extra[pair.a];
    try std.testing.expectEqual(@import("types.zig").Tag.projection, owner.graph.nodes[self_projection].tag);
    owner.contract_members[0].root = self_projection;
    try std.testing.expectError(error.InvalidArtifact, validation.validateGraph(a, owner));
    owner.contract_members[0] = old;
    const helper = owner.graph.nodes[owner.bindings[1].scheme.root];
    owner.contract_members[0].root = helper.a;
    try std.testing.expectError(error.InvalidArtifact, validation.validateGraph(a, owner));
    owner.contract_members[0] = old;
    owner.contract_members[0].name = owner.contract_members[1].name;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(owner, frozen.symbols.len, 1));
    owner.contract_members[0] = old;
    owner.contracts[0].members.len += 1;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(owner, frozen.symbols.len, 1));
}

const associated_rows_producer =
    \\type Scoped a is contract = { type Item = a, effect_rep ! {| e}, effect_rep ! {| f} }
;
fn appendAssociatedRecipe(a: std.mem.Allocator, extra: *[]u32, words: []const u32) !@import("types.zig").List {
    const result: @import("types.zig").List = .{ .start = @intCast(extra.len), .len = @intCast(words.len) };
    const length = std.math.add(usize, extra.len, words.len) catch return error.InvalidArtifact;
    const enlarged = try a.alloc(u32, length);
    @memcpy(enlarged[0..extra.len], extra.*);
    @memcpy(enlarged[extra.len..], words);
    a.free(extra.*);
    extra.* = enlarged;
    return result;
}
fn associatedRowsAdmissionLaw(a: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const owner = &frozen.modules[0];
    try admission.validatePrelude(a, &frozen, associated_rows_producer, "std/prelude.blot");
    const named = owner.interface.contracts[0];
    const executable = owner.core.contracts[0];
    try std.testing.expectEqual(@as(u32, 2), named.row_variables.len);
    try std.testing.expectEqual(@as(u32, 2), executable.row_variables.len);
    var names: [2]u32 = undefined;
    for ([_][]const u8{ "e", "f" }, &names) |name, *symbol| {
        symbol.* = for (frozen.symbols, 0..) |candidate, index_| {
            if (std.mem.eql(u8, candidate.text, name)) break @intCast(index_);
        } else return error.InvalidArtifact;
    }
    var public_rows: [2]u32 = undefined;
    var private_rows: [2]u32 = undefined;
    for (owner.interface.graph.extra[named.row_variables.start..][0..named.row_variables.len], &public_rows) |variable, *row| {
        row.* = for (owner.interface.graph.rows, 0..) |candidate, index_| {
            if (candidate.tail == .variable and candidate.tail.variable == variable and candidate.labels.len == 0) break @intCast(index_);
        } else return error.InvalidArtifact;
    }
    for (owner.core.types.list(executable.row_variables), &private_rows) |variable, *row| {
        row.* = for (owner.core.types.effects.rows, 0..) |candidate, index_| {
            if (candidate.tail == .variable and candidate.tail.variable == variable and candidate.labels.len == 0) break @intCast(index_);
        } else return error.InvalidArtifact;
    }
    // Add corresponding complete row recipes to both immutable owners. The
    // comparison must retain their named positions even when row IDs differ.
    owner.interface.contracts[0].row_parameters = try appendAssociatedRecipe(a, &owner.interface.graph.extra, &public_rows);
    owner.interface.contracts[0].row_parameter_names = try appendAssociatedRecipe(a, &owner.interface.graph.extra, &names);
    owner.core.contracts[0].row_parameters = try appendAssociatedRecipe(a, &owner.core.types.extra, &private_rows);
    owner.core.contracts[0].row_parameter_names = try appendAssociatedRecipe(a, &owner.core.types.extra, &names);
    try admission.validatePrelude(a, &frozen, associated_rows_producer, "std/prelude.blot");
    const start = owner.interface.contracts[0].row_parameters.start;
    std.mem.swap(u32, &owner.interface.graph.extra[start], &owner.interface.graph.extra[start + 1]);
    // Bounds, equation graphs and quantified row graphs still agree. Only the
    // producer's declared row recipe has been changed by the forgery.
    try validation.validate(&owner.interface, frozen.symbols.len, 1);
    try validation.validateGraph(a, &owner.interface);
    if (admission.validatePrelude(a, &frozen, associated_rows_producer, "std/prelude.blot")) |_| {
        return error.TestExpectedError;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.InvalidArtifact);
    }
    std.mem.swap(u32, &owner.interface.graph.extra[start], &owner.interface.graph.extra[start + 1]);
    const names_start = owner.interface.contracts[0].row_parameter_names.start;
    std.mem.swap(u32, &owner.interface.graph.extra[names_start], &owner.interface.graph.extra[names_start + 1]);
    if (admission.validatePrelude(a, &frozen, associated_rows_producer, "std/prelude.blot")) |_| {
        return error.TestExpectedError;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.InvalidArtifact);
    }
}
test "associated declared row recipe admission rejects shifted positions and names through OOM" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, associated_rows_producer);
    defer a.free(bytes);
    try associatedRowsAdmissionLaw(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, associatedRowsAdmissionLaw, .{bytes});
}

const implementation_producer =
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }
;
fn implementationAdmissionLaw(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, implementation_producer, "std/prelude.blot");
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    _ = try pool.intern(allocator, "before");
    try relink.relink(allocator, &frozen, &pool, &.{2});
    const owner = &frozen.modules[0];
    try validation.validate(&owner.interface, pool.entries.items.len + 1, 2);
    try validation.validateGraph(allocator, &owner.interface);
    try @import("frozen_core_validation.zig").validate(allocator, &owner.core, .{ .symbol_count = pool.entries.items.len + 1 });
    var remaining: usize = 1_000_000;
    try @import("implementation_admission.zig").publicCore(allocator, &owner.interface, &owner.core, &remaining);
}
test "implementation portable admission relocation and ownership release every failed allocation" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, implementation_producer);
    defer a.free(bytes);
    try implementationAdmissionLaw(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, implementationAdmissionLaw, .{bytes});
}
test "implementation portable admission rejects forged equations targets and binder recipes" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, implementation_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const owner = &frozen.modules[0].interface;
    try admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot");
    const member = owner.implementation_members[0];
    owner.implementation_members[0].root = @import("types.zig").f32_type;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot"));
    owner.implementation_members[0] = member;
    const target = owner.implementation_members[1].target;
    owner.implementation_members[1].target.binding += 1;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot"));
    owner.implementation_members[1].target = target;
    const variables = owner.implementations[0].variables;
    owner.implementations[0].variables.len = 0;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot"));
    owner.implementations[0].variables = variables;
    const template = owner.member_templates[0];
    owner.member_templates[0].arguments = owner.implementations[0].head;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot"));
    owner.member_templates[0] = template;
    const principal = owner.bindings[template.binding].scheme;
    owner.bindings[template.binding].scheme.variables.len = 0;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot"));
    owner.bindings[template.binding].scheme = principal;
    const executable = &frozen.modules[0].core;
    const body = executable.bodies[executable.bindings[template.binding].body_id];
    const method_root = executable.nodes[body.root];
    executable.nodes[body.root].ty = @import("types.zig").f32_type;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot"));
    executable.nodes[body.root] = method_root;
    var exhausted: usize = 0;
    try std.testing.expectError(error.InvalidArtifact, validation.validateGraphWithBudget(a, owner, &exhausted));
    try std.testing.expectEqual(@as(usize, 0), exhausted);
}

const selected_implementation_producer =
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl Scalar : Source U32 = { type Item = U32, const first = fn value => value }
    \\impl ArraySource a : Source (Array a) where { Source a } = { type Item = Source.Item a, const first = fn values => Source.first (@array.get values 0) }
    \\const answer: U32 = Source.first #[42]
;
fn selectedImplementationAdmissionLaw(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try std.testing.expect(frozen.modules[0].core.selected_proofs.len >= 2);
    try admission.validatePrelude(allocator, &frozen, selected_implementation_producer, "std/prelude.blot");
}
test "implementation portable complete proofs reject forged roots targets and missing prerequisite edges" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, selected_implementation_producer);
    defer a.free(bytes);
    try selectedImplementationAdmissionLaw(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, selectedImplementationAdmissionLaw, .{bytes});
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0].core;
    const last = module.selected_proofs.len - 1;
    const original = module.selected_proofs[last];
    module.selected_proofs[last].prerequisites.len = 0;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, selected_implementation_producer, "std/prelude.blot"));
    module.selected_proofs[last] = original;
    const root = module.selected_members[original.members.start].root;
    module.selected_members[original.members.start].root = @import("types.zig").f32_type;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, selected_implementation_producer, "std/prelude.blot"));
    module.selected_members[original.members.start].root = root;
    const target = module.selected_members[original.members.start + 1].target;
    module.selected_members[original.members.start + 1].target.binding = frozen.modules[0].interface.member_templates[0].binding;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, selected_implementation_producer, "std/prelude.blot"));
    module.selected_members[original.members.start + 1].target = target;
    try admission.validatePrelude(a, &frozen, selected_implementation_producer, "std/prelude.blot");
}

const legacy_implementation_producer =
    \\type Token is data = #Token U32
    \\const Token.add = fn (left: Token) => fn (right: Token) => left
    \\type Source s is contract = { associated "add" s s s ! {}, type Item }
    \\impl TokenSource : Source Token = { type Item = U32 }
    \\const answer: (Source.Item Token) = 42
;
fn legacyImplementationAdmissionLaw(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, legacy_implementation_producer, "std/prelude.blot");
    var present = false;
    for (frozen.modules[0].core.selected_proofs) |proof| if (proof.kind == .predicate and proof.predicate_target.binding != 0) {
        present = true;
    };
    try std.testing.expect(present);
}
test "implementation portable legacy prerequisite certificates retain selected targets through OOM" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, legacy_implementation_producer);
    defer a.free(bytes);
    try legacyImplementationAdmissionLaw(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, legacyImplementationAdmissionLaw, .{bytes});
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    for (frozen.modules[0].core.selected_proofs) |*proof| if (proof.kind == .predicate and proof.predicate_target.binding != 0) {
        proof.predicate_target.binding += 1;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, legacy_implementation_producer, "std/prelude.blot"));
        return;
    };
    return error.TestUnexpectedResult;
}

const inferred_legacy_implementation_producer =
    \\type Token is data = #Token U32
    \\const Token.add = fn (left: Token) => fn (right: Token) => left
    \\type Source s is contract = { associated "add" s s s, type Item }
    \\impl TokenSource : Source Token = { type Item = U32 }
    \\const answer: (Source.Item Token) = 42
;
fn inferredLegacyImplementationAdmissionLaw(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, inferred_legacy_implementation_producer, "std/prelude.blot");
}
test "implementation portable inferred invocation rows remain local to their selected proof" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, inferred_legacy_implementation_producer);
    defer a.free(bytes);
    try inferredLegacyImplementationAdmissionLaw(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, inferredLegacyImplementationAdmissionLaw, .{bytes});
}

test "implementation portable admission rejects paired method recipes and inherited prerequisite deletion" {
    const a = std.testing.allocator;
    {
        const bytes = try artifact(a, implementation_producer);
        defer a.free(bytes);
        var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &frozen);
        try admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot");
        const owner = &frozen.modules[0];
        const pi_root = owner.interface.implementation_members[1].root;
        const core_root = owner.core.implementation_members[1].root;
        const old_pi = owner.interface.graph.nodes[pi_root];
        const old_core = owner.core.types.nodes[core_root];
        owner.interface.graph.nodes[pi_root].b = @import("types.zig").f32_type;
        owner.core.types.nodes[core_root].b = @import("types.zig").f32_type;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot"));
        owner.interface.graph.nodes[pi_root] = old_pi;
        owner.core.types.nodes[core_root] = old_core;
        try admission.validatePrelude(a, &frozen, implementation_producer, "std/prelude.blot");
    }
    {
        const source = "type Ready s is contract = { type Proof }\ntype Source s is contract = { Ready s, type Item }\nimpl ArraySource a : Source (Array a) = { type Item = a }\n";
        const bytes = try artifact(a, source);
        defer a.free(bytes);
        var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &frozen);
        try admission.validatePrelude(a, &frozen, source, "std/prelude.blot");
        const owner = &frozen.modules[0];
        try std.testing.expect(owner.interface.implementations[0].predicates.len != 0);
        owner.interface.implementations[0].predicates.len = 0;
        owner.core.implementations[0].predicates.len = 0;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, source, "std/prelude.blot"));
    }
}
fn compiledImplementation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var compiled = try consume(allocator, bytes, "entry const answer: U32 = Source.first #[42]\n");
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null and compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "implementation compiled producers retain method substitutions and transitive evidence through OOM" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, selected_implementation_producer);
    defer a.free(bytes);
    try compiledImplementation(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compiledImplementation, .{bytes});
}

fn compiledHandlerImplementation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var compiled = try consume(allocator, bytes, "entry const answer: U32 = Source.first (#Token 42)\n");
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null and compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "implementation compiled handler prerequisites reconstruct invocation local rows through OOM" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, @import("implementation_tests.zig").handler_source);
    defer a.free(bytes);
    try compiledHandlerImplementation(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compiledHandlerImplementation, .{bytes});
}

fn compiledRejectedImplementation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var compiled = try consume(allocator, bytes, "entry const answer: (Source.Item U32) = 42\n");
    defer compiled.deinit(allocator);
    const issue = compiled.diagnostic orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("incompatible_implementation", issue.code);
    const publication = issue.publication orelse return error.TestUnexpectedResult;
    const Details = struct { explanation: @import("dispatch_explanation.zig").Explanation };
    const parsed = try std.json.parseFromSlice(Details, allocator, publication.details_json, .{});
    defer parsed.deinit();
    const explained = parsed.value.explanation;
    try std.testing.expect(explained.candidates.len == 1 and explained.steps.len == 1);
    try std.testing.expectEqualStrings("Scalar", explained.candidates[0].origin.?.name.?);
    try std.testing.expect(explained.candidates[0].origin.?.span == null);
    try std.testing.expectEqual(@import("dispatch_explanation.zig").Outcome.requires_evidence, explained.candidates[0].outcome);
    try std.testing.expectEqual(@import("dispatch_explanation.zig").Outcome.incompatible_type, explained.steps[0].outcome);
    try std.testing.expectEqualStrings("U32", explained.steps[0].ty.?);
}
test "implementation compiled rejection preserves prerequisite facts and omits unavailable source positions" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, @import("implementation_tests.zig").rejected_source);
    defer a.free(bytes);
    try compiledRejectedImplementation(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compiledRejectedImplementation, .{bytes});
}

fn compiledWitnessImplementation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var compiled = try consume(allocator, bytes, "entry const answer: U32 = Source.first (#Token (fn () -> U32 => 7))\n");
    defer compiled.deinit(allocator);
    if (compiled.diagnostic) |issue| std.debug.print("compiled witness frontend {s} at {d}: {s}\n", .{ issue.code, issue.start, issue.message });
    if (compiled.compiled.diagnostic) |issue| std.debug.print("compiled witness backend {s}\n", .{@tagName(issue.code)});
    try std.testing.expect(compiled.diagnostic == null and compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "implementation compiled witness prerequisites derive closed local results through OOM" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, @import("implementation_tests.zig").witness_source);
    defer a.free(bytes);
    try compiledWitnessImplementation(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compiledWitnessImplementation, .{bytes});
}

fn compiledSymbolicImplementation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var compiled = try consume(allocator, bytes, "entry const answer = @product.get (@effect.run State.get State.set 42 (fn () => Callable.keep read ())) 1\n");
    defer compiled.deinit(allocator);
    if (compiled.diagnostic) |issue| std.debug.print("compiled symbolic frontend {s}\n", .{issue.code});
    if (compiled.compiled.diagnostic) |issue| std.debug.print("compiled symbolic backend {s}\n", .{@tagName(issue.code)});
    try std.testing.expect(compiled.diagnostic == null and compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "implementation compiled symbolic operation heads preserve selected method invocation rows through OOM" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, @import("implementation_tests.zig").symbolic_source);
    defer a.free(bytes);
    try compiledSymbolicImplementation(a, bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compiledSymbolicImplementation, .{bytes});
}

const paired_capability_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const first = fn (left: State a) => fn (right: State b) => left.get ()
    \\const second = fn (left: State a) => fn (right: State b) => right.get ()
;
test "scoped paired public claims admit the maximum and reject forged selected binders" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, paired_capability_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    try admission.validatePrelude(a, &frozen, paired_capability_producer, "std/prelude.blot");
    const producer = &frozen.modules[0];
    var found: usize = 0;
    for (producer.interface.bindings, 0..) |*binding, index| {
        if (binding.capability_flow != .member_second_unit) continue;
        found += 1;
        binding.capability_flow = .member_first_unit;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, paired_capability_producer, "std/prelude.blot"));
        // A coordinated forged public and private claim still cannot replace
        // the body's exact selected input reference.
        producer.core.bindings[index].capability_flow = .member_first_unit;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, paired_capability_producer, "std/prelude.blot"));
        binding.capability_flow = .member_second_unit;
        producer.core.bindings[index].capability_flow = .member_second_unit;
    }
    try std.testing.expectEqual(@as(usize, 1), found);
    try admission.validatePrelude(a, &frozen, paired_capability_producer, "std/prelude.blot");
}
test "scoped public claim wire rejects unknown values after the admitted maximum" {
    const a = std.testing.allocator;
    const Contract = @import("capability_flow.zig").Contract;
    const bytes = try format.encode(a, key, Contract.member_second_unit);
    defer a.free(bytes);
    try std.testing.expectEqual(Contract.member_second_unit, try format.decode(Contract, a, bytes, key));
    const payload = bytes.len - 4;
    std.mem.writeInt(u32, bytes[payload..][0..4], @backingInt(Contract.member_second_unit) + 1, .little);
    // Recompute integrity so rejection tests the enum domain, not its digest.
    @memcpy(bytes[payload - 32 .. payload], &format.digest(bytes[payload..]));
    try std.testing.expectError(error.InvalidArtifact, format.decode(Contract, a, bytes, key));
}
