const std = @import("std");
const format = @import("dependency_format.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const a = std.testing.allocator;
const key: format.Key = .{ .compiler = @as([32]u8, @splat(1)), .settings = @as([32]u8, @splat(2)), .source = @as([32]u8, @splat(3)), .dependencies = @as([32]u8, @splat(4)) };
const Payload = struct { symbols: []const []const u8, modules: []core.Module };
const source =
    \\const identity = func value => return value
    \\entry const answer = func (value: U32) => return @u32.add (identity value) 2
    \\entry const values = func () => return @array.fill 3 (identity 42)
;

test "dependency invocation wire keeps ordinary payloads compact and validates ordered arguments" {
    const P = @import("../check/capability_flow.zig").Parameters;
    const ordinary = try format.encode(a, key, P.init(3, 5));
    defer a.free(ordinary);
    try std.testing.expectEqual(@as(usize, 212 + 3), ordinary.len);
    try std.testing.expectEqualSlices(u8, &.{ 0, 5, 3 }, ordinary[212..]);
    try std.testing.expectEqualDeep(P.init(3, 5), try format.decode(P, a, ordinary, key));
    const invocation: P = .{ .kind = .invoke_inputs, .mask = 0x8000, .inputs = 16, .invocation_count = 16, .invocation_arguments = 0xe0123456789abcde };
    try std.testing.expect(invocation.valid());
    const bytes = try format.encode(a, key, invocation);
    defer a.free(bytes);
    try std.testing.expectEqual(@as(usize, 212 + 16), bytes.len);
    try std.testing.expectEqualDeep(invocation, try format.decode(P, a, bytes, key));
    for ([_]P{
        .{ .kind = .invoke_inputs, .inputs = 3, .mask = 1, .invocation_count = 2, .invocation_arguments = 0x20 },
        .{ .kind = .invoke_inputs, .inputs = 3, .mask = 1, .invocation_count = 2, .invocation_arguments = 0x31 },
        .{ .kind = .invoke_inputs, .inputs = 3, .mask = 1, .invocation_count = 2, .invocation_arguments = 0x121 },
        .{ .kind = .invoke_inputs, .inputs = 3, .mask = 3, .invocation_count = 2, .invocation_arguments = 0x21 },
        .{ .kind = .invoke_inputs, .inputs = 3, .mask = 1, .invocation_count = 17, .invocation_arguments = 0x21 },
    }) |invalid| {
        try std.testing.expect(!invalid.valid());
        const forged = try format.encode(a, key, invalid);
        defer a.free(forged);
        try std.testing.expectError(error.InvalidArtifact, format.decode(P, a, forged, key));
    }
}

test "dependency type wire omits transient solver certificates and owns decoded semantic fields" {
    const T = @import("../check/types.zig");
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
    var original = try lowerInput(a, @import("fixtures").source("dependency-prelude.blot"), .{ .builtin_catalog = true });
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{});
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
    // The string count, as the five-byte LEB128 of the largest u32.
    @memcpy(changed[212..217], &[_]u8{ 0xff, 0xff, 0xff, 0xff, 0x0f });
    reseal(changed);
    try std.testing.expectError(error.ArtifactLimit, format.decode(Simple, a, changed, key));
    @memcpy(changed, bytes);
    // Three strings encode as count1, then (1+1), (1+6), (1+0), so the tail
    // tag is at 223.
    changed[223] = 19;
    reseal(changed);
    try std.testing.expectError(error.InvalidArtifact, format.decode(Simple, a, changed, key));
    // Only the shortest encoding of a length decodes.
    @memcpy(changed, bytes);
    try std.testing.expectEqual(@as(u8, 3), changed[212]);
    const padded = try std.mem.concat(a, u8, &.{ changed[0..212], &.{ 0x83, 0x00 }, changed[213..] });
    defer a.free(padded);
    std.mem.writeInt(u64, padded[172..180], padded.len - 212, .little);
    reseal(padded);
    try std.testing.expectError(error.InvalidArtifact, format.decode(Simple, a, padded, key));
}

test "dependency format integers round-trip at every width and sign through LEB128" {
    const Wide = struct { small: u8, signed: i8, word: u16, half: i32, full: u64, negative: i64, size: usize, list: []const u32 };
    const cases = [_]Wide{
        .{ .small = 0, .signed = 0, .word = 0, .half = 0, .full = 0, .negative = 0, .size = 0, .list = &.{} },
        .{ .small = 255, .signed = -128, .word = 0xffff, .half = std.math.minInt(i32), .full = std.math.maxInt(u64), .negative = std.math.minInt(i64), .size = std.math.maxInt(usize), .list = &.{ 0, 127, 128, 16383, 16384, std.math.maxInt(u32) } },
        .{ .small = 1, .signed = 127, .word = 128, .half = std.math.maxInt(i32), .full = 1 << 63, .negative = std.math.maxInt(i64), .size = 1, .list = &.{1} },
    };
    for (cases) |case| {
        const bytes = try format.encode(a, key, case);
        defer a.free(bytes);
        var decoded = try format.decode(Wide, a, bytes, key);
        defer format.deinit(a, &decoded);
        try std.testing.expectEqualDeep(case, decoded);
    }
}
