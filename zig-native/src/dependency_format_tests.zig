const std = @import("std");
const format = @import("dependency_format.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;
const key: format.Key = .{ .compiler = @as([32]u8, @splat(1)), .settings = @as([32]u8, @splat(2)), .source = @as([32]u8, @splat(3)), .dependencies = @as([32]u8, @splat(4)) };
const Payload = struct { symbols: []const []const u8, modules: []core.Module };
const source =
    \\const identity = fn value => value
    \\entry const answer = fn (value: U32) => @u32.add (identity value) 2
    \\entry const values = fn () => @array.fill 3 (identity 42)
;

test "dependency type wire omits transient solver certificates and owns decoded semantic fields" {
    const T = @import("types.zig");
    const Value = struct { nodes: []const T.Node };
    const clean = [_]T.Node{.{ .tag = .nominal, .a = 7, .b = 11, .c = 19 }};
    const certified = [_]T.Node{.{ .tag = .nominal, .a = 7, .b = 11, .c = 19, .closed_height = 254, .closed_generation = 42 }};
    const plain = try format.encode(a, key, @as(Value, .{ .nodes = &clean }));
    defer a.free(plain);
    const owned = try format.encode(a, key, @as(Value, .{ .nodes = &certified }));
    defer a.free(owned);
    try std.testing.expectEqualSlices(u8, plain, owned);
    var decoded = try format.decode(Value, a, owned, key);
    defer format.deinit(a, &decoded);
    try std.testing.expectEqualDeep(&clean, decoded.nodes);
    try std.testing.expectEqual(@as(u8, 0), decoded.nodes[0].closed_height);
    try std.testing.expectEqual(@as(u16, 0), decoded.nodes[0].closed_generation);
}

test "dependency header discovery owns untrusted keys and cannot replace final admission" {
    const Value = struct { number: u32, flag: bool };
    const value: Value = .{ .number = 42, .flag = true };
    const bytes = try format.encode(a, key, value);
    defer a.free(bytes);
    const discovered = try format.inspectKey(bytes);
    try std.testing.expectEqualDeep(key, discovered);
    try std.testing.expectEqualDeep(key, try format.inspectKey(bytes[0..212]));
    for (0..212) |length| try std.testing.expectError(error.InvalidArtifact, format.inspectKey(bytes[0..length]));

    bytes[0] ^= 1;
    try std.testing.expectError(error.InvalidArtifact, format.inspectKey(bytes));
    bytes[0] ^= 1;
    bytes[8] ^= 1;
    try std.testing.expectError(error.UnsupportedVersion, format.inspectKey(bytes));
    bytes[8] ^= 1;

    // Header discovery deliberately makes no integrity or source-validity claim.
    bytes[12] ^= 1;
    try std.testing.expectEqualDeep(key, try format.inspectKey(bytes));
    try std.testing.expectError(error.SchemaMismatch, format.decode(Value, a, bytes, key));
    bytes[12] ^= 1;
    bytes[bytes.len - 1] ^= 1;
    try std.testing.expectEqualDeep(key, try format.inspectKey(bytes));
    try std.testing.expectError(error.InvalidArtifact, format.decode(Value, a, bytes, key));
    bytes[bytes.len - 1] ^= 1;
    var current = key;
    current.source = format.digest("changed actual producer");
    try std.testing.expectError(error.StaleArtifact, format.decode(Value, a, bytes, current));
    var staged = try format.decode(Value, a, bytes, discovered);
    defer format.deinit(a, &staged);
    try std.testing.expectEqualDeep(value, staged);
    try std.testing.expect(!std.mem.eql(u8, &current.source, &discovered.source));

    bytes[44] ^= 1;
    try std.testing.expectEqualDeep(key, discovered);
    try std.testing.expect(!std.mem.eql(u8, &key.compiler, &(try format.inspectKey(bytes)).compiler));
}

fn lower(allocator: std.mem.Allocator) !core.Module {
    return lowerInput(allocator, source, .{});
}
fn lowerInput(allocator: std.mem.Allocator, input: []const u8, options: checker.ModuleOptions) !core.Module {
    var tokens = try lexer.lex(allocator, input);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, input, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, options);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &names, &checked);
    result.unit = 1;
    return result;
}

test "dependency format preserves every frozen Core table of the unmodified standard prelude" {
    var original = try lowerInput(a, @embedFile("dependency-prelude.blot"), .{ .builtin_catalog = true });
    defer original.deinit(a);
    try std.testing.expect(original.bodies.len > 100);
    try std.testing.expect(original.nominals.len != 0);
    try std.testing.expect(original.associated.len != 0);
    const bytes = try format.encode(a, key, original);
    defer a.free(bytes);
    var loaded = try format.decode(core.Module, a, bytes, key);
    defer format.deinit(a, &loaded);
    const again = try format.encode(a, key, loaded);
    defer a.free(again);
    try std.testing.expectEqualSlices(u8, bytes, again);
    try std.testing.expectEqual(original.body_lowerings, loaded.body_lowerings);
    try std.testing.expect(loaded.types.nodes.ptr != original.types.nodes.ptr);
}

test "dependency format loads owned generic Core after frontend teardown and preserves Wasm" {
    var original = try lower(a);
    defer original.deinit(a);
    var modules = [_]core.Module{original};
    const borrowed: Payload = .{ .symbols = &.{ "identity", "answer", "values", "π😀" }, .modules = &modules };
    const bytes = try format.encode(a, key, borrowed);
    defer a.free(bytes);
    var loaded = try format.decode(Payload, a, bytes, key);
    defer format.deinit(a, &loaded);
    const again = try format.encode(a, key, loaded);
    defer a.free(again);
    try std.testing.expectEqualSlices(u8, bytes, again);
    try std.testing.expectEqualStrings("π😀", loaded.symbols[3]);
    try std.testing.expect(loaded.modules[0].nodes.ptr != original.nodes.ptr);
    var expected = try backend.compile(a, &modules, 1);
    defer expected.deinit(a);
    var observed = try backend.compile(a, loaded.modules, 1);
    defer observed.deinit(a);
    try std.testing.expect(expected.diagnostic == null);
    try std.testing.expect(observed.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.bytes, observed.bytes);
}

const Simple = struct { strings: []const []const u8, tail: union(enum) { closed, variable: u32 }, annotation: ?[]const u8, bits: f32, count: usize, valid: bool };
const simple: Simple = .{ .strings = &.{ "a", "π😀", "" }, .tail = .{ .variable = 27 }, .annotation = "type", .bits = @bitCast(@as(u32, 0x7fc00017)), .count = 1024, .valid = true };

test "dependency format rejects stale keys schema corrupt truncation and resource limits before publishing" {
    const bytes = try format.encode(a, key, simple);
    defer a.free(bytes);
    inline for (@typeInfo(format.Key).@"struct".field_names) |name| {
        var changed = key;
        @field(changed, name)[0] ^= 1;
        try std.testing.expectError(error.StaleArtifact, format.decode(Simple, a, bytes, changed));
    }
    try std.testing.expectError(error.SchemaMismatch, format.decode(struct { different: u32 }, a, bytes, key));
    for (0..bytes.len) |cut| try std.testing.expectError(error.InvalidArtifact, format.decode(Simple, a, bytes[0..cut], key));
    const corrupt = try a.dupe(u8, bytes);
    defer a.free(corrupt);
    corrupt[corrupt.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidArtifact, format.decode(Simple, a, corrupt, key));
    try std.testing.expectError(error.ArtifactLimit, format.decodeWithLimits(Simple, a, bytes, key, .{ .payload_bytes = 1 }));
    try std.testing.expectError(error.ArtifactLimit, format.decodeWithLimits(Simple, a, bytes, key, .{ .elements = 2 }));
    try std.testing.expectError(error.ArtifactLimit, format.decodeWithLimits(Simple, a, bytes, key, .{ .depth = 1 }));
    var loaded = try format.decode(Simple, a, bytes, key);
    defer format.deinit(a, &loaded);
    try std.testing.expectEqual(@as(u32, 0x7fc00017), @as(u32, @bitCast(loaded.bits)));
    try std.testing.expectEqual(@as(u32, 27), loaded.tail.variable);
    try std.testing.expectEqualStrings("type", loaded.annotation.?);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    const bytes = try format.encode(allocator, key, simple);
    defer allocator.free(bytes);
    var loaded = try format.decode(Simple, allocator, bytes, key);
    defer format.deinit(allocator, &loaded);
    try std.testing.expectEqualStrings("π😀", loaded.strings[1]);
}
test "dependency format exhausts encode and partial decoded allocation failures without leaking" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{});
}

fn reseal(bytes: []u8) void {
    @memcpy(bytes[180..212], &format.digest(bytes[212..]));
}
test "dependency format validates decoded enum discriminants boolean tags counts and nested partial owners" {
    const bytes = try format.encode(a, key, simple);
    defer a.free(bytes);
    const changed = try a.dupe(u8, bytes);
    defer a.free(changed);
    changed[changed.len - 1] = 2;
    reseal(changed);
    try std.testing.expectError(error.InvalidArtifact, format.decode(Simple, a, changed, key));
    @memcpy(changed, bytes);
    std.mem.writeInt(u32, changed[212..216], std.math.maxInt(u32), .little);
    reseal(changed);
    try std.testing.expectError(error.ArtifactLimit, format.decode(Simple, a, changed, key));
    @memcpy(changed, bytes);
    // Three strings encode as count4, then (4+1), (4+6), (4+0), so tail starts at235.
    std.mem.writeInt(u32, changed[235..239], 19, .little);
    reseal(changed);
    try std.testing.expectError(error.InvalidArtifact, format.decode(Simple, a, changed, key));
}
