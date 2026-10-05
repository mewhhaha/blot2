const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const Fixture = struct {
    pool: symbols.Pool = .{},
    tree: ast.Tree,
    checked: check.Checked,
    fn init(allocator: std.mem.Allocator, text: []const u8) !Fixture {
        return initOptions(allocator, text, .{});
    }
    fn initOptions(allocator: std.mem.Allocator, text: []const u8, options: check.ModuleOptions) !Fixture {
        var tokens = try lexer.lex(allocator, text);
        defer tokens.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(allocator);
        var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
        errdefer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, options);
        return .{ .pool = pool, .tree = tree, .checked = checked };
    }
    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.checked.deinit(allocator);
        self.tree.deinit(allocator);
        self.pool.deinit(allocator);
    }
    fn valid(self: *const Fixture) !void {
        for (self.checked.diagnostics) |d| std.debug.print("{s}:{d}\n", .{ @tagName(d.code), d.span.start });
        try std.testing.expectEqual(@as(usize, 0), self.checked.diagnostics.len);
    }
};
const generic_alias =
    \\type Box value is data = #Box value
    \\const Box.pure = fn value => #Box value
    \\const Box.bind = fn candidate => fn next => case candidate of
    \\  #Box value => next value
    \\const monad = fn constructor => @do.monad constructor
    \\const identity = fn value => value
    \\const resolver = identity (monad (identity Box))
    \\const sequence = fn selected => fn candidate => do selected:
    \\  use value <- candidate
    \\  return @u32.add value 2
    \\entry const answer = fn () => do:
    \\  let #Box value = sequence resolver (#Box 40)
    \\  return value
    \\entry const folded = answer ()
;
const lift_forward_unit =
    \\type Box value is data = #Box value
    \\const Box.pure = fn value => #Box value
    \\const Box.bind = fn candidate => fn next => case candidate of
    \\  #Box value => next value
    \\const monad = fn constructor => @do.monad constructor
    \\const present = do (monad Box):
    \\  return 40
    \\const forwarded = do (monad Box):
    \\  return $ #Box 2
    \\const finished = do (monad Box):
    \\  #Box 99
    \\entry const answer = fn () => do:
    \\  let #Box left = present
    \\  let #Box right = forwarded
    \\  let #Box () = finished
    \\  return @u32.add left right
;
const pure_ignores_mixed_returns =
    \\type Box value is data = #Box value
    \\const Box.pure = fn ignored => #Box 42
    \\const sequence = fn enabled => do (@do.monad Box):
    \\  if enabled:
    \\    return #True
    \\  return 40
    \\entry const answer = fn () => do:
    \\  let #Box first = sequence #True
    \\  let #Box second = sequence #False
    \\  return @u32.add first second
;
const scalar_bind_input =
    \\type Box value is data = #Box value
    \\const Box.pure = fn value => #Box value
    \\const Box.bind = fn (candidate:U32) => fn next => next candidate
    \\const sequence = fn () => do (@do.monad Box):
    \\  use value <- 40
    \\  return @u32.add value 2
    \\entry const answer = fn () => do:
    \\  let #Box value = sequence ()
    \\  return value
;
const continuation_multiplicity =
    \\type Twice value is data = #Twice value
    \\const Twice.pure = fn value => #Twice value
    \\const Twice.bind = fn candidate => fn next => case candidate of
    \\  #Twice value => do:
    \\    let #Twice first = next value
    \\    let #Twice second = next (@u32.add value 1)
    \\    return #Twice (@u32.add first second)
    \\const sequence = fn () => do (@do.monad Twice):
    \\  let total = 0
    \\  use value <- #Twice 20
    \\  total := @u32.add self value
    \\  return total
    \\entry const answer = fn () => do:
    \\  let #Twice value = sequence ()
    \\  return value
;
const bind_failure =
    \\type Option value is data = #Present value | #Absent
    \\const Option.pure = fn value => #Present value
    \\const Option.bind = fn candidate => fn next => case candidate of
    \\  #Present value => next value
    \\  #Absent => #Absent
    \\const sequence = fn () => do (@do.monad Option):
    \\  use value <- #Absent
    \\  return @panic "continuation must not execute"
    \\entry const answer = fn () => case sequence () of
    \\  #Present value => value
    \\  #Absent => 42
;
test "ordinary monad methods infer generic aliases arbitrary bind inputs and ignored returns" {
    for ([_][]const u8{ generic_alias, lift_forward_unit, pure_ignores_mixed_returns, scalar_bind_input, continuation_multiplicity, bind_failure }) |text| {
        var f = try Fixture.init(a, text);
        defer f.deinit(a);
        try f.valid();
        try std.testing.expect(f.checked.resolver_blocks.len != 0);
        for (f.checked.resolver_ops) |op| {
            if (op.kind == .pure or op.kind == .bind) {
                // Generic producer operations remain latent. Concrete producers
                // publish the selected ordinary method identity once solved.
                if (op.method != 0) {
                    try std.testing.expectEqual(T.Tag.function, f.checked.types.node(op.method_type).tag);
                }
            }
        }
        for (f.checked.bindings[1..]) |binding| {
            if (binding.kind == .global and std.mem.eql(u8, f.pool.get(binding.name), "answer")) try std.testing.expectEqual(@as(u32, 0), binding.scheme.variables.len);
        }
    }
}
test "resolver protocol rejects invalid factories providers and incompatible selected source methods" {
    const cases = [_]struct { text: []const u8, code: check.Code }{
        .{ .text = "entry const answer=@do.monad 42\n", .code = .type_constructor_required },
        .{ .text = "entry const answer=do 42:\n  return 42\n", .code = .invalid_provider },
        .{ .text = "type Box value is data = #Box value\nentry const answer=do (@do.monad Box):\n  return 42\n", .code = .missing_member },
        .{ .text = "type Box value is data = #Box value\nconst Box.pure=fn(value:U32)=>#Box value\nentry const answer=do (@do.monad Box):\n  return #True\n", .code = .type_mismatch },
        .{ .text = "entry const answer=do:\n  return $ 42\n", .code = .resolver_required },
        .{ .text = "type Box value is data = #Box value\nconst Box.pure=fn value=>value\nentry const answer=do (@do.monad Box):\n  return 42\n", .code = .type_mismatch },
    };
    for (cases) |item| {
        var f = try Fixture.init(a, item.text);
        defer f.deinit(a);
        var found = false;
        for (f.checked.diagnostics) |d| found = found or d.code == item.code;
        if (!found) std.debug.print("Missing {s} for {s}; actual {any}\n", .{ @tagName(item.code), item.text, f.checked.diagnostics });
        try std.testing.expect(found);
    }
}
fn monadFailures(allocator: std.mem.Allocator) !void {
    var f = try Fixture.init(allocator, generic_alias);
    defer f.deinit(allocator);
    try f.valid();
}
test "resolver catalogs protocols and branch continuations free every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, monadFailures, .{});
}

const iteration_prelude =
    \\type Iteration [state,result] is data = #Continue state | #Done result
    \\type Maybe value is data = #Some value | #Nothing
    \\const monad=fn constructor=>@do.monad constructor
    \\const Maybe.pure = fn value => #Some value
    \\const Maybe.map = fn transform => fn candidate => case candidate of
    \\  #Some value => #Some (transform value)
    \\  #Nothing => #Nothing
    \\const Maybe.bind = fn candidate => fn next => case candidate of
    \\  #Some value => next value
    \\  #Nothing => #Nothing
    \\// Finish each callback before advancing, so iteration uses constant stack.
    \\const Maybe.iterate = fn initial => fn step => do:
    \\  let state = initial
    \\  for ever:
    \\    use candidate <- step state
    \\    if let #Some (#Done result) = candidate:
    \\      return #Some result
    \\    let #Some (#Continue next) = candidate else:
    \\      return #Nothing
    \\    state := next
    \\const Maybe.unwrap_or = fn fallback => fn candidate => case candidate of
    \\  #Some value => value
    \\  #Nothing => fallback
;
const nested_loop_break =
    \\const sequence = fn () => do (monad Maybe):
    \\  let total = 0
    \\  for outer in 0..3:
    \\    for inner in 0..4:
    \\      use value <- #Some 1
    \\      total := @u32.add self value
    \\      if @u32.eq inner 1:
    \\        break
    \\    total := @u32.add self 10
    \\    if @u32.eq outer 1:
    \\      break
    \\  return @u32.add total 18
    \\entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
;
const bounded_stack =
    \\const range = fn count => do (monad Maybe):
    \\  let total = 0
    \\  for index in 0..count:
    \\    use value <- #Some 1
    \\    total := @u32.add self value
    \\  return total
    \\const forever = fn count => do (monad Maybe):
    \\  let total = 0
    \\  for ever:
    \\    use value <- #Some 1
    \\    total := @u32.add self value
    \\    if @u32.eq total count:
    \\      return $ #Some total
    \\entry const answer = fn () => @u32.add (Maybe.unwrap_or 0 (range 100000)) (Maybe.unwrap_or 0 (forever 100000))
;
test "monadic iteration freezes actual source methods progress constructors and completion signatures" {
    for ([_][]const u8{ iteration_prelude ++ "\n" ++ nested_loop_break, iteration_prelude ++ "\n" ++ bounded_stack }) |text| {
        var f = try Fixture.initOptions(a, text, .{ .prelude_unit = 1 });
        defer f.deinit(a);
        try f.valid();
        try std.testing.expectEqual(@as(usize, 2), f.checked.resolver_loops.len);
        for (f.checked.resolver_loops) |loop| {
            const cursor = f.checked.types.node(loop.cursor);
            try std.testing.expectEqual(T.Tag.product, cursor.tag);
            try std.testing.expectEqual(@as(u32, 2), cursor.b);
            const op = f.checked.resolver_ops[loop.iterate - 1];
            try std.testing.expectEqual(check.ResolverKind.iterate, op.kind);
            try std.testing.expect(op.method != 0);
            const completion = f.checked.resolver_completions[loop.finish - 1];
            try std.testing.expectEqual(loop.done_constructor, completion.done_constructor);
            try std.testing.expectEqual(@as(u32, 1), completion.completed_types.len);
            try std.testing.expectEqual(@as(u32, 1), f.checked.constructors[loop.done_constructor].identity.unit);
        }
    }
}
fn iterationFailures(allocator: std.mem.Allocator) !void {
    var f = try Fixture.initOptions(allocator, iteration_prelude ++ "\n" ++ nested_loop_break, .{ .prelude_unit = 1 });
    defer f.deinit(allocator);
    try f.valid();
}
test "monadic iteration metadata and completion continuations release every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, iterationFailures, .{});
}

test "two parameter resolver families preserve hidden failure evidence in forwarding" {
    var f = try Fixture.init(a,
        \\type Result [error,value] is data = #Ok value | #Err error
        \\const Result.pure=fn value=>#Ok value
        \\const Result.bind=fn candidate=>fn next=>case candidate of
        \\  #Ok value=>next value
        \\  #Err error=>#Err error
        \\const Result.unwrap_or=fn fallback=>fn candidate=>case candidate of
        \\  #Ok value=>value
        \\  #Err _=>fallback
        \\const checked=fn candidate=>do (@do.monad Result):
        \\  use value <- candidate
        \\  return $ #Ok (@u32.add value 2)
        \\entry const result=fn()=>Result.unwrap_or 0 (checked (#Ok 40))
    );
    defer f.deinit(a);
    try f.valid();
}

test "nested monadic returns retain every progress layer and forwarding continuation" {
    var f = try Fixture.initOptions(a, iteration_prelude ++ "\n" ++
        \\const direct=fn()=>do (monad Maybe):
        \\  for outer in 0..2:
        \\    for inner in 0..2:
        \\      return 42
        \\  return 0
        \\const forward=fn()=>do (monad Maybe):
        \\  for outer in 0..2:
        \\    for inner in 0..2:
        \\      return $ #Some 42
        \\  return 0
        \\entry const answer=fn()=>@u32.add (Maybe.unwrap_or 0 (direct())) (Maybe.unwrap_or 0 (forward()))
    , .{ .prelude_unit = 1 });
    defer f.deinit(a);
    try f.valid();
    var direct = false;
    var forwarded = false;
    for (f.checked.resolver_ops) |op| {
        direct = direct or op.completed_types.len == 2;
        if (op.kind == .forward and op.completion != 0) {
            const completion = f.checked.resolver_completions[op.completion - 1];
            forwarded = forwarded or completion.completed_types.len == 2;
        }
    }
    try std.testing.expect(direct and forwarded);
}
test "monadic loops require source iterate and designated progress rather than same named local constructors" {
    const box =
        \\type Box value is data = #Box value
        \\const Box.pure=fn value=>#Box value
        \\const Box.bind=fn candidate=>fn next=>case candidate of
        \\  #Box value=>next value
        \\entry const answer=fn()=>do (@do.monad Box):
        \\  for index in 0..1:
        \\    use #Box ()
        \\  return 42
    ;
    var missing = try Fixture.initOptions(a, iteration_prelude ++ "\n" ++ box, .{ .prelude_unit = 1 });
    defer missing.deinit(a);
    var found = false;
    for (missing.checked.diagnostics) |d| found = found or d.code == .missing_member;
    try std.testing.expect(found);
    var no_prelude = try Fixture.init(a, iteration_prelude ++ "\n" ++ box);
    defer no_prelude.deinit(a);
    found = false;
    for (no_prelude.checked.diagnostics) |d| found = found or d.code == .unknown_constructor;
    try std.testing.expect(found);
}

test "nested resolver break completes lexical state: nested_resolver_break" {
    var f = try Fixture.initOptions(a, iteration_prelude ++ "\n" ++
        \\const sequence = fn () => do (monad Maybe):
        \\  let total = 0
        \\  for index in 0..3:
        \\    total := @u32.add self 1
        \\    let ignored = do (monad Maybe):
        \\      break
        \\  return total
        \\entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
    , .{ .prelude_unit = 1 });
    defer f.deinit(a);
    try f.valid();
    var found = false;
    for (f.checked.loop_exits) |exit| {
        const op = f.checked.resolver_op_ids[exit.node];
        if (op == 0) continue;
        found = true;
        try std.testing.expectEqual(check.ResolverKind.pure, f.checked.resolver_ops[op - 1].kind);
        try std.testing.expectEqual(T.Tag.product, f.checked.types.node(f.checked.resolver_ops[op - 1].payload).tag);
    }
    try std.testing.expect(found);
}
test "nested resolver break completes lexical state: nested_monad_in_plain_loop_break" {
    var f = try Fixture.initOptions(a, iteration_prelude ++ "\n" ++
        \\entry const answer = fn () => do:
        \\  let total = 0
        \\  for index in 0..3:
        \\    total := @u32.add self 1
        \\    let ignored = do (monad Maybe):
        \\      break
        \\  return total
    , .{ .prelude_unit = 1 });
    defer f.deinit(a);
    try f.valid();
    var found = false;
    for (f.checked.loop_exits) |exit| {
        const op = f.checked.resolver_op_ids[exit.node];
        if (op == 0) continue;
        found = true;
        try std.testing.expectEqual(check.ResolverKind.pure, f.checked.resolver_ops[op - 1].kind);
        try std.testing.expectEqual(T.Tag.product, f.checked.types.node(f.checked.resolver_ops[op - 1].payload).tag);
    }
    try std.testing.expect(found);
}
test "ordinary nested do cannot break a monadic progress boundary" {
    var f = try Fixture.initOptions(a, iteration_prelude ++ "\n" ++
        \\const sequence = fn () => do (monad Maybe):
        \\  let total = 0
        \\  for index in 0..3:
        \\    use value <- #Some 1
        \\    total := @u32.add self value
        \\    let ignored = do:
        \\      break
        \\  return @u32.add total 41
        \\entry const answer = fn () => Maybe.unwrap_or 0 (sequence ())
    , .{ .prelude_unit = 1 });
    defer f.deinit(a);
    var found = false;
    for (f.checked.diagnostics) |d| found = found or d.code == .invalid_return;
    try std.testing.expect(found);
}
test "definitely panicking resolver return invokes no missing pure method" {
    var f = try Fixture.init(a,
        \\type Box value is data = #Box value
        \\const sequence = fn () => do (@do.monad Box):
        \\  return @panic "body panic"
        \\entry const answer: U32 = do:
        \\  let #Box value = sequence ()
        \\  return value
    );
    defer f.deinit(a);
    try f.valid();
    for (f.checked.resolver_ops) |op| try std.testing.expect(op.kind != .pure);
}
