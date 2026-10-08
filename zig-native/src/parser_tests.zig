const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");

fn parsed(allocator: std.mem.Allocator, source: []const u8, pool: *symbols.Pool) !ast.Tree {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
    return parser.parse(allocator, source, lexed.tokens.items, pool);
}

fn clean(source: []const u8) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    for (tree.diagnostics.items) |diagnostic| std.debug.print("syntax:{d}: {s} near {s}\n", .{ diagnostic.start, diagnostic.message(), source[diagnostic.start..@min(source.len, diagnostic.end + 24)] });
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expectEqual(tree.nodes.items.len, tree.spans.items.len);
    for (tree.spans.items) |span| try std.testing.expect(span.start <= span.end and span.end <= source.len);
}

test "fixity precedence, named targets and source overrides retain their identity" {
    const source = "infixr 80 (**) = power\ninfixl 60 (+) = combine\nconst answer = 1 + 2 ** 3 ** 4\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const declaration = tree.fixity(tree.roots.items[1]);
    try std.testing.expectEqualStrings("+", pool.get(declaration.operator));
    try std.testing.expectEqualStrings("combine", pool.get(declaration.target));
    const plus = tree.node(tree.valueDecl(tree.roots.items[2]).body);
    try std.testing.expectEqual(ast.Tag.binary, plus.tag);
    try std.testing.expectEqualStrings("+", pool.get(plus.a));
    const power = tree.node(plus.c);
    try std.testing.expectEqualStrings("**", pool.get(power.a));
    try std.testing.expectEqual(ast.Tag.binary, tree.node(power.c).tag);
    try clean("infixl 70 `qualified.combine`\nconst value = 1 `qualified.combine` 2 * 3\n");
    var attributed = try parsed(std.testing.allocator, "@[attribute]\ninfixl 60 (+) = combine\n", &pool);
    defer attributed.deinit(std.testing.allocator);
    const decorated = attributed.fixity(attributed.roots.items[0]);
    try std.testing.expect(!decorated.named);
    try std.testing.expectEqual(@as(u32, 1), decorated.attributes.len);
    try std.testing.expectEqual(ast.Tag.attribute, attributed.node(attributed.list(decorated.attributes)[0]).tag);
}

test "imports preserve aliases decoded paths and literal source spans" {
    const source = "import * as from from \"./some\\tpath.blot\"\nimport { value as renamed, Type } from \"./other.blot\"\nconst where = 1\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const namespace = tree.importDecl(tree.roots.items[0]);
    try std.testing.expectEqualStrings("from", pool.get(namespace.namespace));
    try std.testing.expectEqualStrings("./some\tpath.blot", pool.get(namespace.path));
    try std.testing.expectEqualStrings("\"./some\\tpath.blot\"", source[namespace.path_span.start..namespace.path_span.end]);
    const named = tree.importDecl(tree.roots.items[1]);
    const binding = tree.importBinding(tree.list(named.bindings)[0]);
    try std.testing.expectEqualStrings("value", pool.get(binding.name));
    try std.testing.expectEqualStrings("renamed", pool.get(binding.alias));
}

test "operator reduction retains each subtree span rather than the full chain span" {
    const source = "infixl 60 (+) = add\ninfixl 70 (*) = multiply\nconst value = 1 + 2 * 3 + 4\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    const root = tree.node(tree.valueDecl(tree.roots.items[2]).body);
    const first = tree.node(root.b);
    const multiply_span = tree.span(first.c);
    try std.testing.expectEqualStrings("2 * 3", source[multiply_span.start..multiply_span.end]);
    const first_span = tree.span(root.b);
    try std.testing.expectEqualStrings("1 + 2 * 3", source[first_span.start..first_span.end]);
}

test "surface syntax preserves nested blocks patterns loops and handlers" {
    try clean(
        \\type Pair [a, b] is data = #Pair (a, b)
        \\type Counter a is effect = { advance: a -> a }
        \\const run = fn (value: Pair [U32, Bool]) -> U32 => do:
        \\  let #Pair (number, flag) = value else:
        \\    return 0
        \\  if let #Some next = #Some number:
        \\    number := next
        \\  else:
        \\    number := self + 1
        \\  for index in 0..number:
        \\    if index > 3:
        \\      break
        \\  return if flag then number else 0
        \\const handle = fn computation => do:
        \\  for request in computation:
        \\    case request of
        \\      effect (Counter.advance U32) number =>
        \\        yield number + 1
        \\      complete value =>
        \\        return value
        \\
    );
}

test "type witnesses anonymous constructor records and array arguments remain distinct" {
    try clean("const witness = function :U32\nconst anonymous = #{ field: 2 }\nconst run = fn () => do:\n  function #[]\n  function #[1, 2]\n  function :U32\n  world.values[1] := self + 2\n  return ()\n");
}

test "argument projections and adjacent indexes bind before application" {
    const source =
        \\const projected = @u32.add (@array.get values 0).x 2
        \\const indexed = f values[1]
        \\const array_argument = f #[1]
        \\const grouped_array = f(#[1])
        \\const chain = (values).x[2].y
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const projected = tree.node(tree.valueDecl(tree.roots.items[0]).body);
    try std.testing.expectEqual(ast.Tag.apply, projected.tag);
    const first_call = tree.node(projected.a);
    try std.testing.expectEqual(ast.Tag.intrinsic, tree.node(first_call.a).tag);
    try std.testing.expectEqual(ast.Tag.field_access, tree.node(first_call.b).tag);
    const indexed = tree.node(tree.valueDecl(tree.roots.items[1]).body);
    try std.testing.expectEqual(ast.Tag.name, tree.node(indexed.a).tag);
    try std.testing.expectEqual(ast.Tag.index_access, tree.node(indexed.b).tag);
    const array_argument = tree.node(tree.valueDecl(tree.roots.items[2]).body);
    try std.testing.expectEqual(ast.Tag.array, tree.node(array_argument.b).tag);
    const grouped_array = tree.node(tree.valueDecl(tree.roots.items[3]).body);
    try std.testing.expectEqual(ast.Tag.group, tree.node(grouped_array.b).tag);
    try std.testing.expectEqual(ast.Tag.array, tree.node(tree.node(grouped_array.b).a).tag);
    const chain_id = tree.valueDecl(tree.roots.items[4]).body;
    const chain = tree.node(chain_id);
    try std.testing.expectEqual(ast.Tag.field_access, chain.tag);
    try std.testing.expectEqual(ast.Tag.index_access, tree.node(chain.a).tag);
    try std.testing.expectEqual(ast.Tag.field_access, tree.node(tree.node(chain.a).a).tag);
    try std.testing.expectEqualStrings("(values).x[2].y", source[tree.span(chain_id).start..tree.span(chain_id).end]);
}

test "qualified names intern member identities before semantic checking" {
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, "const Point.add = fn left => fn right => left\nconst value = namespace.Point.add\n", &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expect(pool.lookup("Point") != null);
    try std.testing.expect(pool.lookup("add") != null);
    try std.testing.expect(pool.lookup("namespace") != null);
    try std.testing.expectEqualStrings("Point.add", pool.get(tree.valueDecl(tree.roots.items[0]).name));
    try std.testing.expectEqualStrings("namespace.Point.add", pool.get(tree.node(tree.valueDecl(tree.roots.items[1]).body).a));
}

test "malformed syntax reports diagnostics and preserves later declarations" {
    const cases = [_]struct { source: []const u8, code: ast.Code }{
        .{ .source = "const first = froM\nconst later = 4\n", .code = .private_marker },
        .{ .source = "const first = (1,\nconst later = 4\n", .code = .expected_expression },
    };
    for (cases) |case| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var lexed = try lexer.lex(std.testing.allocator, case.source);
        defer lexed.deinit(std.testing.allocator);
        var tree = try parser.parse(std.testing.allocator, case.source, lexed.tokens.items, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
        try std.testing.expectEqual(case.code, tree.diagnostics.items[0].code);
        // An unclosed delimiter suppresses lexical newlines; recovery cannot
        // invent a declaration boundary that the token stream does not have.
        if (case.code != .expected_expression) {
            const last = tree.valueDecl(tree.roots.items[tree.roots.items.len - 1]);
            try std.testing.expectEqualStrings("later", pool.get(last.name));
        }
    }
}

test "nested witness atoms stop at a diagnostic rather than overflowing the stack" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "const value = ");
    for (0..600) |_| try source.append(std.testing.allocator, ':');
    try source.appendSlice(std.testing.allocator, "U32\nconst later = 4\n");
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source.items, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(ast.Code.nesting_limit, tree.diagnostics.items[0].code);
    try std.testing.expectEqualStrings("later", pool.get(tree.valueDecl(tree.roots.items[0]).name));
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, "import { answer as value } from \"./module.blot\"\ninfixl 60 (++) = combine\nentry const compute = fn (value: U32) => do:\n  let next = value ++ 2 * 3\n  if next > 0:\n    return next\n  return 0\n", &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
}

test "parser allocation failures release trees symbols and scratch stacks" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

fn corpusDirectory(path: []const u8) !struct { files: usize, errors: usize } {
    const io = std.testing.io;
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{ .files = 0, .errors = 0 },
        else => return err,
    };
    defer dir.close(io);
    var walker = try dir.walk(std.testing.allocator);
    defer walker.deinit();
    var count: usize = 0;
    var errors: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".blot")) continue;
        const source = try dir.readFileAlloc(io, entry.path, std.testing.allocator, .limited(16 * 1024 * 1024));
        defer std.testing.allocator.free(source);
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        for (tree.diagnostics.items) |diagnostic| {
            std.debug.print("{s}/{s}:{d}: {s} near {s}\n", .{ path, entry.path, diagnostic.start, diagnostic.message(), source[diagnostic.start..@min(source.len, diagnostic.end + 32)] });
            errors += 1;
        }
        count += 1;
    }
    return .{ .files = count, .errors = errors };
}

test "real examples standard library and gdev surface grammar parse completely" {
    var examples = try corpusDirectory("examples");
    if (examples.files == 0) examples = try corpusDirectory("../examples");
    if (examples.files == 0) return error.SkipZigTest;
    var standard = try corpusDirectory("std");
    if (standard.files == 0) standard = try corpusDirectory("../std");
    var game = try corpusDirectory("../gdev/packages");
    const game_source = try corpusDirectory("../gdev/src");
    game.files += game_source.files;
    game.errors += game_source.errors;
    if (game.files == 0) {
        game = try corpusDirectory("../../gdev/packages");
        const alternative = try corpusDirectory("../../gdev/src");
        game.files += alternative.files;
        game.errors += alternative.errors;
    }
    try std.testing.expect(examples.files >= 10 and standard.files >= 3);
    if (game.files != 0) try std.testing.expect(game.files >= 20);
    try std.testing.expectEqual(@as(usize, 0), examples.errors + standard.errors + game.errors);
}

test "every executable guide block parses independently" {
    const io = std.testing.io;
    const source = std.Io.Dir.cwd().readFileAlloc(io, "compiler/guide.md", std.testing.allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try std.Io.Dir.cwd().readFileAlloc(io, "../compiler/guide.md", std.testing.allocator, .limited(4 * 1024 * 1024)),
        else => return err,
    };
    defer std.testing.allocator.free(source);
    var remainder: []const u8 = source;
    var count: usize = 0;
    while (std.mem.find(u8, remainder, "```blot\n")) |start| {
        remainder = remainder[start + 8 ..];
        const end = std.mem.find(u8, remainder, "```") orelse return error.TestUnexpectedResult;
        try clean(remainder[0..end]);
        remainder = remainder[end + 3 ..];
        count += 1;
    }
    try std.testing.expect(count >= 10);
}
