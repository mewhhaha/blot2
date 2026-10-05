const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const source =
    \\type Box value is data = #Box value
    \\const Box.pure = fn value => #Box value
    \\const Box.bind = fn candidate => fn next => case candidate of
    \\  #Box value => next value
    \\const sequence = fn () => do (@do.monad Box):
    \\  let total = 20
    \\  use value <- #Box 22
    \\  total := @u32.add self value
    \\  return total
    \\entry const answer = fn () => do:
    \\  let #Box value = sequence ()
    \\  return value
;
const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    checked: check.Checked,
    resolver: core.BindingId,
    total: core.BindingId,
    parameter: core.BindingId,
    fn init() !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &pool);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |diagnostic| std.debug.print("monad {d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        try std.testing.expectEqual(@as(usize, 1), checked.resolver_blocks.len);
        const block = checked.resolver_blocks[0];
        const statements = tree.children(block.node);
        return .{ .tree = tree, .pool = pool, .checked = checked, .resolver = block.resolver, .total = checked.resolved[statements[0]], .parameter = checked.resolver_ops[checked.resolver_op_ids[statements[1]] - 1].continuation_parameter };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn lower(self: *const Fixture, allocator: std.mem.Allocator) !core.Module {
        return core.lower(allocator, &self.tree, &self.pool, &self.checked);
    }
};
fn verify(module: *const core.Module, resolver: core.BindingId, total: core.BindingId, parameter: core.BindingId) !void {
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var binds: usize = 0;
    var factories: usize = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag != .resolver_op) continue;
        const id: core.Id = @intCast(index);
        const info = module.resolverInfo(id);
        const args = module.resolverArguments(id);
        if (info.operation == .monad) {
            factories += 1;
            try std.testing.expectEqual(core.Tag.type_constructor, module.node(info.resolver).tag);
            try std.testing.expectEqual(T.Tag.resolver, module.types.node(node.ty).tag);
            try std.testing.expectEqual(T.Tag.type_constructor, module.types.node(module.types.node(node.ty).a).tag);
            try std.testing.expectEqual(@as(usize, 0), args.len);
        }
        if (info.operation != .bind) continue;
        binds += 1;
        try std.testing.expectEqual(@as(usize, 2), args.len);
        try std.testing.expectEqual(core.Tag.construct, module.node(args[0]).tag);
        const continuation = module.closure(args[1]);
        try std.testing.expectEqual(parameter, continuation.parameter.binding);
        try std.testing.expectEqual(T.Tag.u32, module.types.node(continuation.parameter.ty).tag);
        const captures = module.closureCaptures(args[1]);
        try std.testing.expectEqual(@as(usize, 2), captures.len);
        try std.testing.expect(std.mem.indexOfScalar(core.BindingId, captures, resolver) != null);
        try std.testing.expect(std.mem.indexOfScalar(core.BindingId, captures, total) != null);
        try std.testing.expect(std.mem.indexOfScalar(core.BindingId, captures, parameter) == null);
        try std.testing.expectEqual(T.Tag.function, module.types.node(info.method_type).tag);
        try std.testing.expectEqual(T.Tag.resolver, module.types.node(module.node(info.resolver).ty).tag);
    }
    try std.testing.expectEqual(@as(usize, 1), binds);
    try std.testing.expectEqual(@as(usize, 1), factories);
}
test "monad continuations own typed method signatures and immutable lexical captures" {
    var fixture = try Fixture.init();
    const resolver = fixture.resolver;
    const total = fixture.total;
    const parameter = fixture.parameter;
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try verify(&module, resolver, total, parameter);
}
fn allocationFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try verify(&module, fixture.resolver, fixture.total, fixture.parameter);
}
test "resolver protocol and continuation allocation failures release every owned table" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}

const iteration_source =
    \\type Iteration [state,result] is data = #Continue state | #Done result
    \\type Maybe value is data = #Some value | #Nothing
    \\const monad = fn constructor => @do.monad constructor
    \\const Maybe.pure = fn value => #Some value
    \\const Maybe.bind = fn candidate => fn next => case candidate of
    \\  #Some value => next value
    \\  #Nothing => #Nothing
    \\const Maybe.iterate = fn initial => fn step => do:
    \\  let state = initial
    \\  for ever:
    \\    use candidate <- step state
    \\    if let #Some (#Done result) = candidate:
    \\      return #Some result
    \\    let #Some (#Continue next) = candidate else:
    \\      return #Nothing
    \\    state := next
    \\const sequence = fn forwarded => do (monad Maybe):
    \\  let total = 20
    \\  for outer in 0..2:
    \\    for inner in 0..2:
    \\      use value <- #Some 1
    \\      total := @u32.add self value
    \\      if forwarded:
    \\        return $ #Some (@u32.add total 21)
    \\      if @u32.eq inner 1:
    \\        return @u32.add total 20
    \\      break
    \\  return total
    \\entry const answer = fn () => case sequence #True of
    \\  #Some value => value
    \\  #Nothing => 0
;
const IterationFixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    checked: check.Checked,
    fn init() !IterationFixture {
        return initSource(iteration_source);
    }
    fn initSource(text: []const u8) !IterationFixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .prelude_unit = 1 });
        errdefer checked.deinit(a);
        for (checked.diagnostics) |diagnostic| std.debug.print("iteration {d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .tree = tree, .pool = pool, .checked = checked };
    }
    fn deinit(self: *IterationFixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn lower(self: *const IterationFixture, allocator: std.mem.Allocator) !core.Module {
        return core.lower(allocator, &self.tree, &self.pool, &self.checked);
    }
};
fn verifyIteration(module: *const core.Module, done_constructor: u32) !void {
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var iterations: usize = 0;
    var done_layers: usize = 0;
    for (module.nodes, 0..) |node, index| {
        const id: core.Id = @intCast(index);
        if (node.tag == .construct) {
            const constructor = module.constructors[node.a];
            if (node.a == done_constructor) {
                try std.testing.expectEqual(@as(u32, 1), constructor.identity.unit);
                done_layers += 1;
            }
        }
        if (node.tag != .resolver_op or module.resolverInfo(id).operation != .iterate) continue;
        iterations += 1;
        const arguments = module.resolverArguments(id);
        try std.testing.expectEqual(@as(usize, 2), arguments.len);
        try std.testing.expectEqual(core.Tag.product, module.node(arguments[0]).tag);
        const step = module.closure(arguments[1]);
        const cursor = module.types.node(step.parameter.ty);
        try std.testing.expectEqual(T.Tag.product, cursor.tag);
        try std.testing.expectEqual(@as(u32, 2), cursor.b);
        try std.testing.expect(std.mem.indexOfScalar(core.BindingId, module.closureCaptures(arguments[1]), step.parameter.binding) == null);
    }
    try std.testing.expectEqual(@as(usize, 2), iterations);
    try std.testing.expect(done_layers >= 6);
}
test "monadic loop continuations own cursors and nested progress after frontend teardown" {
    var fixture = try IterationFixture.init();
    const done_constructor = fixture.checked.resolver_loops[0].done_constructor;
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try verifyIteration(&module, done_constructor);
}
fn iterationAllocationFailure(allocator: std.mem.Allocator, fixture: *const IterationFixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try verifyIteration(&module, fixture.checked.resolver_loops[0].done_constructor);
}
test "monadic loop finalizers nested completions and temporary frames release failed allocations" {
    var fixture = try IterationFixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, iterationAllocationFailure, .{&fixture});
}
test "flat monadic statement sequences do not consume the nested expression depth limit" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a,
        \\type Box value is data = #Box value
        \\const Box.pure = fn value => #Box value
        \\const sequence = fn () => do (@do.monad Box):
        \\  let total = 0
    );
    try text.append(a, '\n');
    for (0..1536) |_| try text.appendSlice(a, "  total := @u32.add self 1\n");
    try text.appendSlice(a,
        \\  return total
        \\entry const answer = fn () => do:
        \\  let #Box value = sequence ()
        \\  return value
    );
    var fixture = try IterationFixture.initSource(text.items);
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
}
