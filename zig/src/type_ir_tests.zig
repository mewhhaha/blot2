//! Differential gates for the native type stage. Oracle functions and their
//! transitive calls use the unchanged source algorithms, not native overrides.
const std = @import("std");
const r = @import("runtime.zig");
const bridge = @import("type_bridge.zig");
const core = @import("generated/functions.zig");
const V = r.Value;
const Pair = struct { a: V, b: V };

fn equal(a: V, b: V) !void {
    var work: std.ArrayList(Pair) = .empty;
    defer work.deinit(std.testing.allocator);
    try work.append(std.testing.allocator, .{ .a = a, .b = b });
    while (work.pop()) |p| {
        if (p.a == p.b) continue;
        if (p.a >> 48 < 4 or p.b >> 48 < 4) {
            try std.testing.expectEqual(p.a, p.b);
            continue;
        }
        const tag = r.tag(p.a);
        try std.testing.expectEqual(tag, r.tag(p.b));
        if (tag == .SCon or tag == .SNil) {
            try std.testing.expect(r.stringEqual(p.a, p.b));
            continue;
        }
        const count: usize = switch (tag) {
            .Done, .Fail, .model_VariableTy, .model_ParameterTy, .model_ArrayTy, .model_ProductTy, .model_RowVariable, .model_RowParameter => 1,
            .types_ParameterKinds, .Cons, .model_TypeId, .model_FreeTy, .model_FreeRow, .model_EffectRow, .model_AppliedTy, .model_ProviderTy => 2,
            .model_FunctionTy, .model_StateProviderTy, .model_Diagnostic => 3,
            else => 0,
        };
        for (0..count) |i| try work.append(std.testing.allocator, .{ .a = r.field(p.a, i), .b = r.field(p.b, i) });
    }
}
fn list(ctx: *r.Context, values: []const V) V {
    var result = r.empty(.Nil);
    var i = values.len;
    while (i > 0) {
        i -= 1;
        result = ctx.node(.Cons, &.{ values[i], result });
    }
    return result;
}
fn variable(ctx: *r.Context, id: u64) V {
    return ctx.node(.model_VariableTy, &.{r.nat(id)});
}
fn name(ctx: *r.Context, text: V) V {
    return ctx.node(.model_TypeId, &.{ r.literal("tests😀"), text });
}
fn row(ctx: *r.Context, labels: []const V, tail: V) V {
    return ctx.node(.model_EffectRow, &.{ list(ctx, labels), tail });
}
fn valueBinding(ctx: *r.Context, id: u64, ty: V) V {
    return ctx.node(.types_Substitution, &.{ r.nat(id), ty });
}
fn rowBinding(ctx: *r.Context, id: u64, value: V) V {
    return ctx.node(.types_RowSubstitution, &.{ r.nat(id), value });
}
fn substitutions(ctx: *r.Context, values: []const V) V {
    return ctx.call(core.oracle_types_from_list, &.{list(ctx, values)});
}
fn compareResolve(ctx: *r.Context, subs: V, fuel: u64, work: V) !void {
    const args = [_]V{ subs, r.nat(fuel), work };
    const expected = ctx.call(core.oracle_types_resolve_work_reference, &args);
    const actual = bridge.resolveWork(ctx, &args);
    try equal(expected, actual);
}
fn compareRewrite(ctx: *r.Context, fuel: u64, work: V, replacement: V) !void {
    const args = [_]V{ r.nat(fuel), work, replacement };
    try equal(ctx.call(core.oracle_types_rewrite, &args), bridge.rewrite(ctx, &args));
}

test "typed resolution covers every type and tail with exact fuel and label order" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const a = variable(&ctx, 0);
    const b = variable(&ctx, 1);
    const get = name(&ctx, r.literal("get"));
    const put = name(&ctx, r.literal("put"));
    const open = row(&ctx, &.{ get, get }, ctx.node(.model_RowVariable, &.{r.nat(20)}));
    const generic = row(&ctx, &.{get}, ctx.node(.model_RowParameter, &.{r.nat(20)}));
    const free = row(&ctx, &.{put}, ctx.node(.model_FreeRow, &.{ r.literal("scope"), r.literal("e") }));
    const closed = row(&ctx, &.{get}, r.empty(.model_ClosedRow));
    const types = [_]V{
        r.empty(.model_UnitTy),                                        r.empty(.model_U32Ty),                                             r.empty(.model_BoolTy),                          r.empty(.model_NeverTy),
        r.empty(.model_F32Ty),                                         r.empty(.model_EffectDescriptorTy),                                r.empty(.model_EffectSetTy),                     a,
        ctx.node(.model_ParameterTy, &.{r.nat(0xffffffffffff)}),       ctx.node(.model_FreeTy, &.{ r.literal("scope"), r.literal("a") }), ctx.node(.model_ArrayTy, &.{a}),                 ctx.node(.model_ProductTy, &.{list(&ctx, &.{ a, b })}),
        ctx.node(.model_AppliedTy, &.{ get, list(&ctx, &.{ a, b }) }), ctx.node(.model_FunctionTy, &.{ a, b, open }),                     ctx.node(.model_ProviderTy, &.{ get, generic }), ctx.node(.model_ProviderTy, &.{ get, free }),
        ctx.node(.model_ProviderTy, &.{ put, closed }),                ctx.node(.model_StateProviderTy, &.{ get, put, a }),
    };
    const subs = substitutions(&ctx, &.{ valueBinding(&ctx, 0, r.empty(.model_U32Ty)), valueBinding(&ctx, 1, r.empty(.model_BoolTy)), rowBinding(&ctx, 20, row(&ctx, &.{put}, ctx.node(.model_RowVariable, &.{r.nat(21)}))), rowBinding(&ctx, 21, closed) });
    for (types) |ty| {
        for ([_]u64{ 0, 1, 2, 3, 8, 64 }) |fuel| try compareResolve(&ctx, subs, fuel, ctx.node(.types_OneType, &.{ty}));
        try equal(r.field(ctx.call(core.oracle_types_resolve_work_reference, &.{ subs, r.nat(65536), ctx.node(.types_OneType, &.{ty}) }), 0), ctx.node(.Cons, &.{ r.field(bridge.resolveType(&ctx, &.{ subs, ty }), 0), r.empty(.Nil) }));
    }
    for ([_]u64{ 0, 1, 2, 3, 8, 64 }) |fuel| try compareResolve(&ctx, subs, fuel, ctx.node(.types_ManyTypes, &.{list(&ctx, &types)}));
    try compareResolve(&ctx, substitutions(&ctx, &.{}), 0, ctx.node(.types_ManyTypes, &.{list(&ctx, &types)}));
}

test "chronological aliases and inserted self references only see later bindings" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const a = variable(&ctx, 0);
    const b = variable(&ctx, 1);
    const u32_type = r.empty(.model_U32Ty);
    const bool_type = r.empty(.model_BoolTy);
    const work = ctx.node(.types_ManyTypes, &.{list(&ctx, &.{ a, b, ctx.node(.model_FunctionTy, &.{ a, b, row(&ctx, &.{}, r.empty(.model_ClosedRow)) }) })});
    const histories = [_][]const V{
        &.{valueBinding(&ctx, 0, a)},
        &.{ valueBinding(&ctx, 0, b), valueBinding(&ctx, 1, a) },
        &.{ valueBinding(&ctx, 1, u32_type), valueBinding(&ctx, 0, b) },
        &.{ valueBinding(&ctx, 0, b), valueBinding(&ctx, 0, bool_type), valueBinding(&ctx, 1, u32_type) },
        &.{valueBinding(&ctx, 0, ctx.node(.model_ArrayTy, &.{a}))},
    };
    for (histories) |history| {
        const s = substitutions(&ctx, history);
        for ([_]u64{ 0, 1, 2, 3, 16, 64 }) |fuel| try compareResolve(&ctx, s, fuel, work);
    }
    const early = substitutions(&ctx, histories[2]);
    try equal(ctx.node(.Done, &.{b}), bridge.resolveType(&ctx, &.{ early, a }));
    // Revisit an older immutable snapshot after a newer resolution populated
    // the memo table; neither revision may borrow the other's answer.
    const first = substitutions(&ctx, &.{valueBinding(&ctx, 0, u32_type)});
    const second = substitutions(&ctx, &.{valueBinding(&ctx, 0, bool_type)});
    try equal(ctx.node(.Done, &.{u32_type}), bridge.resolveType(&ctx, &.{ first, a }));
    try equal(ctx.node(.Done, &.{bool_type}), bridge.resolveType(&ctx, &.{ second, a }));
    try equal(ctx.node(.Done, &.{u32_type}), bridge.resolveType(&ctx, &.{ first, a }));
}

test "replacement and renaming cover free names, parameter kinds and error precedence" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const a = variable(&ctx, 0);
    const parameter = ctx.node(.model_ParameterTy, &.{r.nat(0)});
    const free_type = ctx.node(.model_FreeTy, &.{ r.literal("scope"), r.literal("a") });
    const tails = [_]V{ r.empty(.model_ClosedRow), ctx.node(.model_RowVariable, &.{r.nat(0)}), ctx.node(.model_RowParameter, &.{r.nat(0)}), ctx.node(.model_FreeRow, &.{ r.literal("scope"), r.literal("a") }) };
    const map = ctx.node(.nat_index_Leaf, &.{ r.nat(0), r.nat(0xffffffffffff) });
    const replacements = [_]V{
        ctx.node(.types_ReplaceVariable, &.{ r.nat(0), r.empty(.model_U32Ty) }),
        ctx.node(.types_ReplaceVariable, &.{ r.nat(0), parameter }),
        ctx.node(.types_ReplaceParameter, &.{ r.nat(0), a }),
        ctx.node(.types_ReplaceParameter, &.{ r.nat(0), r.empty(.model_BoolTy) }),
        ctx.node(.types_FreshParameters, &.{map}),
        ctx.node(.types_ReplaceFree, &.{ r.literal("scope"), r.literal("a"), parameter }),
        ctx.node(.types_ReplaceFree, &.{ r.literal("scope"), r.literal("a"), free_type }),
        ctx.node(.types_RelocateFree, &.{r.literal("😀suffix")}),
    };
    for (tails) |tail| {
        const function = ctx.node(.model_FunctionTy, &.{ a, ctx.node(.model_ProductTy, &.{list(&ctx, &.{ parameter, free_type })}), row(&ctx, &.{ name(&ctx, r.literal("get")), name(&ctx, r.literal("get")) }, tail) });
        const work = ctx.node(.types_OneType, &.{function});
        for (replacements) |rep| for ([_]u64{ 0, 1, 2, 3, 4, 16 }) |fuel| try compareRewrite(&ctx, fuel, work, rep);
        for ([_]V{ r.empty(.types_FreshVariables), r.empty(.types_SchemeParameters) }) |kind| for ([_]u64{ 0, 1, 2, 3, 4, 16 }) |fuel| {
            const args = [_]V{ r.nat(fuel), work, map, kind };
            try equal(ctx.call(core.oracle_types_rename_work, &args), bridge.rename(&ctx, &args));
        };
    }
}

fn randomRow(ctx: *r.Context, rng: std.Random) V {
    const label = name(ctx, if (rng.boolean()) r.literal("get") else r.literal("put"));
    const labels: [3]V = .{ label, label, name(ctx, r.literal("different")) };
    const tail = switch (rng.uintLessThan(u8, 4)) {
        0 => r.empty(.model_ClosedRow),
        1 => ctx.node(.model_RowVariable, &.{r.nat(20 + rng.uintLessThan(u8, 2))}),
        2 => ctx.node(.model_RowParameter, &.{r.nat(rng.uintLessThan(u8, 4))}),
        else => ctx.node(.model_FreeRow, &.{ r.literal("scope"), r.literal("a") }),
    };
    return row(ctx, labels[0..rng.uintLessThan(usize, 4)], tail);
}
fn randomType(ctx: *r.Context, rng: std.Random, depth: u8) V {
    const kind = rng.uintLessThan(u8, if (depth == 0) 10 else 16);
    return switch (kind) {
        0 => r.empty(.model_UnitTy),
        1 => r.empty(.model_U32Ty),
        2 => r.empty(.model_BoolTy),
        3 => r.empty(.model_F32Ty),
        4 => r.empty(.model_NeverTy),
        5 => r.empty(.model_EffectDescriptorTy),
        6 => r.empty(.model_EffectSetTy),
        7 => variable(ctx, rng.uintLessThan(u8, 4)),
        8 => ctx.node(.model_ParameterTy, &.{r.nat(rng.uintLessThan(u8, 4))}),
        9 => ctx.node(.model_FreeTy, &.{ r.literal("scope"), if (rng.boolean()) r.literal("a") else r.literal("b") }),
        10 => ctx.node(.model_ArrayTy, &.{randomType(ctx, rng, depth - 1)}),
        11 => ctx.node(.model_ProductTy, &.{list(ctx, &.{ randomType(ctx, rng, depth - 1), randomType(ctx, rng, depth - 1) })}),
        12 => ctx.node(.model_AppliedTy, &.{ name(ctx, r.literal("Box")), list(ctx, &.{randomType(ctx, rng, depth - 1)}) }),
        13 => ctx.node(.model_FunctionTy, &.{ randomType(ctx, rng, depth - 1), randomType(ctx, rng, depth - 1), randomRow(ctx, rng) }),
        14 => ctx.node(.model_ProviderTy, &.{ name(ctx, r.literal("Store")), randomRow(ctx, rng) }),
        else => ctx.node(.model_StateProviderTy, &.{ name(ctx, r.literal("read")), name(ctx, r.literal("write")), randomType(ctx, rng, depth - 1) }),
    };
}

test "seeded mixed histories agree with independent generated source algorithms" {
    var random = std.Random.DefaultPrng.init(0x747970656972);
    const rng = random.random();
    for (0..240) |_| {
        var ctx = r.Context.init(std.testing.allocator);
        defer ctx.deinit();
        var history: [6]V = undefined;
        for (&history) |*binding| binding.* = if (rng.boolean()) valueBinding(&ctx, rng.uintLessThan(u8, 4), randomType(&ctx, rng, 2)) else rowBinding(&ctx, 20 + rng.uintLessThan(u8, 2), randomRow(&ctx, rng));
        const s = substitutions(&ctx, history[0..rng.uintLessThan(usize, 7)]);
        const ty = randomType(&ctx, rng, 4);
        const work = if (rng.boolean()) ctx.node(.types_OneType, &.{ty}) else ctx.node(.types_ManyTypes, &.{list(&ctx, &.{ ty, ty, randomType(&ctx, rng, 2) })});
        for ([_]u64{ 0, 1, 2, 4, 8, 64 }) |fuel| try compareResolve(&ctx, s, fuel, work);
        const rep = ctx.node(.types_ReplaceVariable, &.{ r.nat(rng.uintLessThan(u8, 4)), randomType(&ctx, rng, 2) });
        for ([_]u64{ 1, 2, 4, 8, 64 }) |fuel| try compareRewrite(&ctx, fuel, work, rep);
        const effect = randomRow(&ctx, rng);
        for ([_]u64{ 0, 1, 3, 8 }) |cursor| {
            const args = [_]V{ s, effect, r.nat(cursor) };
            try equal(ctx.call(core.oracle_types_resolve_row_at, &args), bridge.resolveRowAt(&ctx, &args));
        }
    }
}

test "bridge preserves deep shared graphs and returns original unchanged types" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const a = variable(&ctx, 2);
    var deep = a;
    for (0..4096) |_| deep = ctx.node(.model_ArrayTy, &.{deep});
    const work = ctx.node(.types_OneType, &.{deep});
    const missing = ctx.node(.types_ReplaceVariable, &.{ r.nat(3), r.empty(.model_U32Ty) });
    const unchanged = bridge.rewrite(&ctx, &.{ r.nat(8192), work, missing });
    try std.testing.expectEqual(r.Tag.Done, r.tag(unchanged));
    try std.testing.expectEqual(deep, r.field(r.field(unchanged, 0), 0));
    const rep = ctx.node(.types_ReplaceVariable, &.{ r.nat(2), r.empty(.model_BoolTy) });
    const rewritten = bridge.rewrite(&ctx, &.{ r.nat(8192), work, rep });
    try std.testing.expectEqual(r.Tag.Done, r.tag(rewritten));
    var cursor = r.field(r.field(rewritten, 0), 0);
    for (0..4096) |_| {
        try std.testing.expectEqual(r.Tag.model_ArrayTy, r.tag(cursor));
        cursor = r.field(cursor, 0);
    }
    try std.testing.expectEqual(r.empty(.model_BoolTy), cursor);
    const id_count = ctx.type_state.?.store.nodes.items.len;
    _ = bridge.rewrite(&ctx, &.{ r.nat(8192), work, rep });
    try std.testing.expectEqual(id_count, ctx.type_state.?.store.nodes.items.len);
    var dag = a;
    const effects = row(&ctx, &.{}, r.empty(.model_ClosedRow));
    for (0..40) |_| dag = ctx.node(.model_FunctionTy, &.{ dag, dag, effects });
    const result = bridge.rewrite(&ctx, &.{ r.nat(100), ctx.node(.types_OneType, &.{dag}), rep });
    try std.testing.expectEqual(r.Tag.Done, r.tag(result));
    try std.testing.expectEqual(@as(usize, 41), ctx.type_state.?.store.visits);
    cursor = r.field(r.field(result, 0), 0);
    for (0..40) |_| {
        try std.testing.expectEqual(r.field(cursor, 0), r.field(cursor, 1));
        cursor = r.field(cursor, 0);
    }
    try std.testing.expectEqual(r.empty(.model_BoolTy), cursor);
}

fn compareScans(ctx: *r.Context, fuel: u64, work: V) !void {
    const args = [_]V{ r.nat(fuel), work };
    try equal(ctx.call(core.oracle_types_free_work, &args), bridge.freeVariables(ctx, &args));
    try equal(ctx.call(core.oracle_types_parameter_kinds, &args), bridge.parameterKinds(ctx, &args));
    try equal(ctx.call(core.oracle_types_annotation_names, &args), bridge.annotationNames(ctx, &args));
}
test "native type scans retain ordering, duplicate annotations and exact fuel" {
    var random = std.Random.DefaultPrng.init(0x7363616e);
    for (0..256) |_| {
        var ctx = r.Context.init(std.testing.allocator);
        defer ctx.deinit();
        const a = randomType(&ctx, random.random(), 6);
        const b = randomType(&ctx, random.random(), 4);
        const work = ctx.node(.types_ManyTypes, &.{list(&ctx, &.{ a, b, a })});
        for ([_]u64{ 128, 0, 1, 2, 3, 4, 5, 8, 12, 64 }) |fuel| {
            try compareScans(&ctx, fuel, work);
            try compareScans(&ctx, fuel, ctx.node(.types_OneType, &.{a}));
        }
    }
}
test "native type scans preserve wide identities and do not expand exhausted DAGs" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    var variables: [48]V = undefined;
    for (&variables, 0..) |*v, i| v.* = variable(&ctx, @as(u64, 1) << @as(u6, @intCast(i)));
    try compareScans(&ctx, 128, ctx.node(.types_ManyTypes, &.{list(&ctx, &variables)}));
    const empty_row = row(&ctx, &.{}, r.empty(.model_ClosedRow));
    var dag = ctx.node(.model_FreeTy, &.{ r.literal("😀"), r.literal("a") });
    for (0..48) |_| dag = ctx.node(.model_FunctionTy, &.{ dag, dag, empty_row });
    const args = [_]V{ r.nat(2), ctx.node(.types_OneType, &.{dag}) };
    const actual = bridge.annotationNames(&ctx, &args);
    try std.testing.expectEqual(r.Tag.Fail, r.tag(actual));
    try equal(ctx.call(core.oracle_types_annotation_names, &args), actual);
    var chain = variable(&ctx, 0xffffffffffff);
    for (0..4096) |_| chain = ctx.node(.model_ArrayTy, &.{chain});
    const before = ctx.type_state.?.scans.visits;
    const result = bridge.freeVariables(&ctx, &.{ r.nat(8192), ctx.node(.types_OneType, &.{chain}) });
    try std.testing.expectEqual(r.Tag.Done, r.tag(result));
    try std.testing.expectEqual(r.nat(0xffffffffffff), r.field(r.field(result, 0), 0));
    const after = ctx.type_state.?.scans.visits;
    try std.testing.expect(after - before <= 4097);
    _ = bridge.freeVariables(&ctx, &.{ r.nat(8192), ctx.node(.types_OneType, &.{chain}) });
    try std.testing.expectEqual(after, ctx.type_state.?.scans.visits);
}
