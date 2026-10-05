const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("check:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
const record_source =
    \\data Pair = #Pair { x: U32, y: F32 }
    \\data One = #One { value: F32 }
    \\data Box a = #Box { value: a }
    \\data Wrapped = #Wrapped { value: (U32,F32) }
    \\data Empty = #Empty {}
    \\const unbox = fn box => case box of
    \\  #Box value => value
    \\entry const pair = case #Pair { y: 2.5, x: 40 } of
    \\  #Pair payload => @f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 1)
    \\entry const tuple = case #Pair { y: 2.5, x: 40 } of
    \\  #Pair (x,y) => @f32.add (@u32.to_f32 x) y
    \\entry const named = case #Pair { y: 2.5, x: 40 } of
    \\  #Pair { y, x } => @f32.add (@u32.to_f32 x) y
    \\entry const one = case #One {value:42.5} of
    \\  #One value => value
    \\entry const generic = @f32.add (@u32.to_f32 (unbox (#Box {value:40}))) (unbox (#Box {value:2.5}))
    \\entry const product_field = case #Wrapped {value:(40,2.5)} of
    \\  #Wrapped payload => @f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 1)
    \\entry const empty = case #Empty {} of
    \\  #Empty => 42
;
fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = if (module.unit == 0) 1 else module.unit, .binding = body.binding };
    unreachable;
}
fn evaluateScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "pair", "tuple", "named", "one", "generic", "product_field" }) |name| {
        const value = try session.value(target(module, name));
        try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 42.5))), value.bits);
    }
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "empty"))).bits);
}
fn pipelineScenario(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, record_source);
    defer module.deinit(allocator);
    try evaluateScenario(allocator, &module);
}
test "record constructor whole payloads preserve declared slots and scalar cardinality under every allocation failure" {
    try pipelineScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, pipelineScenario, .{});
}
fn emitScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("emit:{d}: {s}\n", .{ diagnostic.span.start, @tagName(diagnostic.code) });
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "record payload views retain immutable Core types names and patterns during evaluation and emission" {
    var module = try lower(a, record_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const bindings = try a.dupe(core.Binding, module.bindings);
    defer a.free(bindings);
    const patterns = try a.dupe(core.Pattern, module.patterns);
    defer a.free(patterns);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const type_extra = try a.dupe(types.Id, module.types.extra);
    defer a.free(type_extra);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    var views: usize = 0;
    for (module.patterns) |pattern| if (pattern.tag == .record_payload) {
        views += 1;
        const record = module.types.node(pattern.ty);
        try std.testing.expectEqual(types.Tag.record, record.tag);
        try std.testing.expectEqual(pattern.a, record.b);
        if (pattern.a != 1) try std.testing.expectEqual(types.Tag.product, module.types.node(module.pattern(pattern.b).ty).tag);
    };
    try std.testing.expect(views >= 4);
    try evaluateScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, evaluateScenario, .{&module});
    try emitScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{&module});
    try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
    try std.testing.expectEqualSlices(core.Binding, bindings, module.bindings);
    try std.testing.expectEqualSlices(core.Pattern, patterns, module.patterns);
    try std.testing.expectEqualSlices(types.Node, type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(types.Id, type_extra, module.types.extra);
    try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
}
fn negativeScenario(allocator: std.mem.Allocator) !void {
    for ([_]struct { source: []const u8, code: checker.Code }{
        .{ .source = "data One=#One {value:U32}\nentry const answer=case #One {value:42} of\n  #One payload=>@product.get payload 0\n", .code = .type_mismatch },
        .{ .source = "data Pair=#Pair {x:U32,y:U32}\nentry const answer=case #Pair {x:40,y:2} of\n  #Pair payload=>@u32.add payload 0\n", .code = .type_mismatch },
        .{ .source = "data Empty=#Empty {}\nentry const answer=case #Empty {} of\n  #Empty payload=>42\n", .code = .constructor_arity },
        .{ .source = "data Pair=#Pair {x:U32,y:U32}\nentry const answer=case #Pair {x:40,y:2} of\n  #Pair=>42\n", .code = .constructor_arity },
        .{ .source = "data Pair=#Pair {left:Bool,right:Bool}\nentry const answer=case #Pair {right:#True,left:#False} of\n  #Pair (#True,_)=>0\n  #Pair {left:#False,right:#False}=>42\n", .code = .non_exhaustive_match },
    }) |case| {
        var lexed = try lexer.lex(allocator, case.source);
        defer lexed.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, case.source, lexed.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(case.code, checked.diagnostics[0].code);
    }
}
test "canonical constructor views preserve arity scalar and exhaustive coverage rejection under allocation failure" {
    try negativeScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, negativeScenario, .{});
}

fn importedScenario(allocator: std.mem.Allocator) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    const producer_source = "data Imported value = #Imported {value:value}\n";
    var producer_lexed = try lexer.lex(allocator, producer_source);
    defer producer_lexed.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_lexed.tokens.items, &pool);
    var tree_live = true;
    defer if (tree_live) producer_tree.deinit(allocator);
    var producer = try checker.checkModule(allocator, &producer_tree, &pool, &.{}, &.{}, 1);
    defer producer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), producer.diagnostics.len);
    var producer_core = try core.lower(allocator, &producer_tree, &pool, &producer);
    producer_core.unit = 1;
    defer producer_core.deinit(allocator);
    producer_tree.deinit(allocator);
    tree_live = false;
    const consumer_source =
        \\const unbox = fn box => case box of
        \\  #Imported value => value
        \\entry const unsigned = unbox (#Imported {value:42})
        \\entry const floating = unbox (#Imported {value:42.5})
    ;
    var lexed = try lexer.lex(allocator, consumer_source);
    defer lexed.deinit(allocator);
    var tree = try parser.parse(allocator, consumer_source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    var consumer = try checker.checkModule(allocator, &tree, &pool, &.{}, &.{
        .{ .producer = &producer, .kind = .nominal, .name = pool.lookup("Imported").?, .index = 1, .origin = 0 },
        .{ .producer = &producer, .kind = .constructor, .name = pool.lookup("Imported").?, .index = 1, .origin = 0 },
    }, 2);
    defer consumer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), consumer.diagnostics.len);
    var consumer_core = try core.lower(allocator, &tree, &pool, &consumer);
    consumer_core.unit = 2;
    defer consumer_core.deinit(allocator);
    var session = try evaluator.Session.init(allocator, &.{ producer_core, consumer_core });
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(&consumer_core, "unsigned"))).bits);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 42.5))), (try session.value(target(&consumer_core, "floating"))).bits);
    var result = try backend.compile(allocator, &.{ producer_core, consumer_core }, 2);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
}
test "imported generic record payload views keep producer identity after source syntax teardown" {
    try importedScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importedScenario, .{});
}

const generic_record_source =
    \\type Pack [unused, selected] is data = #Pack { unused: unused, selected: selected }
    \\const identity = fn value => value
    \\const packed = #Pack { unused: identity, selected: fn (value: U32) => @u32.add value 1 }
    \\const invoke = fn callback => callback 1
    \\const sum = fn packed => fn (left: U32) => fn (right: U32) => do:
    \\  let #Pack { selected } = packed
    \\  return selected (@u32.add left right)
    \\const run = fn packed => fn (value: U32) => invoke (fn extra => do:
    \\  let #Pack { selected } = packed
    \\  return selected (@u32.add value extra))
    \\entry const answer = fn (value: U32) => run packed value
    \\entry const partial = fn (value: U32) => invoke (sum packed value)
    \\entry const chain = fn (value: U32) => do:
    \\  let callback = sum packed
    \\  return invoke (callback value)
;
const curried_record_source =
    \\type Clock is effect = { tick: Unit -> U32 }
    \\type Pack callback is data = #Pack { callback: callback, marker: U32 }
    \\const prepare = fn (amount: U32) => fn (value: U32) => do:
    \\  use current <- Clock.tick ()
    \\  return @u32.add current (@u32.add value amount)
    \\const packed = #Pack { callback: prepare, marker: 42 }
    \\const read = fn pack => do:
    \\  let #Pack { marker } = pack
    \\  return marker
    \\entry const answer = fn () => read packed
;
fn retainedRecordEmission(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "retained records preserve generic fields, static captures and curried effect rows under allocation failure" {
    for ([_][]const u8{ generic_record_source, curried_record_source }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try retainedRecordEmission(a, &module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedRecordEmission, .{&module});
    }
}
