const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const closed = @import("closed_local_value.zig");
const backend = @import("../backend/core_backend.zig");
const a = std.testing.allocator;
const definitions =
    \\type Box f is data = #Box f
    \\const box = fn value => #Box value
    \\const get = fn (#Box mapper) => mapper
    \\
;
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    return core.lower(allocator, &tree, &pool, &checked);
}
fn initializer(m: *const core.Module) !core.Id {
    for (m.nodes) |node| if (node.tag == .bind and m.node(node.b).tag == .call) return node.b;
    return error.MissingInitializer;
}
const captured = definitions ++
    \\entry const run = fn (seed: U32) => do:
    \\  let stored = box (fn value => {item: value})
    \\  let read = fn (value: U32) => (get stored value).item
    \\  break read seed
;
const mutable =
    \\type Maybe value is data = #Nothing | #Just value
    \\entry const loop = fn (limit: U32) => do:
    \\  let pending = (#Nothing, #[1])
    \\  let index = 0
    \\  for ever:
    \\    let (state, request) = pending
    \\    if @u32.eq index limit:
    \\      break case state of
    \\        #Nothing => request[0]
    \\        #Just value => @u32.add value request[0]
    \\    pending := (#Just index, #[@u32.add index 2])
    \\    index := @u32.add self 1
    \\entry const branch = fn (value: U32) => do:
    \\  let pending = (#Nothing, #[1])
    \\  if @u32.lt 0 value:
    \\    pending := (#Just value, #[2])
    \\  let (state, request) = pending
    \\  break case state of
    \\    #Nothing => request[0]
    \\    #Just item => @u32.add item request[0]
;
fn compileMutable(allocator: std.mem.Allocator) !void {
    var m = try lower(allocator, mutable);
    defer m.deinit(allocator);
    var result = try backend.compile(allocator, &.{m}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    const name = "\x0eblot:ownership";
    const start = (std.mem.find(u8, result.bytes, name) orelse return error.MissingOwnership) + name.len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, result.bytes[start..][0..3]);
}
test "closed local initializers preserve physical loop and branch state through allocation failure" {
    try compileMutable(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compileMutable, .{});
}
fn compile(allocator: std.mem.Allocator) !void {
    var m = try lower(allocator, captured);
    defer m.deinit(allocator);
    var result = try backend.compile(allocator, &.{m}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    const name = "\x0eblot:ownership";
    const start = (std.mem.find(u8, result.bytes, name) orelse return error.MissingOwnership) + name.len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, result.bytes[start..][0..3]);
}
test "closed local values carry live generic captures with complete ownership through every allocation failure" {
    try compile(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compile, .{});
}
test "closed local value proof keeps exact wrapper dependencies and rejects effects traps runtime captures and demands" {
    var good = try lower(a, captured);
    defer good.deinit(a);
    const proof = closed.analyze(&.{good}, 1, try initializer(&good)) orelse return error.MissingProof;
    try std.testing.expectEqual(@as(usize, 1), proof.len);
    const body = good.body(proof.dependencies[0].binding).?;
    try std.testing.expectEqual(core.Tag.construct, good.node(body.root).tag);
    // Even a source-shaped promise of purity cannot hide a changed executable
    // wrapper body. The structural proof inspects that exact selected body.
    const saved = good.nodes[body.root];
    good.nodes[body.root].tag = .panic;
    try std.testing.expect(closed.analyze(&.{good}, 1, try initializer(&good)) == null);
    good.nodes[body.root] = saved;
    {
        const old_nodes = good.nodes;
        const nodes = try a.alloc(core.Node, old_nodes.len + 1);
        defer a.free(nodes);
        @memcpy(nodes[0..old_nodes.len], old_nodes);
        nodes[old_nodes.len] = saved;
        nodes[body.root] = .{ .tag = .return_, .ty = @import("../check/types.zig").never, .a = @intCast(old_nodes.len) };
        good.nodes = nodes;
        defer good.nodes = old_nodes;
        try std.testing.expect(closed.analyze(&.{good}, 1, try initializer(&good)) != null);
    }
    const cases = [_][]const u8{
        definitions ++ "entry const run = fn (seed: U32) => do:\n  let stored = box (fn value => {item: @u32.add value seed})\n  let #Box mapper = stored\n  break (mapper 3).item\n",
        definitions ++ "entry const run = fn (seed: U32) => do:\n  let stored = box (fn value => {item: @u32.div value 0})\n  let #Box mapper = stored\n  break (mapper seed).item\n",
        definitions ++ "entry const run = fn (host: Unit -> U32 ! {Foreign}) => do:\n  use stored <- box ((fn value => {item: value}), host ())\n  let #Box (mapper, stamp) = stored\n  break @u32.add stamp (mapper 3).item\n",
        definitions ++ "const keep = fn ~value => fn () => @demand value\nentry const run = fn () => do:\n  let stored = box (keep 42)\n  let #Box waiting = stored\n  break waiting ()\n",
        definitions ++ "entry const run = fn (seed: unique U32) => do:\n  let stored = box (fn (value: unique U32) -> once (Unit -> unique U32) => fn () => value)\n  let #Box mapper = stored\n  break (mapper seed) ()\n",
    };
    for (cases) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try std.testing.expect(closed.analyze(&.{m}, 1, try initializer(&m)) == null);
    }
}

test "closed local value proof rejects phantom authority recursively through every data shape" {
    const T = @import("../check/types.zig");
    const fixtures = [_][]const u8{
        "Phantom U32 = #Phantom",
        "(Phantom U32, U32) = (#Phantom, 1)",
        "{item: Phantom U32} = {item: #Phantom}",
        "Array (Phantom U32) = #[#Phantom]",
    };
    const authorities = [_]T.Node{
        .{ .tag = .scoped, .a = T.u32_type, .b = 1, .c = 17 },
        .{ .tag = .usage, .a = T.u32_type, .b = @backingInt(T.UsageKind.unique) },
        .{ .tag = .bound, .a = 0, .b = 0 },
        .{ .tag = .rigid, .a = 17, .b = 0, .c = 0 },
    };
    for (fixtures) |fixture| {
        const source = try a.print("type Phantom value is data = #Phantom\nentry const run = fn () => do:\n  let stored: {s}\n  break ()\n", .{fixture});
        defer a.free(source);
        var m = try lower(a, source);
        defer m.deinit(a);
        var root: core.Id = 0;
        for (m.nodes) |node| if (node.tag == .bind) {
            root = node.b;
            break;
        };
        try std.testing.expect(root != 0);
        try std.testing.expect(closed.analyze(&.{m}, 1, root) != null);
        const original_type = m.nodes[root].ty;
        const outer = m.types.node(original_type);
        const leaf = switch (outer.tag) {
            .nominal => original_type,
            .product => m.types.list(.{ .start = outer.a, .len = outer.b })[0],
            .record => m.types.recordField(outer, 0).ty,
            .array => outer.a,
            else => return error.UnexpectedShape,
        };
        const phantom = m.types.node(leaf);
        try std.testing.expectEqual(T.Tag.nominal, phantom.tag);
        const old_nodes = m.types.nodes;
        const old_extra = m.types.extra;
        const nodes = try a.alloc(T.Node, old_nodes.len + 3);
        defer a.free(nodes);
        const extra = try a.alloc(T.Id, old_extra.len + 4);
        defer a.free(extra);
        @memcpy(nodes[0..old_nodes.len], old_nodes);
        @memcpy(extra[0..old_extra.len], old_extra);
        const authority: T.Id = @intCast(old_nodes.len);
        const phantom_id = authority + 1;
        const outer_id = authority + 2;
        nodes[phantom_id] = phantom;
        nodes[phantom_id].c = @intCast(old_extra.len);
        extra[old_extra.len] = 1;
        extra[old_extra.len + 1] = authority;
        nodes[outer_id] = outer;
        switch (outer.tag) {
            .nominal => m.nodes[root].ty = phantom_id,
            .product => {
                nodes[outer_id].a = @intCast(old_extra.len + 2);
                extra[old_extra.len + 2] = phantom_id;
                extra[old_extra.len + 3] = T.u32_type;
                m.nodes[root].ty = outer_id;
            },
            .record => {
                nodes[outer_id].a = @intCast(old_extra.len + 2);
                extra[old_extra.len + 2] = m.types.recordField(outer, 0).name;
                extra[old_extra.len + 3] = phantom_id;
                m.nodes[root].ty = outer_id;
            },
            .array => {
                nodes[outer_id].a = phantom_id;
                m.nodes[root].ty = outer_id;
            },
            else => unreachable,
        }
        m.types.nodes = nodes;
        m.types.extra = extra;
        defer {
            m.types.nodes = old_nodes;
            m.types.extra = old_extra;
            m.nodes[root].ty = original_type;
        }
        // The value children and ordinary constructor shape stay unchanged.
        // Its exact phantom argument still must not confer scoped, affine or
        // lexical authority on a value promoted into the evaluator.
        for (authorities) |forged| {
            nodes[authority] = forged;
            try std.testing.expect(closed.analyze(&.{m}, 1, root) == null);
        }
    }
}
