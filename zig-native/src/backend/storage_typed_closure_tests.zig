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
    var checked = try check.checkModule(a, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("closure fixture: {s}\n", .{@tagName(diagnostic.code)});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

test "typed closure definitions share runtime captures across parent diamonds and call sites" {
    for ([_]usize{ 1, 4, 8 }) |sites| {
        var source: std.ArrayList(u8) = .empty;
        defer source.deinit(a);
        try source.appendSlice(a,
            \\const make = func (captured: U32) => return do:
            \\  let saved = captured
            \\  return func (argument: U32): U32 => return @u32.add saved argument
            \\const left = func (captured: U32) -> (argument: U32): U32 => return (make captured) argument
            \\const right = func (captured: U32) -> (argument: U32): U32 => return (make captured) argument
            \\const twice = func (captured: U32) -> (argument: U32): U32 => return @u32.add (left captured argument) (right captured argument)
            \\const outer = func (captured: U32) -> (argument: U32): U32 => return @u32.add (twice captured argument) (twice captured argument)
            \\entry const answer = func (input: U32): U32 => return do:
            \\  let marker: GrowArray U32 = #[input]
            \\  let total: U32 = 0
            \\
        );
        for (0..sites) |site| {
            const call = try a.print("  total := @u32.add total (outer (@u32.add marker[0] {d}) {d})\n", .{ site, site + 1 });
            defer a.free(call);
            try source.appendSlice(a, call);
        }
        try source.appendSlice(a, "  return total\n");
        var module = try lower(source.items);
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        if (result.diagnostic) |diagnostic| std.debug.print("closure diamond: {s}\n", .{diagnostic.message()});
        try std.testing.expect(result.diagnostic == null);
        try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_closure_definitions);
        try std.testing.expect(result.counters.scoped_closure_cache_hits > 0);
        try std.testing.expect(result.counters.scoped_emission_expressions < 1200);
    }
}

test "typed closures share definitions inside shared callback reader parents" {
    var module = try lower(
        \\const make_scalar = func (captured: U32) => return do:
        \\  let saved = captured
        \\  return func (argument: U32): U32 => return @u32.add saved argument
        \\const invoke_left = func (callback: U32 -> U32) -> (argument: U32): U32 => return callback argument
        \\const invoke_right = func (callback: U32 -> U32) -> (argument: U32): U32 => return callback argument
        \\const invoke_twice = func (callback: U32 -> U32) -> (argument: U32): U32 => return @u32.add (invoke_left callback argument) (invoke_right callback argument)
        \\entry const shared_parents = func (input: U32): U32 => return do:
        \\  let marker: GrowArray U32 = #[input]
        \\  let first = invoke_twice (make_scalar marker[0]) 3
        \\  let second = invoke_twice (make_scalar (@u32.add marker[0] 11)) 7
        \\  return @u32.add first second
    );
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("shared parent: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_reader_definitions >= 2);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_closure_definitions);
    try std.testing.expect(result.counters.scoped_closure_cache_hits > 0);
}

const publication_source =
    \\const make = func captured => return do:
    \\  let saved = captured
    \\  return func argument => return {captured: saved, argument}
    \\entry const answer = func (input: U32): U32 => return do:
    \\  let marker: GrowArray U32 = #[input]
    \\  let first = (make marker[0]) 3
    \\  let second = (make (@u32.add marker[0] 11)) 7
    \\  return @u32.add first.captured (@u32.add second.captured second.argument)
;
fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_closure_definitions);
    try std.testing.expect(result.counters.scoped_closure_cache_hits > 0);
}
test "typed aggregate closure publication survives allocation failures" {
    var module = try lower(publication_source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}

const variant_source =
    \\type Choice is data = $Whole U32 | $Fraction F32 | $Absent
    \\const inspect = func (choice: Choice): U32 => return case choice of
    \\  $Whole number => number
    \\  $Fraction number => @u32.add 100 (@f32.to_u32 number)
    \\  $Absent => 31
    \\entry const variants = func (input: U32) => return do:
    \\  let marker: GrowArray U32 = #[input]
    \\  let missing = inspect $Absent
    \\  let whole = inspect ($Whole marker[0])
    \\  let fraction = inspect ($Fraction 3.5)
    \\  let again = inspect ($Whole (@u32.add marker[0] 7))
    \\  let joined = if @u32.eq input 0 then $Absent else $Whole marker[0]
    \\  return #[missing, whole, fraction, again, inspect joined]
;
test "plain call input keys erase constructor refinements while keeping runtime variant states" {
    var module = try lower(variant_source);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_inline_definitions);
    try std.testing.expect(result.counters.scoped_inline_cache_hits >= 3);
}

const semantic_source =
    \\const make = func captured => return do:
    \\  let saved = captured
    \\  return func argument => return {captured: saved, argument}
    \\const left = func captured -> argument => return (make captured) argument
    \\const right = func captured -> argument => return (make captured) argument
    \\const twice = func captured -> argument => return do:
    \\  let first = left captured argument
    \\  let second = right captured argument
    \\  return {captured: first.captured, argument: second.argument}
    \\const outer = func captured -> argument => return do:
    \\  let first = twice captured argument
    \\  let second = twice captured argument
    \\  return {argument: first.argument, captured: second.captured}
    \\entry const integers = func (input: U32) => return do:
    \\  let marker: GrowArray U32 = #[input]
    \\  let first = outer {value: marker[0], stamp: 3} {value: @u32.add marker[0] 7, stamp: 5}
    \\  let second = outer {stamp: 11, value: @u32.add marker[0] 13} {stamp: 17, value: @u32.add marker[0] 19}
    \\  return #[first.captured.value, first.captured.stamp, first.argument.value, first.argument.stamp, second.captured.value, second.captured.stamp, second.argument.value, second.argument.stamp]
    \\entry const floating = func (input: F32) => return do:
    \\  let first = outer {value: input, stamp: 23} {value: -0.0, stamp: 29}
    \\  let second = outer {stamp: 31, value: @f32.add input 1.5} {stamp: 37, value: input}
    \\  return #[first.captured.value, @u32.to_f32 first.captured.stamp, first.argument.value, @u32.to_f32 first.argument.stamp, second.captured.value, @u32.to_f32 second.captured.stamp, second.argument.value, @u32.to_f32 second.argument.stamp]
    \\type First is data = $First {value: U32}
    \\type Second is data = $Second {value: U32}
    \\entry const nominals = func (input: U32) => return do:
    \\  let first = outer ($First {value: input}) ($Second {value: @u32.add input 1})
    \\  let second = outer ($Second {value: @u32.add input 2}) ($First {value: @u32.add input 3})
    \\  return #[first.captured.value, first.argument.value, second.captured.value, second.argument.value]
    \\const reading = func (captured: ResizeArray U32) => return do:
    \\  let saved = captured
    \\  return func (argument: ResizeArray U32): U32 => return @u32.add saved[0] argument[0]
    \\const update = func (captured: ResizeArray U32) -> (argument: ResizeArray U32) -> (amount: U32): Unit => return do:
    \\  let value = (reading captured) argument
    \\  argument[0] := @u32.add value amount
    \\  return ()
    \\entry const descriptors = func (input: U32) => return do:
    \\  let first: ResizeArray U32 = #[input, 31]
    \\  let second: ResizeArray U32 = #[@u32.add input 10, 37]
    \\  update first first 1
    \\  update first second 2
    \\  let total: U32 = 0
    \\  for index in 0 .. 3:
    \\    update first second index
    \\    total := @u32.add total ((reading second) first)
    \\  return #[first[0], second[0], total, first[1], second[1]]
    \\entry const snapshots = func (input: U32) => return do:
    \\  let base = input
    \\  let bound: U32 -> U32 = func value => return @u32.add base value
    \\  let before = bound 1
    \\  base := @u32.add input 99
    \\  return #[before, bound 2, base]
;
test "typed closures admit mixed aggregate schemas and descriptor alias contexts" {
    var module = try lower(semantic_source);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("typed closure: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_closure_definitions > 0);
    try std.testing.expect(result.counters.scoped_closure_cache_hits > 0);
}
