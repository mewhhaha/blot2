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

fn graphSource(depth: usize) ![]u8 {
    var source: std.ArrayList(u8) = .empty;
    errdefer source.deinit(a);
    try source.appendSlice(a,
        \\const read_0 = func (rows: GrowArray U32): U32 => return @storage.read rows 0
        \\const write_0 = func (rows: GrowArray U32) -> (amount: U32): Unit => return do:
        \\  @storage.write (@storage.at rows 0) (@u32.add (read_0 rows) amount)
        \\
    );
    for (1..depth + 1) |level| {
        const stage = try a.print("const read_{d} = func (rows: GrowArray U32): U32 => return @u32.add (read_{d} rows) (read_{d} rows)\n" ++
            "const write_{d} = func (rows: GrowArray U32) -> (amount: U32): Unit => return do:\n" ++
            "  write_{d} rows amount\n  write_{d} rows (@u32.add amount 1)\n", .{ level, level - 1, level - 1, level, level - 1, level - 1 });
        defer a.free(stage);
        try source.appendSlice(a, stage);
    }
    const entry = try a.print("entry const answer = func (input: U32): U32 => return do:\n" ++
        "  let first: GrowArray U32 = #[input]\n  let second: GrowArray U32 = #[@u32.add input 101]\n" ++
        "  let total: U32 = 0\n  for index in 0 .. 3:\n" ++
        "    write_{d} first input\n    write_{d} second (@u32.add input index)\n" ++
        "    total := @u32.add total (@u32.add (read_{d} first) (read_{d} second))\n" ++
        "  return @u32.add total (@u32.add (read_{d} first) (read_{d} second))\n", .{ depth, depth, depth, depth, depth, depth });
    defer a.free(entry);
    try source.appendSlice(a, entry);
    return source.toOwnedSlice(a);
}

test "storage descriptor DAGs share nested reader and writer definitions" {
    const small_source = try graphSource(2);
    defer a.free(small_source);
    const large_source = try graphSource(8);
    defer a.free(large_source);
    var small = try lower(a, small_source);
    defer small.deinit(a);
    var large = try lower(a, large_source);
    defer large.deinit(a);
    var shallow = try scoped.compile(a, &.{small}, 1);
    defer shallow.deinit(a);
    var deep = try scoped.compile(a, &.{large}, 1);
    defer deep.deinit(a);
    try std.testing.expect(shallow.diagnostic == null);
    try std.testing.expect(deep.diagnostic == null);
    try std.testing.expect(deep.counters.scoped_reader_definitions > 0);
    try std.testing.expect(deep.counters.scoped_reader_cache_hits > 0);
    try std.testing.expect(deep.counters.scoped_writer_definitions > 0);
    try std.testing.expect(deep.counters.scoped_writer_cache_hits > 0);
    try std.testing.expect(deep.counters.scoped_descriptor_admission_hits > 0);
    // Six more levels should add bounded definitions rather than copying 256 leaves.
    try std.testing.expect(deep.counters.scoped_emission_expressions < shallow.counters.scoped_emission_expressions + 2_000);
    try std.testing.expect(deep.counters.scoped_call_admission_nodes < shallow.counters.scoped_call_admission_nodes + 2_000);
    try std.testing.expect(deep.bytes.len < shallow.bytes.len + 20_000);
    try std.testing.expect(deep.emitted_functions <= shallow.emitted_functions + 24);
}

fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_reader_definitions > 0);
    try std.testing.expect(result.counters.scoped_writer_definitions > 0);
}

test "storage descriptor DAG publication survives allocation failures" {
    const source = try graphSource(2);
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
