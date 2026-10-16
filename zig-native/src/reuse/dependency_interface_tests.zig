const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const backend = @import("../backend/core_backend.zig");
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

const prelude_source = @import("fixtures").source("dependency-fixtures/prelude.blot");
fn rankPublication(a: std.mem.Allocator) !void {
    const bytes = try artifact(a,
        \\const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = fn identity => fn value => (identity value, identity (@u32.to_f32 value))
    );
    defer a.free(bytes);
    var compiled = try consume(a, bytes,
        \\entry const answer: U32 -> U32 = fn value => @product.get (two (fn item => item) value) 0
    );
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "portable identity universals publish a runtime callback principal" {
    try rankPublication(std.testing.allocator);
}
test "portable identity publication owns every producer and consumer allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankPublication, .{});
}
const rank_identity_source =
    \\const id: forall [a] => a -> a = fn value => value
    \\const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = fn identity => fn value => (identity value, identity (@u32.to_f32 value))
;

test "portable identity binder owners reject ordinal sort and distinct owner reuse" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, rank_identity_source);
    defer a.free(bytes);
    for (0..4) |mutation| {
        var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &frozen);
        const owner = &frozen.modules[0].interface;
        const quantified = for (owner.graph.nodes) |node| {
            if (node.tag == .forall) break node;
        } else return error.TestUnexpectedResult;
        const binder = owner.graph.extra[quantified.b];
        switch (mutation) {
            0 => owner.graph.nodes[binder].a = 1,
            1 => owner.graph.nodes[binder].b = 1,
            2 => {
                const next = owner.graph.nodes.len;
                owner.graph.nodes = try a.realloc(owner.graph.nodes, next + 1);
                // Sharing one canonical forall node is legal. This is a new
                // owner node stealing the old owner's bound slot.
                owner.graph.nodes[next] = quantified;
            },
            3 => owner.has_rank_contracts = false,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, rank_identity_source, "std/prelude.blot"));
    }
}

test "portable identity implementations and per use dispatch reconstruct parametric authority" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, rank_identity_source);
    defer a.free(bytes);
    for (0..4) |mutation| {
        var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &frozen);
        const module = &frozen.modules[0].core;
        const body = for (module.bodies) |candidate| {
            if (candidate.root != 0 and module.types.node(module.binding(candidate.binding).ty).tag == .forall) break candidate;
        } else return error.TestUnexpectedResult;
        switch (mutation) {
            0 => module.nodes[body.root] = .{ .tag = .constant, .ty = module.typeOf(body.root), .a = 42 },
            1 => module.references[module.node(body.root).a].binding = body.binding,
            2 => {
                const signature = module.types.node(module.binding(body.binding).ty);
                const foreign = for (module.types.nodes) |node| {
                    if (node.tag == .forall and module.types.extra[node.b] != module.types.extra[signature.b]) break module.types.extra[node.b];
                } else return error.TestUnexpectedResult;
                module.types.nodes[signature.a].a = foreign;
            },
            3 => {
                const apply = for (module.nodes, 0..) |node, index| {
                    if (node.tag == .apply) break index;
                } else return error.TestUnexpectedResult;
                const next = module.types.nodes.len;
                module.types.nodes = try a.realloc(module.types.nodes, next + 1);
                module.types.nodes[next] = .{ .tag = .function, .a = 2, .b = 2 };
                // An apply's executable universal instance is node.c.
                // dispatch_signatures belongs to associated/field selection
                // and does not constrain this ordinary rank application.
                module.nodes[apply].c = @intCast(next);
            },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, rank_identity_source, "std/prelude.blot"));
    }
}
const key: format.Key = .{ .compiler = @as([32]u8, @splat(1)), .settings = @as([32]u8, @splat(2)), .source = @as([32]u8, @splat(3)), .dependencies = @as([32]u8, @splat(4)) };

const rank_array_source =
    \\effect Hidden: Unit -> Unit
    \\const hidden = fn () => Hidden ()
    \\const id: forall [a] => a -> a = fn value => value
    \\const array: (forall [a] => a -> a) -> Array U32 -> Array U32 = fn identity => fn values => identity values
    \\const floating: (forall [a] => a -> a) -> Array F32 -> Array F32 = fn identity => fn values => identity values
    \\const list: (forall [a] => a -> a) -> List U32 -> List U32 = fn identity => fn values => identity values
    \\const floating_list: (forall [a] => a -> a) -> List F32 -> List F32 = fn identity => fn values => identity values
;
test "portable numeric collection identity owns witnesses after producer teardown" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, rank_array_source);
    defer a.free(bytes);
    var compiled = try consume(a, bytes,
        \\entry const answer = fn (value: U32) => array id #[value, 42]
        \\entry const fraction = fn (value: F32) => floating (fn item => item) #[value, 2.5]
        \\entry const listed = fn (value: U32) => @array.from_list (list id [value, 42])
        \\entry const listed_fraction = fn (value: F32) => @array.from_list (floating_list (fn item => item) [value, 2.5])
    );
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "portable numeric collections reject same machine witnesses hidden effects and nonidentity artifacts" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, rank_array_source);
    defer a.free(bytes);
    for (0..8) |mutation| {
        var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &frozen);
        const module = &frozen.modules[0].core;
        const apply = for (module.nodes, 0..) |node, id| {
            var collection: T.Tag = .array;
            if (mutation >= 6) collection = .list;
            if (node.tag == .apply and module.types.node(module.typeOf(node.b)).tag == collection and module.types.node(module.types.node(module.typeOf(node.b)).a).tag == .u32) break id;
        } else return error.TestUnexpectedResult;
        switch (mutation) {
            0, 3, 6, 7 => {
                const scalar = for (module.types.nodes, 0..) |node, id| {
                    const floating = mutation == 0 or mutation == 6;
                    if ((floating and node.tag == .f32) or (!floating and node.tag == .u32)) break id;
                } else return error.TestUnexpectedResult;
                const next = module.types.nodes.len;
                module.types.nodes = try a.realloc(module.types.nodes, next + 2);
                var tag: T.Tag = .array;
                if (mutation == 3 or mutation == 6) tag = .list;
                module.types.nodes[next] = .{ .tag = tag, .a = @intCast(scalar) };
                module.types.nodes[next + 1] = .{ .tag = .function, .a = @intCast(next), .b = @intCast(next) };
                module.nodes[apply].c = @intCast(next + 1);
                module.dispatch_signatures[apply] = @intCast(next + 1);
            },
            1 => {
                const row = for (module.types.nodes) |node| {
                    if (node.tag == .function and module.types.rowLabels(node.c).len != 0) break node.c;
                } else return error.TestUnexpectedResult;
                var actual = module.nodes[apply].c;
                if (actual == 0) actual = module.dispatch_signatures[apply];
                if (actual == 0) actual = module.typeOf(module.nodes[apply].a);
                try std.testing.expect(actual != 0);
                module.types.nodes[actual].c = row;
            },
            2 => {
                const body = for (module.bodies) |candidate| {
                    if (candidate.root != 0 and module.types.node(module.binding(candidate.binding).ty).tag == .forall) break candidate;
                } else return error.TestUnexpectedResult;
                module.nodes[body.root] = .{ .tag = .constant, .ty = module.typeOf(body.root), .a = 42 };
            },
            4, 5 => {
                const floating = for (module.types.nodes, 0..) |node, id| {
                    if (node.tag == .array and module.types.node(node.a).tag == .f32) break id;
                } else return error.TestUnexpectedResult;
                if (mutation == 4) {
                    module.nodes[apply].ty = @intCast(floating);
                } else {
                    const argument = for (module.bindings) |binding| {
                        const root = module.types.node(binding.ty);
                        if (root.tag != .function or module.types.node(root.a).tag != .forall) continue;
                        const arrow = module.types.node(root.b);
                        if (arrow.tag != .function) continue;
                        const input = module.types.node(arrow.a);
                        if (input.tag == .array and module.types.node(input.a).tag == .u32) break arrow.a;
                    } else return error.TestUnexpectedResult;
                    module.types.nodes[argument].a = module.types.nodes[floating].a;
                    try std.testing.expectError(error.InvalidArtifact, @import("../check/rank_portable.zig").publicCore(&frozen.modules[0].interface, module));
                }
            },
            else => unreachable,
        }
        if (mutation != 5) try std.testing.expectError(error.InvalidArtifact, @import("../check/rank_portable.zig").executable(module, .{ .units = @as([]const *const core.Module, &.{module}) }));
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, rank_array_source, "std/prelude.blot"));
    }
}

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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, freezeScenario, .{});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, relinkScenario, .{bytes});
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
    const enlarged = try a.alloc(@import("../check/types.zig").Node, owner.interface.graph.nodes.len + 1);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, consumerScenario, .{ bytes, consumer_source });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, consumerScenario, .{ bytes, "entry const answer:Unit->U32=fn()=>missing\n" });
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
        try std.testing.expectEqual(@import("../backend/opaque_storage.zig").Storage{ .kind = .u32 }, nominal.storage);
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
    nominal.identity.decl = @import("../check/types.zig").opaque_name_bit | producer.interface.bindings[1].name;
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
    try @import("../check/frozen_core_validation.zig").validate(allocator, &frozen.modules[0].core, .{ .symbol_count = pool.entries.items.len + 1 });
}
test "associated type member portable admission and relocation release every failed allocation" {
    const bytes = try artifact(std.testing.allocator, associated_producer);
    defer std.testing.allocator.free(bytes);
    try associatedAdmissionLaw(std.testing.allocator, bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedAdmissionLaw, .{bytes});
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
    owner.contract_members[0].root = @import("../check/types.zig").u32_type;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, associated_producer, "std/prelude.blot"));
    owner.contract_members[0] = old;
    const pair = owner.graph.nodes[owner.contract_members[1].root];
    const self_projection = owner.graph.extra[pair.a];
    try std.testing.expectEqual(@import("../check/types.zig").Tag.projection, owner.graph.nodes[self_projection].tag);
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
fn appendAssociatedRecipe(a: std.mem.Allocator, extra: *[]u32, words: []const u32) !@import("../check/types.zig").List {
    const result: @import("../check/types.zig").List = .{ .start = @intCast(extra.len), .len = @intCast(words.len) };
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, associatedRowsAdmissionLaw, .{bytes});
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
    try @import("../check/frozen_core_validation.zig").validate(allocator, &owner.core, .{ .symbol_count = pool.entries.items.len + 1 });
    var remaining: usize = 1_000_000;
    try @import("../eval/implementation_admission.zig").publicCore(allocator, &owner.interface, &owner.core, &remaining);
}
test "implementation portable admission relocation and ownership release every failed allocation" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, implementation_producer);
    defer a.free(bytes);
    try implementationAdmissionLaw(a, bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, implementationAdmissionLaw, .{bytes});
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
    owner.implementation_members[0].root = @import("../check/types.zig").f32_type;
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
    executable.nodes[body.root].ty = @import("../check/types.zig").f32_type;
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, selectedImplementationAdmissionLaw, .{bytes});
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0].core;
    const last = module.selected_proofs.len - 1;
    const original = module.selected_proofs[last];
    module.selected_proofs[last].prerequisites.len = 0;
    try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, selected_implementation_producer, "std/prelude.blot"));
    module.selected_proofs[last] = original;
    const root = module.selected_members[original.members.start].root;
    module.selected_members[original.members.start].root = @import("../check/types.zig").f32_type;
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, legacyImplementationAdmissionLaw, .{bytes});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, inferredLegacyImplementationAdmissionLaw, .{bytes});
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
        owner.interface.graph.nodes[pi_root].b = @import("../check/types.zig").f32_type;
        owner.core.types.nodes[core_root].b = @import("../check/types.zig").f32_type;
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compiledImplementation, .{bytes});
}

fn compiledHandlerImplementation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var compiled = try consume(allocator, bytes, "entry const answer: U32 = Source.first (#Token 42)\n");
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null and compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "implementation compiled handler prerequisites reconstruct invocation local rows through OOM" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, @import("../eval/implementation_tests.zig").handler_source);
    defer a.free(bytes);
    try compiledHandlerImplementation(a, bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compiledHandlerImplementation, .{bytes});
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
    const bytes = try artifact(a, @import("../eval/implementation_tests.zig").rejected_source);
    defer a.free(bytes);
    try compiledRejectedImplementation(a, bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compiledRejectedImplementation, .{bytes});
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
    const bytes = try artifact(a, @import("../eval/implementation_tests.zig").witness_source);
    defer a.free(bytes);
    try compiledWitnessImplementation(a, bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compiledWitnessImplementation, .{bytes});
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
    const bytes = try artifact(a, @import("../eval/implementation_tests.zig").symbolic_source);
    defer a.free(bytes);
    try compiledSymbolicImplementation(a, bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compiledSymbolicImplementation, .{bytes});
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
    const Contract = @import("../check/capability_flow.zig").Contract;
    const bytes = try format.encode(a, key, Contract.member_second_unit);
    defer a.free(bytes);
    try std.testing.expectEqual(Contract.member_second_unit, try format.decode(Contract, a, bytes, key));
    const payload = bytes.len - 4;
    std.mem.writeInt(u32, bytes[payload..][0..4], @backingInt(Contract.input_shape) + 1, .little);
    // Recompute integrity so rejection tests the enum domain, not its digest.
    @memcpy(bytes[payload - 32 .. payload], &format.digest(bytes[payload..]));
    try std.testing.expectError(error.InvalidArtifact, format.decode(Contract, a, bytes, key));
}

test "scoped selection graph edges survive dependency relocation and reject owned cycles" {
    const a = std.testing.allocator;
    const source = try std.mem.replaceOwned(u8, a, @import("../check/check_effect_tests.zig").selection_source, "entry const answer", "const answer");
    defer a.free(source);
    const bytes = try artifact(a, source);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    _ = try pool.intern(a, "prior-name");
    try relink.relink(a, &frozen, &pool, &.{2});
    const module = &frozen.modules[0].core;
    const bounds = @import("../check/frozen_core_validation.zig");
    try bounds.validate(a, module, .{ .units = &.{module} });
    var count: usize = 0;
    for (module.types.nodes, 0..) |term, index| {
        if (term.tag != .instance_selection) continue;
        count += 1;
        try std.testing.expectEqual(@as(u32, 2), term.a);
        const choice = module.types.extra[term.c + 1];
        const root = for (module.types.nodes, 0..) |node, node_index| {
            if (node.tag == .scoped and node.b == 0 and node.c == index) break node_index;
        } else return error.TestUnexpectedResult;
        module.types.extra[term.c + 1] = @intCast(root);
        try std.testing.expectError(error.InvalidArtifact, bounds.validate(a, module, .{ .units = &.{module} }));
        module.types.extra[term.c + 1] = choice;
    }
    try std.testing.expect(count != 0);
    try bounds.validate(a, module, .{ .units = &.{module} });
}

fn symbolicSelectionArtifactLaw(allocator: std.mem.Allocator) !void {
    const source = try std.mem.replaceOwned(u8, allocator, @import("../check/check_effect_tests.zig").symbolic_selection_source, "entry const answer", "const answer");
    defer allocator.free(source);
    const bytes = try artifact(allocator, source);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    try relink.relink(allocator, &frozen, &pool, &.{2});
    const module = &frozen.modules[0].core;
    try @import("../check/frozen_core_validation.zig").validate(allocator, module, .{ .units = &.{module} });
}
test "scoped selected symbolic factories publish owned dependency graphs" {
    try symbolicSelectionArtifactLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicSelectionArtifactLaw, .{});
}

const parameter_footprint_producer =
    \\const pack = fn first => fn second => fn third => (third, (first, second), first)
    \\const keep = fn unused => fn retained => (retained, 42)
    \\const grouped = fn first => (fn second => (first, second))
;
fn parameterFootprintArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, parameter_footprint_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, parameter_footprint_producer, "std/prelude.blot");
}
test "pure product footprint claims survive artifact ownership and reject forged parameter masks" {
    const a = std.testing.allocator;
    try parameterFootprintArtifactLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, parameterFootprintArtifactLaw, .{});
    const bytes = try artifact(a, parameter_footprint_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.bindings, 0..) |*binding, index| {
        if (binding.capability_parameters.arity() != 3) continue;
        tested += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters = .init(3, 1);
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, parameter_footprint_producer, "std/prelude.blot"));
        module.core.bindings[index].capability_parameters = binding.capability_parameters;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, parameter_footprint_producer, "std/prelude.blot"));
        binding.capability_parameters = .init(17, original.result());
        try std.testing.expectError(error.InvalidArtifact, validation.validate(&module.interface, frozen.symbols.len, frozen.modules.len));
        binding.capability_parameters = original;
        module.core.bindings[index].capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try admission.validatePrelude(a, &frozen, parameter_footprint_producer, "std/prelude.blot");
}

const parameter_invocation_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const invoke = fn (left: State a) => fn (right: State b) => fn (callback: Unit -> U32 ! {left.get, right.get | e}) => callback ()
;
fn parameterInvocationArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, parameter_invocation_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, parameter_invocation_producer, "std/prelude.blot");
}
test "Unit callback footprint claims survive artifacts and reject forged invocation contracts" {
    const a = std.testing.allocator;
    try parameterInvocationArtifactLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, parameterInvocationArtifactLaw, .{});
    const bytes = try artifact(a, parameter_invocation_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.bindings, 0..) |*binding, index| {
        if (binding.capability_parameters.kind != .invoke_unit) continue;
        tested += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters.mask = 1;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, parameter_invocation_producer, "std/prelude.blot"));
        module.core.bindings[index].capability_parameters = binding.capability_parameters;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, parameter_invocation_producer, "std/prelude.blot"));
        binding.capability_parameters = original;
        binding.capability_parameters.kind = .product;
        module.core.bindings[index].capability_parameters = binding.capability_parameters;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, parameter_invocation_producer, "std/prelude.blot"));
        binding.capability_parameters.kind = .invalid;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(&module.interface, frozen.symbols.len, frozen.modules.len));
        binding.capability_parameters = original;
        module.core.bindings[index].capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try admission.validatePrelude(a, &frozen, parameter_invocation_producer, "std/prelude.blot");
}

const record_footprint_producer =
    \\const pack = fn first => fn second => {selected: second, nested: {first}, repeated: first}
;
fn recordFootprintArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, record_footprint_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, record_footprint_producer, "std/prelude.blot");
}
test "record footprint claims survive owned artifacts and reject forged retained fields" {
    const a = std.testing.allocator;
    try recordFootprintArtifactLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, recordFootprintArtifactLaw, .{});
    const bytes = try artifact(a, record_footprint_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.bindings, 0..) |*binding, index| {
        if (!binding.capability_parameters.present()) continue;
        tested += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters.mask = 1;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, record_footprint_producer, "std/prelude.blot"));
        module.core.bindings[index].capability_parameters = binding.capability_parameters;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, record_footprint_producer, "std/prelude.blot"));
        binding.capability_parameters = original;
        module.core.bindings[index].capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try admission.validatePrelude(a, &frozen, record_footprint_producer, "std/prelude.blot");
}

const member_closure_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const read = fn unused => fn (state: State a) => fn () => state.get ()
    \\const ordinary = fn (record: {get: Unit -> U32}) => fn () => record.get ()
;
fn memberClosureArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, member_closure_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, member_closure_producer, "std/prelude.blot");
}
test "member closure capture recipes survive owned artifacts and reject forged capture ordinals" {
    const a = std.testing.allocator;
    try memberClosureArtifactLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, memberClosureArtifactLaw, .{});
    const bytes = try artifact(a, member_closure_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.bindings, 0..) |*binding, index| {
        if (binding.capability_parameters.kind != .member_closure_unit) continue;
        tested += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters.mask = 1;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, member_closure_producer, "std/prelude.blot"));
        module.core.bindings[index].capability_parameters = binding.capability_parameters;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, member_closure_producer, "std/prelude.blot"));
        binding.capability_parameters = original;
        binding.capability_parameters.kind = .invoke_unit;
        module.core.bindings[index].capability_parameters = binding.capability_parameters;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, member_closure_producer, "std/prelude.blot"));
        binding.capability_parameters = original;
        module.core.bindings[index].capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try admission.validatePrelude(a, &frozen, member_closure_producer, "std/prelude.blot");
}

const callable_container_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const keep = fn unused => fn (state: State a) => {callbacks: #[(fn () => state.get ())]}
    \\const alias = fn unused => fn retained => do:
    \\  let version = retained
    \\  return {nested: #[version]}
    \\opaque type Wrapper a = a
    \\const wrap = fn unused => fn retained => #Wrapper retained
    \\const unwrap = fn unused => fn wrapped => case wrapped of
    \\  #Wrapper retained => retained
;
fn callableContainerArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, callable_container_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, callable_container_producer, "std/prelude.blot");
}
test "callable container footprint artifacts reject coordinated capture removal" {
    const a = std.testing.allocator;
    try callableContainerArtifactLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, callableContainerArtifactLaw, .{});
    const bytes = try artifact(a, callable_container_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.bindings, 0..) |*binding, index| {
        if (!binding.capability_parameters.present()) continue;
        tested += 1;
        const original = binding.capability_parameters;
        try std.testing.expectEqual(@as(u16, 2), original.mask);
        binding.capability_parameters.mask = 0;
        module.core.bindings[index].capability_parameters = binding.capability_parameters;
        var captures: [64]u32 = undefined;
        try std.testing.expect(module.core.closures.len <= captures.len);
        for (module.core.closures, 0..) |closure, capture_index| captures[capture_index] = closure.captures.len;
        // The body independently witnesses the retained input. Erasing a
        // redundant closure capture catalog cannot forge that proof either.
        for (module.core.closures) |*closure| closure.captures.len = 0;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, callable_container_producer, "std/prelude.blot"));
        for (module.core.closures, 0..) |*closure, capture_index| closure.captures.len = captures[capture_index];
        binding.capability_parameters = original;
        module.core.bindings[index].capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 4), tested);
    try admission.validatePrelude(a, &frozen, callable_container_producer, "std/prelude.blot");
}

const precise_result_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const bundle = fn (discarded: State a) => fn (retained: State a) => {discarded: fn () => discarded.get (), retained: fn () => retained.get ()}
    \\const select = fn value => value.retained
    \\const operation = fn (state: State a) => state.get
    \\const take_second = fn (values: (a, b)) => @product.get values 1
    \\const take_array = fn values => @array.get values 1
    \\const take_at = fn values => fn index => @array.get values index
;
test "owned result path artifacts reject coordinated selector forgery with unchanged masks" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, precise_result_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    try admission.validatePrelude(a, &frozen, precise_result_producer, "std/prelude.blot");
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.capability_contracts.bindings) |entry| {
        const public = &module.interface.capability_contracts.nodes[entry.root];
        if (public.tag != .project or public.c != @backingInt(@import("../check/capability_contracts.zig").Projection.field)) continue;
        const binding = module.interface.bindings[entry.binding];
        const private = module.core.capability_contracts.header(entry.binding, binding.capability_parameters.arity()).?;
        const core_claim = &module.core.capability_contracts.nodes[private.root];
        const original = public.b;
        var replacement: u32 = 0;
        for (frozen.symbols, 0..) |name, index| if (std.mem.eql(u8, name.text, "discarded")) {
            replacement = @intCast(index);
            break;
        };
        try std.testing.expect(replacement != 0 and replacement != original);
        public.b = replacement;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, precise_result_producer, "std/prelude.blot"));
        core_claim.b = replacement;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, precise_result_producer, "std/prelude.blot"));
        public.b = original;
        core_claim.b = original;
        tested += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try admission.validatePrelude(a, &frozen, precise_result_producer, "std/prelude.blot");
}

const nullary_shape_producer =
    \\type Maybe a is data = #Some a | #None
    \\const absent = fn value => case value of
    \\  #Some payload => payload
    \\  #None => #None
;
test "owned result shapes retain nullary constructor wrappers at immutable admission" {
    const a = std.testing.allocator;
    const bytes = try artifact(a, nullary_shape_producer);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    try admission.validatePrelude(a, &frozen, nullary_shape_producer, "std/prelude.blot");
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.capability_contracts.bindings) |entry| {
        const public = module.interface.capability_contracts.header(entry.binding, module.interface.bindings[entry.binding].capability_parameters.arity()).?;
        const private = module.core.capability_contracts.header(entry.binding, public.arity).?;
        const empty_wrapper = @import("../check/capability_contracts.zig").Term{ .tag = .wrapped };
        var public_node: ?*@import("../check/capability_contracts.zig").Term = null;
        var private_node: ?*@import("../check/capability_contracts.zig").Term = null;
        for (module.interface.capability_contracts.nodes) |*node| if (std.meta.eql(node.*, empty_wrapper)) {
            public_node = node;
            break;
        };
        for (module.core.capability_contracts.nodes) |*node| if (std.meta.eql(node.*, empty_wrapper)) {
            private_node = node;
            break;
        };
        _ = private;
        if (public_node == null or private_node == null) continue;
        public_node.?.* = .{ .tag = .empty };
        private_node.?.* = .{ .tag = .empty };
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, nullary_shape_producer, "std/prelude.blot"));
        public_node.?.* = empty_wrapper;
        private_node.?.* = empty_wrapper;
        tested += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try admission.validatePrelude(a, &frozen, nullary_shape_producer, "std/prelude.blot");
}

test "usage captured once factory keeps its ownership boundary in portable Core" {
    const a = std.testing.allocator;
    const source = "const capture = fn (owner: unique U32) -> once (Unit -> unique U32) => fn () => owner\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try bundle.freeze(a, "std/prelude.blot", source, &pool, &tree, &checked, true);
    defer format.deinit(a, &frozen);
    try validation.validate(&frozen.modules[0].interface, frozen.symbols.len, 1);
    try @import("../check/usage_core.zig").validate(&frozen.modules[0].core);
    try @import("../check/frozen_core_validation.zig").validate(a, &frozen.modules[0].core, .{});
    try admission.validatePrelude(a, &frozen, source, "std/prelude.blot");
}

test "capability import keeps producer graph ordinal distinct from relocated external target" {
    const a = std.testing.allocator;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    const producer = "const project = fn record => record.left\nconst constant = fn () => 7\n";
    var tokens = try lexer.lex(a, producer);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, producer, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.checkModule(a, &tree, &pool, &.{}, &.{}, 2);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const projected = checked.resolved[tree.roots.items[0]];
    const constant = checked.resolved[tree.roots.items[1]];
    try std.testing.expect(checked.capability_contracts.header(projected, 1) != null);
    const catalog: check.ImportedCatalog = .{ .producer = &checked, .kind = .catalog, .index = 0, .origin = 0 };
    var interface = catalog.interface(constant);
    const consumer = "const answer = value ()\n";
    var input_tokens = try lexer.lex(a, consumer);
    defer input_tokens.deinit(a);
    var input_tree = try parser.parse(a, consumer, input_tokens.tokens.items, &pool);
    defer input_tree.deinit(a);
    const name = pool.lookup("value").?;
    const imported: check.ImportedBinding = .{ .name = name, .target = .{ .unit = 3, .binding = projected }, .origin = 0, .interface = interface };
    var result = try check.checkModule(a, &input_tree, &pool, &.{imported}, &.{}, 4);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    // A forged owner ordinal does not decline to unknown or acquire authority.
    interface.producer_binding = projected;
    var forged = imported;
    forged.interface = interface;
    try std.testing.expectError(error.TypeLimit, check.checkModule(a, &input_tree, &pool, &.{forged}, &.{}, 4));
}

test "grouped pure product footprint headers match exact curried Core and reject coordinated shorter claims" {
    const a = std.testing.allocator;
    const source = "const grouped = fn first => ((fn second => (fn first => {kept: second, shadow: first})))\n";
    const bytes = try artifact(a, source);
    defer a.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const module = &frozen.modules[0];
    const original = module.interface.bindings[1].capability_parameters;
    try std.testing.expectEqual(@as(u8, 3), original.arity());
    try std.testing.expectEqual(@as(u16, 6), original.result());
    try std.testing.expectEqual(@as(u32, 3), module.core.body(1).?.parameters.len);
    for ([_]@import("../check/capability_flow.zig").Parameters{ .init(1, 1), .init(3, 3) }) |forged| {
        module.interface.bindings[1].capability_parameters = forged;
        module.core.bindings[1].capability_parameters = forged;
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, source, "std/prelude.blot"));
    }
    module.interface.bindings[1].capability_parameters = original;
    module.core.bindings[1].capability_parameters = original;
    try admission.validatePrelude(a, &frozen, source, "std/prelude.blot");
}

test "grouped callable footprint boundaries preserve once-qualified returned captures" {
    const a = std.testing.allocator;
    const cases = [_][]const u8{
        "const capture = fn (owner: unique U32) -> once (U32 -> unique U32) => (fn (unused: U32) => owner)\n",
        "const capture: (unique U32) -> once (U32 -> unique U32) = fn (owner: unique U32) -> once (U32 -> unique U32) => (fn (unused: U32) => owner)\n",
    };
    for (cases) |source| {
        const bytes = try artifact(a, source);
        defer a.free(bytes);
        var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &frozen);
        const module = &frozen.modules[0];
        const summary = module.interface.bindings[1].capability_parameters;
        try std.testing.expectEqual(@as(u8, 1), summary.arity());
        try std.testing.expectEqual(@as(u16, 1), summary.result());
        try std.testing.expectEqual(@as(u32, 1), module.core.body(1).?.parameters.len);
        try admission.validatePrelude(a, &frozen, source, "std/prelude.blot");
    }
}

const deferred_block_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const fields = fn (discarded: State a) => fn (retained: State a) => do:
    \\  let dropped = fn () => do:
    \\    let alias = discarded
    \\    return alias.get ()
    \\  let kept = fn () => do:
    \\    let alias = retained
    \\    return case (alias, 1) of
    \\      (cell, number) => cell.get ()
    \\  return {discarded: dropped, retained: kept}
;
fn deferredBlockArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, deferred_block_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, deferred_block_producer, "std/prelude.blot");
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.capability_contracts.bindings) |entry| {
        const public = &module.interface.capability_contracts.nodes[entry.root];
        if (public.tag != .record) continue;
        tested += 1;
        const binding = &module.interface.bindings[entry.binding];
        try std.testing.expectEqual(@as(u16, 3), binding.capability_parameters.mask);
        const private = module.core.capability_contracts.header(entry.binding, binding.capability_parameters.arity()).?;
        const claimed = &module.core.capability_contracts.nodes[private.root];
        // Both claims retain the same inputs overall. Swapping only the
        // record's callbacks still forges which lifetime each field exposes.
        const words = module.interface.capability_contracts.words;
        const original = words[public.a + 1];
        words[public.a + 1] = words[public.a + 3];
        if (admission.validatePrelude(allocator, &frozen, deferred_block_producer, "std/prelude.blot")) |_| {
            return error.TestExpectedError;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        const core_words = module.core.capability_contracts.words;
        const core_original = core_words[claimed.a + 1];
        core_words[claimed.a + 1] = core_words[claimed.a + 3];
        for (module.core.closures) |*closure| closure.captures.len = 0;
        if (admission.validatePrelude(allocator, &frozen, deferred_block_producer, "std/prelude.blot")) |_| {
            return error.TestExpectedError;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        // This corrupted private artifact is discarded; no catalog is used
        // as an absence proof in either admission attempt.
        words[public.a + 1] = original;
        core_words[claimed.a + 1] = core_original;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
}
test "deferred block and pattern captures prove exact public result paths under allocation failure" {
    try deferredBlockArtifactLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, deferredBlockArtifactLaw, .{});
}

const scoped_constructor_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const provider = fn unused => fn (state: State a) => fn implementation => @effect.provider state.get implementation
    \\const state = fn unused => fn (state: State a) => fn initial => @effect.state state.get state.set initial
    \\const computation = fn unused => fn action => @computation action
;
fn scopedConstructorArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, scoped_constructor_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, scoped_constructor_producer, "std/prelude.blot");
    const module = &frozen.modules[0];
    try std.testing.expectEqual(@as(usize, 3), module.interface.capability_contracts.bindings.len);
    for (module.interface.capability_contracts.bindings) |entry| {
        const binding = &module.interface.bindings[entry.binding];
        const original = binding.capability_parameters;
        // The private constructor witnesses each retained payload/implementation
        // and selector. Erasing the public and private masks does not erase it.
        binding.capability_parameters.mask = 0;
        module.core.bindings[entry.binding].capability_parameters.mask = 0;
        if (admission.validatePrelude(allocator, &frozen, scoped_constructor_producer, "std/prelude.blot")) |_| {
            return error.TestExpectedError;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        binding.capability_parameters = original;
        module.core.bindings[entry.binding].capability_parameters = original;
    }
}
test "scoped constructor recipes retain operation implementation and initial cell authority through OOM" {
    try scopedConstructorArtifactLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedConstructorArtifactLaw, .{});
}

const generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const choose = fn flag => fn (left: State a) => fn (right: State a) => if flag then left else right
    \\const forward = fn flag => fn (left: State a) => fn (right: State a) => choose flag left right
    \\const freeze = fn value => fn () => value
    \\const bundle = fn flag => fn (left: State a) => fn (right: State a) => fn initial => do:
    \\  let selected = forward flag left right
    \\  return {cell: selected, read: fn () => selected.get (), provider: @effect.state selected.get selected.set initial}
;
const returned_generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const staged = fn (left: State a) => fn (middle: State a) => do:
    \\  let first = if #True then left else middle
    \\  return fn () => {first: first, second: if #False then left else middle}
    \\const returned_forward = fn (left: State a) => fn (right: State a) => staged left right
;
fn generativeInvalid(allocator: std.mem.Allocator, frozen: *const D.FrozenDependency, source: []const u8) !void {
    if (admission.validatePrelude(allocator, frozen, source, "std/prelude.blot")) |_| {
        return error.TestExpectedError;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.InvalidArtifact);
    }
}
fn generativeArtifactValidation(allocator: std.mem.Allocator, bytes: []const u8, source: []const u8, expected: usize) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    const module = &frozen.modules[0];
    var tested: usize = 0;
    for (module.interface.bindings, 0..) |*binding, index| {
        if (binding.scheme.generative.len == 0) continue;
        tested += 1;
        try std.testing.expect(binding.scheme.generative.len == 2 or binding.scheme.generative.len == 4);
        const public = binding.scheme.generative;
        const private = module.core.bindings[index].scheme.generative;
        const body = &module.core.bodies[module.core.bindings[index].body_id];
        const body_binders = body.scheme.generative;
        binding.scheme.generative = .{};
        try generativeInvalid(allocator, &frozen, source);
        module.core.bindings[index].scheme.generative = .{};
        body.scheme.generative = .{};
        // Removing both catalogs leaves the exact body conditional intact.
        try generativeInvalid(allocator, &frozen, source);
        binding.scheme.generative = public;
        module.core.bindings[index].scheme.generative = private;
        body.scheme.generative = body_binders;
        for (0..public.len / 2) |pair| {
            const public_slot = public.start + pair * 2;
            const private_slot = private.start + pair * 2;
            const body_slot = body_binders.start + pair * 2;
            const saved_public = module.interface.graph.extra[public_slot];
            const saved_private = module.core.types.extra[private_slot];
            const saved_body = module.core.types.extra[body_slot];
            module.interface.graph.extra[public_slot] = binding.scheme.root;
            module.core.types.extra[private_slot] = module.core.bindings[index].scheme.root;
            module.core.types.extra[body_slot] = body.scheme.root;
            // Each evaluated selection belongs to its exact declaring arrow,
            // including arrows returned beside earlier captured selections.
            try generativeInvalid(allocator, &frozen, source);
            module.interface.graph.extra[public_slot] = saved_public;
            module.core.types.extra[private_slot] = saved_private;
            module.core.types.extra[body_slot] = saved_body;
        }
        try admission.validatePrelude(allocator, &frozen, source, "std/prelude.blot");
    }
    if (module.core.calls.len != 0) {
        const call = &module.core.calls[0];
        const signature = call.callee_type;
        const original_nodes = module.core.types.nodes;
        const first = original_nodes[signature];
        try std.testing.expect(first.tag == .function);
        const second = original_nodes[first.b];
        try std.testing.expect(second.tag == .function);
        const third = original_nodes[second.b];
        if (third.tag == .function and second.a != third.a) {
            const nodes = try allocator.alloc(@import("../check/types.zig").Node, original_nodes.len + 2);
            defer allocator.free(nodes);
            @memcpy(nodes[0..original_nodes.len], original_nodes);
            const first_id: u32 = @intCast(original_nodes.len);
            nodes[first_id] = first;
            nodes[first_id].b = first_id + 1;
            nodes[first_id + 1] = second;
            nodes[first_id + 1].a = third.a;
            module.core.types.nodes = nodes;
            call.callee_type = first_id;
            defer {
                module.core.types.nodes = original_nodes;
                call.callee_type = signature;
            }
            // All public/body binders and result recipes remain intact. The
            // private call edge cannot replace one selected input with another.
            try generativeInvalid(allocator, &frozen, source);
        }
    }
    try std.testing.expectEqual(expected, tested);
}
// Compilation faults precede decoding and mutation. Sweep those owners once;
// artifact faults reuse the same immutable bytes and exercise every mutant.
fn generativeArtifactEncoding(allocator: std.mem.Allocator, source: []const u8) !void {
    const bytes = try artifact(allocator, source);
    defer allocator.free(bytes);
}
fn generativeArtifact(allocator: std.mem.Allocator, source: []const u8, expected: usize) !void {
    const bytes = try artifact(allocator, source);
    defer allocator.free(bytes);
    try generativeArtifactValidation(allocator, bytes, source, expected);
    const failures = @import("../allocation_failures.zig");
    try failures.checkAllAllocationFailures(allocator, generativeArtifactEncoding, .{source});
    try failures.checkAllAllocationFailures(allocator, generativeArtifactValidation, .{ bytes, source, expected });
}
fn generativeArtifactLaw(allocator: std.mem.Allocator) !void {
    try generativeArtifact(allocator, generative_producer, 3);
}
fn returnedGenerativeArtifactLaw(allocator: std.mem.Allocator) !void {
    try generativeArtifact(allocator, returned_generative_producer, 2);
}
test "generative invocation artifacts own the declaring arrow independently through OOM" {
    try generativeArtifactLaw(std.testing.allocator);
}

fn packagePublication(a: std.mem.Allocator) !void {
    const bytes = try artifact(a,
        \\type Item = exists [a, b] => (a, a -> b, b -> U32)
        \\const make: U32 -> Item = fn value => pack [U32, F32] (value, fn number => @u32.to_f32 number, fn number => @f32.to_u32 number) as Item
        \\const read: Item -> U32 = fn item => unpack item as [a, b] body in (@product.get body 2) ((@product.get body 1) (@product.get body 0))
    );
    defer a.free(bytes);
    var compiled = try consume(a, bytes, "entry const answer: U32 -> U32 = fn value => read (make value)\n");
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.diagnostic == null);
    try std.testing.expect(compiled.compiled.bytes.len > 8);
}
test "portable two binder packages publish checked producer operations" {
    try packagePublication(std.testing.allocator);
}

test "portable package adapters reject witnesses primitives and foreign opening owners" {
    const a = std.testing.allocator;
    const source =
        \\type Item = exists [a, b] => (a, a -> b, b -> U32)
        \\const make: U32 -> Item = fn value => pack [U32, F32] (value, fn number => @u32.to_f32 number, fn number => @f32.to_u32 number) as Item
        \\const read: Item -> U32 = fn item => unpack item as [a, b] body in (@product.get body 2) ((@product.get body 1) (@product.get body 0))
    ;
    const bytes = try artifact(a, source);
    defer a.free(bytes);
    for (0..5) |mutation| {
        var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &frozen);
        const module = &frozen.modules[0].core;
        var changed = false;
        switch (mutation) {
            0 => for (module.nodes) |node| {
                if (node.tag != .package_pack) continue;
                module.types.extra[node.b] = T.f32_type;
                changed = true;
                break;
            },
            1 => for (module.nodes) |*node| {
                if (node.tag != .scalar or node.op != .convert_u32_f32) continue;
                node.op = .convert_f32_u32;
                changed = true;
                break;
            },
            2 => for (module.types.nodes) |*node| {
                if (node.tag != .bound or node.c == 0) continue;
                node.c = 1;
                changed = true;
                break;
            },
            3 => {
                module.has_rank_contracts = false;
                changed = true;
            },
            4 => {
                const parameter = module.parameters[module.bodies[1].parameters.start].binding;
                module.bindings[parameter].kind = .local;
                changed = true;
            },
            else => unreachable,
        }
        try std.testing.expect(changed);
        try std.testing.expectError(error.InvalidArtifact, admission.validatePrelude(a, &frozen, source, "std/prelude.blot"));
    }
}

test "portable two binder package publication releases every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, packagePublication, .{});
}

test "returned invocation binders retain declaring arrows and captured versions through OOM" {
    try returnedGenerativeArtifactLaw(std.testing.allocator);
}

const pattern_capture_producer =
    \\type Application is data = #Application {reset: Unit -> U32}
    \\const reset_scoped = fn application => fn () => do:
    \\  let #Application {reset} = application
    \\  return reset ()
;
fn patternCaptureArtifactLaw(allocator: std.mem.Allocator) !void {
    const bytes = try artifact(allocator, pattern_capture_producer);
    defer allocator.free(bytes);
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, pattern_capture_producer, "std/prelude.blot");
    var tested = false;
    for (frozen.modules[0].interface.bindings, 0..) |*binding, index| {
        if (binding.capability_parameters.kind != .captured_unit) continue;
        tested = true;
        const original = binding.capability_parameters;
        try std.testing.expectEqual(@as(u16, 1), original.mask);
        try std.testing.expectEqual(@as(u8, 1), original.inputs);
        binding.capability_parameters.mask = 0;
        frozen.modules[0].core.bindings[index].capability_parameters.mask = 0;
        if (admission.validatePrelude(allocator, &frozen, pattern_capture_producer, "std/prelude.blot")) |_| {
            return error.TestExpectedError;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        binding.capability_parameters = original;
        frozen.modules[0].core.bindings[index].capability_parameters = original;
    }
    try std.testing.expect(tested);
    try admission.validatePrelude(allocator, &frozen, pattern_capture_producer, "std/prelude.blot");
}
test "nominal pattern initializers retain exact deferred captures independently through OOM" {
    try patternCaptureArtifactLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, patternCaptureArtifactLaw, .{});
}

const formal_generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const call = fn callback => callback ()
    \\const staged = fn (left: State a) => fn (right: State a) => fn () => if #True then left else right
    \\const exercise = fn (left: State a) => fn (right: State a) => do:
    \\  let maker = staged left right
    \\  return call maker
    \\const ordinary = fn () => 42
;
fn formalGenerativeValidation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, formal_generative_producer, "std/prelude.blot");
    const module = &frozen.modules[0].core;
    const V = @import("../check/frozen_core_validation.zig");
    try V.validate(allocator, module, .{});
    var tested = false;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .call or module.calls[node.a].target.binding != 1) continue;
        tested = true;
        try std.testing.expectEqual(@as(u32, 1), node.c);
        const argument = module.node(module.extra[node.b]);
        try std.testing.expect(argument.tag == .reference);
        const reference = &module.references[argument.a];
        const original = reference.*;
        reference.binding = 4;
        // The callback's use type and all declaring facts remain intact. Its
        // executable value cannot borrow a different maker's invocation proof.
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        reference.* = original;
        const selected = module.types.node(node.ty);
        try std.testing.expect(selected.tag == .scoped and selected.b == 0);
        const term = module.types.node(selected.c);
        const version = &module.types.nodes[module.types.nominalArguments(term)[2]];
        try std.testing.expect(version.tag == .instance_version);
        try std.testing.expectEqual(module.span(@intCast(id)).end + 1, version.b);
        const point = version.b;
        version.b += 1;
        const owner_scheme = module.bindings[3].scheme.generative;
        const body = &module.bodies[module.bindings[3].body_id];
        const body_scheme = body.scheme.generative;
        module.bindings[3].scheme.generative = .{};
        body.scheme.generative = .{};
        // A changed endpoint must not turn a fresh invocation into an unchecked
        // captured selection merely because it no longer matches this call.
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        version.b = point;
        module.bindings[3].scheme.generative = owner_scheme;
        body.scheme.generative = body_scheme;
        const helper = &module.bindings[1];
        const root = &module.nodes[module.bodies[helper.body_id].root];
        try std.testing.expect(root.tag == .apply);
        const argument_id = root.b;
        root.b = @intCast(id);
        // Keeping both public/private invoke claims does not replace the exact
        // helper body proof of a Unit callback invocation.
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        root.b = argument_id;
    }
    try std.testing.expect(tested);
    var intermediate = false;
    for (module.nodes, 0..) |*node, id| {
        if (node.tag != .apply) continue;
        const call = @import("../check/capability_flow.zig").coreCall(module, @intCast(id)) orelse continue;
        if (call.target.binding != 2 or call.len != 1) continue;
        intermediate = true;
        const ty = node.ty;
        node.ty = module.bindings[4].ty;
        // The complete application chain owns the prospective callee view;
        // a forged intermediate type cannot bypass the final result proof.
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        node.ty = ty;
    }
    try std.testing.expect(intermediate);
    try V.validate(allocator, module, .{});
}
test "formal Unit callback invocations independently own fresh results and executable arguments through OOM" {
    const allocator = std.testing.allocator;
    const bytes = try artifact(allocator, formal_generative_producer);
    defer allocator.free(bytes);
    try formalGenerativeValidation(allocator, bytes);
    const failures = @import("../allocation_failures.zig");
    try failures.checkAllAllocationFailures(allocator, generativeArtifactEncoding, .{formal_generative_producer});
    try failures.checkAllAllocationFailures(allocator, formalGenerativeValidation, .{bytes});
}

const projected_generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const call = fn callback => callback ()
    \\const staged = fn (left: State a) => fn (right: State a) => fn () => if #True then left else right
    \\const exercise = fn (left: State a) => fn (right: State a) => do:
    \\  let maker = staged left right
    \\  let container = {nested: {maker: maker, ordinary: fn () => 42}, unused: 99}
    \\  let alias = container
    \\  return call alias.nested.maker
    \\const product = fn (left: State a) => fn (right: State a) => do:
    \\  let maker = staged left right
    \\  let container = (maker, fn () => 42)
    \\  let alias = container
    \\  return call (@product.get alias 0)
;
fn projectedGenerativeValidation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, projected_generative_producer, "std/prelude.blot");
    const module = &frozen.modules[0].core;
    const V = @import("../check/frozen_core_validation.zig");
    try V.validate(allocator, module, .{});
    var aliases: usize = 0;
    for (module.bindings, 0..) |*binding, binding_id| {
        if (binding.initializer == 0 or binding.scheme.closed_rows.len == 0 or binding.scheme.generative.len == 0) continue;
        const initializer = module.node(binding.initializer);
        if (initializer.tag != .reference) continue;
        aliases += 1;
        const certificate = binding.scheme.closed_rows;
        binding.scheme.closed_rows = .{};
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        binding.scheme.closed_rows = certificate;
        const closed = module.types.list(certificate)[0];
        var raw_row = false;
        for (module.types.effects.rows) |*row| {
            if (row.tail != .variable or row.tail.variable != closed) continue;
            const tail = row.tail;
            row.tail = .{ .variable = closed + 1000 };
            if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
                if (err == error.OutOfMemory) return err;
                try std.testing.expect(err == error.InvalidArtifact);
            }
            row.tail = tail;
            raw_row = true;
            break;
        }
        try std.testing.expect(raw_row);
        for (module.nodes, 0..) |*node, node_id| {
            if (node.tag != .reference or module.reference(@intCast(node_id)).binding != binding_id) continue;
            const use_type = node.ty;
            node.ty = initializer.ty;
            if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
                if (err == error.OutOfMemory) return err;
                try std.testing.expect(err == error.InvalidArtifact);
            }
            node.ty = use_type;
            break;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), aliases);
    var tested: usize = 0;
    for (module.nodes) |node| {
        if (node.tag != .project or module.types.node(node.ty).tag != .function) continue;
        tested += 1;
        const projection = &module.projections[node.b];
        const original = projection.*;
        const variant = &module.projection_variants[projection.variants.start];
        const field = variant.field;
        variant.field = 1;
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        variant.field = field;
        projection.source_type = projection.result_type;
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        projection.* = original;
        const container = module.types.node(projection.source_type);
        if (container.tag == .record) {
            projection.field = module.types.recordField(container, 1).name;
            if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
                if (err == error.OutOfMemory) return err;
                try std.testing.expect(err == error.InvalidArtifact);
            }
            projection.* = original;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), tested);
    var erased = false;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .call or module.calls[node.a].target.binding != 1) continue;
        const argument = module.node(module.extra[node.b]);
        try std.testing.expect(argument.tag == .project);
        const callback = module.types.node(argument.ty);
        const before = module.types.node(callback.b);
        const after = module.types.node(node.ty);
        try std.testing.expect(before.tag == .scoped and after.tag == .scoped);
        const before_term = module.types.node(before.c);
        const after_term = module.types.node(after.c);
        const prototype = module.types.node(module.types.nominalArguments(before_term)[2]);
        const version = &module.types.nodes[module.types.nominalArguments(after_term)[2]];
        const original_version = version.*;
        try std.testing.expectEqual(module.span(@intCast(id)).end + 1, version.b);
        const projection = &module.projections[argument.b];
        const identity = projection.nominal;
        // The unsupported owner path and erased result/catalogs cannot turn a
        // declaring callback into a capture-only invocation.
        projection.nominal = .{ .unit = module.unit, .decl = 1 };
        version.* = prototype;
        const binding = &module.bindings[3];
        const body = &module.bodies[binding.body_id];
        const public = binding.scheme.generative;
        const private = body.scheme.generative;
        binding.scheme.generative = .{};
        body.scheme.generative = .{};
        if (V.validate(allocator, module, .{})) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        binding.scheme.generative = public;
        body.scheme.generative = private;
        projection.nominal = identity;
        version.* = original_version;
        erased = true;
    }
    try std.testing.expect(erased);
    try V.validate(allocator, module, .{});
}
test "projected invocation owns executable record and product callbacks through OOM" {
    const allocator = std.testing.allocator;
    const bytes = try artifact(allocator, projected_generative_producer);
    defer allocator.free(bytes);
    try projectedGenerativeValidation(allocator, bytes);
    const failures = @import("../allocation_failures.zig");
    try failures.checkAllAllocationFailures(allocator, generativeArtifactEncoding, .{projected_generative_producer});
    try failures.checkAllAllocationFailures(allocator, projectedGenerativeValidation, .{bytes});
}

const input_invocation_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const invoke = fn cell => fn callback => callback cell
    \\const read = fn (cell: State a) => invoke cell (fn (actual: State a) => actual.get ())
    \\const choose = fn (left: State a) => fn (right: State a) => invoke left (fn (unused: State a) => if #True then left else right)
    \\const identity = fn (cell: State a) => invoke cell (fn actual => actual)
    \\const scoped = fn () => @effect.scope (fn (cell: State U32) => do:
    \\  use handled <- do (@effect.state cell.get cell.set 42):
    \\    return invoke cell (fn (actual: State U32) => if #True then actual.get () else 0)
    \\  let (state, value) = handled
    \\  return value
    \\)
;
fn inputInvocationValidation(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    try admission.validatePrelude(allocator, &frozen, input_invocation_producer, "std/prelude.blot");
    const module = &frozen.modules[0].core;
    const V = @import("../check/frozen_core_validation.zig");
    const flow = @import("../check/capability_flow.zig");
    var tested = false;
    for (module.bindings, 0..) |*binding, index| {
        if (binding.capability_parameters.kind != .invoke_input) continue;
        tested = true;
        const original = binding.capability_parameters;
        const public = &frozen.modules[0].interface.bindings[index];
        binding.capability_parameters.mask = @as(u16, original.argument()) | (@as(u16, original.callback()) << 4);
        public.capability_parameters = binding.capability_parameters;
        if (admission.validatePrelude(allocator, &frozen, input_invocation_producer, "std/prelude.blot")) |_| return error.TestExpectedError else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expect(err == error.InvalidArtifact);
        }
        try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, module, .{}));
        binding.capability_parameters = original;
        public.capability_parameters = original;
        const body = module.bodies[binding.body_id];
        const application = module.node(body.root);
        const argument = module.node(application.b);
        const reference = &module.references[argument.a];
        const saved = reference.*;
        reference.binding = module.parameters[body.parameters.start + original.callback()].binding;
        try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, module, .{}));
        reference.* = saved;
        binding.capability_parameters = .{ .kind = .product, .inputs = original.inputs };
        try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, module, .{}));
        binding.capability_parameters = original;
        for (module.nodes, 0..) |node, id| {
            if (node.tag != .call and node.tag != .apply) continue;
            const call = flow.coreCall(module, @intCast(id)) orelse continue;
            if (call.target.binding != index or call.len != original.arity()) continue;
            const callback = &module.nodes[call.arguments[original.callback()]];
            const ty = callback.ty;
            callback.ty = T.unit;
            try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, module, .{}));
            callback.ty = ty;
            break;
        }
    }
    var normalized_owner = false;
    for (module.types.nodes, 0..) |node, carrier| {
        if (node.tag != .scoped or node.b != module.unit) continue;
        for (module.types.operations) |*operation| {
            if (operation.instance.unit != module.unit) continue;
            const original = operation.instance;
            operation.instance = .{ .unit = 0, .decl = @intCast(carrier) };
            try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, module, .{}));
            operation.instance = original;
            normalized_owner = true;
            break;
        }
        if (normalized_owner) break;
    }
    try std.testing.expect(normalized_owner);
    try std.testing.expect(tested);
    try V.validate(allocator, module, .{});
}
test "typed input invocation independently reconstructs callback no store authority through OOM" {
    const allocator = std.testing.allocator;
    const bytes = try artifact(allocator, input_invocation_producer);
    defer allocator.free(bytes);
    try inputInvocationValidation(allocator, bytes);
    const failures = @import("../allocation_failures.zig");
    try failures.checkAllAllocationFailures(allocator, generativeArtifactEncoding, .{input_invocation_producer});
    try failures.checkAllAllocationFailures(allocator, inputInvocationValidation, .{bytes});
}

test "principal reference bounds preserve quantified row callback producers" {
    const a = std.testing.allocator;
    const source =
        \\const apply: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = fn pair => (@product.get pair 0) (@product.get pair 1)
        \\const both: (forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}) -> U32 -> (U32, F32) = fn apply => fn value => (apply ((fn item => item), value), apply ((fn item => item), @u32.to_f32 value))
        \\const foreign_apply: ((forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}), (U32 -> U32 ! {Foreign})) -> U32 ! {Foreign} = fn pair => (@product.get pair 0) (@product.get pair 1, 42)
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModule(a, &tree, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try snapshot.freezePrincipal(a, &tree, &checked);
    defer snapshot.deinit(a, &frozen);
    try validation.validate(&frozen, pool.entries.items.len + 1, 1);
}
