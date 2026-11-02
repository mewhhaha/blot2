const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = false });
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("projected parameter: {s}\n", .{@tagName(diagnostic.code)});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
const callback =
    \\const make_callback = func state => return func (argument: U32): U32 => return @u32.add state.value argument
    \\
;
const owners =
    \\entry const answer = func (input: U32): U32 => return do:
    \\  let first: Array U32 = #[input]
    \\  let second: Array U32 = #[10]
    \\  let left = {editor: @storage.at first 0, editor_clips: @storage.at second 0, tick: make_callback {value: input}, draw: make_callback {value: 3}, save: make_callback {value: 5}, close: make_callback {value: 7}}
    \\  let right = {editor: @storage.at second 0, editor_clips: @storage.at first 0, tick: make_callback {value: 11}, draw: make_callback {value: 13}, save: make_callback {value: 17}, close: make_callback {value: 19}}
    \\
;
fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("projected parameter backend: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
}
test "projected anonymous parameters share owners despite unused goal-bearing callbacks" {
    var module = try lower(callback ++
        \\const read_state = func (access: {editor: Ref U32, editor_clips: Ref U32, tick: U32 -> U32, draw: U32 -> U32, save: U32 -> U32, close: U32 -> U32}) => return do:
        \\  let editor: Ref U32 = access.editor
        \\  let clips: Ref U32 = access.editor_clips
        \\  return @u32.add (@storage.load editor) (@storage.load clips)
        \\
    ++ owners ++
        \\  return @u32.add (read_state left) (read_state right)
    );
    defer module.deinit(a);
    var captured_goals = false;
    for (module.bodies) |body| {
        if (std.mem.eql(u8, module.name(body.declaration_name), "make_callback")) captured_goals = body.scheme.obligations.len != 0;
    }
    try std.testing.expect(captured_goals);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "projected anonymous parameters complete selected named callback source proof before sharing" {
    var module = try lower(callback ++
        \\const read_state = func (access: {editor: Ref U32, editor_clips: Ref U32, tick: U32 -> U32, draw: U32 -> U32, save: U32 -> U32, close: U32 -> U32}) => return do:
        \\  let editor: Ref U32 = access.editor
        \\  return @u32.add (@storage.load editor) (access.tick 1)
        \\
    ++ owners ++
        \\  return @u32.add (read_state left) (read_state right)
    );
    defer module.deinit(a);
    var found = false;
    for (module.bodies) |body| if (std.mem.eql(u8, module.name(body.declaration_name), "make_callback")) {
        // Curried lowering makes this a named partial application. Its source
        // obligation is checked on actual saturated emission in the child.
        found = true;
        try std.testing.expectEqual(@as(u32, 2), body.parameters.len);
        try std.testing.expect(body.scheme.obligations.len != 0);
    };
    try std.testing.expect(found);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
    // The plain enclosing/helper body can complete independently; the selected
    // descriptor callback still requires the original whole-source proof.
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_plain_plan_definitions);
    try std.testing.expectEqual(@as(u64, 2), result.counters.scoped_completed_plan_definitions);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "projected anonymous parameters reject selected literal callbacks with captured goals" {
    var module = try lower(
        \\const make_callback = func state => return do:
        \\  let captured = state
        \\  return func (argument: U32): U32 => return @u32.add captured.value argument
        \\const read_state = func (access: {editor: Ref U32, editor_clips: Ref U32, tick: U32 -> U32, draw: U32 -> U32, save: U32 -> U32, close: U32 -> U32}) => return do:
        \\  let editor: Ref U32 = access.editor
        \\  return @u32.add (@storage.load editor) (access.tick 1)
        \\
    ++ owners ++
        \\  return @u32.add (read_state left) (read_state right)
    );
    defer module.deinit(a);
    var found = false;
    for (module.bodies) |body| if (std.mem.eql(u8, module.name(body.declaration_name), "make_callback")) {
        // The block prevents flattening; the returned literal captures this
        // source field goal and must stay outside the shared callback ABI.
        found = true;
        try std.testing.expectEqual(@as(u32, 1), body.parameters.len);
        try std.testing.expect(body.scheme.obligations.len != 0);
    };
    try std.testing.expect(found);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_owner_graph_definitions);
    // A plain named body may contain this literal locally; the literal is
    // still excluded from the shared descriptor callback interface above.
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_plain_plan_definitions);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_completed_plan_attempts);
}
test "projected anonymous parameters retain whole-record forwarding" {
    var module = try lower(callback ++
        \\const forward = func access => return access
        \\
    ++ owners ++
        \\  let forwarded = forward left
        \\  return @u32.add (@storage.load forwarded.editor) (forwarded.tick 2)
    );
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_owner_graph_definitions);
}

test "projected anonymous parameters retain nested stored views and references" {
    var module = try lower(callback ++
        \\type RootRow is data = $RootRow {clips: &[U32], selected: Ref U32}
        \\const read_state = func (access: {editor: Array RootRow, editor_clips: Array RootRow, tick: U32 -> U32, draw: U32 -> U32, save: U32 -> U32, close: U32 -> U32}) => return do:
        \\  let editor: RootRow = access.editor[0]
        \\  let clips: RootRow = access.editor_clips[0]
        \\  return @u32.add editor.clips[0] (@storage.load clips.selected)
        \\entry const answer = func (input: U32): U32 => return do:
        \\  let first: Array U32 = #[input]
        \\  let second: Array U32 = #[10]
        \\  let first_rows: Array RootRow = #[$RootRow {clips: &first[0..1], selected: @storage.at second 0}]
        \\  let second_rows: Array RootRow = #[$RootRow {clips: &second[0..1], selected: @storage.at first 0}]
        \\  let left = {editor: first_rows, editor_clips: second_rows, tick: make_callback {value: input}, draw: make_callback {value: 3}, save: make_callback {value: 5}, close: make_callback {value: 7}}
        \\  let right = {editor: second_rows, editor_clips: first_rows, tick: make_callback {value: 11}, draw: make_callback {value: 13}, save: make_callback {value: 17}, close: make_callback {value: 19}}
        \\  return @u32.add (read_state left) (read_state right)
    );
    defer module.deinit(a);
    try publish(a, &.{module});
}

const fields = @import("storage_parameter_fields.zig");
fn rawModule(nodes: []core.Node, extra: []u32) core.Module {
    return .{
        .unit = 7,
        .types = .{ .nodes = &.{}, .extra = &.{} },
        .nodes = nodes,
        .spans = &.{},
        .extra = extra,
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = @constCast("editorclipscallback"),
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
}
fn rawProjection(field: u32) core.Projection {
    return .{ .nominal = .{ .unit = 0, .decl = 0 }, .field = field, .source_type = 0, .result_type = 0, .variants = .{} };
}
fn collectorLaw(allocator: std.mem.Allocator) !void {
    // access.editor, access.clips; access.callback remains unreferenced.
    var nodes = [_]core.Node{
        .{ .tag = .invalid },
        .{ .tag = .reference, .a = 0 },
        .{ .tag = .project, .a = 1, .b = 0 },
        .{ .tag = .project, .a = 1, .b = 1 },
        .{ .tag = .product, .a = 0, .b = 2 },
        .{ .tag = .return_, .a = 1 },
        .{ .tag = .closure, .a = 0 },
        .{ .tag = .update, .a = 0 },
        .{ .tag = .call, .a = 0, .b = 2, .c = 1 },
        .{ .tag = .project, .a = 1, .b = 2 },
        .{ .tag = .match },
        .{ .tag = .pattern_bind },
        .{ .tag = .project, .a = 2, .b = 1 },
        .{ .tag = .reference, .a = 1 },
        .{ .tag = .project, .a = 13, .b = 2 },
        .{ .tag = .pattern_bind, .a = 1, .b = 2 },
        .{ .tag = .pattern_bind, .a = 2, .b = 3 },
        .{ .tag = .pattern_bind, .a = 3, .b = 2 },
        .{ .tag = .pattern_bind, .a = 1, .b = 1 },
        .{ .tag = .pattern_bind, .a = 1, .b = 2, .c = 1 },
    };
    var extra = [_]u32{ 2, 3, 1, 42 };
    var m = rawModule(&nodes, &extra);
    var patterns = [_]core.Pattern{ .{ .tag = .invalid }, .{ .tag = .bind, .a = 80 }, .{ .tag = .wildcard }, .{ .tag = .value, .a = 1 } };
    m.patterns = &patterns;
    var references = [_]core.BindingRef{ .{ .unit = 0, .binding = 42 }, .{ .unit = 8, .binding = 42 } };
    m.references = &references;
    var projections = [_]core.Projection{ rawProjection(101), rawProjection(102), rawProjection(103) };
    m.projections = &projections;
    var names = [_]core.FieldName{
        .{ .symbol = 101, .spelling = .{ .start = 0, .len = 6 } },
        .{ .symbol = 102, .spelling = .{ .start = 6, .len = 5 } },
        .{ .symbol = 103, .spelling = .{ .start = 11, .len = 8 } },
    };
    m.field_names = &names;
    var closures = [_]core.ClosureInfo{.{ .body = 1, .parameter = .{ .binding = 80, .ty = 0, .span = .{ .start = 0, .end = 0 } }, .captures = .{ .start = 3, .len = 1 } }};
    m.closures = &closures;
    var updates = [_]core.UpdateInfo{.{ .root = 2, .path = .{}, .value = 3, .self_binding = 80 }};
    m.updates = &updates;
    var selected = try fields.collect(allocator, &m, 4, 42);
    defer selected.deinit(allocator);
    try std.testing.expect(!selected.whole);
    try std.testing.expectEqualSlices(u32, &.{ 101, 102 }, selected.names.items);
    // Whole return, capture, rooted update and whole forwarding all decline.
    for ([_]u32{ 5, 6, 7, 8, 10, 11, 17, 18, 19 }) |root| {
        var whole = try fields.collect(allocator, &m, root, 42);
        defer whole.deinit(allocator);
        try std.testing.expect(whole.whole);
    }
    for ([_]u32{ 15, 16 }, [_]u32{ 101, 102 }) |root, expected| {
        var plain_pattern = try fields.collect(allocator, &m, root, 42);
        defer plain_pattern.deinit(allocator);
        try std.testing.expect(!plain_pattern.whole);
        try std.testing.expectEqualSlices(u32, &.{expected}, plain_pattern.names.items);
    }
    var selected_callback = try fields.collect(allocator, &m, 9, 42);
    defer selected_callback.deinit(allocator);
    try std.testing.expectEqualSlices(u32, &.{103}, selected_callback.names.items);
    var nested = try fields.collect(allocator, &m, 12, 42);
    defer nested.deinit(allocator);
    try std.testing.expectEqualSlices(u32, &.{101}, nested.names.items);
    var foreign = try fields.collect(allocator, &m, 14, 42);
    defer foreign.deinit(allocator);
    try std.testing.expect(!foreign.whole);
    try std.testing.expectEqual(@as(usize, 0), foreign.names.items.len);
    // Real checked anonymous record projections use one tag-zero entry.
    var type_nodes = [_]@import("../check/types.zig").Node{ .{ .tag = .unit }, .{ .tag = .record, .a = 0, .b = 3 }, .{ .tag = .nominal, .a = 1, .b = 1 } };
    var type_extra = [_]u32{ 101, 0, 102, 0, 103, 0 };
    m.types = .{ .nodes = &type_nodes, .extra = &type_extra };
    var projection_variants = [_]core.ProjectionVariant{ .{ .tag = 0, .field = 0 }, .{ .tag = 1, .field = 0 }, .{ .tag = 0, .field = 1 } };
    m.projection_variants = &projection_variants;
    projections[0].source_type = 1;
    projections[0].variants = .{ .start = 0, .len = 1 };
    var checked_record = try fields.collect(allocator, &m, 2, 42);
    defer checked_record.deinit(allocator);
    try std.testing.expect(!checked_record.whole);
    try std.testing.expectEqualSlices(u32, &.{101}, checked_record.names.items);
    var declined: [5]core.Projection = @splat(projections[0]);
    declined[0].nominal = .{ .unit = 1, .decl = 1 };
    declined[1].source_type = 2;
    declined[2].variants = .{ .start = 1, .len = 1 };
    declined[3].variants = .{ .start = 0, .len = 2 };
    declined[4].variants = .{ .start = 2, .len = 1 };
    for (declined) |projection| {
        projections[0] = projection;
        var whole = try fields.collect(allocator, &m, 2, 42);
        defer whole.deinit(allocator);
        try std.testing.expect(whole.whole);
    }
}
test "direct anonymous parameter fields retain complete escape fallback" {
    try collectorLaw(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, collectorLaw, .{});
}

test "projected anonymous parameters discover nominal callback bundles without changing owner graphs through OOM" {
    var module = try lower(
        \\type Hooks is data = $Hooks {tick: U32 -> U32 ! {}, spare: U32 -> U32 ! {}}
        \\const plus = func (value: U32): U32 => return @u32.add value 1
        \\const read_state = func (access: {picked: Ref U32, other: Ref U32, unused: Ref U32, hooks: Hooks}): U32 => return @u32.add (access.hooks.tick (@storage.load access.picked)) (@storage.load access.other)
        \\entry const answer = func (input: U32): U32 => return do:
        \\  let first: Array U32 = #[input]
        \\  let second: Array U32 = #[10]
        \\  let hooks = $Hooks {tick: plus, spare: plus}
        \\  let left = {picked: @storage.at first 0, other: @storage.at second 0, unused: @storage.at second 0, hooks}
        \\  let right = {picked: @storage.at second 0, other: @storage.at first 0, unused: @storage.at first 0, hooks}
        \\  return @u32.add (read_state left) (read_state right)
    );
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
