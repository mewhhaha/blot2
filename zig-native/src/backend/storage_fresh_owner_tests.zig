const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = false });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

const basic_source =
    \\const fresh = func (input: U32): Array U32 => return #[input, @u32.add input 1]
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let marker: GrowArray U32 = #[input]
    \\  let first = fresh marker[0]
    \\  let second = fresh (@u32.add marker[0] 10)
    \\  first[0] := @u32.add self 20
    \\  return #[first[0], first[1], second[0], second[1]]
;

fn publishFresh(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_completed_plan_definitions > 0);
    try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
    try std.testing.expect(result.counters.scoped_result_owner_transfer_definitions > 0);
    try std.testing.expect(result.counters.scoped_transferred_result_owners > 0);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_completed_plan_rollbacks);
    try std.testing.expect(result.counters.scoped_owned_word_calls > 0);
}

test "completed fresh fixed owners publish reusable plans transactionally through OOM" {
    var module = try lower(a, basic_source);
    defer module.deinit(a);
    try publishFresh(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishFresh, .{@as([]const core.Module, &.{module})});
}

fn aliasSource(width: usize) ![]u8 {
    var types: std.ArrayList(u8) = .empty;
    defer types.deinit(a);
    var fields: std.ArrayList(u8) = .empty;
    defer fields.deinit(a);
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(a);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(a);
    var reads: std.ArrayList(u8) = .empty;
    defer reads.deinit(a);
    for (0..width) |index| {
        const ty = try a.print("f{d}: Array U32,", .{index});
        defer a.free(ty);
        try types.appendSlice(a, ty);
        const field = try a.print("f{d}: words,", .{index});
        defer a.free(field);
        try fields.appendSlice(a, field);
        const left = try a.print("f{d}: original,", .{index});
        defer a.free(left);
        try first.appendSlice(a, left);
        const right = try a.print("f{d}: later,", .{index});
        defer a.free(right);
        try second.appendSlice(a, right);
        const read = try a.print("  first_total := @u32.add self first.f{d}[0]\n  second_total := @u32.add self second.f{d}[1]\n", .{ index, index });
        defer a.free(read);
        try reads.appendSlice(a, read);
    }
    var source = try a.dupe(u8, @import("fixtures").source("fresh_owner_return.blot.in"));
    errdefer a.free(source);
    inline for (.{ "__TYPES__", "__INPUT_TYPES__", "__NESTED_TYPES__", "__FIELDS__", "__FIRST__", "__SECOND__", "__READS__" }, .{ types.items, types.items, types.items, fields.items, first.items, second.items, reads.items }) |placeholder, replacement| {
        const next = try std.mem.replaceOwned(u8, a, source, placeholder, replacement);
        a.free(source);
        source = next;
    }
    return source;
}

test "completed fresh fixed owners preserve duplicate aliases borrowed siblings nested calls and promoted ABI" {
    for ([_]usize{ 8, 128 }) |width| {
        const source = try aliasSource(width);
        defer a.free(source);
        var module = try lower(a, source);
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        try std.testing.expect(result.bytes.len > 8);
        try std.testing.expect(result.counters.scoped_completed_plan_definitions >= 2);
        try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
        try std.testing.expect(result.counters.scoped_result_owner_transfer_definitions > 0);
        try std.testing.expect(result.counters.scoped_transferred_result_owners > 0);
        try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_completed_plan_rollbacks);
        if (width == 8) {
            try std.testing.expect(result.counters.scoped_owned_word_calls > 0);
            try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_owned_packed_calls);
        } else {
            try std.testing.expect(result.counters.scoped_packed_plans_promoted > 0);
            try std.testing.expect(result.counters.scoped_owned_word_calls > 0);
        }
    }
}

const mixed_source =
    \\const choose = func (flag: Bool) -> (input: Array U32): Array U32 => return do:
    \\  if flag:
    \\    return input
    \\  let fresh: Array U32 = #[input[0]]
    \\  return fresh
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let marker: GrowArray U32 = #[input]
    \\  let words: Array U32 = #[marker[0]]
    \\  let first = choose (@u32.eq input 0) words
    \\  let second = choose (@u32.eq input 1) words
    \\  return #[first[0], second[0]]
;
const variant_source =
    \\type Choice is data = $Empty U32 | $Words {values: Array U32}
    \\const choose = func (input: U32): Choice => return do:
    \\  if @u32.eq input 0:
    \\    return $Empty 7
    \\  let fresh: Array U32 = #[input]
    \\  return $Words {values: fresh}
    \\entry const answer = func (input: U32): U32 => return do:
    \\  let marker: GrowArray U32 = #[input]
    \\  let first = choose marker[0]
    \\  let second = choose (@u32.add input 1)
    \\  return case second of
    \\    $Empty value => value
    \\    $Words {values} => values[0]
;
const resize_source =
    \\const fresh = func (input: U32): ResizeArray U32 => return #[input]
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let first = fresh input
    \\  let second = fresh (@u32.add input 1)
    \\  @storage.push first 7
    \\  return #[first[0], second[0], first[1]]
;

test "completed fresh owner contracts retain fallback for mixed origins inactive variants and resize owners" {
    inline for (.{ mixed_source, variant_source, resize_source }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        try std.testing.expect(result.bytes.len > 8);
        try std.testing.expect(result.counters.scoped_completed_plan_rollbacks > 0);
    }
}

test "completed fresh owner transfer rejects bare and caller stored borrow escapes" {
    inline for (.{ "fresh_owner_borrow_escape.blot", "fresh_owner_stored_borrow_escape.blot" }) |path| {
        var module = try lower(a, @import("fixtures").source(path));
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}

test "completed fresh owner roles compact scratch holes and reorder distinct aliased results" {
    var module = try lower(a, @import("fixtures").source("fresh_owner_compacted_roles.blot"));
    defer module.deinit(a);
    try publishFresh(a, &.{module});
}
