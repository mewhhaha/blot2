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
const constructor_source =
    \\data Box a=#Box {value:a}
    \\data Pair=#Pair {x:U32,y:F32}
    \\data Phantom a=#Phantom {value:F32}
    \\const wrap=#Box
    \\const pair=#Pair
    \\const unbox=fn box=>case box of
    \\  #Box value=>value
    \\const total=fn selected=>case selected of
    \\  #Pair (x,y)=>@f32.add (@u32.to_f32 x) y
    \\const capture=fn constructor=>fn value=>unbox (constructor value)
    \\const ready=capture #Box
    \\entry const generic=@f32.add (@u32.to_f32 (ready 40)) (ready 2.5)
    \\entry const scalar=unbox (wrap 42.5)
    \\entry const tuple=total (pair (40,2.5))
    \\entry const old_version=(fn()=>do:
    \\  let original=(40,2.5)
    \\  let selected=pair original
    \\  selected.x:=99
    \\  return @f32.add (@u32.to_f32 (@product.get original 0)) selected.y
    \\) ()
    \\const phantom: F32 -> Phantom U32=#Phantom
    \\entry const phantom_value=case phantom 42.5 of
    \\  #Phantom value=>value
    \\entry const runtime=fn (value:F32)=>unbox (wrap value)
;

fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = if (module.unit == 0) 1 else module.unit, .binding = body.binding };
    unreachable;
}
fn graphHash(module: *const core.Module) u64 {
    var hash = std.hash.Wyhash.init(0);
    inline for (@typeInfo(core.Module).@"struct".field_names) |name| {
        const Value = @FieldType(core.Module, name);
        if (@typeInfo(Value) == .pointer and @typeInfo(Value).pointer.size == .slice) hash.update(std.mem.sliceAsBytes(@field(module, name)));
    }
    hash.update(std.mem.sliceAsBytes(module.types.nodes));
    hash.update(std.mem.sliceAsBytes(module.types.extra));
    hash.update(std.mem.sliceAsBytes(module.types.operations));
    hash.update(std.mem.sliceAsBytes(module.types.effects.rows));
    hash.update(std.mem.sliceAsBytes(module.types.effects.labels));
    return hash.final();
}
fn evaluateScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const before = graphHash(module);
    defer std.debug.assert(before == graphHash(module));
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "generic", "scalar", "tuple", "old_version", "phantom_value" }) |name| {
        const value = try session.value(target(module, name));
        try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 42.5))), value.bits);
    }
}
fn pipelineScenario(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, constructor_source);
    defer module.deinit(allocator);
    try evaluateScenario(allocator, &module);
}
test "canonical record constructor arrows reconstruct owned storage under every pipeline allocation failure" {
    try pipelineScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, pipelineScenario, .{});
}
fn emitScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const before = graphHash(module);
    defer std.debug.assert(before == graphHash(module));
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("emit:{d}: {s}\n", .{ diagnostic.span.start, @tagName(diagnostic.code) });
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "canonical scalar and product headers keep record storage names and frozen source graphs immutable" {
    var module = try lower(a, constructor_source);
    defer module.deinit(a);
    var records: usize = 0;
    for (module.constructors[1..]) |constructor| {
        const record = module.types.node(constructor.payload);
        if (record.tag != .record) continue;
        records += 1;
        const arrow = module.types.node(constructor.scheme.root);
        try std.testing.expectEqual(types.Tag.function, arrow.tag);
        if (record.b == 1) {
            try std.testing.expectEqual(module.types.recordField(record, 0).ty, arrow.a);
        } else {
            const product = module.types.node(arrow.a);
            try std.testing.expectEqual(types.Tag.product, product.tag);
            try std.testing.expectEqual(record.b, product.b);
            for (0..record.b) |index| try std.testing.expectEqual(module.types.recordField(record, index).ty, module.types.extra[product.a + index]);
        }
    }
    try std.testing.expectEqual(@as(usize, 3), records);
    try evaluateScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, evaluateScenario, .{&module});
    try emitScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{&module});
}
fn negativeScenario(allocator: std.mem.Allocator) !void {
    for ([_]struct { source: []const u8, code: checker.Code }{
        .{ .source = "type Read is effect={read:Unit -> U32}\ndata Box=#Box {action:Unit -> U32}\nentry const answer=#Box (fn()=>Read.read ())\n", .code = .effect_mismatch },
        .{ .source = "data One=#One {value:F32}\nentry const answer=#One 42\n", .code = .type_mismatch },
        .{ .source = "data Pair=#Pair {x:U32,y:F32}\nentry const answer=#Pair 42\n", .code = .type_mismatch },
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
test "canonical constructor calls preserve incompatible shape and coverage rejection under allocation failure" {
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
        \\entry const unsigned = unbox (#Imported 42)
        \\entry const floating = unbox (#Imported 42.5)
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
test "imported canonical constructor arrows keep producer identity after source syntax teardown" {
    try importedScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importedScenario, .{});
}

const wide_source =
    \\data Wide=#Wide {f0: U32,f1: U32,f2: U32,f3: U32,f4: U32,f5: U32,f6: U32,f7: U32,f8: U32,f9: U32,f10: U32,f11: U32,f12: U32,f13: U32,f14: U32,f15: U32,f16: U32,f17: U32,f18: U32,f19: U32,f20: U32,f21: U32,f22: U32,f23: U32,f24: U32,f25: U32,f26: U32,f27: U32,f28: U32,f29: U32,f30: U32,f31: U32,f32: U32,f33: U32,f34: U32,f35: F32}
    \\const wrap=#Wide
    \\entry const answer=case wrap (40,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2.5) of
    \\  #Wide payload=>@f32.add (@u32.to_f32 (@product.get payload 0)) (@product.get payload 35)
;

fn wideScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const before = graphHash(module);
    defer std.debug.assert(before == graphHash(module));
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 42.5))), (try session.value(target(module, "answer"))).bits);
    try emitScenario(allocator, module);
}
test "wide canonical constructor storage copies outlive scratch fallback failures without mutating source graphs" {
    var module = try lower(a, wide_source);
    defer module.deinit(a);
    try wideScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, wideScenario, .{&module});
}
