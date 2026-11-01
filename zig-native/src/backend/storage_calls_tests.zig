const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;
test {
    _ = @import("scoped_opaque_tests.zig");
    _ = @import("storage_selected_fields_tests.zig");
    _ = @import("storage_assembly_options_tests.zig");
    _ = @import("storage_typed_closure_tests.zig");
}
fn publishSmallModule(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compileWithOptions(allocator, modules, 1, .{ .work_limits = .{ .expressions = 512 } });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
fn publishRefinedModule(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_refinement_indexed_bindings > 0);
}
fn publishSharedScalarModule(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 4), result.counters.scoped_scalar_definitions);
    try std.testing.expect(result.counters.scoped_scalar_cache_hits >= 2);
}
fn publishConcreteFields(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    // Both source field orders share each of read, twice and outer once.
    // The strict semantic key retains their symbolic ambient row identities.
    try std.testing.expectEqual(@as(u64, 3), result.counters.scoped_inline_definitions);
    try std.testing.expect(result.counters.scoped_inline_cache_hits >= 3);
    try std.testing.expect(result.counters.scoped_concrete_admission_hits > 0);
    try std.testing.expect(result.counters.scoped_field_recipe_hits > 0);
    try std.testing.expect(result.counters.scoped_field_name_probes < 32);
}
test "concrete anonymous field instances share body plans through allocation failures" {
    var module = try lower(a,
        \\const read = func row => return @u32.add row.left row.right
        \\const twice = func row => return @u32.add (read row) (read row)
        \\const outer = func row => return @u32.add (twice row) (twice row)
        \\entry const answer = func (input: U32): U32 => return do:
        \\  let marker: GrowArray U32 = #[input]
        \\  let first = outer {right: 3, left: marker[0]}
        \\  let second = outer {left: marker[0], right: 5}
        \\  return @u32.add first second
    );
    defer module.deinit(a);
    try publishConcreteFields(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishConcreteFields, .{@as([]const core.Module, &.{module})});
}
test "concrete field recipes retain declaration types order absence and capacity fallback" {
    var module = try lower(a,
        \\const first = {left: 1, right: 2}
        \\const second = {extra: 0.0, left: 1.0, right: 2.0}
        \\const third = {missing: 0}
        \\entry const answer = func () => return 0
    );
    defer module.deinit(a);
    var first: @import("../check/types.zig").Id = 0;
    var second: @import("../check/types.zig").Id = 0;
    var missing: u32 = 0;
    var left: u32 = 0;
    for (module.bodies) |body| {
        const name = module.name(body.declaration_name);
        const ty = module.typeOf(body.root);
        if (std.mem.eql(u8, name, "first")) first = ty;
        if (std.mem.eql(u8, name, "second")) second = ty;
        if (std.mem.eql(u8, name, "third")) missing = module.types.recordField(module.types.node(ty), 0).name;
    }
    for (0..module.types.node(first).b) |index| {
        const field = module.types.recordField(module.types.node(first), index);
        if (std.mem.eql(u8, module.fieldSpelling(field.name).?, "left")) left = field.name;
    }
    var cache: @import("storage_field_plan.zig").Cache = .{ .allocator = a };
    defer cache.deinit();
    const integer = (try cache.get(&module, left, &module, first)).?;
    const floating = (try cache.get(&module, left, &module, second)).?;
    try std.testing.expectEqual(@import("../check/types.zig").u32_type, integer.ty);
    try std.testing.expectEqual(@import("../check/types.zig").f32_type, floating.ty);
    try std.testing.expectEqual(left, module.types.recordField(module.types.node(first), integer.index).name);
    try std.testing.expectEqual(left, module.types.recordField(module.types.node(second), floating.index).name);
    try std.testing.expect(try cache.get(&module, missing, &module, first) == null);
    const probes = cache.probes;
    try std.testing.expect(try cache.get(&module, missing, &module, first) == null);
    try std.testing.expectEqual(probes, cache.probes);
    try std.testing.expect(cache.hits > 0);
    var uncached: @import("storage_field_plan.zig").Cache = .{ .allocator = a, .maximum_entries = 0 };
    defer uncached.deinit();
    try std.testing.expectEqual(integer, (try uncached.get(&module, left, &module, first)).?);
    try std.testing.expectEqual(@as(u64, 0), uncached.hits);
}
test "nested scalar call definitions share diamonds across exports" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const level0 = func (input: U32): U32 => return @u32.add input 1\n");
    const depth = 10;
    for (1..depth + 1) |level| {
        const definition = try a.print("const level{d} = func (input: U32): U32 => return level{d} (level{d} input)\n", .{ level, level - 1, level - 1 });
        defer a.free(definition);
        try source.appendSlice(a, definition);
    }
    try source.appendSlice(a, "entry const first = func (input: U32): U32 => return level10 input\n" ++
        "entry const second = func (input: U32): U32 => return level10 input\n");
    var module = try lower(a, source.items);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, depth + 3), result.counters.scoped_scalar_definitions);
    try std.testing.expect(result.counters.scoped_scalar_cache_hits >= depth + 1);
    try std.testing.expect(result.counters.scoped_emission_expressions < 300);
    try std.testing.expect(result.counters.scoped_scalar_admission_nodes < 600);
    try std.testing.expect(result.counters.scoped_call_admission_nodes == 0);
}
test "nested scalar call publication survives allocation failures" {
    var module = try lower(a,
        \\const leaf = func (input: U32): U32 => return @u32.add input 1
        \\const twice = func (input: U32): U32 => return leaf (leaf input)
        \\const four = func (input: U32): U32 => return twice (twice input)
        \\entry const answer = func (input: U32): U32 => return four input
    );
    defer module.deinit(a);
    try publishSharedScalarModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSharedScalarModule, .{@as([]const core.Module, &.{module})});
}
test "closed scalar admission retains only completed bounded call graphs" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const level0 = func (input: U32): U32 => return @u32.add input 1\n" ++
        "const declined = func (input: U32): U32 => return do:\n" ++
        "  let first = level0 input\n  let rows: GrowArray U32 = #[first]\n  return rows[0]\n" ++
        "const cycle = func (input: U32): U32 => return cycle input\n" ++
        "const generic = func input => return input\n");
    for (1..81) |level| {
        const definition = try a.print("const level{d} = func (input: U32): U32 => return level{d} input\n", .{ level, level - 1 });
        defer a.free(definition);
        try source.appendSlice(a, definition);
    }
    var module = try lower(a, source.items);
    defer module.deinit(a);
    var graph: @import("storage_calls.zig").ScalarAdmission = .{ .allocator = a, .units = &.{module} };
    defer graph.deinit();
    var fresh: @import("storage_calls.zig").ScalarAdmission = .{ .allocator = a, .units = &.{module} };
    defer fresh.deinit();
    var leaf: core.BindingId = 0;
    var shallow: core.BindingId = 0;
    var deep: core.BindingId = 0;
    for (module.bodies) |body| {
        const name = module.name(body.declaration_name);
        if (std.mem.eql(u8, name, "level0")) leaf = body.binding;
        if (std.mem.eql(u8, name, "level10")) shallow = body.binding;
        if (std.mem.eql(u8, name, "level80")) deep = body.binding;
        if (!std.mem.eql(u8, name, "declined") and !std.mem.eql(u8, name, "cycle") and !std.mem.eql(u8, name, "generic")) continue;
        var remaining: usize = 100_000;
        try std.testing.expect(!try graph.admit(&module, body.binding, &remaining));
        try std.testing.expect(!graph.completed.contains(.{ .unit = 1, .binding = body.binding }));
        try std.testing.expectEqual(@as(usize, 0), graph.len);
    }
    try std.testing.expect(leaf != 0 and shallow != 0 and deep != 0);
    try std.testing.expect(graph.completed.contains(.{ .unit = 1, .binding = leaf }));
    var remaining: usize = 100_000;
    try std.testing.expect(try graph.admit(&module, shallow, &remaining));
    remaining = 100_000;
    try std.testing.expect(!try graph.admit(&module, deep, &remaining));
    remaining = 100_000;
    try std.testing.expect(!try fresh.admit(&module, deep, &remaining));
    try std.testing.expect(!graph.completed.contains(.{ .unit = 1, .binding = deep }));
    remaining = 0;
    try std.testing.expect(!try graph.admit(&module, shallow, &remaining));

    // Inferred zero rows retain exact declaration-owned certificates. A new
    // inventory cannot borrow those certificates from a previously warm memo.
    var uncertified = module;
    const bindings = try a.dupe(core.Binding, module.bindings);
    defer a.free(bindings);
    uncertified.bindings = bindings;
    bindings[shallow].scheme.closed_rows = .{};
    var missing: @import("storage_calls.zig").ScalarAdmission = .{ .allocator = a, .units = &.{uncertified} };
    defer missing.deinit();
    remaining = 100_000;
    try std.testing.expect(!try missing.admit(&uncertified, shallow, &remaining));

    var effectful = module;
    const rows = try a.dupe(@import("../check/types.zig").Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    const labels = try a.alloc(@import("../check/types.zig").Effects.Label, module.types.effects.labels.len + 1);
    defer a.free(labels);
    @memcpy(labels[0..module.types.effects.labels.len], module.types.effects.labels);
    labels[labels.len - 1] = @import("../check/types.zig").foreign_operation;
    const arrow = module.types.node(module.binding(leaf).ty);
    rows[arrow.c].labels = .{ .start = @intCast(labels.len - 1), .len = 1 };
    effectful.types.effects.rows = rows;
    effectful.types.effects.labels = labels;
    var foreign: @import("storage_calls.zig").ScalarAdmission = .{ .allocator = a, .units = &.{effectful} };
    defer foreign.deinit();
    remaining = 100_000;
    try std.testing.expect(!try foreign.admit(&effectful, leaf, &remaining));
}
test "scoped contract methods select checked scalar witnesses through allocation failures" {
    var module = try lower(a,
        \\type Render a is contract = {const render: a -> U32}
        \\impl Number : Render U32 = {const render = func value => return @u32.add value 7}
        \\entry const answer = func (count: U32): Array U32 => return do:
        \\  let output: GrowArray U32 = #[]
        \\  for index in 0 .. count:
        \\    @storage.push output (Render.render index)
        \\  return @storage.freeze output
    );
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "reusable scalar and writer key equality retains distinct implementation contexts" {
    const calls = @import("storage_calls.zig");
    var cache: calls.Cache = .{ .allocator = a };
    defer cache.deinit();
    const left: calls.Key = .{ .unit = 1, .binding = 2, .context = 3, .evidence = &.{ 7, 11, 13 } };
    var right = left;
    right.context = 4;
    try std.testing.expect(!left.eql(right));
    const first = try cache.insert(left, 31, false);
    try std.testing.expect(cache.find(right) == null);
    const second = try cache.insert(right, 32, false);
    try std.testing.expectEqual(first, cache.find(left).?);
    try std.testing.expectEqual(second, cache.find(right).?);
    try std.testing.expectEqual(@as(u32, 31), cache.entries.items[cache.find(left).?].function);
    try std.testing.expectEqual(@as(u32, 32), cache.entries.items[cache.find(right).?].function);
}
test "loop header inline variants publish across entry backedge and continue allocation failures" {
    var module = try lower(a, "type Maybe a is data = $Some a | $Nothing\n" ++
        "entry const trace = func (count: U32): Array U32 => return do:\n" ++
        "  let state: {best: Maybe (Maybe U32), visits: U32} = {best: $Some $Nothing, visits: 0}\n" ++
        "  let observations: GrowArray U32 = #[]\n" ++
        "  for index in 0 .. count:\n" ++
        "    if let $Some value = state.best:\n" ++
        "      if let $Some previous = value:\n" ++
        "        @storage.push observations previous\n" ++
        "        state.best := $Nothing\n" ++
        "        continue\n" ++
        "      state.best := $Some ($Some index)\n" ++
        "    else:\n" ++
        "      state.best := $Some $Nothing\n" ++
        "    @storage.push observations index\n" ++
        "  return @storage.freeze observations\n" ++
        "entry const borrowed = func (count: U32): Array U32 => return do:\n" ++
        "  let labels: Array U32 = #[7]\n" ++
        "  let view = &labels[0..1]\n" ++
        "  let selected: Maybe (&[U32]) = $Some view\n" ++
        "  let observations: GrowArray U32 = #[]\n" ++
        "  for index in 0 .. count:\n" ++
        "    @storage.push observations (case selected of\n" ++
        "      $Some values => @storage.read values 0\n" ++
        "      $Nothing => 99)\n" ++
        "    selected := if @u32.eq (@u32.rem index 2) 0 then $Nothing else $Some view\n" ++
        "    continue\n" ++
        "  return @storage.freeze observations\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "literal lane wrappers retain selector evidence across scoped numeric fallback allocation failures" {
    var module = try lower(a, "const shuffle = func lanes -> left -> right => return @simd.f32x4.shuffle lanes (left, right)\n" ++
        "const swizzle = func lanes -> values => return @simd.f32x4.swizzle lanes values\n" ++
        "const broadcast = func lane -> values => return @simd.f32x4.broadcast values lane\n" ++
        "entry const answer = func (values: Array F32): Array F32 => return do:\n" ++
        "  let input = &values[0..4]\n" ++
        "  let lanes = (input[0], input[1], input[2], input[3])\n" ++
        "  let (a, b, c, d) = shuffle (0, 5, 2, 7) lanes (5.0, 6.0, 7.0, 8.0)\n" ++
        "  let (e, f, g, h) = swizzle (3, 2, 1, 0) lanes\n" ++
        "  let (i, j, k, l) = broadcast 3 lanes\n" ++
        "  return #[a, b, c, d, e, f, g, h, i, j, k, l]\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "proven empty borrowed rows keep zero iteration exits and trap reads across allocation failures" {
    var module = try lower(a, "type Row is data = $Row {text: &[U32]}\n" ++
        "entry const empty = func (count: U32): U32 => return do:\n" ++
        "  let rows: ResizeArray Row = #[]\n" ++
        "  let total = 0\n" ++
        "  for row in rows:\n" ++
        "    for code in row.text:\n" ++
        "      total := @u32.add self code\n" ++
        "  return total\n" ++
        "entry const direct = func (index: U32): U32 => return do:\n" ++
        "  let rows: ResizeArray Row = #[]\n" ++
        "  return @storage.read (@storage.read rows index).text 0\n" ++
        "entry const seeded = func (count: U32): U32 => return do:\n" ++
        "  let labels: Array U32 = #[65]\n" ++
        "  let rows: ResizeArray Row = #[]\n" ++
        "  if @u32.lt 0 count:\n" ++
        "    @storage.push rows ($Row {text: &labels[0..1]})\n" ++
        "  let total = 0\n" ++
        "  for row in rows:\n" ++
        "    for code in row.text:\n" ++
        "      total := @u32.add self code\n" ++
        "  return total\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "impossible refutable bindings emit exiting fallback without inactive borrowed payload allocations" {
    var module = try lower(a, "type Maybe a is data = $Some a | $Nothing\n" ++
        "type LocalCursor is data = $LocalCursor {values: &[U32], index: U32}\n" ++
        "entry const answer = func (): U32 => return do:\n" ++
        "  let step: Maybe LocalCursor = $Nothing\n" ++
        "  let $Some cursor = step else:\n" ++
        "    return 42\n" ++
        "  return @storage.read cursor.values cursor.index\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "wide field refinement restores scoped indexes through allocation failures" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const read = func row => return {");
    for (0..72) |index| {
        const field = try a.print("f{d}: row.f{d},", .{ index, index });
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "}\nentry const answer = func (input: U32) => return do:\n  let values: Array U32 = #[input]\n  values[0] := input\n  let selected = read {");
    for (0..72) |index| {
        const field = try a.print("f{d}: values[0],", .{index});
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "}\n  return @u32.add selected.f0 selected.f71\n");
    var module = try lower(a, source.items);
    defer module.deinit(a);
    try publishRefinedModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishRefinedModule, .{@as([]const core.Module, &.{module})});
}
test "context free inline layouts substitute constructor variables and reject open phantom arguments" {
    var module = try lower(a, "type Maybe a is data = $Some a | $Nothing\n" ++
        "type Pair [a, b] is data = $Pair (a, b)\n" ++
        "type Token a is data = $Token Unit\n" ++
        "type Row is data = $Row {integer: Maybe U32, floating: Maybe F32}\n" ++
        "const fixed: Maybe (Pair [U32, F32]) = $Some ($Pair (7, 1.5))\n" ++
        "const row: Row = $Row {integer: $Some 7, floating: $Some 1.5}\n" ++
        "const phantom: Token U32 = $Token ()\n" ++
        "const open = func (_: a): Token a => return $Token ()\n" ++
        "const borrowed = func (_: Ref U32): Token (Ref U32) => return $Token ()\n" ++
        "const callable = func (_: Unit -> U32): Token (Unit -> U32) => return $Token ()\n" ++
        "entry const answer = func () => return 0\n");
    defer module.deinit(a);
    var found: usize = 0;
    for (module.bodies) |body| {
        const name = module.name(body.declaration_name);
        const accepted = std.mem.eql(u8, name, "fixed") or std.mem.eql(u8, name, "row") or std.mem.eql(u8, name, "phantom");
        const rejected = std.mem.eql(u8, name, "open") or std.mem.eql(u8, name, "borrowed") or std.mem.eql(u8, name, "callable");
        if (!accepted and !rejected) continue;
        try std.testing.expectEqual(@import("../check/types.zig").Tag.nominal, module.types.node(module.typeOf(body.root)).tag);
        var remaining: usize = 100_000;
        try std.testing.expectEqual(accepted, @import("storage_calls.zig").inlineType(&module, module.typeOf(body.root), &remaining, 0));
        if (accepted) {
            var tiny: usize = 1;
            try std.testing.expect(!@import("storage_calls.zig").inlineType(&module, module.typeOf(body.root), &tiny, 0));
        }
        found += 1;
    }
    try std.testing.expectEqual(@as(usize, 6), found);
}
test "closed generic row templates keep repeated copies within the fixed layout budget" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "type Maybe a is data = $Some a | $Nothing\ntype Row is data = $Row {");
    for (0..300) |index| {
        const field = try a.print("f{d}: Maybe F32,", .{index});
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "}\nconst make = func (input: F32) => return $Row {");
    for (0..300) |index| {
        const field = try a.print("f{d}: $Some input,", .{index});
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "}\nconst copy = func (pool: ResizeArray Row) => return @storage.copy pool\nentry const answer = func (input: F32) => return do:\n  let pool: ResizeArray Row = #[make input]\n");
    for (0..200) |index| {
        const call = try a.print("  let copied{d} = copy pool\n", .{index});
        defer a.free(call);
        try source.appendSlice(a, call);
    }
    try source.appendSlice(a, "  return @storage.length pool\n");
    var module = try lower(a, source.items);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("CLOSED_LAYOUT_EMIT {any}\n", .{diagnostic});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
fn publishGeneratorModule(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compileWithOptions(allocator, modules, 1, .{ .work_limits = .{ .expressions = 128 } });
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("GENERATOR_EMIT {any}\n", .{diagnostic});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "unit writers plan fixed scratch generators without expanding repeated calls" {
    var module = try lower(a, "const write = func (destination: ResizeArray U32) -> (input: U32) => return do:\n" ++
        "  let seed = @array.fill 2 input\n" ++
        "  let generated = @array.generate 2 (func (index: U32) => return @u32.add seed[index] index)\n" ++
        "  @storage.push destination (@u32.add generated[0] generated[1])\n" ++
        "entry const answer = func (input: U32) => return do:\n  let destination: ResizeArray U32 = #[]\n" ++
        "  write destination input\n  write destination input\n  write destination input\n  write destination input\n" ++
        "  write destination input\n  write destination input\n  write destination input\n  write destination input\n" ++
        "  return @storage.length destination\n");
    defer module.deinit(a);
    try publishGeneratorModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishGeneratorModule, .{@as([]const core.Module, &.{module})});
}
test "scratch generator writer admission declines borrowed and owning row layouts" {
    for ([_][]const u8{ "&source[0..1]", "#[input]" }) |element| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "const write = func (destination: ResizeArray U32) -> (source: Array U32) -> (input: U32) => return do:\n  let generated = @array.generate 1 (func (_: U32) => return ");
        try text.appendSlice(a, element);
        try text.appendSlice(a, ")\n  @storage.push destination (@storage.length generated[0])\nentry const answer = func (input: U32) => return do:\n  let source = #[input]\n  let destination: ResizeArray U32 = #[]\n");
        for (0..64) |_| try text.appendSlice(a, "  write destination source input\n");
        try text.appendSlice(a, "  return @storage.length destination\n");
        var module = try lower(a, text.items);
        defer module.deinit(a);
        var result = try scoped.compileWithOptions(a, &.{module}, 1, .{ .work_limits = .{ .expressions = 128 } });
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}
test "loaded nominal fields keep semantic witnesses across cached generic contexts" {
    var module = try lowerWithCatalog(a, "type Maybe a is data = $Some a | $Nothing\n" ++
        "const ResizeArray.length = func (values: ResizeArray a): U32 => return @storage.length values\n" ++
        "const View.at = func (values: View a) -> (index: U32) => return @storage.read values index\n" ++
        "type Vector is data = $Vector {x: F32}\ntype Pose is data = $Pose {position: Vector}\n" ++
        "const vector = func (x: F32) => return $Vector {x}\n" ++
        "const Vector.add = func (left: Vector) -> (right: Vector) => return vector (@f32.add left.x right.x)\n" ++
        "const rows = func (pool: ResizeArray (Maybe a)): &[Maybe a] => return &pool[0..pool.length]\n" ++
        "const shifted = func access -> tag => return do:\n  let poses = rows access.pool\n  let $Some pose = poses.at 0 else:\n    return (tag, vector 0.0)\n  return (tag, @type.call \"add\" pose.position (vector 1.0))\n" ++
        "entry const answer = func (input: F32) => return do:\n" ++
        "  let pool: ResizeArray (Maybe Pose) = #[$Some $Pose {position: vector input}]\n" ++
        "  let (integer, first) = shifted {pool} 7\n" ++
        "  pool[0] := $Some $Pose {position: vector (@f32.add input 10.0)}\n" ++
        "  let (floating, second) = shifted {pool} input\n" ++
        "  return #[@u32.to_f32 integer, first.x, floating, second.x]\n", true);
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "inline generic result witnesses preserve distinct same layout nominal instances" {
    var module = try lower(a, "type Maybe a is data = $Some a | $Nothing\n" ++
        "type Actor is data = $Actor U32\ntype Pose is data = $Pose U32\n" ++
        "const pick = func fallback -> maybe => return case maybe of\n  $Some value => value\n  $Nothing => fallback\n" ++
        "const consume = func ($Actor actor) -> ($Pose pose) => return @u32.add (@u32.mul actor 100) pose\n" ++
        "entry const answer = func (input: U32) => return do:\n  let rows: ResizeArray U32 = #[input]\n" ++
        "  let actors: Maybe Actor = if @u32.eq (@u32.bit_and input 1) 0 then $Nothing else $Some ($Actor rows[0])\n" ++
        "  let poses: Maybe Pose = if @u32.eq (@u32.bit_and input 2) 0 then $Nothing else $Some ($Pose rows[0])\n" ++
        "  let actor = pick ($Actor 10) actors\n  let pose = pick ($Pose 20) poses\n  let retained = pick ($Actor 30) actors\n" ++
        "  return @u32.add (consume actor pose) (consume retained pose)\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "writer outlining leaves implicit global pool reads with their owning generator" {
    var module = try lower(a, "const pool: Array U32 = #[5]\n" ++
        "const implicit = func (destination: ResizeArray U32) => return @storage.push destination pool[0]\n" ++
        "const explicit = func (destination: ResizeArray U32) -> (source: Array U32) => return @storage.push destination source[0]\n" ++
        "entry const answer = func (input: U32) => return do:\n  let source = pool\n  source[0] := @u32.add input 7\n  let rows: ResizeArray U32 = #[input]\n  implicit rows\n  explicit rows source\n  return rows[1]\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "plain getters preserve exact dispatch through selected inline helpers" {
    var parts: [103][]const u8 = undefined;
    parts[0] = "const F32.abs = func (value: F32) => return @f32.abs value\n" ++
        "const abs = func value => return value.abs\n" ++
        "type Number is data = $Number F32\n" ++
        "const Number.abs = func (number: Number) => return do:\n  let $Number value = number\n  return @f32.add (@f32.abs value) 10.0\n" ++
        "const kernel = func (input: F32) => return do:\n  let number = $Number input\n  let total = @f32.add (abs input) number.abs\n";
    @memset(parts[1..81], "  total := @f32.add total 1.0\n");
    parts[81] = "  return total\nentry const answer = func (input: F32) => return do:\n  let rows: ResizeArray F32 = #[input]\n  let total: F32 = 0.0\n";
    @memset(parts[82..102], "  total := @f32.add total (kernel rows[0])\n");
    parts[102] = "  return total\n";
    const source = try std.mem.concat(a, u8, &parts);
    defer a.free(source);
    var module = try lowerWithCatalog(a, source, true);
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
fn publishScratchWriter(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compileWithOptions(allocator, modules, 1, .{ .work_limits = .{ .expressions = 512 } });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "Unit writer helpers admit plain local scratch arrays with checked cleanup" {
    const helper = "const keeper: Array U32 = #[123]\n" ++
        "const Array.length = func (values: Array a): U32 => return @array.length values\n" ++
        "const Array.at = func (values: Array a) -> (index: U32) => return @array.get values index\n" ++
        "const ResizeArray.push = func (values: ResizeArray a) -> (value: a) => return @storage.push values value\n" ++
        "const some = func (values: Array U32) -> (predicate: U32 -> Bool) => return do:\n  for index in 0 .. values.length:\n    if predicate (values.at index):\n      return true\n  return false\n" ++
        "const bump = func (first: U32) -> (second: U32) -> (third: U32) => return @u32.add (@u32.add first second) third\n" ++
        "const encode = func (input: U32): Array U32 => return #[input, @u32.add input 1]\n" ++
        "const append = func (values: Array U32) -> (destination: ResizeArray U32) => return do:\n  let read = values.at\n  for index in 0 .. values.length:\n    destination.push (read index)\n" ++
        "const write = func (destination: ResizeArray U32) -> (input: U32) => return do:\n  let encoded = encode input\n  let local: GrowArray U32 = #[]\n  @storage.push local encoded[0]\n  @storage.push local encoded[1]\n  let sum: U32 = 0\n";
    var parts: [102][]const u8 = undefined;
    parts[0] = helper;
    @memset(parts[1..81], "  sum := @u32.add sum 1\n");
    parts[81] = "  let found = some encoded (func outer => return some encoded (func inner => return true))\n  if found:\n    destination.push input\n  let first = bump input\n  let partial = first sum\n  destination.push (partial 0)\n  append (encode sum) destination\n  @storage.push destination local[0]\nentry const answer = func (input: U32) => return do:\n  let rows: ResizeArray U32 = #[input]\n";
    @memset(parts[82..101], "  write rows input\n");
    parts[101] = "  do:\n    let busy: GrowArray U32 = #[0]\n    write rows input\n    @storage.push busy input\n  write rows input\n  return @u32.add rows[0] (@u32.sub keeper[0] 123)\n";
    const source = try std.mem.concat(a, u8, &parts);
    defer a.free(source);
    var module = try lowerWithCatalog(a, source, true);
    defer module.deinit(a);
    try publishScratchWriter(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishScratchWriter, .{@as([]const core.Module, &.{module})});
    var invalid = try lower(a, "const borrow = func () => return &(#[42])[0]\n" ++
        "const write = func (destination: ResizeArray U32) => return do:\n  let scratch: Array U32 = #[1]\n  @storage.push destination (@storage.load (borrow ()))\n" ++
        "entry const answer = func () => return do:\n  let rows: ResizeArray U32 = #[]\n  write rows\n  return rows[0]\n");
    defer invalid.deinit(a);
    var rejected = try scoped.compile(a, &.{invalid}, 1);
    defer rejected.deinit(a);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
}

fn publishSelectedReader(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compileWithOptions(allocator, modules, 1, .{ .work_limits = .{ .expressions = 512 } });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
fn publishLargeKeyFallback(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_outline_key_declines >= 2);
}

test "optional oversized reader and writer keys fall back without hiding invalid borrows" {
    var name: [7000]u8 = undefined;
    @memset(&name, 'x');
    const source = try a.print("type State = {{{s}: ResizeArray U32}}\n" ++
        "const write = func (state: State) -> (amount: U32) => return do:\n  state.{s}[0] := @u32.add state.{s}[0] amount\n" ++
        "const read = func (state: State) => return state.{s}[0]\n" ++
        "entry const answer = func (input: U32) => return do:\n  let rows: ResizeArray U32 = #[10]\n  let state = {{{s}: rows}}\n  write state input\n  write state 1\n  return read state\n", .{ &name, &name, &name, &name, &name });
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    try publishLargeKeyFallback(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishLargeKeyFallback, .{@as([]const core.Module, &.{module})});
    const invalid_source = try a.print("type State = {{{s}: ResizeArray U32}}\n" ++
        "const borrow = func (state: State) => return do:\n  let local: GrowArray U32 = #[1]\n  return &local[0]\n" ++
        "entry const answer = func () => return do:\n  let rows: ResizeArray U32 = #[0]\n  let escaped = borrow {{{s}: rows}}\n  return @storage.load escaped\n", .{ &name, &name });
    defer a.free(invalid_source);
    var invalid = try lower(a, invalid_source);
    defer invalid.deinit(a);
    var rejected = try scoped.compile(a, &.{invalid}, 1);
    defer rejected.deinit(a);
    try std.testing.expect(rejected.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
}

test "selected parameterized readers outline exact descriptor payloads across owners" {
    var parts: [122][]const u8 = undefined;
    parts[0] = "type Research rows is data = $Research {rows: rows, count: U32}\nconst read = func (value: Research rows) => return do:\n  let number = value.count\n";
    @memset(parts[1..101], "  number := @u32.add number 1\n");
    parts[101] = "  return number\nentry const answer = func (input: U32) => return do:\n  let owner: ResizeArray U32 = #[input]\n  let research = $Research {rows: &owner[0..1], count: input}\n  let total: U32 = 0\n";
    @memset(parts[102..121], "  total := @u32.add total (read research)\n");
    parts[121] = "  return total\n";
    const source = try std.mem.concat(a, u8, &parts);
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    var result = try scoped.compileWithOptions(a, &.{module}, 1, .{ .work_limits = .{ .expressions = 512 } });
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("generic reader: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.max_scoped_emission_body_steps <= 512);
    try std.testing.expect(result.counters.scoped_emission_expressions > result.counters.max_scoped_emission_body_steps);
    try std.testing.expect(result.bytes.len > 8);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSelectedReader, .{@as([]const core.Module, &.{module})});
    const callable_source = try std.mem.replaceOwned(u8, a, source, "rows: &owner[0..1]", "rows: func () => return input");
    defer a.free(callable_source);
    var callable_module = try lower(a, callable_source);
    defer callable_module.deinit(a);
    var declined = try scoped.compileWithOptions(a, &.{callable_module}, 1, .{ .work_limits = .{ .expressions = 512 } });
    defer declined.deinit(a);
    try std.testing.expect(declined.diagnostic != null);
    try std.testing.expectEqualStrings("Storage source expansion exceeded its expression budget", declined.diagnostic.?.message());
    try std.testing.expectEqual(@as(usize, 0), declined.bytes.len);
}
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    return lowerWithCatalog(allocator, source, false);
}
fn lowerWithCatalog(allocator: std.mem.Allocator, source: []const u8, builtin_catalog: bool) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = builtin_catalog });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

test "owned calls reuse scalar and destination specializations" {
    var unused = try lower(a, "const unused = func (rows: GrowArray U32) => return @storage.length rows\nentry const answer = func () => return 42\n");
    defer unused.deinit(a);
    try std.testing.expect(!try scoped.required(a, &.{unused}, 1));
    var reached = try lower(a, "const length = func (rows: GrowArray U32) => return @storage.length rows\nentry const answer = func () => return length #[42]\n");
    defer reached.deinit(a);
    try std.testing.expect(try scoped.required(a, &.{reached}, 1));
    const simple_once = "const row = func (value: U32) => return #[value, 7]\nconst number = func (value: U32) => return @u32.add value 1\nentry const answer = func () => return do:\n  let values = row 40\n  break number values[0]\n";
    const simple_twice = "const row = func (value: U32) => return #[value, 7]\nconst number = func (value: U32) => return @u32.add value 1\nentry const answer = func () => return do:\n  let first = row 40\n  let second = row 41\n  let a = number first[0]\n  break @u32.add a (number second[0])\n";
    var left = try lower(a, simple_once);
    defer left.deinit(a);
    var right = try lower(a, simple_twice);
    defer right.deinit(a);
    var first = try scoped.compile(a, &.{left}, 1);
    defer first.deinit(a);
    var second = try scoped.compile(a, &.{right}, 1);
    defer second.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try std.testing.expect(second.diagnostic == null);
    try std.testing.expect(first.bytes.len > 8);
    try std.testing.expectEqual(first.emitted_functions, second.emitted_functions);
}

test "owned callback specialization keeps runtime scalar captures as parameters" {
    var module = try lower(a, "const apply = func (base: U32) => return do:\n  let add = func (value: U32) => return @u32.add base value\n  break @u32.add (add 2) (add 3)\nentry const answer = func () => return apply 10\n");
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "owned inline calls reuse aggregate parameter and result layouts" {
    const helper = "const pair = func (input: {left: U32, right: U32}) => return {left: @u32.add input.left 1, right: input.right}\n";
    var once = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  let result = pair {left: 40, right: 2}\n  return result.left\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  let first = pair {left: 40, right: 2}\n  let second = pair {left: 1, right: 3}\n  return @u32.add first.left second.left\n");
    defer twice.deinit(a);
    var baseline = try lower(a, "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  return 41\n");
    defer baseline.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "owned reader calls reuse code across independent owner identities" {
    const helper = "const read = func (values: ResizeArray U32) => return @storage.read values 0\n";
    const owners = "entry const answer = func () => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, owners ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ owners ++ "  return @u32.add (read first) second[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ owners ++ "  return @u32.add (read first) (read second)\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "closed owned calls reuse code across unrelated generic environments" {
    const helper = "const inc = func (value: U32) => return @u32.add value 1\nconst wrap = func unrelated -> (value: U32) => return do:\n  let scratch: GrowArray U32 = #[value]\n  return inc scratch[0]\n";
    var once = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  return wrap true 41\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  let first = wrap true 41\n  return @u32.add first (wrap 2.0 3)\n");
    defer twice.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "closed direct call graphs reuse inline data without admitting recursive calls" {
    const helper = "const inc = func (value: U32) => return @u32.add value 1\nconst pair = func (input: {left: U32, right: U32}) => return {left: inc input.left, right: input.right}\n";
    const entry = "entry const answer = func () => return do:\n  let rows: GrowArray U32 = #[0]\n";
    var baseline = try lower(a, entry ++ "  return 42\n");
    defer baseline.deinit(a);
    var module = try lower(a, helper ++ entry ++ "  let first = pair {left: 40, right: 2}\n  let second = pair {left: 1, right: 3}\n  return @u32.add first.left second.left\n");
    defer module.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 2, result.emitted_functions);
    var cycle = try lower(a, "const cycle = func (value: U32): U32 => return cycle value\nentry const answer = func () => return cycle 1\n");
    defer cycle.deinit(a);
    var remaining: usize = 10_000;
    for (cycle.bodies) |body| try std.testing.expect(!@import("storage_calls.zig").inlineBody(&.{cycle}, &cycle, body.binding, &remaining));
    try std.testing.expect(remaining != 0);
}

test "owned readonly descriptor captures reuse helpers across caller owners" {
    const helper = "const reading = func (rows: &[U32]) -> (index: U32) => return do:\n  let callback = func (at: U32) => return @storage.read rows at\n  return callback index\n";
    const entry = "entry const answer = func () => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  return @u32.add (reading (&first[0..1]) 0) second[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  return @u32.add (reading (&first[0..1]) 0) (reading (&second[0..1]) 0)\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected numeric declarations reuse exact generic scalar specializations" {
    const helper = "const U32.minus = func (left: U32) -> (right: U32): U32 => return @u32.sub left right\nconst difference = func left -> right => return @type.call \"minus\" left right\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let rows: ResizeArray U32 = #[42, 2]\n";
    var baseline = try lower(a, entry ++ "  return @u32.sub rows[0] rows[1]\n");
    defer baseline.deinit(a);
    var once = try lowerWithCatalog(a, helper ++ entry ++ "  return difference rows[0] rows[1]\n", true);
    defer once.deinit(a);
    var twice = try lowerWithCatalog(a, helper ++ entry ++ "  return @u32.add (difference rows[0] rows[1]) (difference rows[1] 1)\n", true);
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
    try std.testing.expectEqual(base.emitted_functions + 2, left.emitted_functions);
}

test "selected inline data helpers reuse checked record results" {
    const helpers = "const U32.minus = func (left: U32) -> (right: U32): U32 => return @u32.sub left right\nconst pack = func (input: {left: U32, right: U32}) => return {left: @type.call \"minus\" input.left input.right, right: input.right}\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let rows: ResizeArray U32 = #[42, 2]\n";
    var baseline = try lower(a, entry ++ "  return @u32.sub rows[0] rows[1]\n");
    defer baseline.deinit(a);
    var once = try lowerWithCatalog(a, helpers ++ entry ++ "  let result = pack {left: rows[0], right: rows[1]}\n  return result.left\n", true);
    defer once.deinit(a);
    var twice = try lowerWithCatalog(a, helpers ++ entry ++ "  let first = pack {left: rows[0], right: rows[1]}\n  let second = pack {left: 9, right: 1}\n  return @u32.add first.left second.left\n", true);
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 2, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "readonly descriptor records reuse caller result slots across owners" {
    const helper = "type Bundle is data = $Bundle {rows: &[U32], bias: U32}\nconst folded = func (input: Bundle) => return do:\n  let total = input.bias\n  for index in 0..@storage.length input.rows:\n    total := @u32.add self (@storage.read input.rows index)\n  return {total, count: @storage.length input.rows}\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7, 9]\n  let second: ResizeArray U32 = #[11]\n";
    var once = try lower(a, helper ++ entry ++ "  let value = folded ($Bundle {rows: &first[0..2], bias: 1})\n  return value.total\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  let left = folded ($Bundle {rows: &first[0..2], bias: 1})\n  let right = folded ($Bundle {rows: &second[0..1], bias: 2})\n  return @u32.add left.total right.total\n");
    defer twice.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "pure generic wrappers specialize their actual runtime parameter types" {
    const helper = "const inc = func (value: U32) => return @u32.add value 1\nconst wrap = func unrelated -> (value: U32) => return inc value\n";
    var once = try lower(a, helper ++ "entry const answer = func (): U32 => return do:\n  let rows: GrowArray U32 = #[41]\n  return wrap true rows[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ "entry const answer = func (): U32 => return do:\n  let rows: GrowArray U32 = #[41, 3]\n  return @u32.add (wrap true rows[0]) (wrap 2.0 rows[1])\n");
    defer twice.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions + 1, right.emitted_functions);
}

test "static readonly callback arguments reuse selected helpers across owners" {
    const helpers = "const plus = func (value: U32): U32 => return @u32.add value 1\nconst folded = func transform -> (rows: &[U32]): U32 => return do:\n  let total = 0\n  for index in 0..@storage.length rows:\n    total := @u32.add self (transform (@storage.read rows index))\n  return total\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7, 9]\n  let second: ResizeArray U32 = #[11]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helpers ++ entry ++ "  return folded plus (&first[0..2])\n");
    defer once.deinit(a);
    var twice = try lower(a, helpers ++ entry ++ "  return @u32.add (folded plus (&first[0..2])) (folded plus (&second[0..1]))\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 2, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "returned reader descriptors reuse alias maps without fresh owner results" {
    const helper = "type Buffer is data = $Buffer {rows: ResizeArray U32, label: U32}\nconst chosen = func (input: Buffer): Buffer => return input\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  let value = chosen ($Buffer {rows: first, label: 1})\n  return value.rows[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  let left = chosen ($Buffer {rows: first, label: 1})\n  let right = chosen ($Buffer {rows: second, label: 2})\n  return @u32.add left.rows[0] right.rows[0]\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
    const copy = "const copied = func (rows: ResizeArray U32) => return @storage.copy rows\n";
    var direct = try lower(a, entry ++ "  let output = @storage.copy first\n  return output[0]\n");
    defer direct.deinit(a);
    var expanded = try lower(a, copy ++ entry ++ "  let output = copied first\n  return output[0]\n");
    defer expanded.deinit(a);
    var plain = try scoped.compile(a, &.{direct}, 1);
    defer plain.deinit(a);
    var fresh = try scoped.compile(a, &.{expanded}, 1);
    defer fresh.deinit(a);
    try std.testing.expect(plain.diagnostic == null);
    try std.testing.expect(fresh.diagnostic == null);
    try std.testing.expectEqual(plain.emitted_functions, fresh.emitted_functions);
}

test "plain Unit writers reuse checked row mutation and growth helpers" {
    const helper = "const advance = func (rows: ResizeArray U32) -> (amount: U32): Unit => return do:\n  @storage.write (@storage.at rows 0) (@u32.add (@storage.read rows 0) amount)\n  @storage.push rows amount\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, entry ++ "  return @storage.read first 0\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  advance first 2\n  return @storage.read first 0\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  advance first 2\n  advance second 3\n  return @u32.add (@storage.read first 0) (@storage.read second 0)\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected pure calls follow exact reference aliases without expanding callers" {
    const helper = "const rounded = func (value: F32): F32 => return @f32.floor value\nconst raised = func (value: F32): F32 => return @f32.ceil value\nconst alias = rounded\nconst again = alias\nconst upper = raised\nconst convert = func (value: F32): U32 => return @u32.add (@f32.to_u32 (again value)) (@f32.to_u32 (upper value))\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let rows: ResizeArray F32 = #[1.5, 2.5]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add (@f32.to_u32 (@f32.floor rows[0])) (@f32.to_u32 (@f32.ceil rows[0]))\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  return convert rows[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  return @u32.add (convert rows[0]) (convert rows[1])\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 3, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected primitive associated partials reuse their saturated callers" {
    const helper = "const F32.blend = func (left: F32) -> (right: F32) -> (weight: F32): F32 => return @f32.add left (@f32.mul (@f32.sub right left) weight)\nconst F32.weighted = func (left: F32) -> (right: F32) -> (weight: F32): F32 => return @f32.add left (@f32.mul right weight)\nconst blend = func left -> right => return @type.call \"blend\" left right\nconst weighted = func left -> right => return @type.call \"weighted\" left right\nconst interpolate = func (value: F32): F32 => return @f32.add (blend 0.0 value 0.25) (weighted 1.0 value 0.75)\n";
    const entry = "entry const answer = func (): F32 => return do:\n  let rows: ResizeArray F32 = #[2.0, 4.0]\n";
    var baseline = try lower(a, entry ++ "  return @f32.add (@f32.mul rows[0] 0.25) (@f32.add 1.0 (@f32.mul rows[0] 0.75))\n");
    defer baseline.deinit(a);
    var once = try lowerWithCatalog(a, helper ++ entry ++ "  return interpolate rows[0]\n", true);
    defer once.deinit(a);
    var twice = try lowerWithCatalog(a, helper ++ entry ++ "  return @f32.add (interpolate rows[0]) (interpolate rows[1])\n", true);
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    if (left.diagnostic) |diagnostic| {
        std.debug.print("ASSOCIATED_NATIVE_FAILURE {d}:{d}..{d} {s}\n", .{ diagnostic.unit, diagnostic.span.start, diagnostic.span.end, diagnostic.detail });
        for (once.bodies) |body| std.debug.print("ASSOCIATED_NATIVE_BODY {d} {s} parameters={d} span={d}..{d}\n", .{ body.binding, @tagName(once.node(body.root).tag), once.bodyParameters(&body).len, once.span(body.root).start, once.span(body.root).end });
    }
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    // Expanded callers would emit two distinct numeric leaf helpers instead.
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected application policies share wide callback type descriptions within the existing bound" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "type Wide = {");
    for (0..166) |index| {
        const field = try a.print("f{d}: Array U32,", .{index});
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "}\nconst inspect = func (value: Wide): U32 ! {} => return 0\nconst policy = func ");
    for (0..13) |index| {
        const parameter = try a.print("callback_{d} -> ", .{index});
        defer a.free(parameter);
        try source.appendSlice(a, parameter);
    }
    try source.appendSlice(a, "(value: U32): U32 => return @u32.add value 1\nentry const answer = func () => return do:\n  let kept: Array U32 = #[41]\n  return policy ");
    for (0..13) |_| try source.appendSlice(a, "inspect ");
    try source.appendSlice(a, "kept[0]\n");
    var module = try lower(a, source.items);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("wide policy diagnostic: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

const nominal_fields_source =
    \\type Row is data = $Row {left: U32, right: U32}
    \\const read = func row => return @u32.add row.left row.right
    \\const twice = func row => return @u32.add (read row) (read row)
    \\const outer = func row => return @u32.add (twice row) (twice row)
    \\entry const answer = func (input: U32): U32 => return do:
    \\  let first: GrowArray U32 = #[input]
    \\  let second: GrowArray U32 = #[@u32.add input 11]
    \\  let left = outer ($Row {right: 3, left: first[0]})
    \\  let right = outer ($Row {left: second[0], right: 5})
    \\  return @u32.add left right
;

fn publishNominalFields(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_inline_definitions >= 3);
    try std.testing.expect(result.counters.scoped_inline_cache_hits >= 3);
    try std.testing.expect(result.counters.scoped_emission_expressions < 500);
    try std.testing.expect(result.counters.scoped_call_admission_nodes < 500);
}

test "nominal inline field DAGs share bounded definitions across caller values" {
    var module = try lower(a, nominal_fields_source);
    defer module.deinit(a);
    try publishNominalFields(a, &.{module});
}

test "nominal inline field publication survives allocation failures" {
    var module = try lower(a, nominal_fields_source);
    defer module.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishNominalFields, .{@as([]const core.Module, &.{module})});
}

const aggregate_reader_source =
    \\type Sample a is data = $Sample {value: a}
    \\const read = func (access: {rows: GrowArray a, stamp: U32}) => return {sample: $Sample {value: access.rows[0]}, stamp: access.stamp}
    \\const twice = func access => return do:
    \\  let first = read access
    \\  let second = read access
    \\  return {stamp: first.stamp, sample: second.sample}
    \\const outer = func access => return do:
    \\  let first = twice access
    \\  let second = twice access
    \\  return {sample: first.sample, stamp: second.stamp}
    \\entry const integers = func (input: U32) => return do:
    \\  let left: GrowArray U32 = #[input]
    \\  let right: GrowArray U32 = #[@u32.add input 11]
    \\  let first = outer {rows: left, stamp: 3}
    \\  let second = outer {stamp: 7, rows: right}
    \\  left[0] := @u32.add left[0] 19
    \\  let third = outer {stamp: 13, rows: left}
    \\  return #[first.sample.value, first.stamp, second.sample.value, second.stamp, third.sample.value, third.stamp, right[0]]
    \\entry const floats = func (input: F32) => return do:
    \\  let left: GrowArray F32 = #[input]
    \\  let right: GrowArray F32 = #[@f32.add input 2.5]
    \\  let first = outer {stamp: 17, rows: left}
    \\  let second = outer {rows: right, stamp: 23}
    \\  left[0] := @f32.add left[0] 7.25
    \\  let third = outer {rows: left, stamp: 29}
    \\  return #[first.sample.value, @u32.to_f32 first.stamp, second.sample.value, @u32.to_f32 second.stamp, third.sample.value, @u32.to_f32 third.stamp, right[0]]
    \\type Vec3 is data = $Vec3 {x: F32, y: F32, z: F32}
    \\const position = func (rows: GrowArray {position: Vec3}) => return rows[0].position
    \\const position_twice = func rows => return do:
    \\  let first = position rows
    \\  let second = position rows
    \\  return second
    \\const tuple = func (rows: GrowArray {left: F32, right: F32}) => return (rows[0].left, rows[0].right)
    \\const tuple_twice = func rows => return do:
    \\  let (left, ignored) = tuple rows
    \\  let (unused, right) = tuple rows
    \\  return (left, right)
    \\entry const projections = func (input: F32) => return do:
    \\  let poses: GrowArray {position: Vec3} = #[{position: $Vec3 {z: 3.5, x: input, y: -0.0}}]
    \\  let pairs: GrowArray {left: F32, right: F32} = #[{right: -0.0, left: input}]
    \\  let point = position_twice poses
    \\  let (left, right) = tuple_twice pairs
    \\  return #[point.x, point.y, point.z, left, right]
    \\type Choice is data = $Count U32 | $Empty
    \\const choice_read = func (rows: GrowArray Choice): Choice => return rows[0]
    \\const choice_twice = func rows => return do:
    \\  let first = choice_read rows
    \\  let second = choice_read rows
    \\  return second
    \\const choice_value = func (choice: Choice): U32 => return case choice of
    \\  $Count value => value
    \\  $Empty => 31
    \\entry const variants = func (input: U32) => return do:
    \\  let left: GrowArray Choice = #[$Count input]
    \\  let right: GrowArray Choice = #[$Empty]
    \\  let first = choice_twice left
    \\  let second = choice_twice right
    \\  left[0] := $Empty
    \\  right[0] := $Count (@u32.add input 9)
    \\  let third = choice_twice left
    \\  let fourth = choice_twice right
    \\  return #[choice_value first, choice_value second, choice_value third, choice_value fourth]
;

test "shared aggregate readers retain nominal physical schemas across independent owners" {
    var module = try lower(a, aggregate_reader_source);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_reader_definitions >= 3);
    try std.testing.expect(result.counters.scoped_reader_cache_hits >= 4);
    try std.testing.expect(result.counters.scoped_emission_expressions < 2000);
}

fn aggregateReaderDag(allocator: std.mem.Allocator, depth: usize) !core.Module {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    try source.appendSlice(allocator, "type Sample is data = $Sample {value: U32}\nconst level0 = func (rows: GrowArray U32) => return {sample: $Sample {value: rows[0]}, stamp: rows[1]}\n");
    for (1..depth + 1) |level| {
        const definition = try allocator.print("const level{d} = func (rows: GrowArray U32) => return do:\n  let first = level{d} rows\n  let second = level{d} rows\n  return {{stamp: first.stamp, sample: second.sample}}\n", .{ level, level - 1, level - 1 });
        defer allocator.free(definition);
        try source.appendSlice(allocator, definition);
    }
    const entry = try allocator.print("entry const answer = func (input: U32) => return do:\n  let left: GrowArray U32 = #[input, 3]\n  let right: GrowArray U32 = #[@u32.add input 11, 7]\n  let first = level{d} left\n  let second = level{d} right\n  return @u32.add first.sample.value (@u32.add second.sample.value second.stamp)\n", .{ depth, depth });
    defer allocator.free(entry);
    try source.appendSlice(allocator, entry);
    return lower(allocator, source.items);
}

test "shared aggregate reader diamonds keep emission growth bounded" {
    var shallow = try aggregateReaderDag(a, 2);
    defer shallow.deinit(a);
    var deep = try aggregateReaderDag(a, 6);
    defer deep.deinit(a);
    var first = try scoped.compile(a, &.{shallow}, 1);
    defer first.deinit(a);
    var second = try scoped.compile(a, &.{deep}, 1);
    defer second.deinit(a);
    try std.testing.expect(first.diagnostic == null and second.diagnostic == null);
    try std.testing.expect(second.counters.scoped_reader_cache_hits >= 6);
    try std.testing.expect(second.counters.scoped_emission_expressions < first.counters.scoped_emission_expressions * 3);
    try std.testing.expect(second.counters.scoped_emission_expressions < 1200);
}

fn publishAggregateReader(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_reader_cache_hits > 0);
}

test "shared aggregate reader publication survives allocation failures" {
    var module = try aggregateReaderDag(a, 1);
    defer module.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishAggregateReader, .{@as([]const core.Module, &.{module})});
}
