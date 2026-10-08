const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const syntax = @import("syntax_diagnostics.zig");
const a = std.testing.allocator;
const Io = std.Io;

fn path(dir: Io.Dir, name: []const u8) ![]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try dir.realPath(std.testing.io, &buffer);
    return std.Io.Dir.path.join(a, &.{ buffer[0..count], name });
}
fn file(dir: Io.Dir, name: []const u8, source: []const u8) !void {
    try dir.writeFile(std.testing.io, .{ .sub_path = name, .data = source });
}
fn singleOwnership(allocator: std.mem.Allocator) !void {
    const source = "// 🙂\nimport * as module from \"./absent\"\nentry const answer=missing\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    const diagnostic = checked.diagnostics[0];
    try std.testing.expectEqual(check.Code.module_loader_required, diagnostic.code);
    try std.testing.expectEqual(ast.Tag.import_decl, tree.node(diagnostic.node).tag);
    try std.testing.expectEqual(ast.Span{ .start = 8, .end = 8 }, diagnostic.span);
    const published: syntax.Publication = .{ .cause = .native_detail, .code = @tagName(diagnostic.code), .span = diagnostic.span, .message = diagnostic.message() };
    try std.testing.expectEqual(ast.Span{ .start = 6, .end = 6 }, published.utf16(source).?);
    try std.testing.expectEqualStrings("compile a source project to resolve file imports", diagnostic.message());
    try std.testing.expectEqual(@as(usize, 1), checked.bindings.len);
    try std.testing.expectEqual(@as(usize, 0), checked.body_elaborations);
    try std.testing.expectEqual(@as(usize, 0), checked.imported_schemes);
}
test "standalone checker rejects imports before entry semantics and owns every failure" {
    try singleOwnership(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, singleOwnership, .{});
}

test "source input retains imports without loading targets while project mode resolves them" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try file(tmp.dir, "dependency.blot", "const value=42\n");
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const directory = try path(tmp.dir, ".");
    defer a.free(directory);
    for ([_][]const u8{ "./dependency", "./absent", "lib/dependency", "./dep%65ndency%2Eblot", "./%ff%2F", "./雪🙂" }) |import_path| {
        const source = try a.print("import * as module from \"{s}\"\nentry const answer=missing\n", .{import_path});
        defer a.free(source);
        try file(tmp.dir, "main.blot", source);
        var loaded = try project.load(a, std.testing.io, entry, .{ .input_mode = .source, .max_files = 1, .aliases = &.{.{ .prefix = "lib/", .root = directory }} });
        defer loaded.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
        try std.testing.expectEqual(@as(usize, 1), loaded.units.items.len);
        try std.testing.expectEqual(source.len, loaded.source_bytes);
        try std.testing.expectEqual(@as(project.UnitId, 0), loaded.unitImports(loaded.entry)[0].target);
        var checked = try project_check.checkProject(a, &loaded);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqualStrings("module_loader_required", checked.diagnostics[0].codeName());
        try std.testing.expect(checked.modules[loaded.entry - 1] == null);
    }
    try file(tmp.dir, "main.blot", "import { value } from \"./dependency\"\nentry const answer=value\n");
    var loaded = try project.load(a, std.testing.io, entry, .{});
    defer loaded.deinit(a);
    try std.testing.expectEqual(project.InputMode.project, loaded.input_mode);
    try std.testing.expectEqual(@as(usize, 2), loaded.units.items.len);
    var checked = try project_check.checkProject(a, &loaded);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}

fn closureOwnership(allocator: std.mem.Allocator, entry: []const u8, prelude: []const u8) !void {
    var loaded = try project.load(allocator, std.testing.io, entry, .{ .input_mode = .source, .prelude_path = prelude, .max_files = 3 });
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), loaded.units.items.len);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    try std.testing.expectEqual(@as(project.UnitId, 2), loaded.unitImports(loaded.prelude_unit)[0].target);
    try std.testing.expectEqual(@as(project.UnitId, 0), loaded.unitImports(loaded.entry)[0].target);
    var checked = try project_check.checkProject(allocator, &loaded);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    try std.testing.expectEqualStrings("module_loader_required", checked.diagnostics[0].codeName());
    // Source-lowering regions are temporary; no partial typed module escapes
    // when the standalone entry import boundary rejects the compilation.
    for (checked.modules) |module_| try std.testing.expect(module_ == null);
    try std.testing.expectEqual(@as(usize, 0), checked.body_elaborations);
}
test "source input bootstraps the real prelude closure and releases every allocation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try file(tmp.dir, "foundation.blot", "const value=42\n");
    try file(tmp.dir, "prelude.blot", "import * as foundation from \"./foundation\"\nconst inherited=foundation.value\n");
    try file(tmp.dir, "main.blot", "import * as unread from \"./must-not-open\"\nentry const answer=missing\n");
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const prelude = try path(tmp.dir, "prelude.blot");
    defer a.free(prelude);
    try closureOwnership(a, entry, prelude);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, closureOwnership, .{ entry, prelude });
}

test "entry syntax precedes prelude semantics and prelude syntax precedes reading entry" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const prelude = try path(tmp.dir, "prelude.blot");
    defer a.free(prelude);
    try file(tmp.dir, "prelude.blot", "const bad=missing\n");
    try file(tmp.dir, "main.blot", "import * as unread from \"./absent\"\nentry const answer=42\n");
    {
        var loaded = try project.load(a, std.testing.io, entry, .{ .input_mode = .source, .prelude_path = prelude });
        defer loaded.deinit(a);
        var checked = try project_check.checkProject(a, &loaded);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqualStrings("unknown_value", checked.diagnostics[0].codeName());
        try std.testing.expectEqual(loaded.prelude_unit, checked.diagnostics[0].unit);
        try std.testing.expect(checked.modules[loaded.entry - 1] == null);
    }
    try file(tmp.dir, "main.blot", "import * as unread from \"./absent\"\nconst answer=\n");
    {
        var loaded = try project.load(a, std.testing.io, entry, .{ .input_mode = .source, .prelude_path = prelude });
        defer loaded.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), loaded.diagnostics.items.len);
        try std.testing.expectEqual(loaded.entry, loaded.diagnostics.items[0].unit);
        var checked = try project_check.checkProject(a, &loaded);
        defer checked.deinit(a);
        try std.testing.expectEqual(project_check.Code.source_validation, checked.diagnostics[0].code);
    }
    try file(tmp.dir, "prelude.blot", "fn broken");
    var loaded = try project.load(a, std.testing.io, entry, .{ .input_mode = .source, .prelude_path = prelude });
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), loaded.units.items.len);
    try std.testing.expectEqual(@as(project.UnitId, 0), loaded.entry);
    try std.testing.expectEqual(@as(usize, 1), loaded.diagnostics.items.len);
    try std.testing.expectEqual(loaded.prelude_unit, loaded.diagnostics.items[0].unit);
}

fn phaseOwnership(allocator: std.mem.Allocator, entry: []const u8, prelude: []const u8, expected: check.Code) !void {
    var loaded = try project.load(allocator, std.testing.io, entry, .{ .input_mode = .source, .prelude_path = prelude });
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try project_check.checkProject(allocator, &loaded);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    try std.testing.expectEqual(expected, checked.diagnostics[0].semantic.?);
    for (checked.modules) |module_| try std.testing.expect(module_ == null);
    try std.testing.expectEqual(@as(usize, 0), checked.body_elaborations);
}
test "source validation publication cannot carry a typed-body owner or principal value scheme" {
    comptime {
        for (@typeInfo(check.SourceValidation).@"struct".field_types) |Field| {
            if (Field == check.Checked or Field == []check.Binding)
                @compileError("source validation cannot expose reusable typed-body storage");
        }
        if (@hasField(check.SourceDeclaration, "ty") or @hasField(check.SourceDeclaration, "scheme"))
            @compileError("source declaration facts cannot carry inferred value types or schemes");
    }
    try std.testing.expect(!@hasDecl(check.SourceValidation, "interface"));
}
test "source lowering validates static declarations and scopes without inferring prelude expressions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const entry = try path(tmp.dir, "main.blot");
    defer a.free(entry);
    const prelude = try path(tmp.dir, "prelude.blot");
    defer a.free(prelude);
    try file(tmp.dir, "main.blot", "import * as unread from \"./must-not-open\"\nentry const answer=missing\n");
    const Case = struct { source: []const u8, expected: check.Code };
    for ([_]Case{
        .{ .source = "const bad=@u32.add 1 1.5\n", .expected = .module_loader_required },
        .{ .source = "const bad:U32=1.5\n", .expected = .module_loader_required },
        .{ .source = "type Pair is data=#Pair(U32,U32)\nconst bad=#Pair 1\n", .expected = .module_loader_required },
        .{ .source = "type Wrapped is data=#Wrapped U32\nconst bad=#Wrapped 1.5\n", .expected = .module_loader_required },
        .{ .source = "const bad:Missing=42\n", .expected = .unsupported_type },
        .{ .source = "const bad=fn(value:Missing)=>missing\n", .expected = .unsupported_type },
        .{ .source = "const bad=do:\n  let value:Missing=missing\n  return value\n", .expected = .unsupported_type },
        .{ .source = "const bad=do:\n  use value:Missing<-missing\n  return value\n", .expected = .unsupported_type },
        .{ .source = "const bad:U32 where{nope U32}=42\n", .expected = .invalid_constraint },
        .{ .source = "const bad=@u32.add 1\n", .expected = .call_arity },
        .{ .source = "const bad=@requests(fn()=>42)\n", .expected = .requests_scope },
        .{ .source = "const bad=do:\n  yield 42\n", .expected = .yield_scope },
        .{ .source = "const bad=do:\n  break\n", .expected = .break_scope },
        .{ .source = "const bad=missing\ntype Bad is data=#Bad Missing\n", .expected = .unsupported_type },
        .{ .source = "type Bad is data=#Bad Missing\nconst bad=missing\n", .expected = .unknown_value },
        .{ .source = "effect ask:U32\n", .expected = .operation_signature },
        .{ .source = "const bad=do:\n  let value:Missing=42\n  return value\n  43\n", .expected = .unsupported_type },
        .{ .source = "const bad=(fn(value:Missing)=>42) ^ 2\n", .expected = .unsupported_type },
        .{ .source = "const bad=fn()=>do:\n  let invoke=fn(callback:Unit->U32!{|e})=>callback()\n  let identity=fn(value:e)=>value\n  return 42\n", .expected = .annotation_kind_mismatch },
        .{ .source = "type Tick is effect={read:Unit->U32}\nconst handled=fn computation=>do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read value=>\n        yield 42\n", .expected = .request_completion },
        .{ .source = "const handled=fn computation=>do:\n  for request in @requests computation:\n    case request of\n      complete value=>\n        return value\n      complete other=>\n        return other\n", .expected = .request_completion },
        .{ .source = "const handled=fn computation=>do:\n  for request in @requests computation:\n    case other of\n      complete value=>\n        return value\n", .expected = .request_binding },
        .{ .source = "const handled=fn computation=>do:\n  for request in @requests computation .. 10:\n    case request of\n      complete value=>\n        return value\n", .expected = .request_loop_range },
        .{ .source = "type Tick is effect={read:Unit->U32}\nconst handled=fn computation=>do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read value=>\n        yield 1.5\n      complete value=>\n        return value\n", .expected = .module_loader_required },
        .{ .source = "const bad=do:\n  for value in 0 .. 2:\n    break\n  return 42\n", .expected = .module_loader_required },
    }) |case| {
        try file(tmp.dir, "prelude.blot", case.source);
        try phaseOwnership(a, entry, prelude, case.expected);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, phaseOwnership, .{ entry, prelude, case.expected });
    }
}
