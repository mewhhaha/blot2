const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const backend = @import("core_backend.zig");
const validation = @import("../check/frozen_core_validation.zig");
const a = std.testing.allocator;
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
const fixture_source =
    \\const first = func (items: GrowArray U32) => return &items[0]
    \\entry const answer = func () => return do:
    \\  let items: GrowArray U32 = #[41]
    \\  let reference = first items
    \\  let grown = @storage.push items 7
    \\  let changed = @storage.write reference 42
    \\  break @storage.load reference
;
fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try backend.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("scoped diagnostic: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "scoped source storage publishes validated Wasm and releases every failed allocation" {
    var module = try lower(a, fixture_source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "application array owners publish across entries through allocation failure" {
    const source =
        \\const values: GrowArray U32 = #[41]
        \\entry const append = func (value: U32) => return do:
        \\  let added = @storage.push values value
        \\  break @storage.length values
        \\entry const read = func (index: U32) => return values[index]
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "inline nominal patterns and updates preserve type evidence through allocation failure" {
    const source =
        \\type Point is data = $Point {z: U32, x: F32}
        \\const points: GrowArray Point = #[$Point (7, 1.5)]
        \\entry const answer = func () => return do:
        \\  let rows = points
        \\  rows[0].x := @f32.add self 1.0
        \\  let $Point (z, x) = rows[0]
        \\  return x
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
    var changed: usize = 0;
    for (module.patterns) |pattern_| if (pattern_.tag == .record_payload) {
        const child = &module.patterns[pattern_.b];
        const saved = child.ty;
        defer child.ty = saved;
        child.ty = T.boolean;
        var remaining: usize = 100_000;
        const views = [_]*const core.Module{&module};
        const entry = module.bodies[module.bodies.len - 1].binding;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/package_core.zig").checkedInterfaceBody(&module, entry, .{ .units = &views }, &remaining, a));
        changed += 1;
    };
    try std.testing.expect(changed != 0);
}
test "data stack host callbacks publish copy transport through allocation failure" {
    const source =
        \\const values: GrowArray U32 = #[41]
        \\entry const answer = func (host: Array U32 -> Array U32 ! {Foreign}) => return do:
        \\  for 0 .. 1:
        \\    use reply <- host #[values[0]]
        \\    let changed = @storage.write (&values[0]) reply[0]
        \\  return values[0]
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "generic data stack builders reconstruct builtin member authority through allocation failure" {
    const source =
        \\const Array.size = func (items: Array a) => return @array.length items
        \\const copied = func (items: Array a): Array a => return @array.generate items.size (func index => return items[index])
        \\entry const answer = func () => return do:
        \\  let owner: GrowArray U32 = #[42]
        \\  let copy = copied #[owner[0]]
        \\  return copy[0]
    ;
    var module = try lowerWithCatalog(a, source, true);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "local scalar demand caches retain checked captures through allocation failure" {
    const source =
        \\const calls: GrowArray U32 = #[0]
        \\const bump = func () => return do:
        \\  let changed = @storage.write (&calls[0]) (@u32.add calls[0] 1)
        \\  return 42
        \\const twice = func ~(value: U32) -> (flag: Bool) => return do:
        \\  let first = if flag then @demand value else 0
        \\  return @u32.add first (@demand value)
        \\entry const answer = func (flag: Bool) => return twice (bump ()) flag
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "checked source instances admit unused static fields without granting unrelated variables" {
    const source =
        \\const unused = func value => return value
        \\const no_action = func access => return ()
        \\const update = func (rows: GrowArray U32) => return @storage.push rows 42
        \\const stages = func reset -> update => return {reset, update}
        \\const policy = stages no_action update
        \\const run = func stages -> (rows: GrowArray U32) => return do:
        \\  stages.update rows
        \\  return @storage.length rows
        \\entry const answer = func () => return do:
        \\  let rows: GrowArray U32 = #[41]
        \\  return run policy rows
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
    const unrelated = for (module.bodies) |body| {
        if (body.binding == 0) continue;
        const signature = module.types.node(module.binding(body.binding).ty);
        if (signature.tag == .function and signature.a == signature.b and module.types.node(signature.a).tag == .variable) break signature.a;
    } else return error.TestExpectedUnusedGeneric;
    try std.testing.expectEqual(T.Tag.variable, module.types.node(unrelated).tag);
    const entry = module.bodies[module.bodies.len - 1].binding;
    var changed = false;
    for (module.nodes) |*node| if (node.tag == .constant and node.a == 41) {
        const saved = node.ty;
        defer node.ty = saved;
        node.ty = unrelated;
        var remaining: usize = 100_000;
        const views = [_]*const core.Module{&module};
        try std.testing.expectError(error.InvalidArtifact, @import("../check/package_core.zig").checkedInterfaceBody(&module, entry, .{ .units = &views }, &remaining, a));
        changed = true;
    };
    try std.testing.expect(changed);
}
test "scoped storage frozen authority rejects forged modes shapes and operands" {
    var module = try lower(a, fixture_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{});
    var modes: usize = 0;
    var operations: usize = 0;
    for (module.nodes) |*node| {
        const saved = node.*;
        defer node.* = saved;
        if (node.tag == .array) {
            node.ty = T.u32_type;
            try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
            modes += 1;
        } else if (node.tag == .storage) {
            node.c = std.math.maxInt(u32);
            try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
            node.* = saved;
            node.ty = if (saved.ty == T.u32_type) T.boolean else T.u32_type;
            try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
            node.* = saved;
            node.b = 0;
            try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
            operations += 1;
        }
    }
    try std.testing.expect(modes != 0 and operations != 0);
}
test "scoped storage rejects borrowed escapes and shrinking through aliases" {
    const cases = [_]struct { text: []const u8, code: backend.Code }{
        .{ .text = "const escape = func () => return &(#[42])[0]\nentry const bad = func () => return @storage.load (escape ())\n", .code = .storage_escape },
        .{ .text = "entry const bad = func () => return do:\n  let items: ResizeArray U32 = #[42]\n  let first = &items[0]\n  let alias = items\n  let shrunk = @storage.truncate alias 0\n  break @storage.load first\n", .code = .storage_borrow_conflict },
    };
    for (cases) |item| {
        var module = try lower(a, item.text);
        defer module.deinit(a);
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expectEqual(item.code, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}

test "data stack inline records and joined roots release every failed allocation" {
    const source =
        \\entry const answer = func (flag: Bool) => return do:
        \\  let first: GrowArray U32 = #[41]
        \\  let second: GrowArray U32 = #[42]
        \\  let target = if flag then ^first[0] else ^second[0]
        \\  let rows: GrowArray {target: ^U32, value: U32} = #[{value: 1, target: target}]
        \\  let copied = @storage.copy rows
        \\  let read = func () => return @storage.load copied[0].target
        \\  break @u32.add (read ()) copied[0].value
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}

test "storage callback admission rejects a forged missing capture" {
    const source =
        \\entry const answer = func () => return do:
        \\  let items: GrowArray U32 = #[42]
        \\  let reference = &items[0]
        \\  let read = func () => return @storage.load reference
        \\  break read ()
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    var changed: usize = 0;
    for (module.closures) |*closure| {
        if (closure.captures.len == 0) continue;
        const saved = closure.captures;
        defer closure.captures = saved;
        closure.captures.len = 0;
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
        changed += 1;
    }
    try std.testing.expect(changed != 0);
}

test "owned returns cross lexical blocks but never another function boundary" {
    const source =
        \\const other = func (): GrowArray U32 => do:
        \\  return #[1]
        \\const choose = func (limit: U32): GrowArray U32 => do:
        \\  for i in 0..limit:
        \\    let items: GrowArray U32 = #[i]
        \\    if @u32.eq i 5:
        \\      return items
        \\  return #[42]
        \\entry const answer = func (limit: U32) => return (choose limit)[0]
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    const other_root = for (module.bodies) |body| {
        if (std.mem.eql(u8, module.name(body.declaration_name), "other")) break body.root;
    } else return error.TestUnexpectedResult;
    try std.testing.expect(module.node(other_root).tag == .block);
    var changed: usize = 0;
    for (module.nodes) |*node| {
        if (node.tag != .return_ or node.b == other_root) continue;
        const info = @import("../check/storage_types.zig").info(&module.types, module.typeOf(node.a)) orelse continue;
        if (info.kind != .grow) continue;
        const saved = node.b;
        defer node.b = saved;
        node.b = other_root;
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
        changed += 1;
    }
    try std.testing.expect(changed != 0);
}

test "owned return children preserve completed nominal exits through allocation failure" {
    const source =
        \\type Event is data = $Down U32 | $Move (F32, F32) | $None
        \\const decode = func (tag: U32) => return do:
        \\  return case tag of
        \\    1 => do:
        \\      return $Down 7
        \\    2 => do:
        \\      return $Move (2.0, 3.0)
        \\    _ => @panic "invalid"
        \\entry const answer = func (tag: U32) => return do:
        \\  let rows: ResizeArray U32 = #[tag]
        \\  let event = decode rows[0]
        \\  return case event of
        \\    $Down code => code
        \\    $Move (x, y) => @f32.to_u32 (@f32.add x y)
        \\    $None => 0
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}

test "scoped emission work limits bound reusable children without publishing partial Wasm" {
    const scoped = @import("scoped_backend.zig");
    var parts: [102][]const u8 = undefined;
    parts[0] = "const read = func (rows: ResizeArray U32) => return do:\n  let value: U32 = 0\n";
    @memset(parts[1..101], "  value := @u32.add value 1\n");
    parts[101] = "  return @u32.add value rows[0]\nentry const answer = func (value: U32) => return do:\n  let rows: ResizeArray U32 = #[value]\n  return read rows\n";
    const source = try std.mem.concat(a, u8, &parts);
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    var invalid = try scoped.compileWithWorkLimits(a, &.{module}, 1, .{}, .{ .expressions = 0 });
    defer invalid.deinit(a);
    try std.testing.expect(invalid.diagnostic != null);
    try std.testing.expectEqual(@as(usize, 0), invalid.bytes.len);
    var limited = try scoped.compileWithWorkLimits(a, &.{module}, 1, .{}, .{ .expressions = 64 });
    defer limited.deinit(a);
    try std.testing.expect(limited.diagnostic != null);
    try std.testing.expectEqualStrings("Storage source expansion exceeded its expression budget", limited.diagnostic.?.message());
    try std.testing.expectEqual(@as(usize, 0), limited.bytes.len);
    try std.testing.expectEqual(@as(u64, 64), limited.counters.max_scoped_emission_body_steps);
    var sufficient = try scoped.compileWithWorkLimits(a, &.{module}, 1, .{}, .{ .expressions = 1024 });
    defer sufficient.deinit(a);
    try std.testing.expect(sufficient.diagnostic == null);
    try std.testing.expect(sufficient.bytes.len > 8);
    try std.testing.expect(sufficient.counters.max_scoped_emission_body_steps > 64);
    try std.testing.expect(sufficient.counters.max_scoped_emission_body_steps <= 1024);
    try std.testing.expect(sufficient.counters.scoped_emission_expressions > sufficient.counters.max_scoped_emission_body_steps);
}
