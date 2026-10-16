const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const contracts = @import("package_contracts.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
const E = @import("../eval/type_evidence.zig");

fn portableFixture(allocator: std.mem.Allocator, comptime name: []const u8) !core.Module {
    const source = @import("fixtures").source(name);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    errdefer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn validatePortable(allocator: std.mem.Allocator, module: *const core.Module) !void {
    try @import("frozen_core_validation.zig").validate(allocator, module, .{ .units = &[_]*const core.Module{module} });
}
fn ordinaryControl(allocator: std.mem.Allocator) !void {
    var module = try portableFixture(allocator, "package/ordinary-control.blot");
    defer module.deinit(allocator);
    try std.testing.expect(module.has_rank_contracts);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try validatePortable(allocator, &module);
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "package ordinary composition retains actual Scope request loan and demand owners" {
    var module = try portableFixture(std.testing.allocator, "package/mixed-composition.blot");
    defer module.deinit(std.testing.allocator);
    try validatePortable(std.testing.allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, validatePortable, .{&module});
}

test "package ordinary control keeps request decision loop pattern update and demand owners through OOM" {
    try ordinaryControl(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ordinaryControl, .{});
}

fn rejectPortable(allocator: std.mem.Allocator, module: *const core.Module) !void {
    if (validatePortable(allocator, module)) |_| return error.TestUnexpectedResult else |err| {
        if (err != error.InvalidArtifact) return err;
    }
}
fn ordinaryControlMutants(allocator: std.mem.Allocator) !void {
    var module = try portableFixture(allocator, "package/ordinary-control.blot");
    defer module.deinit(allocator);
    try validatePortable(allocator, &module);
    var mutations: usize = 0;
    // The update's self binding cannot authorize an equally typed reference
    // in the root expression or any surrounding lexical owner.
    const update = module.updates[0];
    for (module.references) |*reference| {
        if (reference.unit != 0 and reference.unit != module.unit) continue;
        const declaration = module.binding(reference.binding);
        if (declaration.kind != .parameter or declaration.ty != T.u32_type) continue;
        const before = reference.*;
        reference.binding = update.self_binding;
        try rejectPortable(allocator, &module);
        reference.* = before;
        mutations += 1;
        break;
    }
    // A type-correct reference from another arm remains outside this arm.
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .match) continue;
        const arms = module.matchArms(@intCast(id));
        if (arms.len != 2) continue;
        const first = arms[0].body;
        var donor: ?core.Node = null;
        for (module.nodes) |candidate| {
            if (candidate.tag != .reference or candidate.ty != T.u32_type) continue;
            const reference = module.references[candidate.a];
            if (module.binding(reference.binding).kind == .local and module.binding(reference.binding).initializer == 0 and reference.binding != update.self_binding) donor = candidate;
        }
        const before = module.nodes[first];
        module.nodes[first] = donor orelse return error.TestUnexpectedResult;
        try rejectPortable(allocator, &module);
        module.nodes[first] = before;
        mutations += 1;
        break;
    }
    const request = &module.request_loops[0];
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .block or id == request.return_target or node.ty != request.result_type) continue;
        const before = request.return_target;
        request.return_target = @intCast(id);
        try rejectPortable(allocator, &module);
        request.return_target = before;
        mutations += 1;
        break;
    }
    try std.testing.expectEqual(@as(usize, 3), mutations);
    try validatePortable(allocator, &module);
}

test "package ordinary control rejects leaked arm locals update self and foreign request return owners through OOM" {
    try ordinaryControlMutants(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ordinaryControlMutants, .{});
}

test "package payload substitution preserves operation endpoints and distinct opening identities" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },                    .{ .tag = .unit },                      .{ .tag = .boolean },                                             .{ .tag = .u32 },                       .{ .tag = .f32 },            .{ .tag = .never },
        .{ .tag = .bound },                     .{ .tag = .function, .a = 6, .b = 3 },  .{ .tag = .function, .a = 3, .b = 3 },                            .{ .tag = .function, .a = 2, .b = 3 },  .{ .tag = .bound, .c = 12 }, .{ .tag = .bound, .c = 13 },
        .{ .tag = .function, .a = 10, .b = 3 }, .{ .tag = .function, .a = 11, .b = 3 }, .{ .tag = .usage, .a = 3, .b = @backingInt(T.UsageKind.unique) }, .{ .tag = .function, .a = 14, .b = 3 },
    };
    var extra = [_]T.Id{6};
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra };
    var remaining: usize = 65_536;
    var proof: contracts.Substitution = .{ .types = &graph, .formal = .{ .len = 1 }, .witnesses = &.{3}, .remaining = &remaining };
    try proof.validate(7, 8);
    try std.testing.expectError(error.InvalidArtifact, proof.validate(7, 9));
    proof.witnesses = &.{10};
    try proof.validate(7, 12);
    try std.testing.expectError(error.InvalidArtifact, proof.validate(7, 13));
    proof.witnesses = &.{14};
    try std.testing.expectError(error.InvalidArtifact, proof.validate(7, 15));
    proof.witnesses = &.{3};
    nodes[6].a = 1;
    try std.testing.expectError(error.InvalidArtifact, proof.validate(7, 8));
}

test "package lexical owners reject stolen slots inactive openings and unsealed witnesses" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },                                              .{ .tag = .unit },                        .{ .tag = .boolean },        .{ .tag = .u32 },            .{ .tag = .f32 },   .{ .tag = .never },
        .{ .tag = .bound },                                               .{ .tag = .existential, .a = 6, .c = 1 }, .{ .tag = .bound, .c = 12 }, .{ .tag = .bound, .c = 13 }, .{ .tag = .bound }, .{ .tag = .existential, .a = 10, .b = 3, .c = 1 },
        .{ .tag = .usage, .a = 3, .b = @backingInt(T.UsageKind.unique) },
    };
    var extra = [_]T.Id{ 6, 8, 9, 10 };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra };
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try context.initialize();
    try context.visit(7);
    try context.visit(11);
    try context.pack(7, 3, &.{3});
    try std.testing.expectError(error.InvalidArtifact, context.pack(7, 3, &.{2}));
    try std.testing.expectError(error.InvalidArtifact, context.pack(7, 12, &.{12}));
    try std.testing.expectError(error.InvalidArtifact, context.pack(7, 7, &.{7}));
    try std.testing.expectError(error.InvalidArtifact, context.visit(6));
    try std.testing.expectError(error.InvalidArtifact, context.visit(8));
    try context.open(7, 12, .{ .start = 1, .len = 1 }, 8);
    try context.visit(8);
    try std.testing.expectError(error.InvalidArtifact, context.visit(9));
    try context.open(7, 13, .{ .start = 2, .len = 1 }, 9);
    try context.pack(7, 8, &.{8});
    try std.testing.expectError(error.InvalidArtifact, context.pack(7, 8, &.{9}));
    context.close();
    try std.testing.expectError(error.InvalidArtifact, context.visit(9));
    context.close();
    try std.testing.expectError(error.InvalidArtifact, context.visit(8));
    nodes[11].a = 6;
    try std.testing.expectError(error.InvalidArtifact, context.visit(11));
    nodes[11].a = 10;
    nodes[11].b = 0;
    var forged: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try std.testing.expectError(error.InvalidArtifact, forged.initialize());
}

test "package type owners bound shared DAG and malformed table reads" {
    var nodes: [32]T.Node = @splat(.{ .tag = .unit });
    for (6..nodes.len) |index| nodes[index] = .{ .tag = .function, .a = @intCast(index - 1), .b = @intCast(index - 1) };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &.{} };
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try context.initialize();
    try std.testing.expectError(error.InvalidArtifact, context.visit(nodes.len - 1));
    try std.testing.expectEqual(@as(usize, 0), remaining);
    remaining = 65_536;
    nodes[6] = .{ .tag = .existential, .a = 1, .b = 0xffffffff, .c = 1 };
    try std.testing.expectError(error.InvalidArtifact, context.initialize());
    nodes[6] = .{ .tag = .record, .a = 0, .b = 0xffffffff };
    try std.testing.expectError(error.InvalidArtifact, context.visit(6));
}

test "package covariant row views require whole owned endpoint proof and preserve Foreign" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },                   .{ .tag = .unit },                             .{ .tag = .boolean },                          .{ .tag = .u32 },                              .{ .tag = .f32 }, .{ .tag = .never },
        .{ .tag = .function, .a = 3, .b = 3 }, .{ .tag = .function, .a = 3, .b = 3, .c = 1 }, .{ .tag = .function, .a = 3, .b = 2, .c = 1 }, .{ .tag = .function, .a = 3, .b = 3, .c = 2 },
    };
    var rows = [_]T.Effects.Row{ .{}, .{ .tail = .{ .variable = 0 } }, .{ .labels = .{ .len = 1 } } };
    var labels = [_]T.Effects.Label{T.foreign_operation};
    var operations = [_]T.Operation{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &.{}, .effects = .{ .rows = &rows, .labels = &labels, .variable_count = 1 }, .operations = &operations };
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try context.initialize();
    try std.testing.expectError(error.InvalidArtifact, context.visit(7));
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining, .views = &context };
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 8));
    try std.testing.expect(!context.isPure(1));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 9));
    try std.testing.expect(!context.isPure(1));
    try proof.validate(6, 7);
    try context.visit(7);
    try context.visit(9);
    try proof.validate(9, 9);
}

fn ownedCore(allocator: std.mem.Allocator) !void {
    const source =
        \\type Item = exists [a, b] => (a, a -> b, b -> U32)
        \\const make: U32 -> Item = fn value => pack [U32, F32] (value, fn number => @u32.to_f32 number, fn number => @f32.to_u32 number) as Item
        \\const read: Item -> U32 = fn item => unpack item as [a, b] body in (@product.get body 2) ((@product.get body 1) (@product.get body 0))
        \\entry const answer: U32 -> U32 = fn value => read (make value)
    ;
    const a = allocator;
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.checkModule(a, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &module.types, .remaining = &remaining };
    try context.initialize();
    var packs: usize = 0;
    var openings: usize = 0;
    for (module.nodes, 0..) |node, id| switch (node.tag) {
        .package_pack => {
            try context.pack(node.ty, module.typeOf(node.a), module.types.list(.{ .start = node.b, .len = node.c }));
            packs += 1;
        },
        .package_unpack => {
            const opening = module.packageOpening(@intCast(id));
            try context.open(module.typeOf(node.a), node.b, opening.binders, module.binding(node.b).ty);
            try context.visit(module.typeOf(opening.body));
            context.close();
            try std.testing.expectError(error.InvalidArtifact, context.visit(module.binding(node.b).ty));
            try context.visit(node.ty);
            openings += 1;
        },
        else => {},
    };
    try std.testing.expect(packs != 0 and openings != 0);
    try @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} });
    for (module.nodes) |*node| {
        if (node.tag != .reference or module.types.node(node.ty).tag != .product) continue;
        const original = node.*;
        node.ty = T.u32_type;
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} }));
        node.* = original;
        break;
    }
    for (module.nodes) |node| {
        if (node.tag != .project) continue;
        const original = module.projections[node.b];
        module.projections[node.b].result_type = T.boolean;
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} }));
        module.projections[node.b] = original;
        break;
    }
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .package_unpack) continue;
        const opening = module.packageOpening(@intCast(id));
        const binder = module.types.list(opening.binders)[0];
        const original = module.types.nodes[binder];
        module.types.nodes[binder].c += 1;
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} }));
        module.types.nodes[binder] = original;
        break;
    }
}

fn checkSource(source: []const u8, accepted: bool) !void {
    const a = std.testing.allocator;
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(a, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(accepted, checked.diagnostics.len == 0);
    if (!accepted) try std.testing.expect(for (checked.diagnostics) |diagnostic| {
        if (diagnostic.code == .effect_mismatch) break true;
    } else false);
}

test "opened package operations retain exact owned rows under larger ambients and pure parameters" {
    try checkSource(
        \\type Item = exists [a] => (a, a -> U32)
        \\const read: Item -> U32 ! {Foreign} = fn item => unpack item as [a] body in (fn (operation: a -> U32) => operation (@product.get body 0)) (@product.get body 1)
    , true);
    try checkSource(
        \\type Item = exists [a] => (a, a -> U32)
        \\const read: Item -> U32 ! {Foreign} = fn item => unpack item as [a] body in (fn (operation: a -> U32 ! {Foreign}) => operation (@product.get body 0)) (@product.get body 1)
    , true);
    try checkSource(
        \\type Item = exists [a] => (a, a -> U32 ! {Foreign})
        \\const read: Item -> U32 = fn item => unpack item as [a] body in (fn (operation: a -> U32) => operation (@product.get body 0)) (@product.get body 1)
    , false);
    try checkSource(
        \\type Item = exists [a] => (a, a -> U32)
        \\const wrong = fn (operation: U32 -> U32 ! {Foreign}) => pack [U32] (42, operation) as Item
    , false);
}

test "checked multi binder package Core reconstructs pack and lexical opening substitutions" {
    try ownedCore(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedCore, .{});
}

fn lowerSource(a: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(a, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    return core.lower(a, &syntax, &pool, &checked);
}

fn selectedScopeOwners(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\const identity: forall [a] => a -> a = fn value => value
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\const separate = fn () => @effect.scope (fn (other: State U32) => 0)
        \\const selected = fn (flag: Bool) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
        \\  let choose = fn () => if flag then left else right
        \\  let chosen = choose ()
        \\  let alias = chosen
        \\  let (_, result) = do (@effect.state chosen.get chosen.set 1):
        \\    use alias.set 42
        \\    return alias.get ()
        \\  return result
        \\))
        \\entry const answer = fn (flag: Bool) => identity (selected flag)
    );
    defer module.deinit(allocator);
    try validatePortable(allocator, &module);
    var choices_checked: usize = 0;
    for (module.types.nodes) |selected| {
        if (selected.tag != .instance_selection) continue;
        const choices = module.types.nominalArguments(selected);
        const slot = selected.c + 1;
        const original = module.types.extra[slot];
        module.types.extra[slot] = T.u32_type;
        try rejectPortable(allocator, &module);
        module.types.extra[slot] = original;
        for (module.types.nodes, 0..) |candidate, id| {
            if (candidate.tag != .scoped or candidate.b == 0) continue;
            const left = module.types.node(choices[0]);
            const right = module.types.node(choices[1]);
            if ((candidate.b == left.b and candidate.c == left.c) or (candidate.b == right.b and candidate.c == right.c)) continue;
            module.types.extra[slot] = @intCast(id);
            try rejectPortable(allocator, &module);
            module.types.extra[slot] = original;
            choices_checked += 1;
            break;
        }
    }
    try std.testing.expect(choices_checked != 0);
    var conditional_checked = false;
    for (module.nodes) |*node| {
        if (node.tag != .if_value) continue;
        const result = module.types.node(node.ty);
        if (result.tag != .scoped or result.b != 0 or module.types.node(result.c).tag != .instance_selection) continue;
        const original = node.*;
        node.b = original.c;
        node.c = original.b;
        try rejectPortable(allocator, &module);
        node.* = original;
        conditional_checked = true;
    }
    try std.testing.expect(conditional_checked);
    try validatePortable(allocator, &module);
}
test "portable selected Scope requires both actual lexical choices through OOM" {
    try selectedScopeOwners(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, selectedScopeOwners, .{});
}

const qualified_package_source =
    \\type Item = exists [a] => (unique a, (unique a) -> U32)
    \\const read: (unique U32) -> U32 = fn hidden => @usage.borrow hidden (fn loan => @usage.read loan)
    \\const make = fn (owner: unique U32) => pack [U32] (owner, read) as Item
    \\entry const answer = fn () => do:
    \\  use owner <- @resource.acquire (fn () => 42) (fn released => ())
    \\  return unpack (make owner) as [a] value in do:
    \\    let (hidden, operation) = value
    \\    return operation hidden
;
fn qualifiedPackage(a: std.mem.Allocator) !void {
    var module = try lowerSource(a, qualified_package_source);
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
}
test "qualified package interfaces retain owner moves operations and lexical borrow through all allocation failures" {
    try qualifiedPackage(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, qualifiedPackage, .{});
}

test "qualified package interfaces reject erased owner qualifiers and forged pure resource bodies" {
    const a = std.testing.allocator;
    const V = @import("frozen_core_validation.zig");
    var module = try lowerSource(a, qualified_package_source);
    defer module.deinit(a);
    try V.validate(a, &module, .{});
    var changes: usize = 0;
    for (module.types.nodes) |*node| {
        if (node.tag != .usage or node.b != @backingInt(T.UsageKind.unique) or module.types.node(node.a).tag != .bound) continue;
        const original = node.*;
        node.b = @backingInt(T.UsageKind.shared);
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &module, .{}));
        node.* = original;
        changes += 1;
    }
    try std.testing.expect(changes != 0);
    const signature = module.binding(module.bodies[module.bodies.len - 1].binding).ty;
    const row = module.types.nodes[signature].c;
    module.types.nodes[signature].c = 0;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &module, .{}));
    module.types.nodes[signature].c = row;
    try V.validate(a, &module, .{});
}

test "package immutable result footprint sees hidden closure references despite forged capture lists" {
    const a = std.testing.allocator;
    var module = try lowerSource(a,
        \\type Item = exists [a] => a
        \\const identity: Item -> (U32 -> U32) = fn item => unpack item as [a] hidden in do:
        \\  let observed = hidden
        \\  return fn (value: U32) => do:
        \\    let ignored = 42
        \\    return value
    );
    defer module.deinit(a);
    const context = .{ .units = &[_]*const core.Module{&module} };
    try @import("package_core.zig").executable(&module, context);
    var hidden: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .reference and module.types.node(node.ty).tag == .bound) hidden = @intCast(id);
    }
    try std.testing.expect(hidden != 0);
    var mutated = false;
    for (module.nodes) |*node| {
        if (node.tag != .bind or module.node(node.b).tag != .constant or module.node(node.b).a != 42) continue;
        const original = node.*;
        const binding = module.bindings[node.a];
        node.b = hidden;
        module.bindings[node.a].ty = module.typeOf(hidden);
        module.bindings[node.a].scheme.root = module.typeOf(hidden);
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, context));
        node.* = original;
        module.bindings[node.a] = binding;
        mutated = true;
        break;
    }
    try std.testing.expect(mutated);
    try @import("package_core.zig").executable(&module, context);
}

test "package lexical resealing discharges only witnessed abstract identities" {
    const a = std.testing.allocator;
    var module = try lowerSource(a,
        \\type Item = exists [a] => a
        \\const reseal: Item -> Item = fn item => unpack item as [a] value in pack [a] value as Item
    );
    defer module.deinit(a);
    const context = .{ .units = &[_]*const core.Module{&module} };
    try @import("package_core.zig").executable(&module, context);
    var mutated = false;
    for (module.nodes) |node| {
        if (node.tag != .package_pack) continue;
        const witness = module.types.extra[node.b];
        module.types.extra[node.b] = T.u32_type;
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, context));
        module.types.extra[node.b] = witness;
        mutated = true;
    }
    try std.testing.expect(mutated);
    try @import("package_core.zig").executable(&module, context);
}

test "package sealing proves latent captured identity even when result types are closed" {
    const a = std.testing.allocator;
    var module = try lowerSource(a,
        \\type Item = exists [a] => a
        \\type Callback = exists [b] => U32 -> U32
        \\const hide: Item -> Callback = fn item => unpack item as [a] hidden in do:
        \\  let observed = hidden
        \\  return pack [U32] (fn (value: U32) => do:
        \\    let ignored = 42
        \\    return value) as Callback
    );
    defer module.deinit(a);
    const context = .{ .units = &[_]*const core.Module{&module} };
    try @import("package_core.zig").executable(&module, context);
    var hidden: core.Id = 0;
    var pack: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .reference and module.types.node(node.ty).tag == .bound) hidden = @intCast(id);
        if (node.tag == .package_pack) pack = @intCast(id);
    }
    try std.testing.expect(hidden != 0 and pack != 0);
    var mutated = false;
    for (module.nodes) |*node| {
        if (node.tag != .bind or module.node(node.b).tag != .constant or module.node(node.b).a != 42) continue;
        const original = node.*;
        const binding = module.bindings[node.a];
        node.b = hidden;
        module.bindings[node.a].ty = module.typeOf(hidden);
        module.bindings[node.a].scheme.root = module.typeOf(hidden);
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, context));
        const position = module.node(pack).b;
        const witness = module.types.extra[position];
        module.types.extra[position] = module.typeOf(hidden);
        // Sealing the identity cannot repair a forged physical capture table.
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, context));
        const closure_id = module.node(module.node(pack).a).a;
        const captures = module.closures[closure_id].captures;
        const start = module.extra.len;
        module.extra = try a.realloc(module.extra, start + 1);
        module.extra[start] = module.reference(hidden).binding;
        module.closures[closure_id].captures = .{ .start = @intCast(start), .len = 1 };
        try @import("package_core.zig").executable(&module, context);
        module.closures[closure_id].captures = captures;
        module.types.extra[position] = witness;
        node.* = original;
        module.bindings[node.a] = binding;
        mutated = true;
        break;
    }
    try std.testing.expect(mutated);
}

test "canonical package ordinal sharing reconstructs each enclosing recipe" {
    const a = std.testing.allocator;
    var store = try E.Store.init(a);
    defer store.deinit();
    const first = try store.intern(.bound, 0, 0, &.{});
    const second = try store.intern(.bound, 1, 0, &.{});
    const arrow = try store.intern(.function, first, T.u32_type, &.{});
    const product = try store.intern(.product, 0, 0, &.{ first, arrow });
    const pair = try store.intern(.product, 0, 0, &.{ first, second });
    const one = try store.intern(.existential, product, 1, &.{});
    const two = try store.intern(.existential, pair, 2, &.{});
    try std.testing.expect(one != two);
    try std.testing.expect(@import("../reuse/portable_query.zig").validEvidence(store.view()));
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(store.view(), one));
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(store.view(), two));
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(store.view(), first));
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(store.view(), arrow));
    try @import("package_evidence.zig").validate(store.view());
    const original = store.nodes.items[two];
    store.nodes.items[two].b = 1;
    try std.testing.expectError(error.InvalidArtifact, @import("package_evidence.zig").validate(store.view()));
    store.nodes.items[two] = original;
    store.nodes.items[second].b = 1;
    try std.testing.expectError(error.InvalidArtifact, @import("package_evidence.zig").validate(store.view()));
    store.nodes.items[second].b = 0;
    try @import("package_evidence.zig").validate(store.view());
}

test "canonical package body walking shares admission budget across a forged DAG" {
    var nodes: [32]E.Node = @splat(.{ .tag = .unit });
    nodes[6] = .{ .tag = .bound };
    for (7..nodes.len - 1) |index| nodes[index] = .{ .tag = .function, .a = @intCast(index - 1), .b = @intCast(index - 1) };
    nodes[nodes.len - 1] = .{ .tag = .existential, .a = nodes.len - 2, .b = 1 };
    try std.testing.expectError(error.InvalidArtifact, @import("package_evidence.zig").validate(.{ .nodes = &nodes, .extra = &.{} }));
}

test "foreign package body observations decline validation context reuse" {
    const a = std.testing.allocator;
    const V = @import("frozen_core_validation.zig");
    var ordinary = try lowerSource(a, "entry const answer: U32 -> U32 = fn value => value\n");
    defer ordinary.deinit(a);
    const stable: V.Context = .{ .units = &.{&ordinary} };
    var ordinary_image = try V.ContextImage.capture(a, stable, stable.units);
    defer ordinary_image.deinit(a);
    try std.testing.expect(ordinary_image.matches(stable, stable.units));
    try std.testing.expect(V.equivalentContext(stable, stable, stable.units, stable.units));
    // Numeric admission also reconstructs foreign helper bodies. Its owned
    // caller flag must invalidate the same cache even with ordinary siblings.
    ordinary.has_numeric_proofs = true;
    try std.testing.expect(!ordinary_image.matches(stable, stable.units));
    try std.testing.expect(!V.equivalentContext(stable, stable, stable.units, stable.units));
    ordinary.has_numeric_proofs = false;
    try std.testing.expect(ordinary_image.matches(stable, stable.units));
    var producer = try lowerSource(a,
        \\type Item = exists [a] => (a, a -> U32)
        \\const make: U32 -> Item = fn value => pack [U32] (value, fn number => @u32.add number 1) as Item
    );
    defer producer.deinit(a);
    producer.unit = 2;
    // The foreign-only context carries no existential node. Classify the
    // actual local caller, rather than inferring authority from those units.
    try std.testing.expect(!ordinary_image.matches(stable, &.{&producer}));
    try std.testing.expect(!V.equivalentContext(stable, stable, &.{&producer}, &.{&producer}));
    try std.testing.expect(!ordinary_image.matches(stable, &.{}));
    try std.testing.expect(!V.equivalentContext(stable, stable, &.{}, &.{}));
    var foreign_only = try V.ContextImage.capture(a, stable, &.{&producer});
    defer foreign_only.deinit(a);
    try std.testing.expect(!foreign_only.matches(stable, stable.units));
    const sensitive: V.Context = .{ .units = &.{ &ordinary, &producer } };
    var image = try V.ContextImage.capture(a, sensitive, sensitive.units);
    defer image.deinit(a);
    try std.testing.expect(!image.matches(sensitive, sensitive.units));
    try std.testing.expect(!V.equivalentContext(sensitive, sensitive, sensitive.units, sensitive.units));
    const binding_count = producer.bindings.len;
    var changed = false;
    for (producer.nodes) |*node| {
        if (node.tag != .scalar) continue;
        node.op = .convert_f32_u32;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    try std.testing.expectEqual(binding_count, producer.bindings.len);
    try std.testing.expect(!image.matches(sensitive, sensitive.units));
    try std.testing.expect(!V.equivalentContext(sensitive, sensitive, sensitive.units, sensitive.units));
    try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&producer, sensitive));
}

test "package Foreign row closure belongs to exact body certificates" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },                           .{ .tag = .unit },                             .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never },
        .{ .tag = .function, .a = 3, .b = 3, .c = 1 }, .{ .tag = .function, .a = 3, .b = 3, .c = 2 },
    };
    var extra = [_]T.Id{0};
    var labels = [_]T.Effects.Label{T.foreign_operation};
    var rows = [_]T.Effects.Row{ .{}, .{ .labels = .{ .len = 1 }, .tail = .{ .variable = 0 } }, .{ .labels = .{ .len = 1 } } };
    var operations = [_]T.Operation{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows, .labels = &labels, .variable_count = 1 }, .operations = &operations };
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &graph, .remaining = &remaining, .executable = true };
    try context.initialize();
    try std.testing.expectError(error.InvalidArtifact, context.visit(6));
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining, .views = &context, .left_rows = .{ .len = 1 } };
    try proof.validate(6, 7);
    proof.left_rows = .{};
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 7));
    context.closed_rows[1] = true;
    try context.visit(6);
    try proof.validate(6, 7);
    labels[0] = 0;
    try std.testing.expectError(error.InvalidArtifact, context.visit(6));
}

fn rejectDictionaryModule(allocator: std.mem.Allocator, module: *const core.Module) !void {
    @import("frozen_core_validation.zig").validate(allocator, module, .{}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try std.testing.expectEqual(error.InvalidArtifact, err);
        return;
    };
    try std.testing.expect(false);
}

fn predicatePackSelection(allocator: std.mem.Allocator) !void {
    const source =
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
        \\type Item = exists [a] where { Render a } => a
        \\const item: Item = pack [U32] 42 as Item
        \\const flag: Item = pack [Bool] #True as Item
        \\const read = fn (item: Item) => unpack item as [a] value in Render.show value
        \\const both = fn (left: Item) => fn (right: Item) => unpack left as [a] x in unpack right as [b] y in @u32.add (Render.show x) (Render.show y)
        \\const answer: U32 = @u32.add (read item) (both item flag)
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &tree, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("predicate pack {s} at {}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), checked.dictionary_selections.len);
    try std.testing.expectEqual(@as(usize, 3), checked.dictionary_uses.len);
    const selection = checked.dictionary_selections[0];
    const goals = checked.types.quantifierGoals(selection.quantifier);
    try std.testing.expectEqual(@as(usize, 1), goals.len);
    const proof = checked.selected_proofs[selection.proof.selected];
    try std.testing.expectEqual(goals[0].identity, proof.contract);
    try std.testing.expectEqual(@as(u32, 1), proof.members.len);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), module.dictionary_selections.len);
    try std.testing.expectEqual(@as(usize, 3), module.dictionary_uses.len);
    const dictionary = module.dictionary_selections[0];
    try std.testing.expectEqual(core.Tag.package_pack, module.node(dictionary.owner).tag);
    const members = module.extra[dictionary.members.start..][0..dictionary.members.len];
    try std.testing.expectEqual(@as(usize, 1), members.len);
    try std.testing.expectEqual(core.Tag.reference, module.node(members[0]).tag);
    try std.testing.expectEqual(module.node(dictionary.owner).ty, dictionary.quantifier);
    const validation = @import("frozen_core_validation.zig");
    try validation.validateBounds(&module, .{});
    const stored_selection = module.dictionary_selections[0];
    module.dictionary_selections[0].members.start = 0xffffffff;
    try std.testing.expectError(error.InvalidArtifact, validation.validateBounds(&module, .{}));
    module.dictionary_selections[0] = stored_selection;
    module.dictionary_selections[0].proof = .{ .selected = @intCast(module.selected_proofs.len) };
    try std.testing.expectError(error.InvalidArtifact, validation.validateBounds(&module, .{}));
    module.dictionary_selections[0] = stored_selection;
    const stored_use = module.dictionary_uses[0];
    module.dictionary_uses[0].opening = @intCast(module.bindings.len);
    try std.testing.expectError(error.InvalidArtifact, validation.validateBounds(&module, .{}));
    module.dictionary_uses[0] = stored_use;
    try validation.validateBounds(&module, .{});
    const dictionaries = @import("dictionary_contracts.zig");
    var remaining: usize = 65_536;
    try @import("../eval/selected_implementation_admission.zig").core(allocator, &module, &remaining);
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = &remaining, .executable = true };
    try scopes.initialize();
    for (module.dictionary_selections) |entry| try dictionaries.pack(&module, entry.owner, &scopes);
    module.dictionary_selections[0].proof = module.dictionary_selections[1].proof;
    try std.testing.expectError(error.InvalidArtifact, dictionaries.pack(&module, stored_selection.owner, &scopes));
    module.dictionary_selections[0] = stored_selection;
    const selected_member = module.extra[stored_selection.members.start];
    const saved_reference = module.references[module.node(selected_member).a];
    const other_member = module.extra[module.dictionary_selections[1].members.start];
    module.references[module.node(selected_member).a] = module.reference(other_member);
    try std.testing.expectError(error.InvalidArtifact, dictionaries.pack(&module, stored_selection.owner, &scopes));
    module.references[module.node(selected_member).a] = saved_reference;
    for (module.dictionary_uses) |entry| {
        var opening_id: core.Id = 0;
        for (module.nodes, 0..) |node, ordinal| if (node.tag == .package_unpack and node.b == entry.opening) {
            opening_id = @intCast(ordinal);
            break;
        };
        try std.testing.expect(opening_id != 0);
        const opening_node = module.node(opening_id);
        const opening = module.packageOpening(opening_id);
        try std.testing.expectError(error.InvalidArtifact, dictionaries.use(&module, entry.node, &scopes));
        try scopes.open(module.typeOf(opening_node.a), opening_node.b, opening.binders, module.binding(opening_node.b).ty);
        try dictionaries.use(&module, entry.node, &scopes);
        scopes.close();
    }
    try @import("../eval/implementation_admission.zig").scopes(allocator, &module.types, &module, module.obligations, &remaining);
    try @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} });
    try validation.validate(allocator, &module, .{});
    module.dictionary_selections[0].proof = module.dictionary_selections[1].proof;
    try rejectDictionaryModule(allocator, &module);
    module.dictionary_selections[0] = stored_selection;
    module.references[module.node(selected_member).a] = module.reference(other_member);
    try rejectDictionaryModule(allocator, &module);
    module.references[module.node(selected_member).a] = saved_reference;
    module.dictionary_uses[0].opening = module.dictionary_uses[1].opening;
    try rejectDictionaryModule(allocator, &module);
    module.dictionary_uses[0] = stored_use;
    module.dictionary_uses[0].member = 0xffffffff;
    try rejectDictionaryModule(allocator, &module);
    module.dictionary_uses[0] = stored_use;
    const stored_selections = module.dictionary_selections;
    module.dictionary_selections = &.{};
    rejectDictionaryModule(allocator, &module) catch |err| {
        module.dictionary_selections = stored_selections;
        return err;
    };
    module.dictionary_selections = stored_selections;
    const stored_uses = module.dictionary_uses;
    module.dictionary_uses = &.{};
    rejectDictionaryModule(allocator, &module) catch |err| {
        module.dictionary_uses = stored_uses;
        return err;
    };
    module.dictionary_uses = stored_uses;
    const implementation_body = module.body(module.reference(selected_member).binding).?;
    const stored_body_node = module.node(implementation_body.root);
    module.nodes[implementation_body.root].ty = T.boolean;
    try rejectDictionaryModule(allocator, &module);
    module.nodes[implementation_body.root] = stored_body_node;
    try validation.validate(allocator, &module, .{});
    const answer = checked.resolved[tree.roots.items[tree.roots.items.len - 1]];
    var session = try @import("../eval/core_eval.zig").Session.init(allocator, &.{module});
    defer session.deinit();
    const result = try session.value(.{ .unit = 1, .binding = answer });
    try std.testing.expectEqual(@as(u32, 91), result.bits);
}
test "predicate package packing records the exact checked dictionary and callable member through OOM" {
    try predicatePackSelection(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, predicatePackSelection, .{});
}

fn structuralRankModule(allocator: std.mem.Allocator) !void {
    const source =
        \\const first: forall [a, b] => (a, b) -> a = fn value => @product.get value 0
        \\const twice: forall [a] => a -> (a, a) = fn value => (value, value)
        \\const twice_alias: forall [a] => a -> (a, a) = twice
        \\const record: forall [a] => a -> {value: a} = fn value => {value: value}
        \\const head: forall [a] => Array a -> a = fn values => @array.get values 0
        \\entry const array_head = fn (value: U32) => head #[value, 42]
        \\const keep: forall [a] => a -> (forall [b] => b -> a) = fn first => fn second => first
        \\entry const held = fn (value: U32) => (keep value) #True
        \\const pass: (forall [a] => (Bool, a) -> U32) -> U32 = fn recurse => recurse (#False, 42)
        \\const recursive: forall [a] => (Bool, a) -> U32 = fn pair => if @product.get pair 0 then pass recursive else 0
        \\entry const recursive_call = fn (value: U32) => recursive (#True, value)
        \\entry const whole = fn (value: U32) => first (value, #True)
        \\entry const fraction = fn (value: F32) => @product.get (twice_alias value) 1
        \\entry const stored = fn (value: U32) => (record value).value
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("rank_portable.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} });
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var emitted = try @import("../backend/core_backend.zig").compile(allocator, &.{module}, 1);
    defer emitted.deinit(allocator);
    try std.testing.expect(emitted.diagnostic == null);
    var mutated = false;
    for (module.nodes) |*node| {
        if (node.tag != .reference or module.types.node(node.ty).tag != .bound) continue;
        const saved = node.*;
        node.ty = T.u32_type;
        try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} }));
        node.* = saved;
        mutated = true;
        break;
    }
    try std.testing.expect(mutated);
}

test "structural rank introductions reconstruct multiple binders products records and concrete instances" {
    try structuralRankModule(std.testing.allocator);
}

test "structural rank introductions preserve immutable admission and ABI through every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, structuralRankModule, .{});
}

test "dictionary composed endpoint substitution preserves structural goals and exact opening identity" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },        .{ .tag = .unit },                     .{ .tag = .boolean },                    .{ .tag = .u32 },                        .{ .tag = .f32 },           .{ .tag = .never },
        .{ .tag = .variable },      .{ .tag = .bound },                    .{ .tag = .bound, .c = 12 },             .{ .tag = .bound, .c = 13 },             .{ .tag = .array, .a = 7 }, .{ .tag = .array, .a = 8 },
        .{ .tag = .array, .a = 9 }, .{ .tag = .function, .a = 6, .b = 6 }, .{ .tag = .function, .a = 11, .b = 11 }, .{ .tag = .function, .a = 11, .b = 12 },
    };
    var extra = [_]T.Id{ 6, 7 };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra };
    var remaining: usize = 65_536;
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining };
    try proof.composed(.{ .len = 1 }, &.{10}, .{ .start = 1, .len = 1 }, &.{8}, 13, 14);
    try std.testing.expectError(error.InvalidArtifact, proof.composed(.{ .len = 1 }, &.{10}, .{ .start = 1, .len = 1 }, &.{8}, 13, 15));
    try std.testing.expectError(error.InvalidArtifact, proof.composed(.{ .len = 1 }, &.{10}, .{ .start = 1, .len = 1 }, &.{9}, 13, 14));
    try std.testing.expectError(error.InvalidArtifact, proof.composed(.{ .len = 1 }, &.{10}, .{ .start = 1, .len = 1 }, &.{}, 13, 14));
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, proof.composed(.{ .len = 1 }, &.{10}, .{ .start = 1, .len = 1 }, &.{8}, 13, 14));
    try std.testing.expectEqual(@as(usize, 0), remaining);
}

fn sortedRowModule(allocator: std.mem.Allocator) !void {
    const source =
        \\const apply: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = fn pair => (@product.get pair 0) (@product.get pair 1)
        \\const both: (forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}) -> U32 -> (U32, F32) = fn apply => fn value => (apply ((fn item => item), value), apply ((fn item => item), @u32.to_f32 value))
        \\const foreign_apply: ((forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}), (U32 -> U32 ! {Foreign})) -> U32 ! {Foreign} = fn pair => (@product.get pair 0) (@product.get pair 1, 42)
        \\entry const host = fn (callback: U32 -> U32 ! {Foreign}) => foreign_apply (apply, callback)
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("rank_portable.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} });
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var interface = try @import("../reuse/dependency_snapshot.zig").freezePrincipal(allocator, &syntax, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &interface);
    try @import("../reuse/dependency_interface_validation.zig").validate(&interface, pool.entries.items.len + 1, 1);
    try @import("../reuse/dependency_interface_validation.zig").validateGraph(allocator, &interface);
    try @import("rank_portable.zig").publicCore(&interface, &module);
    var certificate = false;
    for (interface.bindings, 0..) |*binding, slot| {
        if (binding.ty == 0 or binding.scheme.closed_rows.len == 0) continue;
        const owned = binding.scheme.closed_rows;
        binding.scheme.closed_rows = .{};
        try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").interface(&interface));
        try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").publicCore(&interface, &module));
        binding.scheme.closed_rows = owned;
        var producer: *core.Body = undefined;
        for (module.bodies) |*candidate| {
            if (candidate.binding != slot) continue;
            producer = candidate;
            break;
        }
        const saved = producer.closed_rows;
        producer.closed_rows = .{};
        try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").publicCore(&interface, &module));
        producer.closed_rows = saved;
        certificate = true;
        break;
    }
    try std.testing.expect(certificate);
    var emitted = try @import("../backend/core_backend.zig").compile(allocator, &.{module}, 1);
    defer emitted.deinit(allocator);
    try std.testing.expect(emitted.diagnostic == null);
    var protected = false;
    for (module.types.effects.rows) |*row| {
        if (row.tail != .formal) continue;
        const saved = row.*;
        row.tail = .closed;
        try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} }));
        row.* = saved;
        const binder = row.tail.formal;
        const saved_leaf = module.types.nodes[binder];
        module.types.nodes[binder].b = 0;
        try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(allocator, &module, .{}));
        module.types.nodes[binder] = saved_leaf;
        protected = true;
        break;
    }
    try std.testing.expect(protected);
    var tiny: usize = 1;
    try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executableWithBudget(&module, .{ .units = &[_]*const core.Module{&module} }, &tiny));
    try std.testing.expectEqual(@as(usize, 0), tiny);
}
test "sorted universal row carriers retain owned formal rows dynamic calls and Foreign publication" {
    try sortedRowModule(std.testing.allocator);
}

test "sorted universal row carriers preserve complete publication and emission through every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sortedRowModule, .{});
}

test "parametric row matching searches distinct generic operation arguments without losing exact multiplicity or budget" {
    var nodes = [_]T.Node{
        .{ .tag = .absent }, .{ .tag = .unit },                             .{ .tag = .boolean },                .{ .tag = .u32 },                              .{ .tag = .f32 },                              .{ .tag = .never },
        .{ .tag = .bound },  .{ .tag = .function, .a = 1, .b = 1, .c = 1 }, .{ .tag = .forall, .a = 7, .c = 1 }, .{ .tag = .function, .a = 1, .b = 1, .c = 2 }, .{ .tag = .function, .a = 1, .b = 1, .c = 3 },
    };
    var extra = [_]T.Id{ 6, 6, 3, 2 };
    var operations = [_]T.Operation{
        .{ .identity = .{ .unit = 0, .decl = 0 } },                                         .{ .identity = .{ .unit = 0, .decl = 1 } },
        .{ .identity = .{ .unit = 1, .decl = 1 }, .arguments = .{ .start = 1, .len = 1 } }, .{ .identity = .{ .unit = 1, .decl = 1 }, .arguments = .{ .start = 2, .len = 1 } },
        .{ .identity = .{ .unit = 1, .decl = 1 }, .arguments = .{ .start = 3, .len = 1 } },
    };
    var labels = [_]T.Effects.Label{ 2, 3, 3, 4, 3, 3 };
    var rows = [_]T.Effects.Row{ .{}, .{ .labels = .{ .len = 2 } }, .{ .labels = .{ .start = 2, .len = 2 } }, .{ .labels = .{ .start = 4, .len = 2 } } };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra, .operations = &operations, .effects = .{ .rows = &rows, .labels = &labels } };
    var remaining: usize = 65_536;
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining };
    try proof.instantiate(8, 9);
    try std.testing.expectEqual(T.boolean, proof.witnesses[0]);
    try proof.instantiate(8, 10);
    try std.testing.expectEqual(T.u32_type, proof.witnesses[0]);
    labels[3] = 4;
    labels[2] = 4;
    try std.testing.expectError(error.InvalidArtifact, proof.instantiate(8, 9));
    labels[2] = 4;
    labels[3] = 3;
    try proof.instantiate(8, 9);
    try std.testing.expectEqual(T.boolean, proof.witnesses[0]);
    operations[4].instance = .{ .unit = 1, .decl = 2 };
    try std.testing.expectError(error.InvalidArtifact, proof.instantiate(8, 9));
    operations[4].instance = .{ .unit = 0, .decl = 0 };
    remaining = 8;
    try std.testing.expectError(error.InvalidArtifact, proof.instantiate(8, 9));
    try std.testing.expectEqual(@as(usize, 0), remaining);
}

fn dictionaryPublication(allocator: std.mem.Allocator) !void {
    const source =
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
        \\type Future = forall [a, row e] where { Render (a -> a ! {|e}) } => Unit -> Unit
        \\type Item = exists [a] where { Render a } => a
        \\const make: Bool -> Item = fn flag => if flag then pack [U32] 42 as Item else pack [Bool] #True as Item
        \\const read = fn (item: Item) => unpack item as [a] value in Render.show value
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var interface = try @import("../reuse/dependency_snapshot.zig").freezePrincipal(allocator, &syntax, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &interface);
    try @import("../reuse/dependency_interface_validation.zig").validate(&interface, pool.entries.items.len + 1, 1);
    try @import("../reuse/dependency_interface_validation.zig").validateGraph(allocator, &interface);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    try @import("rank_portable.zig").publicCore(&interface, &module);
    const goals = interface.graph.quantifier_goals;
    const obligations = interface.graph.quantifier_obligations;
    interface.graph.quantifier_goals = &.{};
    interface.graph.quantifier_obligations = &.{};
    try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").publicCore(&interface, &module));
    interface.graph.quantifier_goals = goals;
    interface.graph.quantifier_obligations = obligations;
    try std.testing.expect(interface.member_templates.len != 0);
    const template = interface.member_templates[0];
    interface.member_templates[0].contract.decl ^= 1;
    try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").publicCore(&interface, &module));
    interface.member_templates[0] = template;
    const header = interface.bindings[template.binding];
    interface.bindings[template.binding].ty = T.boolean;
    try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").publicCore(&interface, &module));
    interface.bindings[template.binding] = header;
    try @import("rank_portable.zig").publicCore(&interface, &module);
}
test "predicate package producer principals preserve exact dictionary catalogs across publication" {
    try dictionaryPublication(std.testing.allocator);
}

test "predicate package producer publication retains goals and method principals through complete allocation failures" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, dictionaryPublication, .{});
}

fn rejectStoredCapture(allocator: std.mem.Allocator, module: *core.Module, closure: u32, storage: []u32) !void {
    const original_extra = module.extra;
    const original_captures = module.closures[closure].captures;
    defer module.extra = original_extra;
    defer module.closures[closure].captures = original_captures;
    module.extra = storage;
    module.closures[closure].captures = .{ .start = @intCast(original_extra.len), .len = 1 };
    try rejectDictionaryModule(allocator, module);
}
fn inferredSchemeModule(allocator: std.mem.Allocator) !void {
    const source =
        \\const identity = fn value => value
        \\const apply = fn callback => fn value => callback value
        \\const forget = fn value => do:
        \\  return fn (unit: Unit) => @u32.add 40 2
        \\const annotated: forall [a] => a -> a = identity
        \\const through: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = fn pair => apply (@product.get pair 0) (@product.get pair 1)
        \\type Item = exists [a] => (a, a -> U32)
        \\const make = fn (value: U32) => pack [U32] (value, identity) as Item
        \\const read = fn (item: Item) => unpack item as [a] value in (@product.get value 1) (identity (@product.get value 0))
        \\const discard = fn (item: Item) => unpack item as [a] value in forget (@product.get value 0)
        \\entry const forgotten = fn (value: U32) => (discard (make value)) ()
        \\entry const answer = fn (value: U32) => read (make value)
        \\entry const whole = fn (value: U32) => annotated (apply identity value)
        \\entry const host = fn (callback: U32 -> U32 ! {Foreign}) => through (callback, 42)
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("inferred scheme {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var interface = try @import("../reuse/dependency_snapshot.zig").freezePrincipal(allocator, &syntax, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &interface);
    try @import("../reuse/dependency_interface_validation.zig").validate(&interface, pool.entries.items.len + 1, 1);
    try @import("../reuse/dependency_interface_validation.zig").validateGraph(allocator, &interface);
    try @import("rank_portable.zig").publicCore(&interface, &module);
    var emitted = try @import("../backend/core_backend.zig").compile(allocator, &.{module}, 1);
    defer emitted.deinit(allocator);
    try std.testing.expect(emitted.diagnostic == null);
    const forget_body = module.body(3).?;
    const forget_parameter = module.bodyParameters(forget_body)[0].binding;
    const returned = module.node(module.node(module.children(forget_body.root)[0]).a);
    try std.testing.expectEqual(core.Tag.closure, returned.tag);
    const returned_closure = returned.a;
    const original_extra = module.extra;
    const with_capture = try allocator.alloc(u32, original_extra.len + 1);
    defer allocator.free(with_capture);
    @memcpy(with_capture[0..original_extra.len], original_extra);
    with_capture[original_extra.len] = forget_parameter;
    try rejectStoredCapture(allocator, &module, returned_closure, with_capture);
    const identity_scheme = module.bindings[1].scheme;
    const identity_variable = module.types.extra[identity_scheme.variables.start];
    module.types.extra[identity_scheme.variables.start] = module.types.list(module.bindings[2].scheme.variables)[0];
    try rejectDictionaryModule(allocator, &module);
    module.types.extra[identity_scheme.variables.start] = identity_variable;
    const apply_scheme = module.bindings[2].scheme;
    const apply_body = module.bindings[2].body_id;
    module.bindings[2].scheme.row_variables = .{};
    module.bodies[apply_body].scheme.row_variables = .{};
    try rejectDictionaryModule(allocator, &module);
    module.bindings[2].scheme = apply_scheme;
    module.bodies[apply_body].scheme = apply_scheme;
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "inferred generic schemes retain their own type and row variables beside explicit quantifiers and packages" {
    try inferredSchemeModule(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, inferredSchemeModule, .{});
}

fn associatedCoreScenario(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const identity: T.NominalIdentity = .{ .unit = 1, .decl = 37 };
    const binder = try source.boundType(0, 0);
    const argument = try source.sequence(.array, binder);
    const projection_ = try source.projection(identity, 41, &.{argument});
    const goal: T.Obligation = .{ .kind = .contract, .identity = identity, .ty = try source.product(&.{argument}), .source = 0 };
    const package = try source.quantifiedWithGoals(.existential, projection_, &.{binder}, &.{goal});
    const universal_binder = try source.boundType(0, 0);
    const universal_argument = try source.sequence(.array, universal_binder);
    const universal_projection = try source.projection(identity, 41, &.{universal_argument});
    const universal_goal: T.Obligation = .{ .kind = .contract, .identity = identity, .ty = try source.product(&.{universal_argument}), .source = 0 };
    const universal = try source.quantifiedWithGoals(.forall, try source.function(universal_argument, universal_projection), &.{universal_binder}, &.{universal_goal});
    const first = try source.boundType(0, 0);
    source.nodes.items[first].c = 12;
    const second = try source.boundType(0, 0);
    source.nodes.items[second].c = 13;
    const first_projection = try source.projection(identity, 41, &.{try source.sequence(.array, first)});
    const second_projection = try source.projection(identity, 41, &.{try source.sequence(.array, second)});
    const first_list = try source.saveList(&.{first});
    const second_list = try source.saveList(&.{second});
    var graph: core.Types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .quantifier_goals = source.quantifier_goals.items, .quantifier_obligations = source.quantifier_obligations.items };
    var remaining: usize = 65_536;
    var scope: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try scope.initialize();
    try scope.visit(universal);
    try scope.visit(package);
    try std.testing.expectError(error.InvalidArtifact, scope.visit(projection_));
    try scope.open(package, 12, first_list, first_projection);
    try scope.visit(first_projection);
    try std.testing.expectError(error.InvalidArtifact, scope.visit(second_projection));
    try scope.open(package, 13, second_list, second_projection);
    var comparison: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining, .views = &scope };
    try comparison.validate(first_projection, first_projection);
    try std.testing.expectError(error.InvalidArtifact, comparison.validate(first_projection, second_projection));
    try scope.pack(package, first_projection, &.{first});
    try std.testing.expectError(error.InvalidArtifact, scope.pack(package, first_projection, &.{second}));
    scope.close();
    scope.close();
    try std.testing.expectError(error.InvalidArtifact, scope.visit(first_projection));
    graph.nodes[projection_].b += 1;
    try std.testing.expectError(error.InvalidArtifact, scope.visit(package));
    graph.nodes[projection_].b -= 1;
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, scope.visit(universal));
}
test "associated package and universal projections require exact active goals and independent opening substitutions through OOM" {
    try associatedCoreScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedCoreScenario, .{});
}

fn dictionaryGoalFootprintScenario(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const binder = try source.boundType(0, 0);
    const contract: T.NominalIdentity = .{ .unit = 1, .decl = 51 };
    const arguments = try source.product(&.{try source.sequence(.array, binder)});
    const signature = try source.function(T.unit, T.u32_type);
    const goal: T.Obligation = .{ .ty = arguments, .kind = .contract, .identity = contract, .source = 0 };
    const package = try source.quantifiedWithGoals(.existential, signature, &.{binder}, &.{goal});
    const first = try source.boundType(0, 0);
    source.nodes.items[first].c = 12;
    const second = try source.boundType(0, 0);
    source.nodes.items[second].c = 13;
    const first_list = try source.saveList(&.{first});
    const second_list = try source.saveList(&.{second});
    var graph: core.Types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .quantifier_goals = source.quantifier_goals.items, .quantifier_obligations = source.quantifier_obligations.items };
    var remaining: usize = 65_536;
    var scope: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try scope.initialize();
    try scope.open(package, 12, first_list, signature);
    try scope.open(package, 13, second_list, signature);
    var sealed: std.bit_set.Static(4096) = .empty;
    try std.testing.expect(!try scope.goalFootprint(signature, package, first_list, &sealed, 0));
    try std.testing.expect(try scope.goalFootprint(goal.ty, package, first_list, &sealed, 0));
    sealed.set(first);
    try std.testing.expect(!try scope.goalFootprint(goal.ty, package, first_list, &sealed, 0));
    try std.testing.expect(try scope.goalFootprint(goal.ty, package, second_list, &sealed, 0));
    sealed.set(second);
    try std.testing.expect(!try scope.goalFootprint(goal.ty, package, second_list, &sealed, 0));
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, scope.goalFootprint(goal.ty, package, first_list, &sealed, 0));
}
test "closed dictionary signatures retain the exact opening goal footprint until every hidden witness is resealed through OOM" {
    try dictionaryGoalFootprintScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, dictionaryGoalFootprintScenario, .{});
}

fn sourceDictionaryCaptureScenario(allocator: std.mem.Allocator) !void {
    const prefix =
        "type Tag a is contract = { const read: Unit -> U32 }\n" ++
        "impl Number : Tag U32 = { const read = fn unit => 42 }\n" ++
        "type Item = exists [a] where { Tag a } => Unit\n" ++
        "type Sealed = exists [b] => Unit -> U32\n";
    const cases = [_]struct { body: []const u8, escapes: bool }{
        .{ .body = "Tag.read ()", .escapes = false },
        .{ .body = "Tag.read", .escapes = true },
        .{ .body = "fn (unit: Unit) => Tag.read unit", .escapes = true },
        .{ .body = "(Tag.read, 7)", .escapes = true },
        .{ .body = "pack [U32] Tag.read as Sealed", .escapes = true },
        .{ .body = "pack [a] Tag.read as Sealed", .escapes = false },
    };
    for (cases) |case| {
        const source = try std.mem.concat(allocator, u8, &.{ prefix, "const keep = fn (item: Item) => unpack item as [a] value in ", case.body, "\n" });
        defer allocator.free(source);
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModule(allocator, &tree, &pool, &.{}, &.{}, 1);
        defer checked.deinit(allocator);
        var escaped = false;
        for (checked.diagnostics) |issue| {
            if (issue.code == .package_escape) escaped = true else std.debug.print("capture {s}: {s}\n", .{ case.body, @tagName(issue.code) });
        }
        if (case.escapes != escaped) std.debug.print("capture mismatch {s}: expected {} found {}, uses {}\n", .{ case.body, case.escapes, escaped, checked.dictionary_uses.len });
        try std.testing.expectEqual(case.escapes, escaped);
        if (!case.escapes) try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    }
}
test "source dictionary closures retain scoped goals with closed signatures and allow exact witness resealing through OOM" {
    try sourceDictionaryCaptureScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sourceDictionaryCaptureScenario, .{});
}

fn associatedPackProjectionScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Source a is contract = { type Item }
        \\impl Number : Source U32 = { type Item = U32 }
        \\impl Flag : Source Bool = { type Item = Bool }
        \\type Item = exists [a] where { Source a } => a
        \\const item: Item = pack [U32] 42 as Item
        \\const flag: Item = pack [Bool] #True as Item
    ;
    var module = try lowerSource(allocator, source);
    defer module.deinit(allocator);
    // Source projection normalization is qualified separately. Construct the
    // immutable payload equation on this already selected producer package.
    const quantifier = module.dictionary_selections[0].quantifier;
    const owner = module.types.node(quantifier);
    const binder = module.types.list(.{ .start = owner.b, .len = owner.c })[0];
    const identity = module.contracts[0].identity;
    const extra_start = module.types.extra.len;
    module.types.extra = try allocator.realloc(module.types.extra, extra_start + 3);
    @memcpy(module.types.extra[extra_start..], &[_]T.Id{ 1, binder, module.contract_members[0].name });
    const projection: T.Id = @intCast(module.types.nodes.len);
    module.types.nodes = try allocator.realloc(module.types.nodes, module.types.nodes.len + 1);
    module.types.nodes[projection] = .{ .tag = .projection, .a = identity.unit, .b = identity.decl, .c = @intCast(extra_start) };
    module.types.nodes[quantifier].a = projection;
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(allocator, &module, .{});
    try std.testing.expectEqual(@as(usize, 2), module.dictionary_selections.len);
    const selection = module.dictionary_selections[0];
    const pack_node = module.node(selection.owner);
    var remaining: usize = 65_536;
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = &remaining };
    try scopes.initialize();
    const dictionaries = @import("dictionary_contracts.zig");
    try dictionaries.pack(&module, selection.owner, &scopes);
    var resolver: dictionaries.PackProjection = .{ .module = &module, .owner = selection.owner };
    scopes.projection_resolver = resolver.resolver();
    const witnesses = module.types.list(.{ .start = pack_node.b, .len = pack_node.c });
    try scopes.pack(pack_node.ty, module.typeOf(pack_node.a), witnesses);
    try std.testing.expectError(error.InvalidArtifact, scopes.pack(pack_node.ty, T.boolean, witnesses));
    resolver.owner = module.dictionary_selections[1].owner;
    try std.testing.expectError(error.InvalidArtifact, scopes.pack(pack_node.ty, module.typeOf(pack_node.a), witnesses));
    resolver.owner = selection.owner;
    const original = module.dictionary_selections[0];
    module.dictionary_selections[0].owner = module.dictionary_selections[1].owner;
    try std.testing.expectError(error.InvalidArtifact, scopes.pack(pack_node.ty, module.typeOf(pack_node.a), witnesses));
    module.dictionary_selections[0] = original;
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, scopes.pack(pack_node.ty, module.typeOf(pack_node.a), witnesses));
}
test "associated package representation uses only the exact pack selected type member through OOM" {
    try associatedPackProjectionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedPackProjectionScenario, .{});
}

fn closedDictionaryCoreCaptureScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Tag a is contract = { const read: Unit -> U32 }
        \\impl Number : Tag U32 = { const read = fn unit => 42 }
        \\type Item = exists [a] where { Tag a } => Unit
        \\type Sealed = exists [b] => Unit -> U32
        \\const item: Item = pack [U32] () as Item
        \\const keep = fn (item: Item) => unpack item as [a] value in pack [a] Tag.read as Sealed
    ;
    var module = try lowerSource(allocator, source);
    defer module.deinit(allocator);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(allocator, &module, .{});
    var sealed: core.Id = 0;
    for (module.nodes, 0..) |node, ordinal| {
        if (node.tag != .package_pack or module.types.node(module.typeOf(node.a)).tag != .function) continue;
        sealed = @intCast(ordinal);
    }
    try std.testing.expect(sealed != 0);
    const pack_node = module.node(sealed);
    const original = module.types.extra[pack_node.b];
    module.types.extra[pack_node.b] = T.u32_type;
    try rejectDictionaryModule(allocator, &module);
    module.types.extra[pack_node.b] = original;
    try validation.validate(allocator, &module, .{});
}
test "immutable closed dictionary captures require exact goal witness resealing through OOM" {
    try closedDictionaryCoreCaptureScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, closedDictionaryCoreCaptureScenario, .{});
}

fn dictionaryResealingScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
        \\type Item = exists [a] where { Render a } => a
        \\const make = fn (flag: Bool) => if flag then pack [U32] 42 as Item else pack [Bool] #True as Item
        \\const reseal = fn (item: Item) => unpack item as [a] value in pack [a] value as Item
        \\const choose = fn (left: Item) => fn (right: Item) => unpack left as [a] x in unpack right as [b] y in pack [b] y as Item
        \\const seal: forall [a] where { Render a } => a -> Item = fn value => pack [a] value as Item
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("resealing {s} at {}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    defer module.deinit(allocator);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(allocator, &module, .{});
    var count: usize = 0;
    for (module.dictionary_selections, 0..) |selection, ordinal| switch (selection.proof) {
        .selected => {},
        .given => |given| {
            count += 1;
            module.dictionary_selections[ordinal].proof.given.goal = 0xffffffff;
            try rejectDictionaryModule(allocator, &module);
            module.dictionary_selections[ordinal] = selection;
            module.dictionary_selections[ordinal].proof.given.quantifier = T.u32_type;
            try rejectDictionaryModule(allocator, &module);
            module.dictionary_selections[ordinal] = selection;
            const argument = module.types.extra[given.arguments.start];
            module.types.extra[given.arguments.start] = T.boolean;
            try rejectDictionaryModule(allocator, &module);
            module.types.extra[given.arguments.start] = argument;
            if (given.introduction != 0) {
                module.dictionary_selections[ordinal].proof.given.introduction = module.node(selection.owner).a;
                try rejectDictionaryModule(allocator, &module);
            } else {
                module.dictionary_selections[ordinal].proof.given.opening = 0;
                try rejectDictionaryModule(allocator, &module);
            }
            module.dictionary_selections[ordinal] = selection;
        },
    };
    try std.testing.expectEqual(@as(usize, 3), count);
    try validation.validate(allocator, &module, .{});
}
test "dictionary resealing preserves exact opening and universal evidence through complete OOM" {
    try dictionaryResealingScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, dictionaryResealingScenario, .{});
}

fn ordinaryPredicateSchemeScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Identity = forall [a] => a -> a
        \\const identity: Identity = fn value => value
        \\type Point is data = #Point { x: U32 }
        \\const Point.add = fn (left: Point) => fn (right: U32) => @u32.add left.x right
        \\const combine = fn left => fn right => @type.call "add" left right
        \\const represented: a -> a where { type_rep a } = fn value => value
        \\const field = fn value => value.x
        \\const forward = fn value => combine value 22
        \\const answer = forward (#Point { x: represented (field {x: 20}) })
        \\const named = field (#Point {x: 7})
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(allocator, &module, .{});
    var interface = try @import("../reuse/dependency_snapshot.zig").freezePrincipal(allocator, &syntax, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &interface);
    try @import("../reuse/dependency_interface_validation.zig").validate(&interface, pool.entries.items.len + 1, 1);
    try @import("../reuse/dependency_interface_validation.zig").validateGraph(allocator, &interface);
    try @import("rank_portable.zig").publicCore(&interface, &module);
    var changed = false;
    for (module.bodies) |*body| {
        if (body.scheme.obligations.len == 0 or module.node(body.root).tag != .associated) continue;
        const header = body.scheme;
        body.scheme.obligations = .{};
        module.bindings[body.binding].scheme.obligations = .{};
        try rejectDictionaryModule(allocator, &module);
        body.scheme = header;
        module.bindings[body.binding].scheme = header;
        const published = interface.bindings[body.binding].scheme;
        interface.bindings[body.binding].scheme.obligations = .{};
        try std.testing.expectError(error.InvalidArtifact, @import("rank_portable.zig").publicCore(&interface, &module));
        interface.bindings[body.binding].scheme = published;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    try validation.validate(allocator, &module, .{});
    try @import("rank_portable.zig").publicCore(&interface, &module);
}
test "ordinary inferred predicate schemes coexist with annotated universal bodies through OOM" {
    try ordinaryPredicateSchemeScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ordinaryPredicateSchemeScenario, .{});
}

fn inferredGoalForwardingScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
        \\const helper = fn value => Render.show value
        \\const render: forall [a] where { Render a } => a -> U32 = fn value => helper value
        \\const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
        \\entry const answer = fn () => both render
    ;
    var module = try lowerSource(allocator, source);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "implicit helper requirements consume only exact active universal goals through OOM" {
    try inferredGoalForwardingScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, inferredGoalForwardingScenario, .{});
}

fn schemeBijectionScenario(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const x = try source.fresh();
    const y = try source.fresh();
    const u = try source.fresh();
    const v = try source.fresh();
    const left_row = try source.freshEffects();
    const right_row = try source.freshEffects();
    const left: T.Scheme = .{ .root = try source.functionWithEffects(x, y, left_row), .variables = try source.saveList(&.{ x, y }), .row_variables = try source.saveList(&.{source.row(left_row).tail.variable}) };
    var right: T.Scheme = .{ .root = try source.functionWithEffects(u, v, right_row), .variables = try source.saveList(&.{ v, u }), .row_variables = try source.saveList(&.{source.row(right_row).tail.variable}) };
    const concrete = try source.functionWithEffects(T.u32_type, T.u32_type, right_row);
    const widened = try source.effects.row(&.{T.foreign_operation}, .{ .variable = source.row(right_row).tail.variable });
    const widening = try source.functionWithEffects(u, v, widened);
    var graph: core.Types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .effects = .{ .rows = source.effects.rows.items, .labels = source.effects.labels.items, .variable_count = @intCast(source.effects.variables.items.len) }, .operations = source.operations.items };
    var remaining: usize = 65_536;
    var scope: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try scope.initialize();
    try scope.generic(right);
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining, .views = &scope };
    const empty: []const T.Obligation = &.{};
    try proof.schemeGoals(left, right, empty, empty);
    const left_goals = [_]T.Obligation{.{ .ty = x, .kind = .type_rep, .source = 0 }};
    var right_goals = [_]T.Obligation{.{ .ty = u, .kind = .type_rep, .source = 0 }};
    try proof.schemeGoals(left, right, &left_goals, &right_goals);
    right_goals[0].ty = v;
    try std.testing.expectError(error.InvalidArtifact, proof.schemeGoals(left, right, &left_goals, &right_goals));
    right_goals[0].ty = u;
    const original = right.root;
    right.root = concrete;
    try std.testing.expectError(error.InvalidArtifact, proof.schemeGoals(left, right, empty, empty));
    right.root = widening;
    try std.testing.expectError(error.InvalidArtifact, proof.schemeGoals(left, right, empty, empty));
    right.root = original;
    try proof.schemeGoals(left, right, &left_goals, &right_goals);
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, proof.schemeGoals(left, right, &left_goals, &right_goals));
}
test "ordinary scheme publication preserves a bijection of variables rows and goal endpoints through OOM" {
    try schemeBijectionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, schemeBijectionScenario, .{});
}

fn ordinaryRightOwnerScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\const identity: forall [a] => a -> a = fn value => value
        \\type Left is data = #Left {value: U32}
        \\type Right is data = #Right {value: U32}
        \\const Left.add = fn (left: Left) => fn (right: U32) => @u32.add left.value right
        \\const Right.add = fn (left: Left) => fn (right: Right) => @u32.add left.value right.value
        \\const combine = fn left => fn right => @type.call "add" left right
        \\const answer = identity (combine (#Left {value: 20}) (#Right {value: 22}))
    ;
    var module = try lowerSource(allocator, source);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    try std.testing.expect(module.associated.len >= 2);
    const methods = module.associated;
    {
        module.associated = methods[0..1];
        defer module.associated = methods;
        try rejectDictionaryModule(allocator, &module);
    }
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "ordinary associated assumptions retry the right owner without retaining failed proof authority through OOM" {
    try ordinaryRightOwnerScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ordinaryRightOwnerScenario, .{});
}

fn openingWithinUniversalScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Item = exists [b] => (b, b -> U32)
        \\const make = fn value => pack [U32] (value, fn (payload: U32) => payload) as Item
        \\const read: forall [a] => a -> Item -> U32 = fn ignored => fn item => unpack item as [b] value in (@product.get value 1) (@product.get value 0)
        \\entry const answer = fn () => read #True (make 42)
    ;
    var module = try lowerSource(allocator, source);
    defer module.deinit(allocator);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(allocator, &module, .{});
    var changed = false;
    for (module.types.nodes) |*leaf| {
        if (leaf.tag != .bound or leaf.c == 0 or leaf.b != 0) continue;
        const original = leaf.*;
        {
            defer leaf.* = original;
            leaf.a += 1;
            try rejectDictionaryModule(allocator, &module);
            leaf.* = original;
            leaf.c = @intCast(module.bindings.len + 1);
            try rejectDictionaryModule(allocator, &module);
        }
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    try validation.validate(allocator, &module, .{});
}
test "universal bodies retain exact nested existential opening ownership through OOM" {
    try openingWithinUniversalScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, openingWithinUniversalScenario, .{});
}

fn ordinaryProjectionScopeScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
        \\impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
        \\type Package = exists [a] where { Source a } => a
        \\const make = fn (value: U32) => pack [U32] value as Package
        \\const read = fn (item: Package) => unpack item as [a] value in Source.show value (Source.get value)
        \\const calculate = fn (value: U32) => read (make value)
        \\const identity: forall [a] => a -> a = fn value => value
        \\const keep: a -> (Source.Item a) -> (Source.Item a) where { Source a } = fn witness => fn value => value
        \\const carried = fn (value: U32) => keep value value
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("ordinary projection {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var interface = try @import("../reuse/dependency_snapshot.zig").freezePrincipal(allocator, &syntax, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &interface);
    try @import("../reuse/dependency_interface_validation.zig").validateGraph(allocator, &interface);
    try @import("rank_portable.zig").publicCore(&interface, &module);
    var helper: core.BindingId = 0;
    for (module.bodies) |body| {
        if (body.scheme.variables.len != 1 or body.scheme.obligations.len == 0) continue;
        const first = module.types.node(body.scheme.root);
        if (first.tag != .function) continue;
        const second = module.types.node(first.b);
        if (second.tag == .function and module.types.node(second.a).tag == .projection and module.types.node(second.b).tag == .projection) helper = body.binding;
    }
    try std.testing.expectEqual(true, helper != 0);
    var remaining: usize = 65_536;
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = &remaining, .obligations = module.obligations };
    try scopes.initialize();
    const helper_scheme = module.binding(helper).scheme;
    var exercised = false;
    for (module.nodes, 0..) |node, ordinal| {
        if (node.tag != .call) continue;
        const call = module.call(@intCast(ordinal));
        if (call.target.binding != helper) continue;
        var mapping: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
        var declaration: @import("scheme_projection.zig").Resolver = .{ .module = &module, .producer = &module, .binding = helper };
        mapping.projection_resolver = declaration.resolver();
        try mapping.instantiateScheme(helper_scheme, call.callee_type);
        mapping.projection_resolver = null;
        mapping.instance = helper_scheme.variables;
        mapping.instance_rows = helper_scheme.row_variables;
        var applied: @import("scheme_projection.zig").Resolver = .{ .module = &module, .producer = &module, .binding = helper, .applied = &mapping };
        var endpoint: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes, .projection_resolver = applied.resolver() };
        const first = module.types.node(call.callee_type);
        const second = module.types.node(first.b);
        try endpoint.validate(second.a, T.u32_type);
        try std.testing.expectError(error.InvalidArtifact, endpoint.validate(second.a, T.boolean));
        const original = mapping.witnesses;
        mapping.witnesses[0] = T.boolean;
        try std.testing.expectError(error.InvalidArtifact, endpoint.validate(second.a, T.u32_type));
        mapping.witnesses = original;
        try endpoint.validate(second.a, T.u32_type);
        remaining = 1;
        try std.testing.expectError(error.InvalidArtifact, endpoint.validate(second.a, T.u32_type));
        exercised = true;
        break;
    }
    try std.testing.expectEqual(true, exercised);
    var changed = false;
    for (module.obligations) |*goal| {
        if (goal.kind != .contract) continue;
        const original = goal.*;
        defer goal.* = original;
        goal.kind = .type_rep;
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} }));
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    changed = false;
    for (interface.obligations) |*goal| {
        if (goal.kind != .contract) continue;
        const original = goal.*;
        defer goal.* = original;
        goal.kind = .type_rep;
        try std.testing.expectError(error.InvalidArtifact, @import("package_portable.zig").interface(&interface));
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "ordinary projection endpoints require their exact owning scheme contract through OOM" {
    try ordinaryProjectionScopeScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ordinaryProjectionScopeScenario, .{});
}

fn rejectAssociatedPayloadMutants(allocator: std.mem.Allocator, module: *core.Module) !void {
    const reader = @import("frozen_core_validation.zig");
    var corruptions: usize = 0;
    for (module.dictionary_selections) |*selection| {
        if (selection.proof != .selected) continue;
        const original = selection.*;
        for (module.nodes, 0..) |node, index| {
            if (node.tag != .package_pack or index == selection.owner) continue;
            selection.owner = @intCast(index);
            try rejectDictionaryModule(allocator, module);
            corruptions += 1;
            selection.* = original;
            break;
        }
        const proof = module.selected_proofs[selection.proof.selected];
        for (module.selected_members[proof.members.start..][0..proof.members.len]) |*member| {
            if (member.kind != .type_) continue;
            const saved = member.*;
            member.root = T.boolean;
            try rejectDictionaryModule(allocator, module);
            corruptions += 1;
            member.* = saved;
            break;
        }
        break;
    }
    for (module.types.quantifier_obligations) |*goal| {
        if (goal.kind != .contract) continue;
        const saved = goal.*;
        goal.identity.decl ^= 1;
        try rejectDictionaryModule(allocator, module);
        corruptions += 1;
        goal.* = saved;
        break;
    }
    for (module.types.nodes) |node| {
        if (node.tag != .projection) continue;
        const at = node.c + 1 + module.types.extra[node.c];
        const saved = module.types.extra[at];
        module.types.extra[at] = 0;
        try rejectDictionaryModule(allocator, module);
        corruptions += 1;
        module.types.extra[at] = saved;
        break;
    }
    try std.testing.expectEqual(@as(usize, 4), corruptions);
    try reader.validate(allocator, module, .{});
}
fn associatedPayloadPackScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
        \\impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
        \\type Package = exists [a] where { Source a } => (a, Source.Item a)
        \\const make = fn (value: U32) => pack [U32] (value, value) as Package
        \\const reseal = fn (item: Package) => unpack item as [a] value in pack [a] value as Package
        \\const seal: forall [a] where { Source a } => a -> (Source.Item a) -> Package = fn value => fn item => pack [a] (value, item) as Package
        \\const read = fn (item: Package) => unpack item as [a] value in Source.show (@product.get value 0) (@product.get value 1)
        \\entry const answer = fn () => read (make 42)
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    for (syntax.diagnostics.items) |issue| std.debug.print("payload syntax {s} at {d}\n", .{ @tagName(issue.code), issue.start });
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("payload source {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var interface = try @import("../reuse/dependency_snapshot.zig").freezePrincipal(allocator, &syntax, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &interface);
    try @import("../reuse/dependency_interface_validation.zig").validateGraph(allocator, &interface);
    try @import("rank_portable.zig").publicCore(&interface, &module);
    try rejectAssociatedPayloadMutants(allocator, &module);
    var emitted = try @import("../backend/core_backend.zig").compile(allocator, &.{module}, 1);
    defer emitted.deinit(allocator);
    if (emitted.diagnostic) |issue| std.debug.print("payload emission {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expect(emitted.diagnostic == null);
}
test "package payload projections use only their own selected type members through OOM" {
    try associatedPayloadPackScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedPayloadPackScenario, .{});
}

fn associatedPayloadRejectionScenario(allocator: std.mem.Allocator) !void {
    const prefix = "type Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = U32 }\n";
    for ([_][]const u8{
        "type Package = exists [a] => (a, Source.Item a)\nconst bad = pack [U32] (1,42) as Package\n",
        "type Package = exists [a] where {Source a} => (a, Source.Item a)\nconst bad = pack [U32] (1,#True) as Package\n",
        "type Package = exists [a] where {Source a} => (a, Source.Item a)\nconst bad = pack [Bool] (#True,42) as Package\n",
    }) |body| {
        const source = try std.mem.concat(allocator, u8, &.{ prefix, body });
        defer allocator.free(source);
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer syntax.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
        var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
    }
}
test "package associated payloads reject ambient missing and incompatible evidence through OOM" {
    try associatedPayloadRejectionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedPayloadRejectionScenario, .{});
}

fn rankStagingCorruptions(allocator: std.mem.Allocator, module: *core.Module) !void {
    const staging = @import("typed_staging.zig");
    var changed: usize = 0;
    for (module.nodes) |node| {
        if (node.tag != .staging or node.c != @backingInt(staging.Op.quote)) continue;
        const code_type = module.types.node(node.ty);
        const latent = module.types.nominalArguments(code_type)[1];
        if (module.types.nodes[latent].c == 0) continue;
        const saved = module.types.nodes[latent];
        module.types.nodes[latent].c = 0;
        try rejectDictionaryModule(allocator, module);
        module.types.nodes[latent] = saved;
        changed += 1;
        break;
    }
    for (module.nodes) |node| {
        if (node.tag != .operation_value) continue;
        const saved = module.types.nodes[node.ty];
        module.types.nodes[node.ty].c = 0;
        try rejectDictionaryModule(allocator, module);
        module.types.nodes[node.ty] = saved;
        changed += 1;
        break;
    }
    for (module.nodes) |*node| {
        if (node.tag != .handle) continue;
        const saved = node.*;
        for (module.nodes, 0..) |provider, index| {
            if (provider.tag != .effect_provider or provider.ty == module.typeOf(node.a)) continue;
            const first = module.types.node(provider.ty);
            const actual = module.types.node(module.typeOf(node.a));
            if (first.a == actual.a) continue;
            node.a = @intCast(index);
            try rejectDictionaryModule(allocator, module);
            node.* = saved;
            changed += 1;
            break;
        }
        break;
    }
    for (module.closures) |closure| {
        const body = module.node(closure.body);
        if (body.tag != .apply or module.node(body.a).tag != .operation_value) continue;
        const saved = module.types.nodes[closure.function_type];
        module.types.nodes[closure.function_type].c = 0;
        try rejectDictionaryModule(allocator, module);
        module.types.nodes[closure.function_type] = saved;
        changed += 1;
        break;
    }
    try std.testing.expectEqual(@as(usize, 4), changed);
    try @import("frozen_core_validation.zig").validate(allocator, module, .{});
}
fn unusedImportedRows(allocator: std.mem.Allocator, producer: *const core.Module) !void {
    var consumer = producer.*;
    consumer.unit = 2;
    consumer.nodes = &.{};
    consumer.bodies = &.{};
    consumer.bindings = try allocator.dupe(core.Binding, producer.bindings);
    defer allocator.free(consumer.bindings);
    for (consumer.bindings[1..], 1..) |*binding, id| {
        binding.kind = .external;
        binding.target = .{ .unit = producer.unit, .binding = @intCast(id) };
    }
    const context = .{ .units = &[_]*const core.Module{ producer, &consumer } };
    try @import("package_core.zig").executable(&consumer, context);
    var changed: usize = 0;
    for (consumer.bindings[1..]) |*binding| {
        if (binding.scheme.closed_rows.len == 0) continue;
        const saved = binding.*;
        binding.scheme.closed_rows = .{};
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&consumer, context));
        binding.* = saved;
        binding.target.binding = 1; // The unrelated pure identity owns no certificate.
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").executable(&consumer, context));
        binding.* = saved;
        changed += 1;
    }
    try std.testing.expect(changed != 0);
    try @import("package_core.zig").executable(&consumer, context);
}
fn rankCoexistenceScenario(allocator: std.mem.Allocator, body: []const u8) !void {
    const source = try std.mem.concat(allocator, u8, &.{ "const identity: forall [a] => a -> a = fn value => value\n", body });
    defer allocator.free(source);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    for (syntax.diagnostics.items) |issue| std.debug.print("coexist syntax {s} at {d}\n", .{ @tagName(issue.code), issue.start });
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("coexist source {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var interface = try @import("../reuse/dependency_snapshot.zig").freezePrincipal(allocator, &syntax, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &interface);
    try @import("../reuse/dependency_interface_validation.zig").validate(&interface, pool.entries.items.len + 1, 1);
    try @import("../reuse/dependency_interface_validation.zig").validateGraph(allocator, &interface);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    defer module.deinit(allocator);
    try @import("rank_portable.zig").publicCore(&interface, &module);
    try @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} });
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    if (std.mem.find(u8, source, "const invoke") != null) try unusedImportedRows(allocator, &module);
    if (std.mem.find(u8, source, "let deferred") != null) try rankStagingCorruptions(allocator, &module);
    var emitted = try @import("../backend/core_backend.zig").compile(allocator, &.{module}, 1);
    defer emitted.deinit(allocator);
    if (emitted.diagnostic) |issue| std.debug.print("coexist emission {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expect(emitted.diagnostic == null);
}
test "rank interfaces coexist with closed effectful future code through complete OOM" {
    const source =
        \\effect Read: Unit -> U32
        \\const future = @code.quote (Read ())
        \\entry const answer = fn () => identity 42
    ;
    try rankCoexistenceScenario(std.testing.allocator, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankCoexistenceScenario, .{source});
}

test "rank interfaces retain handlers for effectful typed code through complete OOM" {
    const source =
        \\effect Read: Unit -> U32
        \\const future = @code.quote (Read ())
        \\const provider = @effect.provider Read (fn () => 42)
        \\effect Write: Unit -> Unit
        \\const writer = @effect.provider Write (fn () => ())
        \\entry const answer = fn () => do provider:
        \\  let deferred = fn () => Read ()
        \\  use value <- @code.emit future
        \\  return value
    ;
    try rankCoexistenceScenario(std.testing.allocator, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankCoexistenceScenario, .{source});
}

test "rank call views preserve separately evaluated operation arguments through complete OOM" {
    const source =
        \\effect Read: Unit -> U32
        \\const pass = fn value => identity value
        \\const invoke = fn () => identity (Read ())
        \\const future = @code.quote (invoke ())
        \\const provider = @effect.provider Read (fn () => 42)
        \\entry const answer = fn () => do provider:
        \\  use value <- @code.emit future
        \\  return value
    ;
    try rankCoexistenceScenario(std.testing.allocator, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankCoexistenceScenario, .{source});
}

fn rankHandlerCaptureScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Tag a is contract = { const read: Unit -> U32 }
        \\impl Number : Tag U32 = { const read = fn unit => 42 }
        \\type Item = exists [a] where { Tag a } => Unit
        \\type Sealed = exists [b] => Unit -> U32
        \\effect Tick: Unit -> Unit
        \\const provider = @effect.provider Tick (fn () => ())
        \\const copy = provider
        \\const item: Item = pack [U32] () as Item
        \\const keep = fn (item: Item) => unpack item as [a] value in pack [a] Tag.read as Sealed
    ;
    var module = try lowerSource(allocator, source);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var sealed: core.Id = 0;
    var provider: core.Id = 0;
    for (module.nodes, 0..) |node, ordinal| {
        if (node.tag == .package_pack and module.types.node(module.typeOf(node.a)).tag == .function) sealed = @intCast(ordinal);
        if (node.tag == .reference and module.types.node(node.ty).tag == .provider) provider = @intCast(ordinal);
    }
    try std.testing.expect(sealed != 0 and provider != 0);
    const wrapped: core.Id = @intCast(module.nodes.len);
    module.nodes = try allocator.realloc(module.nodes, module.nodes.len + 1);
    module.spans = try allocator.realloc(module.spans, module.spans.len + 1);
    module.merge_ranges = try allocator.realloc(module.merge_ranges, module.merge_ranges.len + 1);
    const payload = module.node(sealed).a;
    module.nodes[wrapped] = .{ .tag = .handle, .a = provider, .b = payload, .ty = module.types.node(module.typeOf(sealed)).a };
    module.spans[wrapped] = module.spans[payload];
    module.merge_ranges[wrapped] = .{};
    if (module.dispatch_signatures.len != 0) {
        module.dispatch_signatures = try allocator.realloc(module.dispatch_signatures, module.dispatch_signatures.len + 1);
        module.dispatch_signatures[wrapped] = 0;
    }
    module.nodes[sealed].a = wrapped;
    for (module.dictionary_selections) |selection| {
        if (selection.owner == sealed) module.extra[selection.contents.start] = wrapped;
    }
    try @import("package_core.zig").executable(&module, .{ .units = &[_]*const core.Module{&module} });
    try @import("frozen_core_validation.zig").validateBounds(&module, .{});
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    const pack_node = module.node(sealed);
    const witness = module.types.extra[pack_node.b];
    module.types.extra[pack_node.b] = T.u32_type;
    try rejectDictionaryModule(allocator, &module);
    module.types.extra[pack_node.b] = witness;
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "rank handler results preserve closed dictionary capture footprints through complete OOM" {
    try rankHandlerCaptureScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankHandlerCaptureScenario, .{});
}

fn effectfulScalarActionScenario(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\effect Read: Unit -> U32
        \\const action = fn () => Read ()
        \\const declared: Unit -> U32 ! {Foreign} = fn () => 42
        \\const factory = fn (seed: U32) => fn () => seed
    );
    defer module.deinit(allocator);
    var actions: usize = 0;
    for (module.bindings, 0..) |binding, index| {
        if (binding.kind != .global) continue;
        const arrow = module.types.node(binding.ty);
        if (arrow.tag != .function or arrow.a != T.unit or arrow.b != T.u32_type or module.types.row(arrow.c).labels.len == 0) continue;
        try std.testing.expect(binding.capability_flow != .input_shape);
        try std.testing.expect(!binding.capability_parameters.present());
        try std.testing.expect(module.capability_contracts.header(@intCast(index), 1) == null);
        actions += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), actions);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "effectful scalar Unit actions do not publish constructor input shapes through complete OOM" {
    try effectfulScalarActionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, effectfulScalarActionScenario, .{});
}

test "closed declared effect rows admit conservative source views without callback or owner erasure" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },                           .{ .tag = .unit },                             .{ .tag = .boolean },                          .{ .tag = .u32 },                      .{ .tag = .f32 },                      .{ .tag = .never },
        .{ .tag = .function, .a = 1, .b = 3, .c = 1 }, .{ .tag = .function, .a = 1, .b = 3, .c = 2 }, .{ .tag = .function, .a = 1, .b = 3 },         .{ .tag = .function, .a = 6, .b = 3 }, .{ .tag = .function, .a = 7, .b = 3 }, .{ .tag = .function, .a = 1, .b = 3, .c = 3 },
        .{ .tag = .function, .a = 1, .b = 3, .c = 4 }, .{ .tag = .function, .a = 1, .b = 3, .c = 5 }, .{ .tag = .function, .a = 1, .b = 3, .c = 6 },
    };
    var extra = [_]T.Id{ T.u32_type, T.boolean };
    var operations = [_]T.Operation{
        .{ .identity = .{ .unit = 0, .decl = 0 } },                                                                                .{ .identity = .{ .unit = 0, .decl = 1 } },
        .{ .identity = .{ .unit = 1, .decl = 4 }, .instance = .{ .unit = 9, .decl = 1 }, .arguments = .{ .start = 0, .len = 1 } }, .{ .identity = .{ .unit = 1, .decl = 4 }, .instance = .{ .unit = 9, .decl = 2 }, .arguments = .{ .start = 0, .len = 1 } },
        .{ .identity = .{ .unit = 2, .decl = 4 }, .instance = .{ .unit = 9, .decl = 1 }, .arguments = .{ .start = 0, .len = 1 } }, .{ .identity = .{ .unit = 1, .decl = 4 }, .instance = .{ .unit = 9, .decl = 1 }, .arguments = .{ .start = 1, .len = 1 } },
    };
    var labels = [_]T.Effects.Label{ 2, 2, 1, 3, 4, 5, 2 };
    var rows = [_]T.Effects.Row{
        .{},                                                                  .{ .labels = .{ .start = 0, .len = 1 } }, .{ .labels = .{ .start = 1, .len = 2 } },
        .{ .labels = .{ .start = 3, .len = 1 } },                             .{ .labels = .{ .start = 4, .len = 1 } }, .{ .labels = .{ .start = 5, .len = 1 } },
        .{ .labels = .{ .start = 6, .len = 1 }, .tail = .{ .variable = 0 } },
    };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra, .operations = &operations, .effects = .{ .rows = &rows, .labels = &labels, .variable_count = 1 } };
    var remaining: usize = 65_536;
    var scopes: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try scopes.initialize();
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .views = &scopes, .remaining = &remaining, .foreign_views = true };
    try proof.validate(6, 7);
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 8));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(9, 10));
    for ([_]T.Id{ 11, 12, 13 }) |changed| try std.testing.expectError(error.InvalidArtifact, proof.validate(6, changed));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(14, 7));
    proof.foreign_views = false;
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 7));
    proof.foreign_views = true;
    remaining = 0;
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 7));
}

test "exact Foreign inference views publish only complete endpoints and preserve wider lexical row owners" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },
        .{ .tag = .unit },
        .{ .tag = .boolean },
        .{ .tag = .u32 },
        .{ .tag = .f32 },
        .{ .tag = .never },
        .{ .tag = .function, .a = 3, .b = 3, .c = 1 },
        .{ .tag = .function, .a = 3, .b = 3, .c = 2 },
        .{ .tag = .function, .a = 3, .b = 2, .c = 2 },
        .{ .tag = .product, .a = 0, .b = 2 },
        .{ .tag = .product, .a = 2, .b = 2 },
        .{ .tag = .product, .a = 4, .b = 2 },
        .{ .tag = .function, .a = 3, .b = 3, .c = 3 },
        .{ .tag = .function, .a = 3, .b = 3, .c = 4 },
        .{ .tag = .function, .a = 3, .b = 3, .c = 5 },
        .{ .tag = .function, .a = 3, .b = 3, .c = 6 },
        .{ .tag = .function, .a = 3, .b = 3 },
        .{ .tag = .bound, .a = 0, .b = 1 },
        .{ .tag = .forall, .a = 19, .b = 6, .c = 1 },
        .{ .tag = .function, .a = 3, .b = 3, .c = 7 },
        .{ .tag = .bound, .a = 0, .b = 1 },
        .{ .tag = .forall, .a = 22, .b = 7, .c = 1 },
        .{ .tag = .function, .a = 3, .b = 3, .c = 8 },
    };
    var extra = [_]u32{ 6, 3, 7, 3, 8, 3, 17, 20, 1, 0 };
    var rows = [_]T.Effects.Row{
        .{},
        .{ .labels = .{ .len = 1 } },
        .{ .labels = .{ .len = 1 }, .tail = .{ .variable = 0 } },
        .{ .labels = .{ .len = 2 }, .tail = .{ .variable = 1 } },
        .{ .labels = .{ .start = 2, .len = 2 }, .tail = .{ .variable = 2 } },
        .{ .labels = .{ .start = 1, .len = 1 }, .tail = .{ .variable = 3 } },
        .{ .labels = .{ .len = 1 }, .tail = .{ .variable = 4 } },
        .{ .labels = .{ .len = 1 }, .tail = .{ .formal = 17 } },
        .{ .labels = .{ .len = 1 }, .tail = .{ .formal = 20 } },
    };
    // The repeated Foreign occurrence is a real separate row occurrence.
    var repeated = [_]T.Effects.Label{ T.foreign_operation, 2, T.foreign_operation, T.foreign_operation };
    var operations = [_]T.Operation{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } }, .{ .identity = .{ .unit = 1, .decl = 1 } } };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows, .labels = &repeated, .variable_count = 5 }, .operations = &operations };
    var remaining: usize = 65_536;
    var scopes: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try scopes.initialize();
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining, .views = &scopes, .foreign_views = true };
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(7));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(9, 11));
    try std.testing.expect(!scopes.closed_rows[2]);
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(7));
    try proof.validate(9, 10);
    try std.testing.expect(scopes.closed_rows[2]);
    try scopes.visit(10);

    // Covariant supersets remain legal only under their existing lexical owner.
    try proof.validate(6, 12);
    try std.testing.expect(!scopes.closed_rows[3]);
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(12));
    try scopes.pushGeneric(.{ .root = 12, .row_variables = .{ .start = 8, .len = 1 } });
    try proof.validate(6, 12);
    try scopes.visit(12);
    try std.testing.expect(!scopes.closed_rows[3]);
    scopes.popGeneric();
    try proof.validate(6, 13);
    try std.testing.expect(!scopes.closed_rows[4]);
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(13));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 14));
    try std.testing.expect(!scopes.closed_rows[5]);
    try std.testing.expectError(error.InvalidArtifact, proof.validate(15, 7));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 16));

    // Formal row tails are never closed by inference-view publication.
    try scopes.enter(18);
    try proof.validate(6, 19);
    try scopes.visit(19);
    try std.testing.expect(!scopes.closed_rows[7]);
    scopes.leave();
    try scopes.enter(21);
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(19));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(19, 22));
    scopes.leave();
    try std.testing.expect(!scopes.closed_rows[7] and !scopes.closed_rows[8]);

    scopes.closed_rows[2] = false;
    try scopes.pushGeneric(.{ .root = 7, .row_variables = .{ .start = 9, .len = 1 } });
    try proof.validate(6, 7);
    try scopes.visit(7);
    try std.testing.expect(!scopes.closed_rows[2]);
    scopes.popGeneric();
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(7));
    rows[2].tail = .{ .variable = 5 };
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 7));
    try std.testing.expect(!scopes.closed_rows[2]);
    rows[2].tail = .{ .variable = 0 };
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 7));
    try std.testing.expectEqual(0, remaining);
    try std.testing.expect(!scopes.closed_rows[2]);
}

const named_ordinary_owner_source =
    \\type Maybe a is data = #Some a | #Nothing
    \\const identity: forall [a] => a -> a = fn value => value
    \\const same = fn left => fn right => @type.same left right
    \\const inspect = fn (candidate: Maybe U32) => do:
    \\  let #Some value = candidate else:
    \\    return 0
    \\  if let #Some extra = candidate:
    \\    use same value extra
    \\  return value
    \\const helper = fn (value: U32) => inspect (#Some value)
    \\const generated = @code.quote (fn (value: U32) => helper value)
    \\entry const run = fn (value: U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => helper value)))
;
fn namedOrdinaryOwners(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator, named_ordinary_owner_source);
    defer module.deinit(allocator);
    var fallback: usize = 0;
    for (module.nodes) |node| if (node.tag == .pattern_bind and node.c != 0) {
        fallback += 1;
    };
    try std.testing.expect(fallback != 0);
    try validatePortable(allocator, &module);
}
test "named ordinary owners retain value witnesses empty arms and exiting fallbacks through OOM" {
    try namedOrdinaryOwners(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, namedOrdinaryOwners, .{});
}
fn packageWorkspace(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var remaining: usize = 1_000_000;
    var workspace: @import("scheme_equations.zig").Workspace = .{ .allocator = allocator };
    @import("package_core.zig").executableWorkspace(module, .{ .units = &[_]*const core.Module{module} }, &remaining, &workspace) catch |err| {
        if (workspace.oom) return error.OutOfMemory;
        return err;
    };
    if (workspace.oom) return error.OutOfMemory;
}
fn rejectedPackageWorkspace(allocator: std.mem.Allocator, module: *const core.Module) !void {
    if (packageWorkspace(allocator, module)) |_| return error.TestUnexpectedResult else |err| {
        if (err != error.InvalidArtifact) return err;
    }
}
test "package fallback storage rejects success pattern theft and fallthrough before expression admission through OOM" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator, named_ordinary_owner_source);
    defer module.deinit(allocator);
    try packageWorkspace(allocator, &module);
    var mutations: usize = 0;
    for (module.nodes) |pattern_node| {
        if (pattern_node.tag != .pattern_bind or pattern_node.c == 0) continue;
        const pattern = module.pattern(module.pattern(pattern_node.a).b);
        try std.testing.expect(pattern.tag == .bind);
        var reference: core.Id = 0;
        for (module.nodes, 0..) |node, id| {
            if (node.tag == .reference and module.reference(@intCast(id)).binding == pattern.a) reference = @intCast(id);
        }
        try std.testing.expect(reference != 0);
        const statements = module.children(pattern_node.c);
        try std.testing.expect(statements.len == 1);
        const fallback = &module.nodes[statements[0]];
        const saved = fallback.*;
        try std.testing.expect(saved.tag == .return_);
        fallback.a = reference;
        try rejectedPackageWorkspace(allocator, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, rejectedPackageWorkspace, .{&module});
        fallback.* = .{ .tag = .constant, .ty = T.unit };
        try rejectedPackageWorkspace(allocator, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, rejectedPackageWorkspace, .{&module});
        fallback.* = saved;
        mutations += 1;
    }
    try std.testing.expect(mutations != 0);
    try packageWorkspace(allocator, &module);
}
test "ordinary type witnesses reject opened abstract representation through OOM" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\type Item = exists [a] => a
        \\const inspect = fn (item: Item) => unpack item as [a] value in do:
        \\  let ignored = value
        \\  return @type.same 0 (fn () => 1)
    );
    defer module.deinit(allocator);
    try packageWorkspace(allocator, &module);
    var hidden: core.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag == .reference and module.types.node(node.ty).tag == .bound) hidden = @intCast(id);
    }
    try std.testing.expect(hidden != 0);
    var mutations: usize = 0;
    for (module.nodes) |*node| {
        if (node.tag != .type_same) continue;
        const saved = node.a;
        node.a = hidden;
        try rejectedPackageWorkspace(allocator, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, rejectedPackageWorkspace, .{&module});
        node.a = saved;
        mutations += 1;
    }
    try std.testing.expect(mutations != 0);
    try packageWorkspace(allocator, &module);
}

test "generic cursor primitives require actual collection predicates and element identities through OOM" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\type Maybe a is data = #Some a | #Nothing
        \\const identity: forall [a] => a -> a = fn value => value
        \\const next = fn cursor => if @cursor.has cursor then #Some (@cursor.value cursor, @cursor.advance cursor) else #Nothing
    );
    defer module.deinit(allocator);
    try packageWorkspace(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, packageWorkspace, .{&module});
    var changed: usize = 0;
    for (module.bodies) |*body| {
        if (body.scheme.obligations.len == 0) continue;
        const binding = &module.bindings[body.binding];
        const goals = module.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len];
        const results = try allocator.alloc(T.Id, goals.len);
        defer allocator.free(results);
        var collection = false;
        for (goals, results) |*goal, *saved| {
            saved.* = goal.result;
            if (goal.kind != .collection) continue;
            collection = true;
            goal.result = T.boolean;
        }
        if (!collection) continue;
        try rejectedPackageWorkspace(allocator, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, rejectedPackageWorkspace, .{&module});
        for (goals, results) |*goal, saved| goal.result = saved;
        const original = body.scheme.obligations;
        body.scheme.obligations = .{};
        binding.scheme.obligations = .{};
        try rejectedPackageWorkspace(allocator, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, rejectedPackageWorkspace, .{&module});
        body.scheme.obligations = original;
        binding.scheme.obligations = original;
        changed += 1;
    }
    try std.testing.expect(changed != 0);
    try packageWorkspace(allocator, &module);
}

test "validation bounds receipts retain exact context and never publish failed checks" {
    var module = try portableFixture(std.testing.allocator, "package/ordinary-control.blot");
    defer module.deinit(std.testing.allocator);
    const equations = @import("scheme_equations.zig");
    var workspace: equations.Workspace = .{ .allocator = std.testing.allocator };
    const units = [_]*const core.Module{&module};
    try std.testing.expectError(error.InvalidArtifact, equations.bounds(&workspace, &module, .{ .units = &units, .source_length = 0 }));
    try std.testing.expectEqual(@as(usize, 0), workspace.bounds_count);
    try equations.bounds(&workspace, &module, .{ .units = &units });
    try std.testing.expectEqual(@as(usize, 1), workspace.bounds_count);
    try equations.bounds(&workspace, &module, .{ .units = &units });
    try std.testing.expectEqual(@as(usize, 1), workspace.bounds_count);
    try std.testing.expectError(error.InvalidArtifact, equations.bounds(&workspace, &module, .{ .units = &units, .source_length = 0 }));
    try std.testing.expectError(error.InvalidArtifact, equations.bounds(&workspace, &module, .{ .units = &units, .symbol_count = 1 }));
    const duplicates = [_]*const core.Module{ &module, &module };
    try std.testing.expectError(error.InvalidArtifact, equations.bounds(&workspace, &module, .{ .units = &duplicates }));
    var sibling = module;
    sibling.unit += 1;
    const pair = [_]*const core.Module{ &module, &sibling };
    try equations.bounds(&workspace, &module, .{ .units = &pair });
    try std.testing.expectEqual(@as(usize, 1), workspace.bounds_count);
    try std.testing.expectError(error.InvalidArtifact, equations.bounds(&workspace, &module, .{ .units = &duplicates }));
    var invalid = module;
    invalid.unit = 0;
    const invalid_units = [_]*const core.Module{&invalid};
    try std.testing.expectError(error.InvalidArtifact, equations.bounds(&workspace, &module, .{ .units = &invalid_units }));
    try std.testing.expectEqual(@as(usize, 1), workspace.bounds_count);
    try std.testing.expect(!workspace.proved(&module));
}
