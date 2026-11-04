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

fn publishMutatingBorrow(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 2), result.counters.scoped_completed_plan_definitions);
    try std.testing.expectEqual(@as(u64, 2), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
    try std.testing.expect(result.counters.scoped_function_plan_write_events > 0);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
}

test "completed function mutating borrowed results retain prewrite refs through OOM" {
    var module = try lower(a, simd_source);
    defer module.deinit(a);
    try publishMutatingBorrow(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishMutatingBorrow, .{@as([]const core.Module, &.{module})});
}

fn mutatingOwnerSource(width: usize, comptime path: []const u8) ![]u8 {
    var types: std.ArrayList(u8) = .empty;
    defer types.deinit(a);
    var distinct: std.ArrayList(u8) = .empty;
    defer distinct.deinit(a);
    var shared: std.ArrayList(u8) = .empty;
    defer shared.deinit(a);
    var reads: std.ArrayList(u8) = .empty;
    defer reads.deinit(a);
    for (0..width) |index| {
        const ty = try a.print("f{d}: Array U32,", .{index});
        defer a.free(ty);
        try types.appendSlice(a, ty);
        var owner: []const u8 = "first";
        if (index % 2 != 0) owner = "second";
        const field = try a.print("f{d}: {s},", .{ index, owner });
        defer a.free(field);
        try distinct.appendSlice(a, field);
        const alias = try a.print("f{d}: second,", .{index});
        defer a.free(alias);
        try shared.appendSlice(a, alias);
        const read = try a.print("current.f{d}[0],", .{index});
        defer a.free(read);
        try reads.appendSlice(a, read);
    }
    const template = @import("fixtures").source(path);
    const typed = try std.mem.replaceOwned(u8, a, template, "__TYPES__", types.items);
    defer a.free(typed);
    const first = try std.mem.replaceOwned(u8, a, typed, "__DISTINCT__", distinct.items);
    defer a.free(first);
    const second = try std.mem.replaceOwned(u8, a, first, "__SHARED__", shared.items);
    defer a.free(second);
    return std.mem.replaceOwned(u8, a, second, "__READS__", reads.items);
}

fn publishMutatingOwner(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_function_plan_definitions > 0);
    try std.testing.expect(result.counters.scoped_owner_graph_definitions > 0);
    try std.testing.expect(result.counters.scoped_function_plan_write_events > 0);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
}

test "completed mutating owner results retain shared distinct joined and loop caller roots through OOM" {
    const source = try mutatingOwnerSource(8, "mutating_owner_return.blot.in");
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    try publishMutatingOwner(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishMutatingOwner, .{@as([]const core.Module, &.{module})});
}

test "completed mutating owner results retain addressed wide caller roots" {
    const source = try mutatingOwnerSource(128, "mutating_owner_return.blot.in");
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_function_plan_definitions > 0);
    try std.testing.expect(result.counters.scoped_function_plan_write_events > 0);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
    try std.testing.expect(result.counters.scoped_addressed_definitions + result.counters.scoped_packed_plans_promoted > 0);
    try std.testing.expect(result.counters.scoped_addressed_calls + result.counters.scoped_owned_word_calls > 0);
}

test "completed mutating owner result cache hits reject shorter stored borrows and fresh event escapes" {
    inline for (.{ "mutating_owner_return_lifetime.blot", "mutating_owner_return_event_escape.blot" }) |path| {
        var module = try lower(a, @import("fixtures").source(path));
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
        if (comptime std.mem.eql(u8, path, "mutating_owner_return_lifetime.blot")) {
            try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
        } else {
            try std.testing.expect(result.counters.scoped_completed_plan_rollbacks > 0);
        }
    }
    var module = try lower(a, @import("fixtures").source("mutating_owner_return_truncate.blot"));
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_borrow_conflict, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    try std.testing.expect(result.counters.scoped_completed_plan_definitions > 0);
}

fn publishNestedOwner(allocator: std.mem.Allocator, modules: []const core.Module, width: usize) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
    try std.testing.expect(result.counters.scoped_function_plan_write_events > 0);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
    // Only nested returns descriptors. Each unchanged Array has four words;
    // forwarding three words would leave its owner address in the result slot.
    try std.testing.expect(result.counters.scoped_result_store_words_avoided >= width * 4);
    try std.testing.expect(result.counters.scoped_result_load_words_avoided >= width * 4);
    if (width == 8) {
        try std.testing.expect(result.counters.scoped_owned_word_calls > 0);
        try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_owned_packed_calls);
    } else {
        try std.testing.expect(result.counters.scoped_addressed_definitions + result.counters.scoped_packed_plans_promoted > 0);
        try std.testing.expect(result.counters.scoped_addressed_calls + result.counters.scoped_owned_word_calls > 0);
    }
}

test "completed mutating owner results forward complete descriptors across nested loop writes through OOM" {
    for ([_]usize{ 8, 128 }) |width| {
        const source = try mutatingOwnerSource(width, "mutating_owner_return_nested.blot.in");
        defer a.free(source);
        var module = try lower(a, source);
        defer module.deinit(a);
        try publishNestedOwner(a, &.{module}, width);
        if (width == 8) try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishNestedOwner, .{ @as([]const core.Module, &.{module}), width });
    }
}

fn publishFreshOwnerTransfer(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_completed_plan_definitions > 0);
    try std.testing.expect(result.counters.scoped_result_owner_transfer_definitions > 0);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
}

test "completed mutating owner results transfer fresh fixed result owners through OOM" {
    var module = try lower(a, @import("fixtures").source("mutating_owner_return_fresh.blot"));
    defer module.deinit(a);
    try publishFreshOwnerTransfer(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishFreshOwnerTransfer, .{@as([]const core.Module, &.{module})});
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
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
    var escaped = try lower(a, escape_source);
    defer escaped.deinit(a);
    var rejected = try scoped.compile(a, &.{escaped}, 1);
    defer rejected.deinit(a);
    try std.testing.expect(rejected.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
}

const plain_native_source =
    \\type Vec is data = $Vec {x: U32, y: U32}
    \\type Pose is data = $Pose {position: Vec, stamp: U32}
    \\const Vec.add = func (left: Vec) -> (right: Vec): Vec => return $Vec {x: @u32.add left.x right.x, y: @u32.add left.y right.y}
    \\const translate = func (pose: Pose) -> (shift: Vec): Pose => return do:
    \\  pose.position := @type.call "add" self shift
    \\  return pose
    \\const scratch = func (value: {x: U32, y: U32}): {x: U32, y: U32} => return do:
    \\  let words: Array U32 = #[value.x, value.y]
    \\  value.x := @u32.add words[0] words[1]
    \\  return value
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let live: GrowArray U32 = #[input]
    \\  let before = $Pose {position: $Vec {x: live[0], y: 2}, stamp: 17}
    \\  let first = translate before ($Vec {x: 3,y: 5})
    \\  let second = translate before ($Vec {x: 7,y: 11})
    \\  let a = scratch {x: first.position.x,y: first.position.y}
    \\  let b = scratch {x: second.position.x,y: second.position.y}
    \\  return #[before.position.x,a.x,b.x,first.stamp,second.stamp]
;

const plain_persistent_source =
    \\const pool: ResizeArray U32 = #[4]
    \\const peek = func (value: {x: U32}): {x: U32} => return do:
    \\  value.x := @u32.add self pool[0]
    \\  return value
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let a = peek {x: input}
    \\  @storage.write (@storage.at pool 0) (@u32.add pool[0] 10)
    \\  let b = peek {x: input}
    \\  return #[a.x,b.x,pool[0]]
;

const plain_escape_source =
    \\const bad = func (input: U32): Ref U32 => return do:
    \\  let words: Array U32 = #[input]
    \\  return @storage.at words 0
    \\entry const answer = func (input: U32): U32 => return @storage.load (bad input)
;

fn publishPlainPlans(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 2), result.counters.scoped_plain_plan_definitions);
    try std.testing.expect(result.counters.scoped_writer_cache_hits >= 2);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_owner_graph_inputs);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
}
test "completed plain plans retain functional nominal updates and local scratch results through OOM" {
    var module = try lower(a, plain_native_source);
    defer module.deinit(a);
    try publishPlainPlans(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishPlainPlans, .{@as([]const core.Module, &.{module})});
}
fn publishPlainFallback(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_plain_plan_definitions);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_completed_plan_rollbacks);
    try std.testing.expect(result.counters.scoped_completed_plan_discarded_expressions > 0);
}
test "completed plain plans decline hidden persistent pools and preserve fresh borrow rejection through OOM" {
    var module = try lower(a, plain_persistent_source);
    defer module.deinit(a);
    try publishPlainFallback(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishPlainFallback, .{@as([]const core.Module, &.{module})});
    var escaped = try lower(a, plain_escape_source);
    defer escaped.deinit(a);
    var rejected = try scoped.compile(a, &.{escaped}, 1);
    defer rejected.deinit(a);
    try std.testing.expect(rejected.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
}

const plain_boundary_source =
    \\type Choice is data = $Count U32 | $Pair {x: U32, y: U32}
    \\const floating = func (input: F32): F32 => return do:
    \\  let row = {value: input}
    \\  row.value := @f32.neg self
    \\  return row.value
    \\const unit = func (): Unit => return do:
    \\  let values: Array U32 = #[1]
    \\  values[0] := 2
    \\  return ()
    \\const aggregate = func (): {x: U32, y: U32} => return do:
    \\  let row = {x: 2, y: 3}
    \\  row.x := @u32.add self 5
    \\  return row
    \\const choose = func (flag: Bool) -> (input: U32): Choice => return do:
    \\  let row = {value: input}
    \\  row.value := @u32.add self 1
    \\  if flag:
    \\    return $Count row.value
    \\  return $Pair {x: row.value, y: 17}
    \\const total = func (input: U32): U32 => return do:
    \\  let values: Array U32 = #[input, @u32.add input 1]
    \\  return @u32.add values[0] values[1]
    \\const local_ref = func (input: U32): U32 => return do:
    \\  let value = input
    \\  @storage.write (&value) (@u32.add input 5)
    \\  return value
    \\entry const answer = func (bits: U32): Array U32 => return do:
    \\  let marker: GrowArray U32 = #[bits]
    \\  let (input,a,b,c) = @simd.u32x4.from_bits (bits,bits,bits,bits)
    \\  let result = floating input
    \\  let (output,d,e,f) = @simd.f32x4.bits (result,result,result,result)
    \\  unit ()
    \\  unit ()
    \\  let record = aggregate ()
    \\  let again = aggregate ()
    \\  let first = total marker[0]
    \\  let second = total (@u32.add marker[0] 1)
    \\  let local = local_ref marker[0]
    \\  let choice = choose (@u32.eq (@u32.rem bits 2) 0) bits
    \\  let selected = case choice of
    \\    $Count value => value
    \\    $Pair {x,y} => @u32.add x y
    \\  return #[output,record.x,record.y,again.x,again.y,first,second,local,marker[0],selected]
;

fn publishPlainBoundaries(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 6), result.counters.scoped_plain_plan_definitions);
    try std.testing.expect(result.counters.scoped_plain_plan_hits >= 3);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_owner_graph_inputs);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
}
test "completed plain word ABI retains scalar float nullary variants scratch and local references through OOM" {
    var module = try lower(a, plain_boundary_source);
    defer module.deinit(a);
    try publishPlainBoundaries(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishPlainBoundaries, .{@as([]const core.Module, &.{module})});
}
