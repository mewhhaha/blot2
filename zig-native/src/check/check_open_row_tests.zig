const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const project = @import("../reuse/project.zig");
const project_check = @import("../reuse/project_check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;

const source =
    \\effect Read: Unit -> U32
    \\type State a is effect = { get: Unit -> a }
    \\const invoke: (Unit -> a ! {| e}) -> a ! {| e} = func callback => return callback ()
    \\const pair: (Unit -> U32 ! {| e}) -> (Unit -> U32 ! {| e}) -> U32 = func left => return func right => return 42
    \\const integer = func (callback: Unit -> U32 ! {| e}) => return callback ()
    \\const floating = func (callback: Unit -> F32 ! {| e}) => return callback ()
    \\const prefixed = func (callback: Unit -> U32 ! {State.get U32, Read, Read | e}) => return callback ()
    \\const local = func () => return do:
    \\  let first = func (callback: Unit -> U32 ! {| e}) => return callback ()
    \\  let second = func (value: e) => return value
    \\  break second (first (func () => return 42))
    \\const inherited = func () => return do:
    \\  let shared = func (callback: Unit -> U32 ! {| e}) => return callback ()
    \\  break func (callback: Unit -> U32 ! {| e}) => return shared callback
    \\entry const answer = func () => return invoke (func () => return local ())
;

fn named(checked: *const check.Checked, pool: *const symbols.Pool, name: []const u8) check.Binding {
    for (checked.bindings) |binding| if (binding.kind == .global and std.mem.eql(u8, pool.get(binding.name), name)) return binding;
    unreachable;
}

fn sourceRows(allocator: std.mem.Allocator) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("OPEN_ROW {s} at {d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const invoke = named(&checked, &pool, "invoke");
    const signature = checked.types.node(invoke.scheme.root);
    const callback = checked.types.node(signature.a);
    try std.testing.expect(checked.types.row(signature.c).tail == .variable);
    try std.testing.expectEqual(checked.types.row(callback.c).tail.variable, checked.types.row(signature.c).tail.variable);
    try std.testing.expectEqualSlices(u32, &.{checked.types.row(callback.c).tail.variable}, checked.types.list(invoke.scheme.row_variables));
    try std.testing.expectEqual(@as(u32, 0), invoke.scheme.closed_rows.len);
    const pair = named(&checked, &pool, "pair");
    const first = checked.types.node(pair.scheme.root);
    const second = checked.types.node(first.b);
    const left = checked.types.node(first.a);
    const right = checked.types.node(second.a);
    try std.testing.expectEqual(checked.types.row(left.c).tail.variable, checked.types.row(right.c).tail.variable);
    try std.testing.expectEqual(@as(u32, 1), pair.scheme.row_variables.len);
    const integer = checked.types.node(named(&checked, &pool, "integer").scheme.root);
    const floating = checked.types.node(named(&checked, &pool, "floating").scheme.root);
    try std.testing.expect(checked.types.row(checked.types.node(integer.a).c).tail.variable != checked.types.row(checked.types.node(floating.a).c).tail.variable);
    const prefixed = checked.types.node(named(&checked, &pool, "prefixed").scheme.root);
    const prefixed_callback = checked.types.node(prefixed.a);
    const labels = checked.types.rowLabels(prefixed_callback.c);
    try std.testing.expectEqual(@as(usize, 3), labels.len);
    try std.testing.expect(checked.types.row(prefixed_callback.c).tail == .variable);
    var read_count: usize = 0;
    var state_count: usize = 0;
    for (labels) |label| {
        const arguments = checked.types.operationArguments(label);
        if (arguments.len == 0) read_count += 1 else {
            try std.testing.expectEqualSlices(T.Id, &.{T.u32_type}, arguments);
            state_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), read_count);
    try std.testing.expectEqual(@as(usize, 1), state_count);
    const inherited = checked.types.node(named(&checked, &pool, "inherited").scheme.root);
    const inherited_result = checked.types.node(inherited.b);
    const inherited_callback = checked.types.node(inherited_result.a);
    var shared: ?check.Binding = null;
    for (checked.bindings) |binding| if (binding.kind == .local and std.mem.eql(u8, pool.get(binding.name), "shared")) {
        shared = binding;
    };
    const shared_signature = checked.types.node(shared.?.scheme.root);
    const shared_callback = checked.types.node(shared_signature.a);
    try std.testing.expectEqual(checked.types.row(inherited_callback.c).tail.variable, checked.types.row(shared_callback.c).tail.variable);
}

test "written open rows preserve shared tails concrete prefixes and binding scopes" {
    try sourceRows(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, sourceRows, .{});
}

fn rejectedRows(allocator: std.mem.Allocator) !void {
    const cases = [_]struct { source: []const u8, code: check.Code, marker: []const u8 }{
        .{ .source = "const bad: e -> U32 ! {| e} = func value => return 1\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "e}" },
        .{ .source = "const bad = func (callback: Unit -> U32 ! {| e}) => return func (value: e) => return 42\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "e) => return 42" },
        .{ .source = "const bad = func (value: e) => return do:\n  let invoke = func (callback: Unit -> U32 ! {| e}) => return callback ()\n  break 42\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "let invoke" },
        .{ .source = "const bad = func (callback: Unit -> U32 ! {| e}) => return do:\n  let identity = func (value: e) => return value\n  break 42\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "let identity" },
        .{ .source = "const outer = func () => return do:\n  let invoke = func (callback: Unit -> U32 ! {| e}) => return callback ()\n  break func (value: e) => return value\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "let invoke" },
        .{ .source = "const outer = func () => return do:\n  let identity = func (value: e) => return value\n  break func (callback: Unit -> U32 ! {| e}) => return callback ()\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "let identity" },
        .{ .source = "type State a is effect = { get: Unit -> a }\nconst bad = func (callback: Unit -> U32 ! {State.get e | e}) => return callback ()\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "e | e" },
        .{ .source = "type Box is data = $Box { callback: Unit -> U32 ! {| e} }\nentry const answer = 42\n", .code = .invalid_effect_annotation, .marker = "e}" },
        .{ .source = "const pure = func (callback: Unit -> U32) => return callback ()\nconst bad = func (callback: Unit -> U32 ! {Foreign | e}) => return pure callback\nentry const answer = 42\n", .code = .effect_mismatch, .marker = "pure callback" },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(allocator, item.source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
        if (checked.diagnostics[0].code != item.code) std.debug.print("OPEN_ROW_REJECT expected {s} actual {s}\n", .{ @tagName(item.code), @tagName(checked.diagnostics[0].code) });
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
        try std.testing.expectEqual(@as(u32, @intCast(std.mem.find(u8, item.source, item.marker).?)), checked.diagnostics[0].span.start);
    }
}

test "written open rows reject type-row collisions and pure callbacks" {
    try rejectedRows(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedRows, .{});
}

fn rejectedTailNames(allocator: std.mem.Allocator) !void {
    for ([_][]const u8{ "U32", "Token", "Bool" }) |name| {
        const text = try allocator.print("const invoke = func (callback: Unit -> U32 ! {{| {s}}}) => return callback ()\n", .{name});
        defer allocator.free(text);
        var tokens = try lexer.lex(allocator, text);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), tree.diagnostics.items.len);
        try std.testing.expectEqual(@import("../parse/ast.zig").Code.GPU_FRONTEND_SYNTAX_ERROR, tree.diagnostics.items[0].code);
        try std.testing.expectEqual(@as(u32, 0), tree.diagnostics.items[0].start);
        try std.testing.expectEqual(@as(u32, 5), tree.diagnostics.items[0].end);
    }
}

test "written row tails use the grammar identifier token" {
    try rejectedTailNames(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedTailNames, .{});
}

fn importedRows(allocator: std.mem.Allocator, loaded: *project.Project) !void {
    var checked = try project_check.checkProject(allocator, loaded);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("OPEN_ROW_IMPORT {s} at {d}\n", .{ diagnostic.codeName(), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const entry = checked.module(loaded.entry);
    var imported: ?check.Binding = null;
    for (entry.checked.bindings) |binding| if (binding.kind == .external and binding.name == loaded.symbols.lookup("invoke").?) {
        imported = binding;
    };
    const scheme = imported.?.scheme;
    try std.testing.expectEqual(@as(u32, 1), scheme.variables.len);
    try std.testing.expectEqual(@as(u32, 1), scheme.row_variables.len);
    const outer = entry.checked.types.node(scheme.root);
    const callback = entry.checked.types.node(outer.a);
    try std.testing.expectEqual(entry.checked.types.row(callback.c).tail.variable, entry.checked.types.row(outer.c).tail.variable);
    var seen_integer = false;
    var seen_floating = false;
    for (entry.checked.bindings) |binding| {
        const name = loaded.symbols.get(binding.name);
        if (std.mem.eql(u8, name, "integer")) {
            try std.testing.expectEqual(T.u32_type, entry.checked.types.node(binding.scheme.root).b);
            seen_integer = true;
        }
        if (std.mem.eql(u8, name, "floating")) {
            try std.testing.expectEqual(T.f32_type, entry.checked.types.node(binding.scheme.root).b);
            seen_floating = true;
        }
    }
    try std.testing.expect(seen_integer and seen_floating);
}

test "written row quantifiers survive source imports and independent caller instances" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "library.blot", .data = "const invoke: (Unit -> a ! {| e}) -> a ! {| e} = func callback => return callback ()\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data =
        \\import { invoke } from "./library"
        \\effect Read: Unit -> U32
        \\effect Measure: Unit -> F32
        \\const reader = @effect.provider Read (func () => return 42)
        \\const measure = @effect.provider Measure (func () => return 42.5)
        \\entry const integer = func () => return do reader:
        \\  break invoke (func () => return Read ())
        \\entry const floating = func () => return do measure:
        \\  break invoke (func () => return Measure ())
    });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var loaded = try project.load(a, std.testing.io, path, .{});
    defer loaded.deinit(a);
    try importedRows(a, &loaded);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importedRows, .{&loaded});
}
