const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const display = @import("purity_diagnostics.zig");
const a = std.testing.allocator;
const source190 = "\neffect ask: Unit -> U32\nlet value = do:\n  use answer <- ask ()\n  return answer\n";
fn rejected(allocator: std.mem.Allocator, source: []const u8, expected: check.Code, point: ?u32, message: ?[]const u8) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    try std.testing.expectEqual(expected, checked.diagnostics[0].code);
    if (point) |start| try std.testing.expectEqualDeep(@import("ast.zig").Span{ .start = start, .end = start }, checked.diagnostics[0].span);
    if (checked.diagnostics[0].purity != null) {
        try std.testing.expect(checked.initializer_rejected);
        try std.testing.expectEqual(@as(usize, 1), checked.bindings.len);
        try std.testing.expectEqual(@as(usize, 0), checked.expr_types.len);
        try std.testing.expectEqual(@as(usize, 0), checked.obligations.len);
    }
    if (message) |expected_message| {
        const text = try display.format(allocator, &pool, "main", checked.diagnostics[0].purity.?);
        defer allocator.free(text);
        try std.testing.expectEqualStrings(expected_message, text);
    }
    var lowered = try core.lower(allocator, &tree, &pool, &checked);
    defer lowered.deinit(allocator);
    try std.testing.expectEqual(core.Code.unchecked, lowered.diagnostics[0].code);
    try std.testing.expectEqual(@as(usize, 1), lowered.bodies.len);
    var result = try backend.compile(allocator, &.{lowered}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(backend.Code.no_entry, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}
test "initializer actual frozen runtime reason first operation and no typed Core publication" {
    try rejected(a, source190, .initializer_effect, 29, "pure evaluation cannot perform main::ask; sequence an operation with use inside a provider scope");
    try rejected(a, "effect ask: Unit -> U32\nconst value = do:\n  use answer <- ask ()\n  return answer\n", .const_effect, 30, "pure evaluation cannot perform main::ask; sequence an operation with use inside a provider scope");
    try rejected(a, "effect zebra: Unit -> U32\neffect alpha: Unit -> U32\nlet value = do:\n  use first <- zebra ()\n  use second <- alpha ()\n  return @u32.add first second\n", .initializer_effect, 56, "pure evaluation cannot perform main::zebra; sequence an operation with use inside a provider scope");
    try rejected(a, "effect zebra: Unit -> U32\neffect alpha: Unit -> U32\nlet value = do:\n  use second <- alpha ()\n  use first <- zebra ()\n  return @u32.add first second\n", .initializer_effect, 56, "pure evaluation cannot perform main::alpha; sequence an operation with use inside a provider scope");
}
test "initializer successful type constraints precede purity and failed type checking refuses Core" {
    try rejected(a, "effect ask: Unit -> U32\nlet value: U32 = do:\n  use answer <- ask ()\n  return #True\n", .type_mismatch, null, null);
}
test "initializer all allocation failures release source row witness and rejection owners" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, rejected, .{ source190, check.Code.initializer_effect, @as(?u32, 29), @as(?[]const u8, "pure evaluation cannot perform main::ask; sequence an operation with use inside a provider scope") });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, rejected, .{ "effect ask: Unit -> U32\nlet value: U32 = do:\n  use answer <- ask ()\n  return #True\n", check.Code.type_mismatch, @as(?u32, null), @as(?[]const u8, null) });
}
fn failedProject(allocator: std.mem.Allocator, path: []const u8) !void {
    var loaded = try project.load(allocator, std.testing.io, path, .{ .prelude_path = null });
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try project_check.checkProject(allocator, &loaded);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    const diagnostic = checked.diagnostics[0];
    try std.testing.expectEqual(check.Code.initializer_effect, diagnostic.semantic.?);
    const witness = diagnostic.purity.?;
    try std.testing.expect(witness.identity.unit != diagnostic.unit);
    try std.testing.expectEqualStrings("ask", loaded.symbols.get(witness.family));
    try std.testing.expect(checked.modules[loaded.entry - 1] == null);
    const text = try display.format(allocator, &loaded.symbols, "dependency.blot", witness);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("pure evaluation cannot perform dependency.blot::ask; sequence an operation with use inside a provider scope", text);
}
test "initializer aliased import retains producer identity and rejects typed module publication at every allocation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "dependency.blot", .data = "effect ask: Unit -> U32\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import { ask as query } from \"./dependency\"\nlet value = do:\n  use answer <- query ()\n  return answer\nentry const answer = 42\n" });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(a, &.{ buffer[0..count], "main.blot" });
    defer a.free(path);
    try failedProject(a, path);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, failedProject, .{path});
}

fn retainedSnapshot(allocator: std.mem.Allocator, source: []const u8) !void {
    const snapshot: display.Witness = scope: {
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var lexed = try lexer.lex(allocator, source);
        defer lexed.deinit(allocator);
        var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.checkModule(allocator, &tree, &pool, &.{}, &.{}, 37);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.initializer_rejected);
        try std.testing.expectEqual(check.Code.initializer_effect, checked.diagnostics[0].code);
        try std.testing.expectEqual(@as(usize, 1), checked.bindings.len);
        const owned = try checked.diagnostics[0].purity.?.clone(allocator);
        errdefer owned.deinit(allocator);
        try std.testing.expect(owned.operation_name.?.ptr != checked.diagnostics[0].purity.?.operation_name.?.ptr);
        break :scope owned;
    };
    defer snapshot.deinit(allocator);
    // Lexical scopes destroy source/symbol/type owners before rendering.
    const empty_pool: symbols.Pool = .{};
    const text = try display.format(allocator, &empty_pool, "unused", snapshot);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "main::Reader.read<") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, "; sequence an operation with use inside a provider scope"));
}
test "canonical purity display source store and symbols teardown plus every failed allocation owns snapshots" {
    const sources = [_][]const u8{
        "type Reader a is effect={read:Unit->a}\nlet value=Reader.read (Array (U32,F32)) ()\n",
        "type Reader {pair:(a,[b,c])} is effect={read:Unit->a}\nlet value=Reader.read {pair:(U32,[F32,Bool])} ()\n",
        "type Reader a is effect={read:Unit->a}\nlet value=do:\n  let selected=1\n  if #True:\n    selected:=2\n  use answer<-Reader.read U32 ()\n  return @u32.add selected answer\n",
    };
    for (sources) |source| {
        try retainedSnapshot(a, source);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedSnapshot, .{source});
    }
}

fn specializedProjectSnapshot(allocator: std.mem.Allocator, path: []const u8) !void {
    var loaded = try project.load(allocator, std.testing.io, path, .{ .prelude_path = null });
    var loaded_alive = true;
    defer if (loaded_alive) loaded.deinit(allocator);
    var checked = try project_check.checkProject(allocator, &loaded);
    var checked_alive = true;
    defer if (checked_alive) checked.deinit(allocator);
    try std.testing.expectEqual(check.Code.initializer_effect, checked.diagnostics[0].semantic.?);
    try std.testing.expect(checked.modules[loaded.entry - 1] == null);
    const witness = try checked.diagnostics[0].purity.?.clone(allocator);
    defer witness.deinit(allocator);
    checked.deinit(allocator);
    checked_alive = false;
    loaded.deinit(allocator);
    loaded_alive = false;
    const empty_pool: symbols.Pool = .{};
    const text = try display.format(allocator, &empty_pool, "unused", witness);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "dependency.blot::Reader.read<") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "dependency.blot3:Box6:1:i1:f") != null);
}
test "canonical purity imported shaped nominal effect snapshots outlive all project owners and fail safely" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "dependency.blot", .data = "type Box {pair:(a,b)} is data=#Box (a,b)\ntype Reader a is effect={read:Unit->a}\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import * as api from \"./dependency\"\nlet value=api.Reader.read (api.Box ({pair:(U32,F32)})) ()\nentry const answer=42\n" });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(a, &.{ buffer[0..count], "main.blot" });
    defer a.free(path);
    try specializedProjectSnapshot(a, path);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, specializedProjectSnapshot, .{path});
}

fn schemeOnlyInitializer(allocator: std.mem.Allocator) !void {
    const T = @import("types.zig");
    const source = "entry const answer=read ()\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var producer = try T.Store.init(allocator);
    defer producer.deinit();
    const label = try producer.internOperation(.{ .unit = 2, .decl = 7 }, &.{});
    const ty = try producer.functionWithEffects(T.unit, T.u32_type, try producer.effects.row(&.{label}, .closed));
    var checked = try check.checkWithImports(allocator, &tree, &pool, &.{.{ .name = pool.lookup("read").?, .target = .{ .unit = 2, .binding = 1 }, .origin = 0, .interface = .{ .types = .{ .store = &producer }, .scheme = .{ .root = ty }, .obligations = &.{} } }});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(check.Code.const_effect, checked.diagnostics[0].code);
    try std.testing.expect(checked.initializer_rejected);
    try std.testing.expect(checked.diagnostics[0].purity.?.origin_unavailable);
    try std.testing.expect(checked.diagnostics[0].purity.?.operation_name == null);
    try std.testing.expectError(error.OperationPurityOriginRequired, display.format(allocator, &pool, "unused", checked.diagnostics[0].purity.?));
    var lowered = try core.lower(allocator, &tree, &pool, &checked);
    defer lowered.deinit(allocator);
    try std.testing.expectEqual(core.Code.unchecked, lowered.diagnostics[0].code);
}
test "canonical purity scheme-only imports preserve typed category and mark missing source provenance at every allocation" {
    try schemeOnlyInitializer(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, schemeOnlyInitializer, .{});
}
