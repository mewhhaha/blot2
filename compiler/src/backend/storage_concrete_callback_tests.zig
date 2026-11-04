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
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn fieldName(index: usize) ![]u8 {
    return a.print("f{d}", .{index});
}

fn callbackSource(width: usize, calls: usize) ![]u8 {
    var fields: std.ArrayList(u8) = .empty;
    defer fields.deinit(a);
    var members: std.ArrayList(u8) = .empty;
    defer members.deinit(a);
    var declarations: std.ArrayList(u8) = .empty;
    defer declarations.deinit(a);
    var reads: std.ArrayList(u8) = .empty;
    defer reads.deinit(a);

    for (0..width) |index| {
        const name = try fieldName(index);
        defer a.free(name);
        if (index != 0) {
            try fields.appendSlice(a, ", ");
            try members.appendSlice(a, ", ");
        }
        try fields.appendSlice(a, name);
        try fields.appendSlice(a, ": Array U32");
        try members.appendSlice(a, name);
        try members.appendSlice(a, ": owner_");
        const owner = try a.print("{d}", .{index});
        defer a.free(owner);
        try members.appendSlice(a, owner);

        const declaration = try a.print("  let owner_{d}: Array U32 = #[@u32.add input {d}]\n", .{ index, index });
        defer a.free(declaration);
        try declarations.appendSlice(a, declaration);
        const formatted = try a.print("  result := @u32.add self bundle.{s}[0]\n", .{name});
        defer a.free(formatted);
        try reads.appendSlice(a, formatted);
    }

    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "type Bundle is data = $Bundle {");
    try source.appendSlice(a, fields.items);
    try source.appendSlice(a,
        \\}
        \\const checksum = func (bundle: Bundle): U32 => return do:
        \\  let result = 0
    );
    try source.appendSlice(a, "\n");
    try source.appendSlice(a, reads.items);
    try source.appendSlice(a,
        \\  return result
        \\const visit = func (bundle: Bundle) -> (first: Unit -> U32 ! {}) -> (second: Unit -> U32 ! {}) -> (third: Unit -> U32 ! {}) -> (fourth: Unit -> U32 ! {}): U32 => return do:
        \\  let result = checksum bundle
        \\  result := @u32.add self (first ())
        \\  result := @u32.add self (second ())
        \\  result := @u32.add self (third ())
        \\  result := @u32.add self (fourth ())
        \\  return result
        \\entry const answer = func (input: U32): U32 => return do:
        \\  let marker: Array U32 = #[0]
        \\  marker[0] := input
    );
    try source.appendSlice(a, "\n");
    try source.appendSlice(a, declarations.items);
    try source.appendSlice(a, "  let bundle = $Bundle {");
    try source.appendSlice(a, members.items);
    try source.appendSlice(a, "\n");
    try source.appendSlice(a,
        \\  }
        \\  let first = func (): U32 => return checksum bundle
        \\  let second = func (): U32 => return checksum bundle
        \\  let third = func (): U32 => return checksum bundle
        \\  let fourth = func (): U32 => return checksum bundle
    );
    try source.appendSlice(a, "\n");
    try source.appendSlice(a, "  let total = 0\n");
    for (0..calls) |index| {
        const call = try a.print("  let visit_{d} = visit bundle first second third fourth\n", .{index});
        defer a.free(call);
        try source.appendSlice(a, call);
        const accumulated = try a.print("  total := @u32.add self visit_{d}\n", .{index});
        defer a.free(accumulated);
        try source.appendSlice(a, accumulated);
    }
    try source.appendSlice(a, "  return total\n");
    return try source.toOwnedSlice(a);
}

fn checkConcreteQualifiers(module: *const core.Module) !void {
    try std.testing.expect(module.closures.len >= 4);
    for (module.closures) |closure| {
        try std.testing.expect(closure.qualifier != 0);
        try std.testing.expect(closure.closed_rows.len > 0);
        const binding = module.bindings[closure.qualifier];
        try std.testing.expectEqual(@as(u32, 0), binding.scheme.variables.len);
        try std.testing.expectEqual(@as(u32, 0), binding.scheme.row_variables.len);
        try std.testing.expectEqual(@as(u32, 0), binding.scheme.obligations.len);
        try std.testing.expectEqual(@as(u32, 0), binding.scheme.generative.len);
        try std.testing.expectEqual(@as(u32, 0), binding.public_variables.len);
        try std.testing.expectEqual(@as(u32, 0), binding.public_rows.len);
    }
}

fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_input_alias_words_avoided >= 128);
    try std.testing.expect(result.counters.scoped_completed_plan_definitions >= 2);
    try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
}

test "closed concrete callback qualifiers admit wide exact alias partitions" {
    for ([_]usize{ 1, 8 }) |calls| {
        const source = try callbackSource(32, calls);
        defer a.free(source);
        var module = try lower(source);
        defer module.deinit(a);
        try checkConcreteQualifiers(&module);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        try std.testing.expect(result.bytes.len > 8);
        try std.testing.expect(result.counters.scoped_input_alias_words_avoided >= 512);
        try std.testing.expect(result.counters.scoped_addressed_definitions > 0);
        try std.testing.expect(result.counters.scoped_completed_plan_definitions >= 2);
        try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
        try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
    }
}

test "closed concrete callback qualifier publication survives allocation failures" {
    const source = try callbackSource(8, 1);
    defer a.free(source);
    var module = try lower(source);
    defer module.deinit(a);
    try checkConcreteQualifiers(&module);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}

fn publishAddressed(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_addressed_definitions > 0);
    try std.testing.expect(result.counters.scoped_addressed_calls > 0);
    try std.testing.expect(result.counters.scoped_addressed_input_loads > 0);
    try std.testing.expect(result.counters.scoped_addressed_snapshot_words > 0);
    try std.testing.expect(result.counters.scoped_addressed_retained_bytes_max <= 32 * 1024);
    try std.testing.expect(result.counters.scoped_addressed_retained_slots_max <= 8);
    try std.testing.expectEqual(result.counters.scoped_addressed_retries, result.counters.scoped_completed_plan_rollbacks);
}

test "addressed callback publication retains snapshot ownership and bounded storage through full OOM" {
    const source = try callbackSource(16, 2);
    defer a.free(source);
    var module = try lower(source);
    defer module.deinit(a);
    try publishAddressed(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishAddressed, .{@as([]const core.Module, &.{module})});
}
