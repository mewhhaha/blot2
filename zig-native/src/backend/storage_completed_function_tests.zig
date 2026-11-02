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

const truncate_source =
    \\type Row is data = $Row {target: Ref U32}
    \\const bump = func (rows: ResizeArray Row): Unit => return do:
    \\  for row in rows:
    \\    @storage.write row.target (@u32.add (@storage.load row.target) 1)
    \\const change = func (rows: ResizeArray Row): U32 => return do:
    \\  bump rows
    \\  @storage.truncate rows 1
    \\  return @storage.length rows
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let left: Array U32 = #[input]
    \\  let right: Array U32 = #[@u32.add input 10]
    \\  let rows: ResizeArray Row = #[$Row {target: @storage.at left 0}, $Row {target: @storage.at right 0}]
    \\  let count = change rows
    \\  return #[left[0], right[0], count]
;
const reserve_source =
    \\type Row is data = $Row {target: Ref U32}
    \\const bump = func (rows: ResizeArray Row): Unit => return do:
    \\  for row in rows:
    \\    @storage.write row.target (@u32.add (@storage.load row.target) 1)
    \\const change = func (rows: ResizeArray Row): U32 => return do:
    \\  bump rows
    \\  @storage.reserve rows 4
    \\  @storage.push rows (@storage.read rows 0)
    \\  return @storage.length rows
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let left: Array U32 = #[input]
    \\  let right: Array U32 = #[@u32.add input 10]
    \\  let rows: ResizeArray Row = #[$Row {target: @storage.at left 0}, $Row {target: @storage.at right 0}]
    \\  let count = change rows
    \\  return #[left[0], right[0], count]
;
const freeze_source =
    \\type Row is data = $Row {target: Ref U32}
    \\const bump = func (rows: ResizeArray Row): Unit => return do:
    \\  for row in rows:
    \\    @storage.write row.target (@u32.add (@storage.load row.target) 1)
    \\const change = func (rows: ResizeArray Row): U32 => return do:
    \\  bump rows
    \\  let frozen = @storage.freeze rows
    \\  return @storage.length frozen
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let left: Array U32 = #[input]
    \\  let right: Array U32 = #[@u32.add input 10]
    \\  let rows: ResizeArray Row = #[$Row {target: @storage.at left 0}, $Row {target: @storage.at right 0}]
    \\  let count = change rows
    \\  return #[left[0], right[0], count]
;
const simd_source =
    \\const target = func (words: Array U32): Ref U32 => return @storage.at words 0
    \\const change = func (words: Array U32): Ref U32 => return do:
    \\  let place = target words
    \\  let changed = @simd.store words 0 (9,8,7,6)
    \\  return place
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let first: Array U32 = #[input,2,3,4]
    \\  let second: Array U32 = #[5,6,7,input]
    \\  let a = change first
    \\  let b = change second
    \\  return #[@storage.load a, first[1], first[2], first[3], @storage.load b, second[1], second[2], second[3]]
;
const borrow_source =
    \\type Row is data = $Row {target: Ref U32}
    \\const target = func (rows: Array Row): Ref U32 => return (@storage.read rows 0).target
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let first: Array U32 = #[input]
    \\  let second: Array U32 = #[@u32.add input 10]
    \\  let a: Array Row = #[$Row {target: @storage.at first 0}]
    \\  let b: Array Row = #[$Row {target: @storage.at second 0}]
    \\  let left = target a
    \\  let right = target b
    \\  @storage.write left (@u32.add (@storage.load left) 1)
    \\  @storage.write right (@u32.add (@storage.load right) 2)
    \\  return #[first[0],second[0],@storage.load left,@storage.load right]
;
const escape_source =
    \\type Row is data = $Row {target: Ref U32}
    \\const target = func (rows: Array Row): Ref U32 => return (@storage.read rows 0).target
    \\const escape = func (): Ref U32 => return do:
    \\  let values: Array U32 = #[7]
    \\  let rows: Array Row = #[$Row {target: @storage.at values 0}]
    \\  return target rows
    \\entry const answer = func (): U32 => return @storage.load (escape ())
;

fn publishRollback(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_completed_plan_rollbacks);
    try std.testing.expect(result.counters.scoped_completed_plan_discarded_expressions > 0);
    // The nested helper from the rejected function must be removed and safely
    // recreated by ordinary inline fallback, rather than left orphaned.
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_completed_plan_definitions);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_owner_graph_definitions);
}

test "completed function rollback removes nested helpers before truncate reserve and freeze through OOM" {
    inline for (.{ truncate_source, reserve_source, freeze_source }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try publishRollback(a, &.{module});
    }
    var module = try lower(a, truncate_source);
    defer module.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishRollback, .{@as([]const core.Module, &.{module})});
}

test "completed function read only borrowed results decline SIMD stores before inline fallback through OOM" {
    var module = try lower(a, simd_source);
    defer module.deinit(a);
    try publishRollback(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishRollback, .{@as([]const core.Module, &.{module})});
}

test "completed function borrowed results reuse distinct caller owners and preserve lifetime rejection" {
    var module = try lower(a, borrow_source);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_completed_plan_definitions);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_completed_plan_rollbacks);
    var escaped = try lower(a, escape_source);
    defer escaped.deinit(a);
    var rejected = try scoped.compile(a, &.{escaped}, 1);
    defer rejected.deinit(a);
    try std.testing.expect(rejected.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
}
