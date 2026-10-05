const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(a, &syntax, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    module.unit = 1;
    return module;
}
const Control = struct { source: []const u8, expected: ?backend.Code, zero_steps: bool = false, diagnostic_start: ?u32 = null };
const controls = [_]Control{
    .{ .source = "entry const answer = fn argument => @type.same argument argument\n", .expected = .entry_type, .zero_steps = true },
    .{ .source = "entry const answer: U32 -> Bool = fn argument => @type.same argument argument\n", .expected = null },
    .{ .source = "entry const answer = fn argument => argument\nentry const failure = @type.same (@panic \"left witness\") (@panic \"right witness\")\n", .expected = .invalid_annotation, .zero_steps = true },
    .{ .source = "entry const answer = @array.get #[] 0\n", .expected = .entry_type, .zero_steps = true },
    .{ .source = "entry const answer = @panic \"boom\"\n", .expected = .entry_type, .zero_steps = true },
    .{ .source = "entry const earlier: U32 = @panic \"earlier\"\nentry const answer = @array.get #[] 0\n", .expected = .entry_type, .zero_steps = true },
    .{ .source = "entry const answer: U32 = @array.get #[] 0\n", .expected = .array_bounds },
    .{ .source = "entry const answer: F32 = @array.get #[] 0\n", .expected = .array_bounds },
    .{ .source = "entry const answer: U32 = @panic \"boom\"\n", .expected = .const_panic },
    .{ .source = "entry const answer = if #True then 42 else @panic \"unreachable\"\n", .expected = null },
    .{ .source = "const maker = fn captured => fn (value: U32) => @u32.add captured value\nentry const answer = maker 21\n", .expected = null },
    // Frozen witness selection validates source types before value evaluation.
    .{ .source = "entry const failure = @type.same (@panic \"left witness\") (@panic \"right witness\")\n", .expected = .invalid_annotation, .zero_steps = true },
    .{ .source = "const compare = fn left => fn right => @type.same left right\nentry const failure = compare (@panic \"left witness\") (@panic \"right witness\")\n", .expected = .invalid_annotation, .zero_steps = true },
    .{ .source = "const compare = fn left => fn right => @type.same left right\nconst alias = compare\nentry const failure = alias (@panic \"left witness\") (@panic \"right witness\")\n", .expected = .ambiguous_associated, .zero_steps = true },
    .{ .source = "const unused = fn left => fn right => @type.same left right\nentry const failure = @type.same (@panic \"left witness\") (@panic \"right witness\")\n", .expected = .invalid_annotation, .zero_steps = true },
    .{ .source = "entry const answer = do:\n  let selected: U32 where {associated \"missing\" Bool Bool Bool} = 42\n  return @array.get #[] 0\n", .expected = .missing_associated, .zero_steps = true },
    // An unused callable's clauses remain suspended during source selection.
    .{ .source = "entry const answer = do:\n  let selected: U32 -> U32 where {associated \"missing\" Bool Bool Bool} = fn value => value\n  return @array.get #[] 0\n", .expected = .entry_type, .zero_steps = true },
    .{ .source = "entry let earlier: Array U32 = #[]\nentry const answer = @array.get #[] 0\n", .expected = .entry_let_type, .zero_steps = true, .diagnostic_start = 10 },
    .{ .source = "entry const earlier = fn value => value\nentry const answer = @array.get #[] 0\n", .expected = .entry_type, .zero_steps = true, .diagnostic_start = 12 },
};
fn emission(allocator: std.mem.Allocator, module: *const core.Module, control: Control) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(control.expected, if (result.diagnostic) |diagnostic| diagnostic.code else null);
    if (control.diagnostic_start) |start| try std.testing.expectEqual(start, result.diagnostic.?.span.start);
    if (control.zero_steps) try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    if (control.expected != null and !control.zero_steps) try std.testing.expect(result.constant_steps > 0);
    if (control.expected == null) try std.testing.expect(result.bytes.len > 8);
}
fn frozenScenario(module: *const core.Module, control: Control) !void {
    const source_names = try a.dupe(core.RuntimeName, module.source_names);
    defer a.free(source_names);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const bindings = try a.dupe(core.Binding, module.bindings);
    defer a.free(bindings);
    const bodies = try a.dupe(core.Body, module.bodies);
    defer a.free(bodies);
    const type_nodes = try a.dupe(@import("types.zig").Node, module.types.nodes);
    defer a.free(type_nodes);
    const extra = try a.dupe(u32, module.types.extra);
    defer a.free(extra);
    const rows = try a.dupe(@import("effects.zig").Row, module.types.effects.rows);
    defer a.free(rows);
    const labels = try a.dupe(u32, module.types.effects.labels);
    defer a.free(labels);
    try emission(a, module, control);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emission, .{ module, control });
    try std.testing.expectEqualSlices(core.RuntimeName, source_names, module.source_names);
    try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
    try std.testing.expectEqualSlices(core.Binding, bindings, module.bindings);
    try std.testing.expectEqualSlices(core.Body, bodies, module.bodies);
    try std.testing.expectEqualSlices(@import("types.zig").Node, type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(u32, extra, module.types.extra);
    try std.testing.expectEqualSlices(@import("effects.zig").Row, rows, module.types.effects.rows);
    try std.testing.expectEqualSlices(u32, labels, module.types.effects.labels);
}
test "unconstrained value entry rejection precedes eager constants while explicit interfaces preserve bounds and panic under every allocation failure" {
    for (controls) |control| {
        var module = try lower(control.source);
        defer module.deinit(a);
        try frozenScenario(&module, control);
    }
}

test "owned entry validation remains complete beyond the former structural certificate limit" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const unused = [");
    for (0..4096) |_| try source.appendSlice(a, "0,");
    try source.appendSlice(a, "0]\nentry const answer = @panic \"boom\"\n");
    var module = try lower(source.items);
    defer module.deinit(a);
    try emission(a, &module, .{ .source = source.items, .expected = .entry_type, .zero_steps = true });
}

const nominal_entry_source =
    \\type Box is data = #Box U32
    \\const Box.read: Box -> U32 where {} = fn (value: Box) => value.read
    \\entry const selected: Box -> U32 = fn value => value.read
    \\entry const answer = 42
;
const nominal_entry_suffix = "::Box -> U32), which does not fit the guest ABI: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool";

fn nominalEntryScenario(allocator: std.mem.Allocator, module: *const core.Module, source_mode: bool) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var identity = try @import("runtime_identity.zig").Metadata.capture(allocator, &pool, &.{.{ .unit = 1, .path = "/project/renamed.blot" }}, 1);
    var identity_alive = true;
    defer if (identity_alive) identity.deinit(allocator);
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .identity = identity.view(), .diagnostic_source_mode = source_mode });
    defer result.deinit(allocator);
    identity.deinit(allocator);
    identity_alive = false;
    try std.testing.expectEqual(backend.Code.entry_type, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    const origin = if (source_mode) "main" else "renamed.blot";
    const expected = try allocator.print("entry `selected` has type ({s}{s}", .{ origin, nominal_entry_suffix });
    defer allocator.free(expected);
    try std.testing.expectEqualStrings(expected, result.diagnostic.?.message());
    try std.testing.expectEqualSlices(u8, result.owned_message, result.diagnostic.?.detail);
}

test "nominal entry diagnostics use the current context after identity destruction under every allocation failure" {
    var module = try lower(nominal_entry_source);
    defer module.deinit(a);
    for ([_]bool{ true, false }) |source_mode| {
        try nominalEntryScenario(a, &module, source_mode);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, nominalEntryScenario, .{ &module, source_mode });
    }
}

test "nominal entry diagnostic text outlives the frozen Core owner" {
    var result = owned: {
        var module = try lower(nominal_entry_source);
        defer module.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var identity = try @import("runtime_identity.zig").Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/project/other-name.blot" }}, 1);
        defer identity.deinit(a);
        break :owned try backend.compileWithOptions(a, &.{module}, 1, .{ .identity = identity.view(), .diagnostic_source_mode = true });
    };
    defer result.deinit(a);
    try std.testing.expectEqualStrings("entry `selected` has type (main" ++ nominal_entry_suffix, result.diagnostic.?.message());
    try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
}

const closed_effect_entry_controls = [_]struct { source: []const u8, message: []const u8, point: u32 }{
    .{ .source = "type Audit is effect = { probe: Unit -> Unit }\nconst unused_request = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Audit.probe () =>\n        yield ()\n      complete value =>\n        return value\nentry const answer = fn (host: U32 -> U32) => host 41\n", .message = "entry `answer` has type ((U32 -> U32) -> U32), which does not fit the guest ABI: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool", .point = 257 },
    .{ .source = "type Audit is effect = { probe: Unit -> Unit }\nconst unused_request = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Audit.probe () =>\n        yield ()\n      complete value =>\n        return value\neffect Other: Unit -> Unit\nentry const answer = fn (host: U32 -> U32 ! {Other}) => host 41\n", .message = "entry `answer` has type ((U32 -> U32 ! {main::Other}) -> U32 ! {main::Other}), which does not fit the guest ABI: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool", .point = 284 },
    .{ .source = "type Audit is effect = { probe: Unit -> Unit }\nconst unused_request = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Audit.probe () =>\n        yield ()\n      complete value =>\n        return value\neffect Other: Unit -> Unit\nentry const answer = fn (host: U32 -> U32 ! {Foreign, Other}) => host 41\n", .message = "entry `answer` has type ((U32 -> U32 ! {blot:compiler::Foreign, main::Other}) -> U32 ! {blot:compiler::Foreign, main::Other}), which does not fit the guest ABI: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool", .point = 284 },
    .{ .source = "type Audit is effect = { probe: Unit -> Unit }\nconst unused_request = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Audit.probe () =>\n        yield ()\n      complete value =>\n        return value\nentry const answer = fn (host: (U32, U32) -> U32 ! {Foreign}) => host (20, 22)\n", .message = "entry `answer` has type (((U32, U32) -> U32 ! {blot:compiler::Foreign}) -> U32 ! {blot:compiler::Foreign}), which does not fit the guest ABI: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool", .point = 257 },
    .{ .source = "type Audit is effect = { probe: Unit -> Unit }\nconst unused_request = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Audit.probe () =>\n        yield ()\n      complete value =>\n        return value\nentry const answer = fn (host: Unit -> (U32, U32) ! {Foreign}) => @product.get (host ()) 0\n", .message = "entry `answer` has type ((Unit -> (U32, U32) ! {blot:compiler::Foreign}) -> U32 ! {blot:compiler::Foreign}), which does not fit the guest ABI: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool", .point = 257 },
    .{ .source = "type Audit is effect = { probe: Unit -> Unit }\nconst unused_request = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Audit.probe () =>\n        yield ()\n      complete value =>\n        return value\ntype Token is data = #Token U32\nentry const answer = fn (host: Token -> U32 ! {Foreign}) => host (#Token 41)\n", .message = "entry `answer` has type ((main::Token -> U32 ! {blot:compiler::Foreign}) -> U32 ! {blot:compiler::Foreign}), which does not fit the guest ABI: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool", .point = 289 },
};

fn closedEffectEntryScenario(allocator: std.mem.Allocator, module: *const core.Module, control: @typeInfo(@TypeOf(closed_effect_entry_controls)).array.child) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var identity = try @import("runtime_identity.zig").Metadata.capture(allocator, &pool, &.{.{ .unit = 1, .path = "/project/renamed.blot" }}, 1);
    var identity_alive = true;
    defer if (identity_alive) identity.deinit(allocator);
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .identity = identity.view(), .diagnostic_source_mode = true });
    defer result.deinit(allocator);
    identity.deinit(allocator);
    identity_alive = false;
    try std.testing.expectEqual(backend.Code.entry_type, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    try std.testing.expectEqual(control.point, result.diagnostic.?.span.start);
    try std.testing.expectEqual(control.point, result.diagnostic.?.span.end);
    try std.testing.expectEqualStrings(control.message, result.diagnostic.?.message());
    try std.testing.expectEqualSlices(u8, result.owned_message, result.diagnostic.?.detail);
}

test "closed callback entry diagnostics print selected effects under every allocation failure" {
    for (closed_effect_entry_controls) |control| {
        var module = try lower(control.source);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const type_nodes = try a.dupe(@import("types.zig").Node, module.types.nodes);
        defer a.free(type_nodes);
        const rows = try a.dupe(@import("types.zig").Effects.Row, module.types.effects.rows);
        defer a.free(rows);
        try closedEffectEntryScenario(a, &module, control);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, closedEffectEntryScenario, .{ &module, control });
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
        try std.testing.expectEqualDeep(rows, module.types.effects.rows);
    }
}

test "closed callback entry diagnostic text outlives its Core and identity owners" {
    for (closed_effect_entry_controls) |control| {
        var result = owned: {
            var module = try lower(control.source);
            defer module.deinit(a);
            var pool: symbols.Pool = .{};
            defer pool.deinit(a);
            var identity = try @import("runtime_identity.zig").Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/project/other-name.blot" }}, 1);
            defer identity.deinit(a);
            break :owned try backend.compileWithOptions(a, &.{module}, 1, .{ .identity = identity.view(), .diagnostic_source_mode = true });
        };
        defer result.deinit(a);
        try std.testing.expectEqualStrings(control.message, result.diagnostic.?.message());
        try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    }
}
