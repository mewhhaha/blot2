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

fn stagedSurface(allocator: std.mem.Allocator) !void {
    const source =
        \\type Choice is data = $Some U32 | $None
        \\const run = func value => return value
        \\const staged = #run run 42
        \\entry const answer = func () => return case $Some staged of
        \\  $Some value => value
        \\  $None => 0
        \\entry const flag = true
        \\const apply = func f -> x => return f $ x
        \\const values = #[1, 2]
        \\const linked = [1, 2]
        \\const block = #do:
        \\  let value = 40
        \\  break @u32.add value 2
        \\const qualified = $run.Some 42
        \\const legacy_qualified = #run.Some 42
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, source, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expect(tree.has_typed_staging);
    const body = tree.valueDecl(tree.roots.items[2]).body;
    const run = tree.node(body);
    try std.testing.expectEqual(ast.Tag.apply, run.tag);
    try std.testing.expectEqualStrings("@code.evaluate", pool.get(tree.node(run.a).a));
    const block = tree.node(tree.valueDecl(tree.roots.items[8]).body);
    try std.testing.expectEqual(ast.Tag.apply, block.tag);
    try std.testing.expectEqualStrings("@code.evaluate", pool.get(tree.node(block.a).a));
    try std.testing.expectEqual(ast.Tag.block, tree.node(block.b).tag);
    var array = false;
    var list = false;
    for (tree.nodes.items) |node| if (node.tag == .array) {
        if (node.c == 0) array = true else list = true;
    };
    try std.testing.expect(array and list);
}

test "dollar constructors and run staging preserve list arrays and spaced dollar application through OOM" {
    try stagedSurface(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, stagedSurface, .{});
}

test "multi-parameter lambda sugar lowers to a curried chain with the result on the final stage" {
    const source = "const combine = func (first: U32) -> (second: U32) : U32 => return @u32.add first second\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const outer = tree.node(tree.valueDecl(tree.roots.items[0]).body);
    try std.testing.expectEqual(ast.Tag.lambda, outer.tag);
    try std.testing.expectEqual(@as(ast.Id, 0), outer.c);
    const inner = tree.node(outer.b);
    try std.testing.expectEqual(ast.Tag.lambda, inner.tag);
    try std.testing.expect(inner.c != 0);
    try std.testing.expectEqual(ast.Tag.parameter, tree.node(outer.a).tag);
    try std.testing.expectEqual(ast.Tag.parameter, tree.node(inner.a).tag);
}

test "functions require explicit return and reject whitespace separated parameters" {
    for ([_][]const u8{
        "const identity = fn x => return x\n",
        "const identity = func x => x\n",
        "const add = func x y => return @u32.add x y\n",
        "const typed = func (x: U32) -> U32 => return x\n",
    }) |source| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
    }
    try clean("const identity = func x => return x\n");
    try clean("const identity = func x => do:\n  return x\n");
    try clean("const add = func x -> y => return @u32.add x y\n");
}

fn curriedParameterAllocation(allocator: std.mem.Allocator) !void {
    const source = "const ninth = func a -> b -> c -> d -> e -> f -> g -> h -> i => return i\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, source, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var body = tree.valueDecl(tree.roots.items[0]).body;
    for (0..9) |_| {
        try std.testing.expectEqual(ast.Tag.lambda, tree.node(body).tag);
        body = tree.node(body).b;
    }
}

test "long curried parameter lists release fallback storage through allocation faults" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, curriedParameterAllocation, .{});
}

test "return exits a function while break value finishes a do and bare break exits a loop" {
    const source =
        \\const choose = func flag => return do:
        \\  let value = do:
        \\    if flag:
        \\      return 7
        \\    break 3
        \\  for index in 0..1:
        \\    break
        \\  break value
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var function_returns: usize = 0;
    var block_results: usize = 0;
    var loop_breaks: usize = 0;
    for (tree.nodes.items) |node| switch (node.tag) {
        .function_return_stmt => function_returns += 1,
        .return_stmt => block_results += 1,
        .break_stmt => loop_breaks += 1,
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), function_returns);
    try std.testing.expectEqual(@as(usize, 2), block_results);
    try std.testing.expectEqual(@as(usize, 1), loop_breaks);
}

test "spread temporaries preserve the surrounding collection type" {
    const source = "entry const main = func (n: U32) => return #[#[n], ...#[#[1]]]\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var temporary_count: usize = 0;
    for (tree.nodes.items) |node| {
        if (node.tag != .iterator_bind) continue;
        temporary_count += 1;
        try std.testing.expect(std.mem.startsWith(u8, pool.get(node.a), "$collection."));
    }
    try std.testing.expectEqual(@as(usize, 2), temporary_count);
}

fn numericProofSyntax(allocator: std.mem.Allocator) !void {
    const source =
        \\const at: (values: Array a) -> (index: U32) -> (@proof.Index values index) -> a = func values => return func index => return func proof => return @array.get values index
        \\const bounded: (values: List U32) -> (index: U32) -> (@proof.U32Lt index (@list.length values)) -> U32 = func values => return func index => return func proof => return index
        \\const zero: (value: U32) -> (@proof.U32Eq value 0) -> U32 = func value => return func proof => return value
        \\const fits: (@proof.U32AddFits 4294967295 0) -> U32 = func proof => return 0
        \\const subtracts: (@proof.U32SubFits 1 0) -> U32 = func proof => return 1
        \\const inclusive: (@proof.U32Le 1 1) -> U32 = func proof => return 1
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, source, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 6), tree.roots.items.len);
    var proof_heads: usize = 0;
    var length_heads: usize = 0;
    for (tree.nodes.items) |node| if (node.tag == .type_name) {
        const name = pool.get(node.a);
        if (@import("../check/numeric_proof_terms.zig").typeName(name) != null) proof_heads += 1;
        if (std.mem.eql(u8, name, "@list.length")) length_heads += 1;
    };
    try std.testing.expectEqual(@as(usize, 6), proof_heads);
    try std.testing.expectEqual(@as(usize, 1), length_heads);
}
test "numeric proof annotation syntax owns only bounded operand descriptions through OOM" {
    try numericProofSyntax(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, numericProofSyntax, .{});
    for ([_][]const u8{
        "const x: @proof.U32Eq (@u32.add 1 2) 3 = ()\n",
        "const x: @proof.Index (make ()) 0 = ()\n",
        "const x: @proof.U32Lt 0 = ()\n",
        "const x: @other.Index values 0 = ()\n",
    }) |source| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
    }
}

fn contractMemberSyntax(allocator: std.mem.Allocator) !void {
    const source =
        \\type Source s is contract = {
        \\  type Item,
        \\  type Stored = (Source.Item s, s),
        \\  const first: s -> (Source.Item s),
        \\  Type_rep s,
        \\}
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, source, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const contract = tree.node(tree.roots.items[0]);
    try std.testing.expectEqual(ast.Tag.contract_decl, contract.tag);
    const body = tree.node(contract.b);
    const members = tree.list(.{ .start = body.a, .len = body.b });
    try std.testing.expectEqual(@as(usize, 4), members.len);
    try std.testing.expectEqual(ast.Tag.contract_type_member, tree.node(members[0]).tag);
    try std.testing.expectEqual(@as(u32, 0), tree.node(members[0]).b);
    try std.testing.expectEqual(ast.Tag.type_product, tree.node(tree.node(members[1]).b).tag);
    try std.testing.expectEqual(ast.Tag.contract_value_member, tree.node(members[2]).tag);
    try std.testing.expectEqual(ast.Tag.type_function, tree.node(tree.node(members[2]).b).tag);
    try std.testing.expectEqual(ast.Tag.constraint, tree.node(members[3]).tag);
}

test "contract members preserve abstract equations signatures and ordinary predicates through OOM" {
    try contractMemberSyntax(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, contractMemberSyntax, .{});
    for ([_][]const u8{
        "const value: U32 where { type Item = U32 } = 42\n",
        "type Source s is contract = { const first = func value => return value }\n",
        "type Source s is contract = { type Item x = x }\n",
    }) |source| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
    }
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
test "spark and receive lower to checked task operations with bounded syntax" {
    const source =
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let pending = *(work 42)
        \\  return |pending|)
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var spawns: usize = 0;
    var joins: usize = 0;
    for (tree.nodes.items) |node| if (node.tag == .intrinsic) {
        const name = pool.get(node.a);
        spawns += @intFromBool(std.mem.eql(u8, name, "@task.spawn"));
        joins += @intFromBool(std.mem.eql(u8, name, "@task.receive"));
    };
    try std.testing.expectEqual(@as(usize, 1), spawns);
    try std.testing.expectEqual(@as(usize, 1), joins);
    for ([_]struct { source: []const u8, code: ast.Code }{
        .{ .source = "entry const value = func () => return @task.scope (func group => return do:\n  return *(work))\n", .code = .task_spark_call },
    }) |case| {
        var rejected = try parsed(std.testing.allocator, case.source, &pool);
        defer rejected.deinit(std.testing.allocator);
        try std.testing.expect(rejected.diagnostics.items.len != 0);
        try std.testing.expectEqual(case.code, rejected.diagnostics.items[0].code);
    }
}

test "spark syntax leaves task region selection to checking" {
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, "const start = func value => return *(work value)\n", &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var regions: usize = 0;
    for (tree.nodes.items) |node| {
        if (node.tag != .task_region) continue;
        regions += 1;
        try std.testing.expectEqual(@as(u32, 0), node.a | node.b | node.c);
    }
    try std.testing.expectEqual(@as(usize, 1), regions);
}

test "spark binds call arguments before creating the child" {
    const source =
        \\entry const answer = func () => return @task.scope (func group => return do:
        \\  let pending = *(combine (first 1) (second 2))
        \\  return |pending|)
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var found = false;
    for (tree.nodes.items) |node| {
        if (node.tag != .block or node.b != 3) continue;
        const statements = tree.list(.{ .start = node.a, .len = node.b });
        if (tree.node(statements[0]).tag != .let_stmt or tree.node(statements[1]).tag != .let_stmt) continue;
        if (tree.node(statements[2]).tag != .return_stmt) continue;
        found = true;
        const first = tree.node(statements[0]);
        const second = tree.node(statements[1]);
        try std.testing.expectEqual(ast.Tag.group, tree.node(first.b).tag);
        try std.testing.expectEqual(ast.Tag.group, tree.node(second.b).tag);
        try std.testing.expectEqual(ast.Tag.apply, tree.node(tree.node(statements[2]).a).tag);
    }
    try std.testing.expect(found);
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
        \\const run = func (value: Pair [U32, Bool]) : U32 => return do:
        \\  let #Pair (number, flag) = value else:
        \\    break 0
        \\  if let #Some next = #Some number:
        \\    number := next
        \\  else:
        \\    number := self + 1
        \\  for index in 0..number:
        \\    if index > 3:
        \\      break
        \\  break if flag then number else 0
        \\const handle = func computation => return do:
        \\  for request in computation:
        \\    case request of
        \\      effect (Counter.advance U32) number =>
        \\        yield number + 1
        \\      complete value =>
        \\        break value
        \\
    );
}

test "type witnesses anonymous constructor records and array arguments remain distinct" {
    try clean("const witness = function :U32\nconst anonymous = #{ field: 2 }\nconst run = func () => return do:\n  function #[]\n  function #[1, 2]\n  function :U32\n  world.values[1] := self + 2\n  break ()\n");
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
    var tree = try parsed(std.testing.allocator, "const Point.add = func left => return func right => return left\nconst value = namespace.Point.add\n", &pool);
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
    var tree = try parsed(allocator, "import { answer as value } from \"./module.blot\"\ninfixl 60 (++) = combine\nentry const compute = func (value: U32) => return do:\n  let next = value ++ 2 * 3\n  if next > 0:\n    break next\n  break 0\n", &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
}

test "parser allocation failures release trees symbols and scratch stacks" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
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

test "repository examples and standard library surface grammar parse completely" {
    var examples = try corpusDirectory("examples");
    if (examples.files == 0) examples = try corpusDirectory("../examples");
    if (examples.files == 0) return error.SkipZigTest;
    var standard = try corpusDirectory("std");
    if (standard.files == 0) standard = try corpusDirectory("../std");
    // External consumers migrate independently of this compiler's syntax.
    // The default corpus must be reproducible from this repository alone.
    try std.testing.expect(examples.files >= 10 and standard.files >= 3);
    try std.testing.expectEqual(@as(usize, 0), examples.errors + standard.errors);
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

fn implementationSyntax(allocator: std.mem.Allocator) !void {
    const source =
        \\private impl ArraySource a : Source (Array a) where { Type_rep a } = {
        \\  type Item = a,
        \\  const first: (Array a) -> a = func values => return @array.get values 0,
        \\}
        \\impl Pair (a, b) => type c : Combined (a, b) c = {}
        \\const impl = func impl => return impl
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, source, &pool);
    defer tree.deinit(allocator);
    for (tree.diagnostics.items) |issue| std.debug.print("implementation syntax at {d}: {s} expected {any} near {s}\n", .{ issue.start, issue.message(), issue.expected_token, source[issue.start..@min(source.len, issue.end + 20)] });
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 3), tree.roots.items.len);
    const root = tree.roots.items[0];
    try std.testing.expectEqual(ast.Tag.implementation_decl, tree.node(root).tag);
    try std.testing.expect(tree.declarationTraits(root).private);
    const declaration = tree.implementation(root);
    try std.testing.expectEqual(@as(u32, 1), declaration.parameters.len);
    try std.testing.expectEqual(@as(u32, 1), declaration.where.len);
    try std.testing.expectEqual(@as(u32, 2), declaration.members.len);
    const members = tree.list(declaration.members);
    try std.testing.expectEqual(ast.Tag.contract_type_member, tree.node(members[0]).tag);
    try std.testing.expectEqual(ast.Tag.value_decl, tree.node(members[1]).tag);
    try std.testing.expectEqual(ast.Tag.lambda, tree.node(tree.valueDecl(members[1]).body).tag);
    try std.testing.expectEqual(@as(u32, 2), tree.implementation(tree.roots.items[1]).parameters.len);
}

test "implementation contextual headers retain explicit parameters heads prerequisites and lambda members" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, implementationSyntax, .{});
    for ([_][]const u8{
        "entry impl X : Source U32 = {}\n",
        "opaque impl X : Source U32 = {}\n",
        "impl X : Source U32 = { const first = other }\n",
        "impl X : Source U32 = { type Item }\n",
    }) |source| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
    }
}

fn usageQualifierSyntax(a: std.mem.Allocator) !void {
    const source =
        \\const unique = 1
        \\const f: once (borrow r U32 -> shared U32) = func x => return x
        \\const g: cleanup (unique U32 -> Unit) = func x => return ()
        \\const h: borrow_mut r [U32] = unique
        \\const i: many (U32 -> U32) = func x => return x
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var tree = try parser.parse(a, source, lexed.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 5), tree.roots.items.len);
    const f = tree.node(tree.valueDecl(tree.roots.items[1]).annotation);
    try std.testing.expectEqual(ast.Tag.type_usage, f.tag);
    try std.testing.expectEqual(@backingInt(ast.UsageKind.once), f.a);
    const arrow = tree.node(f.b);
    try std.testing.expectEqual(ast.Tag.type_function, arrow.tag);
    const input = tree.node(arrow.a);
    try std.testing.expectEqual(@backingInt(ast.UsageKind.borrow), input.a);
    try std.testing.expectEqualStrings("r", pool.get(input.c));
    try std.testing.expectEqual(@backingInt(ast.UsageKind.shared), tree.node(arrow.b).a);
}

test "usage qualifiers own grouped arrows and loan regions without reserving value names" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, usageQualifierSyntax, .{});
    for ([_][]const u8{ "const f: borrow r = 0\n", "const f: borrow_mut U32 = 0\n", "const f: once (U32 ->) = 0\n" }) |source| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
    }
}
fn typedStagingSyntax(allocator: std.mem.Allocator) !void {
    const source =
        \\const code = 1
        \\const descriptor = func code => return code
        \\const left: code [U32, row {}] = @code.quote 40
        \\const shape: descriptor (code [U32, row {Foreign}]) = @code.describe left
        \\type Generator = forall [row e] => code [U32, row e]
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, source, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expect(tree.has_typed_staging);
    const code = tree.node(tree.valueDecl(tree.roots.items[2]).annotation);
    try std.testing.expectEqual(ast.Tag.type_code, code.tag);
    try std.testing.expectEqualStrings("U32", pool.get(tree.node(code.a).a));
    try std.testing.expectEqual(ast.Tag.effect_row, tree.node(code.b).tag);
    try std.testing.expectEqual(@as(u32, 0), tree.node(code.b).b);
    const descriptor = tree.node(tree.valueDecl(tree.roots.items[3]).annotation);
    try std.testing.expectEqual(ast.Tag.type_descriptor, descriptor.tag);
    const foreign_code = tree.node(descriptor.a);
    try std.testing.expectEqual(ast.Tag.type_code, foreign_code.tag);
    try std.testing.expectEqual(@as(u32, 1), tree.node(foreign_code.b).b);
    const generator = tree.node(tree.node(tree.roots.items[4]).b);
    const open_code = tree.node(tree.extra.items[generator.c]);
    try std.testing.expectEqual(ast.Tag.type_code, open_code.tag);
    try std.testing.expectEqualStrings("e", pool.get(tree.node(tree.node(open_code.b).c).a));
}
test "typed staging syntax owns result rows and descriptors without reserving value names" {
    try typedStagingSyntax(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, typedStagingSyntax, .{});
    for ([_][]const u8{ "code [U32]", "code [U32, {}]", "code [U32, row]", "descriptor () ->" }) |annotation| {
        const source = try std.testing.allocator.print("const invalid: {s} = ()\n", .{annotation});
        defer std.testing.allocator.free(source);
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
    }
}

fn quantifiedPackageSyntax(a: std.mem.Allocator) !void {
    const source =
        \\const forall = func pack => return pack
        \\type Id = forall [a] => a -> a
        \\type Borrower = forall [a, row e, region r] => borrow r a -> a ! {| e}
        \\type Item = exists [a] where { Render a } => a
        \\const make = pack [U32] 42 as Item
        \\const read = func item => return unpack item as [a] value in Render.show value
        \\const plain = func unpack => return unpack 1
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parsed(a, source, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 7), tree.roots.items.len);
    const id = tree.node(tree.node(tree.roots.items[1]).b);
    try std.testing.expectEqual(ast.Tag.type_forall, id.tag);
    try std.testing.expectEqual(@as(u32, 1), id.b);
    try std.testing.expectEqual(ast.Tag.type_function, tree.node(tree.extra.items[id.c]).tag);
    const borrower = tree.node(tree.node(tree.roots.items[2]).b);
    const binders = tree.list(.{ .start = borrower.a, .len = borrower.b });
    try std.testing.expectEqual(@backingInt(ast.BinderSort.row), tree.node(binders[1]).b);
    try std.testing.expectEqual(@backingInt(ast.BinderSort.region), tree.node(binders[2]).b);
    const item = tree.node(tree.node(tree.roots.items[3]).b);
    try std.testing.expectEqual(ast.Tag.type_exists, item.tag);
    try std.testing.expect(tree.extra.items[item.c + 1] != 0);
    const pack = tree.node(tree.valueDecl(tree.roots.items[4]).body);
    try std.testing.expectEqual(ast.Tag.package_pack, pack.tag);
    try std.testing.expectEqual(@as(u32, 1), pack.b);
    const unpack = tree.node(tree.node(tree.valueDecl(tree.roots.items[5]).body).b);
    try std.testing.expectEqual(ast.Tag.package_unpack, unpack.tag);
    try std.testing.expectEqualStrings("value", pool.get(tree.extra.items[unpack.c + 1]));
}

test "quantified packages retain sorted binders evidence and exact lexical openings" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, quantifiedPackageSyntax, .{});
    for ([_][]const u8{
        "type Bad = forall [] => U32\n",
        "type Bad = exists [a] a\n",
        "const bad = pack [] 42 as Item\n",
        "const bad = unpack item as [a] value 42\n",
    }) |source| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(std.testing.allocator);
        var tree = try parsed(std.testing.allocator, source, &pool);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expect(tree.diagnostics.items.len != 0);
    }
}

fn dollarApplication(allocator: std.mem.Allocator) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parsed(allocator, "const answer = outer first $ inner $ value\n", &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const root = tree.node(tree.valueDecl(tree.roots.items[0]).body);
    try std.testing.expectEqual(ast.Tag.apply, root.tag);
    try std.testing.expectEqual(ast.Tag.apply, tree.node(root.a).tag);
    try std.testing.expectEqual(ast.Tag.group, tree.node(root.b).tag);
    try std.testing.expectEqual(ast.Tag.apply, tree.node(tree.node(root.b).a).tag);
    var custom = try parsed(allocator, "infixr 0 ($) = choose\nconst choose = func a -> b => return a\nconst answer = 1 $ 2\n", &pool);
    defer custom.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), custom.diagnostics.items.len);
    try std.testing.expectEqual(ast.Tag.binary, custom.node(custom.valueDecl(custom.roots.items[2]).body).tag);
}

test "default dollar groups application while explicit fixities retain operator dispatch through OOM" {
    try dollarApplication(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, dollarApplication, .{});
}

test "boolean words are literal patterns and logical precedence is fixed" {
    const source =
        \\entry const value = true or false and false
        \\entry const classify = func (value: Bool) => return case value of
        \\  true => 1
        \\  false => 0
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var tree = try parsed(std.testing.allocator, source, &pool);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const outer = tree.node(tree.valueDecl(tree.roots.items[0]).body);
    try std.testing.expectEqual(ast.Tag.binary, outer.tag);
    try std.testing.expectEqualStrings("or", pool.get(outer.a));
    const inner = tree.node(outer.c);
    try std.testing.expectEqual(ast.Tag.binary, inner.tag);
    try std.testing.expectEqualStrings("and", pool.get(inner.a));
    for ([_][]const u8{
        "const and = 1\n",
        "const or = 1\n",
        "const true = 1\n",
        "const false = 1\n",
        "infixl 50 (and) = combine\n",
        "infixl 50 (or) = combine\n",
        "entry const value = #true\n",
        "entry const value = $false\n",
    }) |invalid| {
        var rejected = try parsed(std.testing.allocator, invalid, &pool);
        defer rejected.deinit(std.testing.allocator);
        try std.testing.expect(rejected.diagnostics.items.len != 0);
    }
}
