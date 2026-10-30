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

fn symbolicNominalGetterScenario(allocator: std.mem.Allocator) !void {
    var module = try portableFixture(allocator, "package/mixed-composition.blot");
    defer module.deinit(allocator);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try validatePortable(allocator, &module);
    var found = false;
    for (module.projections) |*projection| {
        const receiver = module.types.node(projection.source_type);
        if (receiver.tag != .nominal or projection.variants.len != 0 or projection.nominal.unit != 0 or projection.nominal.decl != 0) continue;
        const original = projection.*;
        defer projection.* = original;
        // Previously published explicit receiver metadata keeps its exact
        // public method proof too; neither representation authorizes payloads.
        projection.nominal = .{ .unit = receiver.a, .decl = receiver.b };
        try validatePortable(allocator, &module);
        projection.* = original;
        // Equal payload/result layouts cannot supply a different public
        // member, receiver or physical payload projection.
        projection.field = 0;
        try rejectPortable(allocator, &module);
        projection.* = original;
        const unrelated = for (module.implementation_members) |member| {
            if (member.name != 0 and member.name != original.field) break member.name;
        } else return error.TestUnexpectedResult;
        projection.field = unrelated;
        try rejectPortable(allocator, &module);
        projection.* = original;
        projection.source_type = T.u32_type;
        try rejectPortable(allocator, &module);
        projection.* = original;
        projection.nominal = .{ .unit = receiver.a + 1, .decl = receiver.b };
        try rejectPortable(allocator, &module);
        projection.* = original;
        try std.testing.expect(module.projection_variants.len != 0);
        projection.variants = .{ .start = 0, .len = 1 };
        try rejectPortable(allocator, &module);
        projection.* = original;
        found = true;
        break;
    }
    try std.testing.expect(found);
    try validatePortable(allocator, &module);
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "package symbolic nominal getters retain exact public member authority and reject payload guesses through OOM" {
    try symbolicNominalGetterScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicNominalGetterScenario, .{});
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
        \\const make: U32 -> Item = func value => return pack [U32, F32] (value, func number => return @u32.to_f32 number, func number => return @f32.to_u32 number) as Item
        \\const read: Item -> U32 = func item => return unpack item as [a, b] body in (@product.get body 2) ((@product.get body 1) (@product.get body 0))
        \\entry const answer: U32 -> U32 = func value => return read (make value)
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
        \\const read: Item -> U32 ! {Foreign} = func item => return unpack item as [a] body in (func (operation: a -> U32) => return operation (@product.get body 0)) (@product.get body 1)
    , true);
    try checkSource(
        \\type Item = exists [a] => (a, a -> U32)
        \\const read: Item -> U32 ! {Foreign} = func item => return unpack item as [a] body in (func (operation: a -> U32 ! {Foreign}) => return operation (@product.get body 0)) (@product.get body 1)
    , true);
    try checkSource(
        \\type Item = exists [a] => (a, a -> U32 ! {Foreign})
        \\const read: Item -> U32 = func item => return unpack item as [a] body in (func (operation: a -> U32) => return operation (@product.get body 0)) (@product.get body 1)
    , false);
    try checkSource(
        \\type Item = exists [a] => (a, a -> U32)
        \\const wrong = func (operation: U32 -> U32 ! {Foreign}) => return pack [U32] (42, operation) as Item
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
        \\const identity: forall [a] => a -> a = func value => return value
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\const separate = func () => return @effect.scope (func (other: State U32) => return 0)
        \\const selected = func (flag: Bool) => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
        \\  let choose = func () => return if flag then left else right
        \\  let chosen = choose ()
        \\  let alias = chosen
        \\  let (_, result) = do (@effect.state chosen.get chosen.set 1):
        \\    use alias.set 42
        \\    break alias.get ()
        \\  break result
        \\))
        \\entry const answer = func (flag: Bool) => return identity (selected flag)
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
    \\const read: (unique U32) -> U32 = func hidden => return @usage.borrow hidden (func loan => return @usage.read loan)
    \\const make = func (owner: unique U32) => return pack [U32] (owner, read) as Item
    \\entry const answer = func () => return do:
    \\  use owner <- @resource.acquire (func () => return 42) (func released => return ())
    \\  break unpack (make owner) as [a] value in do:
    \\    let (hidden, operation) = value
    \\    break operation hidden
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
        \\const identity: Item -> (U32 -> U32) = func item => return unpack item as [a] hidden in do:
        \\  let observed = hidden
        \\  break func (value: U32) => return do:
        \\    let ignored = 42
        \\    break value
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
        \\const reseal: Item -> Item = func item => return unpack item as [a] value in pack [a] value as Item
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
        \\const hide: Item -> Callback = func item => return unpack item as [a] hidden in do:
        \\  let observed = hidden
        \\  break pack [U32] (func (value: U32) => return do:
        \\    let ignored = 42
        \\    break value) as Callback
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
    var ordinary = try lowerSource(a, "entry const answer: U32 -> U32 = func value => return value\n");
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
        \\const make: U32 -> Item = func value => return pack [U32] (value, func number => return @u32.add number 1) as Item
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
    try context.closed_rows.set(1);
    try context.visit(6);
    try proof.validate(6, 7);
    labels[0] = 0;
    try std.testing.expectError(error.InvalidArtifact, context.visit(6));
}

fn rejectDictionaryModule(allocator: std.mem.Allocator, module: *const core.Module) !void {
    @import("frozen_core_validation.zig").validate(allocator, module, .{}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (err != error.InvalidArtifact) return err;
        return;
    };
    try std.testing.expect(false);
}

fn predicatePackSelection(allocator: std.mem.Allocator) !void {
    const source =
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\type Item = exists [a] where { Render a } => a
        \\const item: Item = pack [U32] 42 as Item
        \\const flag: Item = pack [Bool] true as Item
        \\const read = func (item: Item) => return unpack item as [a] value in Render.show value
        \\const both = func (left: Item) => return func (right: Item) => return unpack left as [a] x in unpack right as [b] y in @u32.add (Render.show x) (Render.show y)
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
        \\const first: forall [a, b] => (a, b) -> a = func value => return @product.get value 0
        \\const twice: forall [a] => a -> (a, a) = func value => return (value, value)
        \\const twice_alias: forall [a] => a -> (a, a) = twice
        \\const record: forall [a] => a -> {value: a} = func value => return {value: value}
        \\const head: forall [a] => Array a -> a = func values => return @array.get values 0
        \\entry const array_head = func (value: U32) => return head #[value, 42]
        \\const keep: forall [a] => a -> (forall [b] => b -> a) = func first => return func second => return first
        \\entry const held = func (value: U32) => return (keep value) true
        \\const pass: (forall [a] => (Bool, a) -> U32) -> U32 = func recurse => return recurse (false, 42)
        \\const recursive: forall [a] => (Bool, a) -> U32 = func pair => return if @product.get pair 0 then pass recursive else 0
        \\entry const recursive_call = func (value: U32) => return recursive (true, value)
        \\entry const whole = func (value: U32) => return first (value, true)
        \\entry const fraction = func (value: F32) => return @product.get (twice_alias value) 1
        \\entry const stored = func (value: U32) => return (record value).value
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
        \\const apply: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = func pair => return (@product.get pair 0) (@product.get pair 1)
        \\const both: (forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}) -> U32 -> (U32, F32) = func apply => return func value => return (apply ((func item => return item), value), apply ((func item => return item), @u32.to_f32 value))
        \\const foreign_apply: ((forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}), (U32 -> U32 ! {Foreign})) -> U32 ! {Foreign} = func pair => return (@product.get pair 0) (@product.get pair 1, 42)
        \\entry const host = func (callback: U32 -> U32 ! {Foreign}) => return foreign_apply (apply, callback)
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
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\type Future = forall [a, row e] where { Render (a -> a ! {|e}) } => Unit -> Unit
        \\type Item = exists [a] where { Render a } => a
        \\const make: Bool -> Item = func flag => return if flag then pack [U32] 42 as Item else pack [Bool] true as Item
        \\const read = func (item: Item) => return unpack item as [a] value in Render.show value
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
        \\const identity = func value => return value
        \\const apply = func callback => return func value => return callback value
        \\const forget = func value => return do:
        \\  break func (unit: Unit) => return @u32.add 40 2
        \\const annotated: forall [a] => a -> a = identity
        \\const through: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = func pair => return apply (@product.get pair 0) (@product.get pair 1)
        \\type Item = exists [a] => (a, a -> U32)
        \\const make = func (value: U32) => return pack [U32] (value, identity) as Item
        \\const read = func (item: Item) => return unpack item as [a] value in (@product.get value 1) (identity (@product.get value 0))
        \\const discard = func (item: Item) => return unpack item as [a] value in forget (@product.get value 0)
        \\entry const forgotten = func (value: U32) => return (discard (make value)) ()
        \\entry const answer = func (value: U32) => return read (make value)
        \\entry const whole = func (value: U32) => return annotated (apply identity value)
        \\entry const host = func (callback: U32 -> U32 ! {Foreign}) => return through (callback, 42)
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
        "impl Number : Tag U32 = { const read = func unit => return 42 }\n" ++
        "type Item = exists [a] where { Tag a } => Unit\n" ++
        "type Sealed = exists [b] => Unit -> U32\n";
    const cases = [_]struct { body: []const u8, escapes: bool }{
        .{ .body = "Tag.read ()", .escapes = false },
        .{ .body = "Tag.read", .escapes = true },
        .{ .body = "func (unit: Unit) => return Tag.read unit", .escapes = true },
        .{ .body = "(Tag.read, 7)", .escapes = true },
        .{ .body = "pack [U32] Tag.read as Sealed", .escapes = true },
        .{ .body = "pack [a] Tag.read as Sealed", .escapes = false },
    };
    for (cases) |case| {
        const source = try std.mem.concat(allocator, u8, &.{ prefix, "const keep = func (item: Item) => return unpack item as [a] value in ", case.body, "\n" });
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
        \\const flag: Item = pack [Bool] true as Item
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
        \\impl Number : Tag U32 = { const read = func unit => return 42 }
        \\type Item = exists [a] where { Tag a } => Unit
        \\type Sealed = exists [b] => Unit -> U32
        \\const item: Item = pack [U32] () as Item
        \\const keep = func (item: Item) => return unpack item as [a] value in pack [a] Tag.read as Sealed
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
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\type Item = exists [a] where { Render a } => a
        \\const make = func (flag: Bool) => return if flag then pack [U32] 42 as Item else pack [Bool] true as Item
        \\const reseal = func (item: Item) => return unpack item as [a] value in pack [a] value as Item
        \\const choose = func (left: Item) => return func (right: Item) => return unpack left as [a] x in unpack right as [b] y in pack [b] y as Item
        \\const seal: forall [a] where { Render a } => a -> Item = func value => return pack [a] value as Item
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
        \\const identity: Identity = func value => return value
        \\type Point is data = #Point { x: U32 }
        \\const Point.add = func (left: Point) => return func (right: U32) => return @u32.add left.x right
        \\const Point.from = func (value: U32) => return #Point {x: value}
        \\const convert: a -> b where { result "from" a b } = func value => return @type.result "from" value
        \\const converted: Point = convert 20
        \\const combine = func left => return func right => return @type.call "add" left right
        \\const represented: a -> a where { type_rep a } = func value => return value
        \\const field = func value => return value.x
        \\const forward = func value => return combine value 22
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
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\const helper = func value => return Render.show value
        \\const render: forall [a] where { Render a } => a -> U32 = func value => return helper value
        \\const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
        \\entry const answer = func () => return both render
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
        \\const identity: forall [a] => a -> a = func value => return value
        \\type Left is data = #Left {value: U32}
        \\type Right is data = #Right {value: U32}
        \\const Left.add = func (left: Left) => return func (right: U32) => return @u32.add left.value right
        \\const Right.add = func (left: Left) => return func (right: Right) => return @u32.add left.value right.value
        \\const combine = func left => return func right => return @type.call "add" left right
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
        \\const make = func value => return pack [U32] (value, func (payload: U32) => return payload) as Item
        \\const read: forall [a] => a -> Item -> U32 = func ignored => return func item => return unpack item as [b] value in (@product.get value 1) (@product.get value 0)
        \\entry const answer = func () => return read true (make 42)
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
        \\impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
        \\type Package = exists [a] where { Source a } => a
        \\const make = func (value: U32) => return pack [U32] value as Package
        \\const read = func (item: Package) => return unpack item as [a] value in Source.show value (Source.get value)
        \\const calculate = func (value: U32) => return read (make value)
        \\const identity: forall [a] => a -> a = func value => return value
        \\const keep: a -> (Source.Item a) -> (Source.Item a) where { Source a } = func witness => return func value => return value
        \\const carried = func (value: U32) => return keep value value
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
        \\impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
        \\type Package = exists [a] where { Source a } => (a, Source.Item a)
        \\const make = func (value: U32) => return pack [U32] (value, value) as Package
        \\const reseal = func (item: Package) => return unpack item as [a] value in pack [a] value as Package
        \\const seal: forall [a] where { Source a } => a -> (Source.Item a) -> Package = func value => return func item => return pack [a] (value, item) as Package
        \\const read = func (item: Package) => return unpack item as [a] value in Source.show (@product.get value 0) (@product.get value 1)
        \\entry const answer = func () => return read (make 42)
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
        "type Package = exists [a] where {Source a} => (a, Source.Item a)\nconst bad = pack [U32] (1,true) as Package\n",
        "type Package = exists [a] where {Source a} => (a, Source.Item a)\nconst bad = pack [Bool] (true,42) as Package\n",
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
    const source = try std.mem.concat(allocator, u8, &.{ "const identity: forall [a] => a -> a = func value => return value\n", body });
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
        \\entry const answer = func () => return identity 42
    ;
    try rankCoexistenceScenario(std.testing.allocator, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankCoexistenceScenario, .{source});
}

test "rank interfaces retain handlers for effectful typed code through complete OOM" {
    const source =
        \\effect Read: Unit -> U32
        \\const future = @code.quote (Read ())
        \\const provider = @effect.provider Read (func () => return 42)
        \\effect Write: Unit -> Unit
        \\const writer = @effect.provider Write (func () => return ())
        \\entry const answer = func () => return do provider:
        \\  let deferred = func () => return Read ()
        \\  use value <- @code.emit future
        \\  break value
    ;
    try rankCoexistenceScenario(std.testing.allocator, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankCoexistenceScenario, .{source});
}

test "rank call views preserve separately evaluated operation arguments through complete OOM" {
    const source =
        \\effect Read: Unit -> U32
        \\const pass = func value => return identity value
        \\const invoke = func () => return identity (Read ())
        \\const future = @code.quote (invoke ())
        \\const provider = @effect.provider Read (func () => return 42)
        \\entry const answer = func () => return do provider:
        \\  use value <- @code.emit future
        \\  break value
    ;
    try rankCoexistenceScenario(std.testing.allocator, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankCoexistenceScenario, .{source});
}

fn rankHandlerCaptureScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Tag a is contract = { const read: Unit -> U32 }
        \\impl Number : Tag U32 = { const read = func unit => return 42 }
        \\type Item = exists [a] where { Tag a } => Unit
        \\type Sealed = exists [b] => Unit -> U32
        \\effect Tick: Unit -> Unit
        \\const provider = @effect.provider Tick (func () => return ())
        \\const copy = provider
        \\const item: Item = pack [U32] () as Item
        \\const keep = func (item: Item) => return unpack item as [a] value in pack [a] Tag.read as Sealed
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
        \\const action = func () => return Read ()
        \\const declared: Unit -> U32 ! {Foreign} = func () => return 42
        \\const factory = func (seed: U32) => return func () => return seed
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
    try std.testing.expect(!scopes.closed_rows.contains(2));
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(7));
    try proof.validate(9, 10);
    try std.testing.expect(scopes.closed_rows.contains(2));
    try scopes.visit(10);

    // Covariant supersets remain legal only under their existing lexical owner.
    try proof.validate(6, 12);
    try std.testing.expect(!scopes.closed_rows.contains(3));
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(12));
    try scopes.pushGeneric(.{ .root = 12, .row_variables = .{ .start = 8, .len = 1 } });
    try proof.validate(6, 12);
    try scopes.visit(12);
    try std.testing.expect(!scopes.closed_rows.contains(3));
    scopes.popGeneric();
    try proof.validate(6, 13);
    try std.testing.expect(!scopes.closed_rows.contains(4));
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(13));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 14));
    try std.testing.expect(!scopes.closed_rows.contains(5));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(15, 7));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 16));

    // Formal row tails are never closed by inference-view publication.
    try scopes.enter(18);
    try proof.validate(6, 19);
    try scopes.visit(19);
    try std.testing.expect(!scopes.closed_rows.contains(7));
    scopes.leave();
    try scopes.enter(21);
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(19));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(19, 22));
    scopes.leave();
    try std.testing.expect(!scopes.closed_rows.contains(7) and !scopes.closed_rows.contains(8));

    scopes.closed_rows.unset(2);
    try scopes.pushGeneric(.{ .root = 7, .row_variables = .{ .start = 9, .len = 1 } });
    try proof.validate(6, 7);
    try scopes.visit(7);
    try std.testing.expect(!scopes.closed_rows.contains(2));
    scopes.popGeneric();
    try std.testing.expectError(error.InvalidArtifact, scopes.visit(7));
    rows[2].tail = .{ .variable = 5 };
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 7));
    try std.testing.expect(!scopes.closed_rows.contains(2));
    rows[2].tail = .{ .variable = 0 };
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 7));
    try std.testing.expectEqual(0, remaining);
    try std.testing.expect(!scopes.closed_rows.contains(2));
}

const named_ordinary_owner_source =
    \\type Maybe a is data = #Some a | #Nothing
    \\const identity: forall [a] => a -> a = func value => return value
    \\const same = func left => return func right => return @type.same left right
    \\const inspect = func (candidate: Maybe U32) => return do:
    \\  let #Some value = candidate else:
    \\    break 0
    \\  if let #Some extra = candidate:
    \\    use same value extra
    \\  break value
    \\const helper = func (value: U32) => return inspect (#Some value)
    \\const generated = @code.quote (func (value: U32) => return helper value)
    \\entry const run = func (value: U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return helper value)))
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
        \\const inspect = func (item: Item) => return unpack item as [a] value in do:
        \\  let ignored = value
        \\  break @type.same 0 (func () => return 1)
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
        \\const identity: forall [a] => a -> a = func value => return value
        \\const next = func cursor => return if @cursor.has cursor then #Some (@cursor.value cursor, @cursor.advance cursor) else #Nothing
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

test "callback field selection preserves latent effects and invocation cannot erase them" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\effect Read: Unit -> U32
        \\const pick = func stages => return stages.route
        \\const action = func () => return Read ()
        \\const selected: Unit -> U32 ! {Read} = pick {route: action}
        \\const pure: Unit -> U32 = func () => return 0
        \\const invoke: Unit -> U32 ! {Read} = func () => return selected ()
    );
    defer module.deinit(allocator);
    validatePortable(allocator, &module) catch return error.CallbackSelectionRejected;
    // The getter remains pure, but its result keeps the callback's effect row.
    // Erasing that row from the actual invocation's public contract is invalid.
    var pure_type: T.Id = 0;
    var invoked: ?usize = null;
    for (module.bodies, 0..) |body, index| {
        if (std.mem.eql(u8, module.name(body.declaration_name), "pure")) pure_type = body.scheme.root;
        if (std.mem.eql(u8, module.name(body.declaration_name), "invoke")) invoked = index;
    }
    if (pure_type == 0 or invoked == null) return error.CallbackInvocationBodyMissing;
    const body = &module.bodies[invoked.?];
    const binding = &module.bindings[body.binding];
    const original_body = body.*;
    const original_binding = binding.*;
    defer body.* = original_body;
    defer binding.* = original_binding;
    // Forge just the invoker's declaration, leaving the callback and the real
    // call edge's effect row intact. Shared interned types must stay untouched.
    body.scheme.root = pure_type;
    binding.ty = pure_type;
    binding.scheme.root = pure_type;
    var remaining: usize = 65_536;
    @import("package_core.zig").checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator) catch |err| {
        if (err != error.InvalidArtifact) return err;
        return;
    };
    return error.CallbackInvocationErasureAccepted;
}

test "source collection prerequisites admit owned readers but reject Ref and Link" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\const first = func cursor => return @cursor.value cursor
        \\const grown = func (items: Cursor (GrowArray U32)) => return first items
        \\const resized = func (items: Cursor (ResizeArray U32)) => return first items
        \\const viewed = func (items: Cursor (&[U32])) => return first items
        \\const direct = func (items: Cursor (ResizeArray U32)) => return @cursor.value items
    );
    defer module.deinit(allocator);
    const package = @import("package_core.zig");
    for (module.bodies) |body| {
        var remaining: usize = 65_536;
        if (module.binding(body.binding).kind != .global) continue;
        try package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
    }
    var changed = false;
    for (module.bodies) |body| {
        if (!std.mem.eql(u8, module.name(body.declaration_name), "resized")) continue;
        const function = module.types.node(body.scheme.root);
        const reader = module.types.node(function.a).a;
        const original = module.types.nodes[reader];
        try std.testing.expect(original.tag == .nominal);
        inline for (.{ @import("storage_types.zig").Kind.ref, @import("storage_types.zig").Kind.link }) |kind| {
            module.types.nodes[reader].b = @backingInt(kind);
            defer module.types.nodes[reader] = original;
            var remaining: usize = 65_536;
            try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator));
        }
        changed = true;
    }
    try std.testing.expect(changed);
}

test "source nominal fields instantiate only the constructor owned binders" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\type Box a is data = $Box {value: a}
        \\const read = func boxed => return boxed.value
        \\const unbox = func (boxed: Box U32): U32 => return read boxed
    );
    defer module.deinit(allocator);
    const package = @import("package_core.zig");
    var target: core.BindingId = 0;
    for (module.bodies) |body| {
        if (std.mem.eql(u8, module.name(body.declaration_name), "unbox")) target = body.binding;
        var remaining: usize = 65_536;
        if (module.binding(body.binding).kind != .global) continue;
        try package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
    }
    try std.testing.expect(target != 0);
    var mutated = false;
    for (module.constructors) |*constructor| {
        if (constructor.scheme.variables.len == 0) continue;
        const saved = constructor.scheme.variables;
        constructor.scheme.variables = .{};
        defer constructor.scheme.variables = saved;
        // The same type variable node without this constructor's ownership
        // must not be treated as an instantiable payload witness.
        var remaining: usize = 65_536;
        try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBody(&module, target, .{}, &remaining, allocator));
        mutated = true;
        break;
    }
    try std.testing.expect(mutated);
}

test "source SIMD authority preserves exact catalog lanes and comparison masks" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\type Words = (U32, U32, U32, U32)
        \\type Floats = (F32, F32, F32, F32)
        \\const xor = func (left: Words) -> (right: Words): Words => return @simd.u32x4.bit_xor left right
        \\const compare = func (left: Floats) -> (right: Floats): Words => return @simd.f32x4.lt left right
    );
    defer module.deinit(allocator);
    const package = @import("package_core.zig");
    var target: core.BindingId = 0;
    for (module.bodies) |body| {
        if (module.binding(body.binding).kind != .global) continue;
        if (std.mem.eql(u8, module.name(body.declaration_name), "xor")) target = body.binding;
        var remaining: usize = 65_536;
        try package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
    }
    try std.testing.expect(target != 0);
    const arrow = module.types.node(module.binding(target).scheme.root);
    const vector_type = module.types.node(arrow.a);
    try std.testing.expect(vector_type.tag == .product and vector_type.b == 4);
    const saved = module.types.extra[vector_type.a + 2];
    module.types.extra[vector_type.a + 2] = T.f32_type;
    defer module.types.extra[vector_type.a + 2] = saved;
    // Equal aggregate widths and shared input/output aliases cannot authorize
    // a mixed F32 lane in a U32 vector operation.
    var remaining: usize = 65_536;
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBody(&module, target, .{}, &remaining, allocator));
}

test "compile scoped source proofs reuse completed bodies without lending caller effect authority" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\effect Read: Unit -> U32
        \\const read = func () => return Read ()
        \\const good: Unit -> U32 ! {Read} = func () => return read ()
        \\const extra: Unit -> U32 ! {Read} = func () => return read ()
        \\const invoke: Unit -> U32 ! {Read} = func () => return extra ()
        \\const pure: Unit -> U32 = func () => return 42
    );
    defer module.deinit(allocator);
    var good: core.BindingId = 0;
    var invoke: core.BindingId = 0;
    var pure_type: T.Id = 0;
    for (module.bodies) |body| {
        const name = module.name(body.declaration_name);
        if (std.mem.eql(u8, name, "good")) good = body.binding;
        if (std.mem.eql(u8, name, "invoke")) invoke = body.binding;
        if (std.mem.eql(u8, name, "pure")) pure_type = body.scheme.root;
    }
    try std.testing.expect(good != 0 and invoke != 0 and pure_type != 0);
    // Construct the negative immutable environment before the cache exists.
    // The real call to extra/read still performs Read; only this declaration
    // falsely claims a pure ambient.
    module.bindings[invoke].ty = pure_type;
    module.bindings[invoke].scheme.root = pure_type;
    for (module.bodies) |*body| if (body.binding == invoke) {
        body.scheme.root = pure_type;
    };
    const package = @import("package_core.zig");
    var cache = try package.SourceProofCache.init(allocator, &.{&module});
    defer cache.deinit();
    var remaining: usize = 65_536;
    try package.checkedInterfaceBodyCached(&cache, &module, good, &remaining, null, null);
    const completed = cache.completed.count();
    try std.testing.expect(completed >= 2);
    const after_first = remaining;
    try package.checkedInterfaceBodyCached(&cache, &module, good, &remaining, null, null);
    try std.testing.expectEqual(after_first, remaining);
    try std.testing.expectEqual(completed, cache.completed.count());
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBodyCached(&cache, &module, invoke, &remaining, null, null));
    // A failed root may validate extra locally, but publishes no new claims.
    try std.testing.expectEqual(completed, cache.completed.count());
    var different_view = module;
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBodyCached(&cache, &different_view, good, &remaining, null, null));
    try immutableUsageFactScenario(allocator);
    try moduleSourceBudgetScenario(allocator);
}

fn moduleSourceBudgetScenario(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\const first = func () => return 42
        \\const second = func () => return 43
    );
    defer module.deinit(allocator);
    var first: core.BindingId = 0;
    var second: core.BindingId = 0;
    for (module.bodies) |body| {
        if (std.mem.eql(u8, module.name(body.declaration_name), "first")) first = body.binding;
        if (std.mem.eql(u8, module.name(body.declaration_name), "second")) second = body.binding;
    }
    try std.testing.expect(first != 0 and second != 0);
    var peer = module;
    peer.unit = 2;
    const package = @import("package_core.zig");
    const units = &[_]*const core.Module{ &module, &peer };
    var global = try package.SourceProofCache.init(allocator, units);
    defer global.deinit();
    var remaining: usize = 65_536;
    try package.checkedInterfaceBodyCached(&global, &module, first, &remaining, null, null);
    const cost = 65_536 - remaining;
    try std.testing.expect(cost != 0 and global.remainingTotal() == null);
    var cache = try package.SourceProofCache.initWithModuleBudget(allocator, units, cost);
    defer cache.deinit();
    try std.testing.expectEqual(cost * 2, cache.remainingTotal().?);
    // The explicit-global API remains separate; opt-in counters are shared
    // across this module's roots and cannot borrow the peer's allowance.
    remaining = 1;
    try package.checkedInterfaceBodyCached(&cache, &module, first, &remaining, null, null);
    try std.testing.expectEqual(@as(usize, 1), remaining);
    try std.testing.expectEqual(@as(usize, 0), cache.moduleRemaining(module.unit).?);
    try std.testing.expect(cache.exhaustedUnit() == null);
    try package.checkedInterfaceBodyCached(&cache, &module, first, &remaining, null, null);
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBodyCached(&cache, &module, second, &remaining, null, null));
    try std.testing.expectEqual(module.unit, cache.exhaustedUnit().?);
    try std.testing.expectEqual(cost, cache.moduleRemaining(peer.unit).?);
    try package.checkedInterfaceBodyCached(&cache, &peer, first, &remaining, null, null);
    try std.testing.expect(cache.exhaustedUnit() == null);
    try std.testing.expectEqual(@as(usize, 0), cache.remainingTotal().?);
}

fn immutableUsageFactScenario(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator, "const value: U32 = 42");
    defer module.deinit(allocator);
    const package = @import("package_core.zig");
    var cache = try package.SourceProofCache.init(allocator, &.{&module});
    defer cache.deinit();
    var remaining: usize = 65_536;
    // Immutable structural facts are reusable; a mutable solver type graph
    // with the same unit and root ID must compute its own different answer.
    try std.testing.expect(!try cache.containsUsage(&module, T.u32_type, &remaining));
    const fact_count = cache.usage_facts.count();
    const nodes = try allocator.dupe(T.Node, module.types.nodes);
    defer allocator.free(nodes);
    nodes[T.u32_type] = .{ .tag = .usage, .a = T.unit, .b = @backingInt(T.UsageKind.unique) };
    const mutable_view: core.Module = .{
        .unit = module.unit,
        .types = .{ .nodes = nodes, .extra = module.types.extra },
        .nominals = module.nominals,
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    try std.testing.expect(try cache.containsUsage(&mutable_view, T.u32_type, &remaining));
    try std.testing.expectEqual(fact_count, cache.usage_facts.count());
    try std.testing.expect(!try cache.containsUsage(&module, T.u32_type, &remaining));
}

test "source imported callee assumptions preserve exact producer and public arguments" {
    const allocator = std.testing.allocator;
    var producer = try lowerSource(allocator,
        \\const combine = func x => return func y => return @type.call "add" x y
        \\const other = func x => return func y => return @type.call "mul" x y
        \\const wrapper = func x => return combine x x
    );
    defer producer.deinit(allocator);
    var combine: core.BindingId = 0;
    var other: core.BindingId = 0;
    var wrapper: core.BindingId = 0;
    for (producer.bodies) |body| {
        const name = producer.name(body.declaration_name);
        if (std.mem.eql(u8, name, "combine")) combine = body.binding;
        if (std.mem.eql(u8, name, "other")) other = body.binding;
        if (std.mem.eql(u8, name, "wrapper")) wrapper = body.binding;
    }
    try std.testing.expect(combine != 0 and other != 0 and wrapper != 0);
    var consumer = producer;
    consumer.unit = 2;
    consumer.bindings = try allocator.dupe(core.Binding, producer.bindings);
    defer allocator.free(consumer.bindings);
    consumer.calls = try allocator.dupe(core.CallInfo, producer.calls);
    defer allocator.free(consumer.calls);
    consumer.references = try allocator.dupe(core.BindingRef, producer.references);
    defer allocator.free(consumer.references);
    consumer.obligations = try allocator.dupe(core.Obligation, producer.obligations);
    defer allocator.free(consumer.obligations);
    consumer.bindings[combine].kind = .external;
    consumer.bindings[combine].target = .{ .unit = producer.unit, .binding = combine };
    for (consumer.calls) |*call| if (call.target.unit == 0 and call.target.binding == combine) {
        call.target.unit = producer.unit;
    };
    for (consumer.references) |*reference| if (reference.unit == 0 and reference.binding == combine) {
        reference.unit = producer.unit;
    };
    for (consumer.obligations) |*goal| if (goal.kind == .callee_use and goal.identity.decl == combine) {
        goal.identity.unit = consumer.unit;
    };
    const package = @import("package_core.zig");
    const context = .{ .units = &[_]*const core.Module{ &producer, &consumer } };
    var remaining: usize = 65_536;
    try package.checkedInterfaceBody(&consumer, wrapper, context, &remaining, allocator);
    consumer.bindings[combine].target.binding = other;
    remaining = 65_536;
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBody(&consumer, wrapper, context, &remaining, allocator));
    consumer.bindings[combine].target.binding = combine;
    const selected: usize = for (consumer.obligations, 0..) |goal, index| {
        if (goal.kind == .callee_use and goal.identity.decl == combine) break index;
    } else return error.TestUnexpectedResult;
    const pack = consumer.types.node(consumer.obligations[selected].ty);
    try std.testing.expect(pack.tag == .product and pack.b != 0);
    const original_types = consumer.types;
    const wrong_nodes = try allocator.alloc(T.Node, original_types.nodes.len + 1);
    defer allocator.free(wrong_nodes);
    @memcpy(wrong_nodes[0..original_types.nodes.len], original_types.nodes);
    const wrong_extra = try allocator.alloc(T.Id, original_types.extra.len + pack.b);
    defer allocator.free(wrong_extra);
    @memcpy(wrong_extra[0..original_types.extra.len], original_types.extra);
    @memcpy(wrong_extra[original_types.extra.len..], original_types.list(.{ .start = pack.a, .len = pack.b }));
    wrong_extra[original_types.extra.len] = T.f32_type;
    wrong_nodes[original_types.nodes.len] = .{ .tag = .product, .a = @intCast(original_types.extra.len), .b = pack.b };
    consumer.types = .{
        .nodes = wrong_nodes,
        .extra = wrong_extra,
        .effects = original_types.effects,
        .operations = original_types.operations,
        .quantifier_goals = original_types.quantifier_goals,
        .quantifier_obligations = original_types.quantifier_obligations,
    };
    consumer.obligations[selected].ty = @intCast(original_types.nodes.len);
    remaining = 65_536;
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBody(&consumer, wrapper, context, &remaining, allocator));
}

test "source policy call results establish exact callback rows before their use" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\const policy = func (seed: U32) => return {run: func (value: U32) => return @u32.add seed value}
        \\const invoke = func codec -> value => return codec.run value
        \\const answer = func (value: U32) => return invoke (policy value) value
    );
    defer module.deinit(allocator);
    const body = for (module.bodies) |candidate| {
        if (std.mem.eql(u8, module.name(candidate.declaration_name), "answer")) break candidate;
    } else return error.MissingSelectedBody;
    var remaining: usize = 65_536;
    try @import("package_core.zig").checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
}

test "source loop carries retain only the branch that reaches the backedge" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\const scan = func (items: Array U32) => return do:
        \\  let total = 0
        \\  let valid = true
        \\  for value in items:
        \\    if @u32.lt 0 value:
        \\      total := @u32.add self value
        \\    else:
        \\      let forbidden = 123456789
        \\      valid := false
        \\      break
        \\  return @u32.add total (if valid then 100 else 0)
    );
    defer module.deinit(allocator);
    const package = @import("package_core.zig");
    const body = for (module.bodies) |candidate| {
        if (std.mem.eql(u8, module.name(candidate.declaration_name), "scan")) break candidate;
    } else return error.MissingScanBody;
    var remaining: usize = 65_536;
    try package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
    var forbidden: core.BindingId = 0;
    for (module.nodes) |node| if (node.tag == .bind) {
        const value = module.node(node.b);
        if (value.tag == .constant and value.a == 123456789) forbidden = node.a;
    };
    try std.testing.expect(forbidden != 0);
    const carry = for (module.loop_carries) |*candidate| {
        if (module.binding(candidate.incoming).ty == T.u32_type) break candidate;
    } else return error.MissingCarry;
    const original = carry.backedge;
    defer carry.backedge = original;
    carry.backedge = forbidden;
    remaining = 65_536;
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator));
    carry.backedge = original;
    remaining = 65_536;
    try package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
}

test "source lexical storage admits high binding identities without granting branch locals" {
    const allocator = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    var text: [80]u8 = undefined;
    for (0..4100) |index| try source.appendSlice(allocator, try std.mem.print(&text, "const pad_{d} = 0\n", .{index}));
    try source.appendSlice(allocator,
        \\const selected = func (flag: Bool) -> (input: U32) => return do:
        \\  let outer = @u32.add input 1
        \\  if flag:
        \\    let inner = @u32.add outer 2
        \\    return inner
        \\  return outer
    );
    var module = try lowerSource(allocator, source.items);
    defer module.deinit(allocator);
    try std.testing.expect(module.bindings.len > 4096);
    const package = @import("package_core.zig");
    const body = for (module.bodies) |candidate| {
        if (std.mem.eql(u8, module.name(candidate.declaration_name), "selected")) break candidate;
    } else return error.MissingSelectedBody;
    var remaining: usize = 1_000_000;
    try package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
    // The last lexical declaration belongs to the conditional branch. Forging
    // the final read to use it must still fail despite identical scalar types.
    var inner: core.BindingId = 0;
    var final_read: core.Id = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag == .bind) inner = node.a;
        if (node.tag == .reference and node.ty == T.u32_type) final_read = @intCast(index);
    }
    try std.testing.expect(inner > 4096 and final_read != 0);
    const reference = module.nodes[final_read].a;
    const original = module.references[reference];
    module.references[reference].binding = inner;
    remaining = 1_000_000;
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator));
    module.references[reference] = original;
    remaining = 1_000_000;
    try package.checkedInterfaceBody(&module, body.binding, .{}, &remaining, allocator);
}

test "source ordinary scheme lists retain exact ownership without package binder limits" {
    const count = 192;
    var nodes: [count + 7]T.Node = @splat(.{ .tag = .variable });
    nodes[0] = .{ .tag = .absent };
    nodes[T.unit] = .{ .tag = .unit };
    nodes[T.boolean] = .{ .tag = .boolean };
    nodes[T.u32_type] = .{ .tag = .u32 };
    nodes[T.f32_type] = .{ .tag = .f32 };
    nodes[T.never] = .{ .tag = .never };
    var extra: [count * 2 + 2]u32 = undefined;
    for (0..count) |i| {
        extra[i] = @intCast(i + 6);
        extra[count + i] = @intCast(i);
    }
    extra[count * 2] = count + 6;
    extra[count * 2 + 1] = count;
    var rows = [_]T.Effects.Row{.{}};
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows, .variable_count = count + 1 } };
    const scheme: T.Scheme = .{ .root = T.unit, .variables = .{ .len = count }, .row_variables = .{ .start = count, .len = count } };
    var remaining: usize = 65_536;
    var source: contracts.Context = .{ .types = &graph, .remaining = &remaining, .large_plain_graph = true, .source_instances = true };
    try source.initialize();
    try source.generic(scheme);
    try std.testing.expect(try source.ownsVariable(count + 5));
    try std.testing.expect(!try source.ownsVariable(count + 6));
    try std.testing.expect(try source.ownsRow(count - 1));
    try std.testing.expect(!try source.ownsRow(count));
    // Repeated membership inquiries spend bounded work without rescanning the
    // scheme. A copied scope keeps its own lexical authority after push/pop.
    const work_before = remaining;
    for (0..count) |_| {
        try std.testing.expect(try source.ownsVariable(count + 5));
        try std.testing.expect(try source.ownsRow(count - 1));
    }
    try std.testing.expectEqual(@as(usize, count * 2), work_before - remaining);
    var saved = source;
    const nested: T.Scheme = .{ .root = T.unit, .variables = .{ .start = count * 2, .len = 1 }, .row_variables = .{ .start = count * 2 + 1, .len = 1 } };
    try source.pushGeneric(nested);
    try std.testing.expect(try source.ownsVariable(count + 6));
    try std.testing.expect(try source.ownsRow(count));
    try std.testing.expect(!try saved.ownsVariable(count + 6));
    try std.testing.expect(!try saved.ownsRow(count));
    source.popGeneric();
    try std.testing.expect(!try source.ownsVariable(count + 6));
    try std.testing.expect(!try source.ownsRow(count));
    try source.pushGeneric(nested);
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, source.ownsVariable(count + 6));
    try std.testing.expect(!source.scheme_membership_valid);
    source = saved;
    remaining = 65_536;
    try std.testing.expect(!try source.ownsVariable(count + 6));
    try std.testing.expect(!try source.ownsRow(count));
    var portable: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try portable.initialize();
    try std.testing.expectError(error.InvalidArtifact, portable.generic(scheme));
    try std.testing.expectEqual(@as(usize, 0), portable.scheme_count);
    extra[1] = extra[0];
    try std.testing.expectError(error.InvalidArtifact, source.pushGeneric(scheme));
    try std.testing.expectEqual(@as(usize, 1), source.scheme_count);
    extra[1] = 7;
    extra[count + 1] = extra[count];
    try std.testing.expectError(error.InvalidArtifact, source.pushGeneric(scheme));
    try std.testing.expectEqual(@as(usize, 1), source.scheme_count);
    extra[count + 1] = 1;
    nodes[6] = .{ .tag = .u32 };
    try std.testing.expectError(error.InvalidArtifact, source.pushGeneric(scheme));
    try std.testing.expectEqual(@as(usize, 1), source.scheme_count);
    nodes[6] = .{ .tag = .variable };
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, source.pushGeneric(scheme));
    try std.testing.expectEqual(@as(usize, 1), source.scheme_count);
}

test "generalized alias row parameters retain exact witnesses before body closure views" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },                           .{ .tag = .unit },                             .{ .tag = .boolean },                          .{ .tag = .u32 },                              .{ .tag = .f32 },                    .{ .tag = .never },
        .{ .tag = .function, .a = 1, .b = 1, .c = 1 }, .{ .tag = .function, .a = 1, .b = 1, .c = 2 }, .{ .tag = .function, .a = 1, .b = 1, .c = 0 }, .{ .tag = .function, .a = 1, .b = 1, .c = 3 }, .{ .tag = .record, .a = 1, .b = 2 }, .{ .tag = .record, .a = 5, .b = 2 },
        .{ .tag = .record, .a = 9, .b = 2 },           .{ .tag = .record, .a = 13, .b = 2 },
    };
    // A partial factory's implementation closed carrier 0, while the
    // resulting declaration generalized that same carrier as an endpoint.
    var extra = [_]T.Id{ 0, 100, 6, 101, 6, 100, 7, 101, 7, 100, 7, 101, 8, 100, 9, 101, 8 };
    var labels = [_]T.Effects.Label{T.foreign_operation};
    var rows = [_]T.Effects.Row{ .{}, .{ .tail = .{ .variable = 0 } }, .{ .tail = .{ .variable = 1 } }, .{ .labels = .{ .len = 1 } } };
    var operations = [_]T.Operation{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows, .labels = &labels, .variable_count = 2 }, .operations = &operations };
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try context.initialize();
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining, .views = &context, .foreign_views = true, .left_rows = .{ .len = 1 } };
    const scheme: T.Scheme = .{ .root = 10, .row_variables = .{ .len = 1 } };
    try proof.instantiateScheme(scheme, 11);
    try std.testing.expectEqual(@as(T.Effects.Id, 2), proof.scheme_row_witnesses[0].?.row);
    try std.testing.expect(!context.closed_rows.contains(2) and !context.pure_rows.contains(2));
    // Repeated occurrences retain one exact choice: neither an unrelated
    // inference tail nor Foreign may be silently collapsed to a pure row.
    try std.testing.expectError(error.InvalidArtifact, proof.instantiateScheme(scheme, 12));
    try std.testing.expectError(error.InvalidArtifact, proof.instantiateScheme(scheme, 13));
}

test "repeated callback witnesses compare exact immutable row aliases without granting purity" {
    var nodes = [_]T.Node{
        .{ .tag = .absent },                           .{ .tag = .unit },                             .{ .tag = .boolean },                          .{ .tag = .u32 },                              .{ .tag = .f32 }, .{ .tag = .never },
        .{ .tag = .function, .a = 3, .b = 1, .c = 1 }, .{ .tag = .function, .a = 3, .b = 1, .c = 2 }, .{ .tag = .function, .a = 3, .b = 1, .c = 3 }, .{ .tag = .function, .a = 3, .b = 1, .c = 4 },
    };
    var extra = [_]T.Id{};
    var labels = [_]T.Effects.Label{T.foreign_operation};
    var rows = [_]T.Effects.Row{ .{}, .{ .tail = .{ .variable = 0 } }, .{ .tail = .{ .variable = 0 } }, .{ .tail = .{ .variable = 1 } }, .{ .labels = .{ .len = 1 }, .tail = .{ .variable = 0 } } };
    var operations = [_]T.Operation{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } };
    var graph: core.Types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows, .labels = &labels, .variable_count = 2 }, .operations = &operations };
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &graph, .remaining = &remaining };
    try context.initialize();
    var proof: contracts.Principal = .{ .left = &graph, .right = &graph, .remaining = &remaining, .views = &context };
    try proof.validate(6, 7);
    try std.testing.expect(!context.closed_rows.contains(1) and !context.closed_rows.contains(2));
    try std.testing.expect(!context.pure_rows.contains(1) and !context.pure_rows.contains(2));
    try std.testing.expectError(error.InvalidArtifact, context.visit(7));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 8));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(6, 9));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(9, 6));
    try context.pure_rows.set(1);
    try context.closed_rows.set(1);
    try proof.validate(6, 7);
    try std.testing.expect(context.pure_rows.contains(2) and context.closed_rows.contains(2));
}

test "source instance ownership survives solver copying without thawing types or effects" {
    const Equations = @import("scheme_equations.zig");
    var nodes = [_]T.Node{
        .{ .tag = .absent },           .{ .tag = .unit },             .{ .tag = .boolean },                          .{ .tag = .u32 },                              .{ .tag = .f32 },                              .{ .tag = .never },
        .{ .tag = .variable, .a = 0 }, .{ .tag = .variable, .a = 1 }, .{ .tag = .function, .a = 3, .b = 1, .c = 1 }, .{ .tag = .function, .a = 3, .b = 1, .c = 2 }, .{ .tag = .function, .a = 3, .b = 1, .c = 3 },
    };
    var extra = [_]T.Id{};
    var labels = [_]T.Effects.Label{T.foreign_operation};
    var rows = [_]T.Effects.Row{ .{}, .{ .tail = .{ .variable = 0 } }, .{ .tail = .{ .variable = 1 } }, .{ .labels = .{ .len = 1 }, .tail = .{ .variable = 0 } } };
    var operations = [_]T.Operation{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } };
    const module: core.Module = .{
        .types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows, .labels = &labels, .variable_count = 2 }, .operations = &operations },
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    var remaining: usize = 65_536;
    var context: contracts.Context = .{ .types = &module.types, .remaining = &remaining, .source_instances = true };
    try context.initialize();
    try context.instance_variables.set(6);
    try context.instance_rows.set(0);
    var solver = try Equations.Solver.init(std.testing.allocator, &module, &context, &remaining);
    defer solver.deinit();
    try std.testing.expect(solver.ownsRigid(solver.graph.node(6)));
    try std.testing.expect(!solver.ownsRigid(solver.graph.node(7)));
    const owned_row = solver.graph.row(1).tail.formal;
    const unowned_row = solver.graph.row(2).tail.formal;
    try std.testing.expect(solver.ownsRigid(solver.graph.node(owned_row)));
    try std.testing.expect(!solver.ownsRigid(solver.graph.node(unowned_row)));
    var foreign_identity = solver.graph.node(owned_row);
    foreign_identity.a += 1;
    try std.testing.expect(!solver.ownsRigid(foreign_identity));
    var inquiry = context;
    inquiry.types = &solver.graph;
    inquiry.solver = &solver;
    try inquiry.visit(8);
    try std.testing.expectError(error.InvalidArtifact, inquiry.visit(9));
    var proof: contracts.Principal = .{ .left = &solver.graph, .right = &solver.graph, .remaining = &remaining, .views = &inquiry };
    try proof.validate(owned_row, owned_row);
    try std.testing.expectError(error.InvalidArtifact, proof.validate(8, 10));
    try std.testing.expectError(error.InvalidArtifact, proof.validate(10, 8));
    try std.testing.expectError(error.InvalidArtifact, solver.unify(6, T.f32_type));
    try std.testing.expect(!inquiry.pure_rows.contains(1) and !inquiry.closed_rows.contains(1));
    var portable = context;
    portable.source_instances = false;
    var rejected = try Equations.Solver.init(std.testing.allocator, &module, &portable, &remaining);
    defer rejected.deinit();
    try std.testing.expect(!rejected.ownsRigid(rejected.graph.node(6)));
    try std.testing.expect(!rejected.ownsRigid(rejected.graph.node(rejected.graph.row(1).tail.formal)));
}

// These helpers borrow the caller's temporary graph buffers only for one
// synchronous proof. The owned module never stores those temporary buffers.
fn rejectMergeRows(module: *const core.Module, binding: core.BindingId, callback_type: T.Id, rows: []T.Effects.Row, allocator: std.mem.Allocator) !void {
    var inquiry = module.*;
    inquiry.types.effects.rows = rows;
    inquiry.types.effects.variable_count += 1;
    const callback = inquiry.types.nodes[callback_type];
    defer inquiry.types.nodes[callback_type] = callback;
    inquiry.types.nodes[callback_type].c = @intCast(rows.len - 1);
    var remaining: usize = 1_000_000;
    try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").checkedInterfaceBody(&inquiry, binding, .{}, &remaining, allocator));
}
fn rejectMergeField(module: *const core.Module, binding: core.BindingId, nodes: []T.Node, extra: []u32, allocator: std.mem.Allocator) !void {
    var inquiry = module.*;
    inquiry.types.nodes = nodes;
    inquiry.types.extra = extra;
    var found = false;
    for (inquiry.nodes) |*node| if (node.tag == .record_merge) {
        const saved = node.ty;
        defer node.ty = saved;
        node.ty = @intCast(nodes.len - 1);
        var remaining: usize = 1_000_000;
        try std.testing.expectError(error.InvalidArtifact, @import("package_core.zig").checkedInterfaceBody(&inquiry, binding, .{}, &remaining, allocator));
        found = true;
    };
    try std.testing.expect(found);
}

fn mergeSelectionScenario(allocator: std.mem.Allocator) !void {
    var module = try lowerSource(allocator,
        \\type Access = {callback: U32 -> Unit ! {}}
        \\const merge = func (base: Access): Access => return @record.merge base {}
    );
    defer module.deinit(allocator);
    var binding: core.BindingId = 0;
    for (module.bodies) |body| if (std.mem.eql(u8, module.name(body.declaration_name), "merge")) {
        binding = body.binding;
    };
    try std.testing.expect(binding != 0);
    var remaining: usize = 1_000_000;
    try @import("package_core.zig").checkedInterfaceBody(&module, binding, .{}, &remaining, allocator);
    const function = module.types.node(module.binding(binding).ty);
    const access = module.types.node(function.a);
    try std.testing.expectEqual(T.Tag.record, access.tag);
    const field = module.types.recordField(access, 0);
    const callback = module.types.nodes[field.ty];
    try std.testing.expectEqual(T.Tag.function, callback.tag);
    // Exact merge field identity must not admit an unowned callback row at
    // the independent executable header/input/output boundary.
    const original_effects = module.types.effects;
    const expanded_rows = try allocator.alloc(T.Effects.Row, original_effects.rows.len + 1);
    defer allocator.free(expanded_rows);
    @memcpy(expanded_rows[0..original_effects.rows.len], original_effects.rows);
    expanded_rows[original_effects.rows.len] = .{ .tail = .{ .variable = original_effects.variable_count } };
    try rejectMergeRows(&module, binding, field.ty, expanded_rows, allocator);
    // A forged result record cannot substitute a numeric field for the
    // selected callback field, even though its name and record width match.
    const original_types = module.types;
    const expanded_nodes = try allocator.alloc(T.Node, original_types.nodes.len + 1);
    defer allocator.free(expanded_nodes);
    @memcpy(expanded_nodes[0..original_types.nodes.len], original_types.nodes);
    const expanded_extra = try allocator.alloc(u32, original_types.extra.len + 2);
    defer allocator.free(expanded_extra);
    @memcpy(expanded_extra[0..original_types.extra.len], original_types.extra);
    expanded_extra[original_types.extra.len] = field.name;
    expanded_extra[original_types.extra.len + 1] = T.u32_type;
    expanded_nodes[original_types.nodes.len] = .{ .tag = .record, .a = @intCast(original_types.extra.len), .b = 1 };
    try rejectMergeField(&module, binding, expanded_nodes, expanded_extra, allocator);
}
test "record merge selection identity does not admit unknown callback rows or forged fields" {
    try mergeSelectionScenario(std.testing.allocator);
}
