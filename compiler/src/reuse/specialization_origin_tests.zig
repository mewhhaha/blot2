const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");

fn diagnose(source: []const u8) !backend.Diagnostic {
    const allocator = std.testing.allocator;
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    module.unit = 1;
    var result = try backend.compileWithOptions(allocator, &.{module}, 1, .{});
    defer result.deinit(allocator);
    const diagnostic = result.diagnostic orelse return error.TestExpectedDiagnostic;
    try std.testing.expectEqual(backend.Code.missing_associated, diagnostic.code);
    try std.testing.expect(diagnostic.dispatch != null);
    return diagnostic;
}

fn span(source: []const u8, expression: []const u8) core.Span {
    const start = std.mem.find(u8, source, expression).?;
    return .{ .start = @intCast(start), .end = @intCast(start + expression.len) };
}

test "specialization dispatch keeps its definition beside the outermost use" {
    const cases = [_]struct { source: []const u8, use: []const u8, definition: []const u8 }{
        .{ .source = "const add=func a=> return func b=> return @type.call \"add\" a b\nentry const answer=func()=> return do:\n  let x=add true false\n  break 7\n", .use = "add true false", .definition = "@type.call \"add\" a b" },
        .{ .source = "const add=func a=> return func b=> return @type.call \"add\" a b\nconst forward=func a=> return func b=> return add a b\nentry const answer=func()=> return do:\n  let x=forward true false\n  break 7\n", .use = "forward true false", .definition = "@type.call \"add\" a b" },
        .{ .source = "const twice=func f=> return func x=> return f (f x)\nentry const answer=func()=> return do:\n  let x=twice (func v=> return @type.call \"add\" v v) true\n  break 7\n", .use = "twice (func v=> return @type.call \"add\" v v) true", .definition = "@type.call \"add\" v v" },
        .{ .source = "const add=func a=> return func b=> return @type.call \"add\" a b\nentry const answer=do:\n  let x=add true false\n  break 7\n", .use = "add true false", .definition = "@type.call \"add\" a b" },
        .{ .source = "type Box is data= $Box U32\nconst convert=func v=> return @type.result \"from\" v\nentry const answer=func()=> return do:\n  let value: Box=convert 1\n  break 7\n", .use = "convert 1", .definition = "@type.result \"from\" v" },
    };
    for (cases) |case| {
        const diagnostic = try diagnose(case.source);
        errdefer std.debug.print("{s}\n{any}\n", .{ case.source, diagnostic });
        try std.testing.expectEqualDeep(span(case.source, case.use), diagnostic.span);
        try std.testing.expectEqual(@as(u32, 1), diagnostic.unit);
        const related = diagnostic.related orelse return error.TestExpectedRelated;
        try std.testing.expectEqualDeep(span(case.source, case.definition), related.span);
        try std.testing.expectEqual(@as(u32, 1), related.unit);
    }
}

test "specialization keeps concrete failures at their own body" {
    const source = "const broken=func value=> return @type.call \"add\" true false\nentry const answer=func()=> return do:\n  let x=broken 42\n  break 7\n";
    const diagnostic = try diagnose(source);
    try std.testing.expectEqualDeep(span(source, "@type.call \"add\" true false"), diagnostic.span);
    try std.testing.expect(diagnostic.related == null);
}

test "specialization keeps concrete callback failures inside the callback" {
    const sources = [_][]const u8{
        "const twice=func f=> return func x=> return f (f x)\nentry const answer=func()=> return do:\n  let x=twice (func v=> return @type.call \"add\" true false) true\n  break 7\n",
        "const twice=func f=> return func x=> return f (f x)\nentry const answer=func()=> return do:\n  let x=twice (func (v: Bool)=> return @type.call \"add\" v v) true\n  break 7\n",
    };
    for (sources) |source| {
        const diagnostic = try diagnose(source);
        try std.testing.expect(diagnostic.related == null);
        try std.testing.expectEqual(@as(u32, 1), diagnostic.unit);
        try std.testing.expectEqual(@as(u32, @intCast(std.mem.find(u8, source, "@type.call").?)), diagnostic.span.start);
    }
}

test "specialization callback provenance survives the dependency codec" {
    const allocator = std.testing.allocator;
    const source = "const generic=func value=> return value\nconst fixed=func (value: Bool)=> return value\nentry const answer=7\n";
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    const codec = @import("dependency_format.zig");
    const key: codec.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try codec.encode(allocator, key, module);
    defer allocator.free(bytes);
    var decoded = try codec.decode(core.Module, allocator, bytes, key);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualDeep(module.parameters, decoded.parameters);
    try std.testing.expectEqualDeep(module.closures, decoded.closures);
    var inferred: usize = 0;
    var fixed: usize = 0;
    for (decoded.parameters) |parameter| {
        if (parameter.inferred) inferred += 1 else fixed += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), inferred);
    try std.testing.expectEqual(@as(usize, 1), fixed);
}
