const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const T = @import("types.zig");
fn law(source: []const u8, expected: ?check.Code) !void {
    const a = std.testing.allocator;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    for (tree.diagnostics.items) |d| std.debug.print("syntax {any}\n", .{d});
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var result = try check.check(a, &tree, &pool);
    defer result.deinit(a);
    if (expected) |code| {
        for (result.diagnostics) |d| if (d.code == code) return;
    } else if (result.diagnostics.len == 0) return;
    for (result.diagnostics) |d| std.debug.print("usage {s} {d}\n", .{ @tagName(d.code), d.span.start });
    std.debug.print("failed usage source {s} expected {any}\n", .{ source, expected });
    return error.TestUnexpectedResult;
}
test "usage qualifiers preserve affine moves aliases and branch ownership" {
    try law("const keep = fn (owner: unique U32) => owner\n", null);
    try law("const duplicate = fn (owner: unique U32) => (owner, owner)\n", .use_after_move);
    try law("const alias = fn (owner: unique U32) => do:\n  let next = owner\n  return (next, owner)\n", .use_after_move);
    try law("const branch = fn (owner: unique U32) => fn choose => do:\n  if choose:\n    let moved = owner\n  return owner\n", .use_after_move);
    try law("const pair = fn (owners: (unique U32, U32)) => (owners, owners)\n", .use_after_move);
    try law("const unknown = fn (owner: unique U32) => fn (callback: a -> a) => callback owner\n", .multiplicity_unknown);
}
test "usage once calls cannot repeat or hide in many closures" {
    try law("const run = fn (callback: once (Unit -> U32)) => callback ()\n", null);
    try law("const twice = fn (callback: once (Unit -> U32)) => (callback (), callback ())\n", .once_reused);
    try law("const many_capture = fn (owner: unique U32) => fn () => owner\n", .duplicate_owner);
    try law("const capture = fn (owner: unique U32) -> once (Unit -> unique U32) => fn () => owner\n", null);
    try law("const one: once (Unit -> U32) = fn () => 7\n", null);
    try law("const loops = fn (callback: once (Unit -> U32)) => do:\n  for index in 0..3:\n    let value = callback ()\n  return ()\n", .once_reused);
}

test "usage immutable Core rejects repeated owners independently of source and capture catalogs" {
    const a = std.testing.allocator;
    const source = "const call = fn (callback: once (Unit -> U32)) => do:\n  let value = callback ()\n  return value\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("usage_core.zig").validate(&module);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(a, &module, .{});
    var callback: u32 = 0;
    var returned: u32 = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag == .reference and module.types.node(module.binding(module.reference(@intCast(index)).binding).ty).tag == .usage) callback = @intCast(index);
        if (node.tag == .return_) returned = @intCast(index);
    }
    try std.testing.expect(callback != 0 and returned != 0);
    const original = module.nodes[returned].a;
    module.nodes[returned].a = callback;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
    module.nodes[returned].a = original;
    module.has_usage_contracts = false;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
    module.has_usage_contracts = true;
    try validation.validate(a, &module, .{});
}

test "usage unchecked package and cleanup authority stay rejected" {
    try law("const hidden = fn (owner: unique U32) => pack [unique U32] owner as exists [a] => a\n", .usage_evidence_mismatch);
    try law("data Box = #Box (unique U32)\nconst read = fn owner => #Box owner\n", null);
    try law("const cleanup = fn (release: cleanup (Unit -> Unit)) => release ()\n", .cleanup_not_safe);
    try law("const bad = fn (owner: shared (unique U32)) => owner\n", .usage_evidence_mismatch);
}
fn usageOwnershipAllocationLaw(allocator: std.mem.Allocator) !void {
    const source =
        "const capture = fn (owner: unique U32) -> once (Unit -> unique U32) => fn () => owner\n" ++
        "const controlled = fn (callback: once (Unit -> Bool)) => do:\n  let value = do:\n    return #True\n  for index in 0..1:\n    let checked = case #True of\n      #True if callback () => #True\n      #True => #True\n      #False => #False\n  return #True\n" ++
        "const stopped = fn (callback: once (Unit -> U32)) => do:\n  for ever:\n    use callback ()\n    break\n  return ()\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "usage owning capture and control flow preserve cleanup on every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, usageOwnershipAllocationLaw, .{});
}

test "usage range bounds execute once before loop ownership joins" {
    try law("const bounds = fn (callback: once (Unit -> U32)) => do:\n  for (callback ())..3:\n    use ()\n  return callback ()\n", .once_reused);
    try law("const bounds = fn (callback: once (Unit -> U32)) => do:\n  for index in 0..(callback ()):\n    use ()\n  return callback ()\n", .once_reused);
    try law("const bounds = fn (callback: once (Unit -> U32)) => do:\n  for index in 0..(callback ()):\n    use ()\n  return ()\n", null);
}

test "usage failed guards retain outer moves and cannot consume pattern owners" {
    try law("const guarded = fn (callback: once (Unit -> Bool)) => case #True of\n  #True if callback () => #True\n  #True => callback ()\n  #False => #False\n", .once_reused);
    try law("const separate = fn (callback: once (Unit -> Bool)) => case #True of\n  #True => callback ()\n  #False => callback ()\n", null);
    try law("const guarded = fn (callbacks: (once (Unit -> Bool), Bool)) => case callbacks of\n  (callback, #True) if callback () => #True\n  (callback, _) => callback ()\n", .duplicate_owner);
}

test "usage nested do returns restore the enclosing owner flow" {
    try law("const nested = fn (callback: once (Unit -> U32)) => do:\n  let value = do:\n    return callback ()\n  return callback ()\n", .once_reused);
    try law("const nested = fn (callback: once (Unit -> Bool)) => do:\n  let value = do:\n    if #True:\n      return callback ()\n    return #False\n  return callback ()\n", .once_reused);
    try law("const nested = fn (callback: once (Unit -> U32)) => do:\n  let value = do:\n    return 7\n  return callback ()\n", null);
    try law("const named = fn (callback: once (Unit -> U32)) => do:\n  use next <- callback\n  return next ()\n", null);
}

test "usage loop breaks and returns carry moves without creating a backedge" {
    try law("const stopped = fn (callback: once (Unit -> U32)) => do:\n  for ever:\n    use callback ()\n    break\n  return ()\n", null);
    try law("const stopped = fn (callback: once (Unit -> U32)) => do:\n  for ever:\n    if #True:\n      use callback ()\n      break\n    break\n  return callback ()\n", .once_reused);
    try law("const stopped = fn (callback: once (Unit -> U32)) => do:\n  for ever:\n    let value = do:\n      use callback ()\n      break\n  return ()\n", null);
    try law("const returned = fn (callback: once (Unit -> U32)) => do:\n  for index in 0..3:\n    return callback ()\n  return 0\n", null);
}

fn portableControl(source: []const u8, corruption: enum { none, nested, guard, break_, bound, carry }) !void {
    const a = std.testing.allocator;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    for (checked.diagnostics) |d| std.debug.print("portable usage {s}\n", .{@tagName(d.code)});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("usage_core.zig").validate(&module);
    if (corruption == .none) return;
    if (corruption == .guard) {
        var guard: u32 = 0;
        for (module.match_arms) |arm| if (arm.guard != 0) {
            guard = arm.guard;
        };
        try std.testing.expect(guard != 0);
        module.match_arms[1].body = guard;
    } else if (corruption == .nested) {
        var call: u32 = 0;
        var inner_return: u32 = 0;
        for (module.nodes, 0..) |node, index| {
            if (node.tag == .apply) call = @intCast(index);
            if (node.tag == .return_ and module.nodes[node.a].tag == .constant) inner_return = @intCast(index);
        }
        try std.testing.expect(call != 0 and inner_return != 0);
        module.nodes[inner_return].a = call;
    } else if (corruption == .carry) {
        var callback: u32 = 0;
        var stopped: u32 = 0;
        for (module.nodes, 0..) |node, index| {
            if (node.tag == .reference and module.types.node(module.binding(module.reference(@intCast(index)).binding).ty).tag == .usage) callback = @intCast(index);
            if (node.tag == .break_ and node.c != 0) stopped = @intCast(index);
        }
        try std.testing.expect(callback != 0 and stopped != 0);
        module.extra[module.nodes[stopped].b] = callback;
    } else if (corruption == .bound) {
        try std.testing.expectEqual(@as(usize, 1), module.loops.len);
        const end = module.loops[0].end;
        module.nodes[end].a += 1;
    } else {
        var call: u32 = 0;
        var returned: u32 = 0;
        for (module.nodes, 0..) |node, index| {
            if (node.tag == .apply) call = @intCast(index);
            if (node.tag == .return_) returned = @intCast(index);
        }
        try std.testing.expect(call != 0 and returned != 0);
        module.nodes[returned].a = call;
    }
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
}

test "usage immutable control flow reconstructs nested return guard fallthrough and break moves" {
    try portableControl("const nested = fn (callback: once (Unit -> Bool)) => do:\n  let value = do:\n    return #True\n  return callback ()\n", .nested);
    try portableControl("const guarded = fn (callback: once (Unit -> Bool)) => case #True of\n  #True if callback () => #True\n  #True => #True\n  #False => #False\n", .guard);
    try portableControl("const stopped = fn (callback: once (Unit -> U32)) => do:\n  for ever:\n    use callback ()\n    break\n  return 0\n", .break_);
    try portableControl("const bounds = fn (callback: once (Unit -> U32)) => do:\n  for index in 0..(callback ()):\n    use ()\n  return ()\n", .none);
    try portableControl("const returned = fn (callback: once (Unit -> U32)) => do:\n  for index in 0..3:\n    return callback ()\n  return 0\n", .none);
}

test "usage exact one iteration bounds admit outer owners and reject later reuse" {
    try law("const one = fn (callback: once (Unit -> U32)) => do:\n  for index in (3)..(4):\n    use callback ()\n  return ()\n", null);
    try law("const reused = fn (callback: once (Unit -> U32)) => do:\n  for index in 3..4:\n    use callback ()\n  return callback ()\n", .once_reused);
    try law("const repeated = fn (callback: once (Unit -> U32)) => do:\n  for index in 3..5:\n    use callback ()\n  return ()\n", .once_reused);
    try portableControl("const one = fn (callback: once (Unit -> U32)) => do:\n  for index in (3)..(4):\n    use callback ()\n  return ()\n", .bound);
}

test "usage closures discover guard and if let capture ownership" {
    try law("const hidden = fn (callback: once (Unit -> Bool)) => fn () => case #True of\n  #True if callback () => #True\n  #True => #True\n  #False => #False\n", .duplicate_owner);
    try law("const hidden = fn (callback: once (Unit -> U32)) => fn () => do:\n  if let #True = #True:\n    return callback ()\n  return 0\n", .duplicate_owner);
}

test "usage lexical loans restore owners and reject result capture and conflicting access" {
    try law("const inspect = fn (owner: unique U32) => do:\n  let result = @usage.borrow owner (fn loan => @usage.read loan)\n  return owner\n", null);
    try law("const inspect = fn (owner: unique U32) => @usage.borrow_mut owner (fn loan => @u32.add (@usage.read loan) (@usage.read loan))\n", null);
    try law("const escape = fn (owner: unique U32) => @usage.borrow owner (fn loan => loan)\n", .borrow_escape);
    try law("const escape = fn (owner: unique U32) => @usage.borrow owner (fn loan => fn () => @usage.read loan)\n", .borrow_escape);
    try law("const conflict = fn (owner: unique U32) => @usage.borrow owner (fn loan => owner)\n", .borrow_conflict);
    try law("const incompatible = fn (owner: shared U32) => @usage.borrow_mut owner (fn loan => 7)\n", .usage_evidence_mismatch);
    try law("const moved = fn (owner: unique U32) => do:\n  let next = owner\n  return @usage.borrow owner (fn loan => @usage.read loan)\n", .borrow_conflict);
    try law("const nested = fn (owner: unique U32) => @usage.borrow_mut owner (fn loan => @usage.borrow loan (fn inner => @usage.read inner))\n", null);
}

test "usage loan callbacks cannot pass captured region authority to unknown callees" {
    try law("const bad = fn (store: (Unit -> Unit ! {}) -> Unit ! {Foreign}) => fn (owner: unique U32) => @usage.borrow owner (fn loan => store (fn () => do:\n  let value = loan\n  return ()\n))\n", .borrow_escape);
    try law("const size = fn (owner: unique (Array U32)) => @usage.borrow owner (fn loan => @usage.length loan)\n", null);
    try law("const size = fn (owner: unique (List U32)) => @usage.borrow owner (fn loan => @usage.length loan)\n", null);
}

fn loanArtifact(allocator: std.mem.Allocator, corrupt: bool) !void {
    const source = "const inspect = fn (owner: unique U32) => do:\n  let result = @usage.borrow owner (fn loan => @usage.read loan)\n  return result\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    if (!corrupt) return;
    var read: u32 = 0;
    var returned: u32 = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag == .usage_read) read = @intCast(index);
        if (node.tag == .return_) returned = @intCast(index);
    }
    try std.testing.expect(read != 0 and returned != 0);
    const prior = module.nodes[returned].a;
    module.nodes[returned].a = read;
    // Scalar result types match. The physical read still names a retired loan.
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.nodes[returned].a = prior;
    for (module.types.nodes) |*node| if (node.tag == .bound and node.b == 2) {
        node.c = module.bodies[0].binding;
        break;
    };
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
}

test "usage immutable loan reads retain lexical region ownership and reject retired reads" {
    try loanArtifact(std.testing.allocator, true);
    try portableControl("const nested = fn (owner: unique U32) => @usage.borrow_mut owner (fn loan => @usage.borrow loan (fn inner => @usage.read inner))\n", .none);
}

test "usage lexical loan publication releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, loanArtifact, .{false});
}

test "usage fresh scalar inputs preserve ownership without casting existing bindings" {
    try law("const inspect = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)\nentry const answer = fn () => inspect 9\n", null);
    try law("const inspect = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)\nconst bad = fn (existing: U32) => inspect existing\n", .type_mismatch);
    try law("const inspect = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)\nconst bad = fn (existing: shared U32) => inspect existing\n", .type_mismatch);
    try law("const escape = fn (owner: unique U32) -> unique U32 => @usage.borrow owner (fn loan => loan)\n", .borrow_escape);
}

test "usage immutable break operands retain executable owner moves" {
    try portableControl("const carry = fn (callback: once (Unit -> U32)) => do:\n  let count = 0\n  for ever:\n    count := @u32.add self 1\n    break\n  return callback ()\n", .carry);
}

fn storedLoan(named: bool) !void {
    const a = std.testing.allocator;
    var source: []const u8 = "const inspect = fn (store: (Unit -> U32 ! {}) -> U32 ! {Foreign}) => fn (owner: unique U32) => @usage.borrow owner (fn loan => do:\n  let callback = fn () => 7\n  return @u32.add (store callback) (@usage.read loan)\n)\n";
    if (named) source = "const store = fn (callback: Unit -> U32 ! {}) => callback ()\nconst inspect = fn (owner: unique U32) => @usage.borrow owner (fn loan => do:\n  let callback = fn () => 7\n  return @u32.add (store callback) (@usage.read loan)\n)\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try @import("usage_core.zig").validate(&module);
    var read: u32 = 0;
    var captured: u32 = std.math.maxInt(u32);
    for (module.nodes) |node| {
        if (node.tag == .usage_read) read = node.a;
        if (node.tag == .closure and module.nodes[module.closures[node.a].body].tag == .constant) captured = node.a;
    }
    try std.testing.expect(read != 0 and captured != std.math.maxInt(u32));
    var read_node: u32 = 0;
    for (module.nodes, 0..) |node, index| if (node.tag == .usage_read) {
        read_node = @intCast(index);
    };
    module.closures[captured].body = read_node;
    const prior = module.extra;
    module.extra = try a.alloc(u32, prior.len + 1);
    @memcpy(module.extra[0..prior.len], prior);
    module.extra[prior.len] = module.references[module.nodes[read].a].binding;
    module.closures[captured].captures = .{ .start = @intCast(prior.len), .len = 1 };
    a.free(prior);
    // Every header still promises a scalar result. The aliased closure now
    // retains a live loan, so passing it to either call target must decline.
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
}

test "usage portable calls reject hidden loan capture arguments through aliases" {
    try storedLoan(false);
    try storedLoan(true);
}

test "resource scalar scopes check finite pure cleanup and fresh loans" {
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => ()) (fn loan => @usage.read loan)\n", null);
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => @panic \"cleanup\") (fn loan => @usage.read loan)\n", null);
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => ()) (fn loan => loan)\n", .borrow_escape);
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => (fn () => ()) ()) (fn loan => ())\n", .cleanup_not_safe);
    try law("const run = fn (drop: unique U32 -> Unit) => @resource.scope (fn () => 9) drop (fn loan => @usage.read loan)\n", .cleanup_not_safe);
    try law("const run = fn () => @resource.scope (fn () => #[1]) (fn owner => ()) (fn loan => @usage.length loan)\n", null);
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => do:\n  for index in 0..3:\n    let value = index\n  return ()) (fn loan => ())\n", null);
    try law("const run = @resource.scope (fn () => 9) (fn owner => ()) (fn loan => @usage.read loan)\n", .const_effect);
}

fn resourceArtifact(a: std.mem.Allocator, corrupt: bool, kind: enum { integer, unit, float, boolean, array, list }) !void {
    const literal = switch (kind) {
        .integer => "9",
        .unit => "()",
        .float => "1.5",
        .boolean => "#True",
        .array => "#[1, 2]",
        .list => "[1.5, 2.5]",
    };
    var read: []const u8 = "read";
    if (kind == .array or kind == .list) read = "length";
    const source = try a.print("const run = fn () => @resource.scope (fn () => {s}) (fn owner => ()) (fn loan => @usage.{s} loan)\n", .{ literal, read });
    defer a.free(source);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    if (!corrupt) return;
    for (module.nodes) |node| if (node.tag == .resource_scope) {
        const original = module.node(node.b).ty;
        const wrapper = module.types.node(original);
        const saved = module.types.nodes[wrapper.a];
        if (kind == .array or kind == .list) {
            const owner = module.types.node(saved.a);
            const payload = module.types.nodes[owner.a];
            module.types.nodes[owner.a].a = original;
            try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
            try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(a, &module, .{}));
            module.types.nodes[owner.a] = payload;
        }
        module.types.nodes[wrapper.a].c = 1;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.types.nodes[wrapper.a] = saved;
        // Erasing the owning builtin Foreign effect cannot make a resource
        // eligible for startup execution or bypass its invocation journal.
        const binding = for (module.bodies) |body| {
            if (body.root != 0) break body.binding;
        } else return error.TestUnexpectedResult;
        var outer = module.bindings[binding].ty;
        while (module.types.node(outer).tag == .forall or module.types.node(outer).tag == .usage) outer = module.types.node(outer).a;
        try std.testing.expect(module.types.node(outer).tag == .function);
        const saved_outer = module.types.nodes[outer];
        module.types.nodes[outer].c = 0;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.types.nodes[outer] = saved_outer;
        const callback = module.closures[module.node(node.c).a];
        const saved_body = module.closures[module.node(node.b).a].body;
        module.closures[module.node(node.b).a].body = callback.body;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.closures[module.node(node.b).a].body = saved_body;
        const saved_node = module.nodes[saved_body];
        module.nodes[saved_body] = .{ .tag = .force, .a = saved_body, .ty = saved_node.ty };
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.nodes[saved_body] = saved_node;
        module.nodes[saved_body] = .{ .tag = .project, .a = saved_body, .ty = saved_node.ty };
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.nodes[saved_body] = saved_node;
        // An unused cleanup-qualified type is not an executable receipt and
        // must also decline at the whole-module portable boundary.
        const types = try a.alloc(T.Node, module.types.nodes.len + 1);
        @memcpy(types[0..module.types.nodes.len], module.types.nodes);
        types[module.types.nodes.len] = .{ .tag = .usage, .a = T.u32_type, .b = @backingInt(T.UsageKind.cleanup) };
        a.free(module.types.nodes);
        module.types.nodes = types;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        return;
    };
    return error.TestUnexpectedResult;
}
test "resource cleanup cannot hide recursive member invocations in projections" {
    try law("type Counter is data = #Counter Unit\nconst Counter.next: Counter -> U32 ! {} = fn counter => Counter.next counter\nconst run = fn (counter: Counter) => @resource.scope (fn () => 9) (fn owner => do:\n  let value = counter.next\n  return ()) (fn loan => @usage.read loan)\n", .cleanup_not_safe);
}

test "resource immutable adapter and loan contracts cannot be forged" {
    try resourceArtifact(std.testing.allocator, true, .integer);
}
test "resource source and immutable publication release every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, resourceArtifact, .{ false, .integer });
}

test "resource immutable scalar scopes preserve Unit Bool and F32 shapes" {
    try resourceArtifact(std.testing.allocator, false, .unit);
    try resourceArtifact(std.testing.allocator, false, .boolean);
    try resourceArtifact(std.testing.allocator, false, .float);
}

test "resource reference payloads own fresh primitive collections without binding promotion" {
    try law("const run = fn () => @resource.scope (fn () => #[1, 2]) (fn owner => ()) (fn loan => @usage.length loan)\n", null);
    try law("const run = fn () => @resource.scope (fn () => [1.5, 2.5]) (fn owner => ()) (fn loan => @usage.length loan)\n", null);
    try law("const run = fn () => @resource.scope (fn () -> unique (Array U32) => #[]) (fn owner => ()) (fn loan => @usage.length loan)\n", null);
    try law("const inspect = fn (owner: unique (Array U32)) => @usage.borrow owner (fn loan => @usage.length loan)\nconst run = fn () => inspect #[1, 2]\n", null);
    try law("const run = fn (existing: Array U32) => @resource.scope (fn () => existing) (fn owner => ()) (fn loan => @usage.length loan)\n", .type_mismatch);
    try law("const run = fn (existing: shared (Array U32)) => @resource.scope (fn () => existing) (fn owner => ()) (fn loan => @usage.length loan)\n", .type_mismatch);
    try law("const run = fn () => @resource.scope (fn () => #[1, 2]) (fn owner => ()) (fn loan => loan)\n", .borrow_escape);
    try portableControl("const run = fn () => @resource.scope (fn () => #[(1, 2)]) (fn owner => ()) (fn loan => ())\n", .none);
}

test "resource reference immutable scopes reject callable payload forgery and release failed publication" {
    try resourceArtifact(std.testing.allocator, true, .array);
    try resourceArtifact(std.testing.allocator, true, .list);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, resourceArtifact, .{ false, .array });
}

test "usage sharing consumes unique owners and permits repeated immutable scalar collection views" {
    try law("const read = fn () => do:\n  let owner: unique (Array U32) = #[1, 2]\n  let convert: once (Unit -> shared (Array U32)) = fn () => @usage.share owner\n  let shared = convert ()\n  return @usage.length shared\n", null);
    try law("const bad = fn (value: Array U32) => do:\n  let owner: unique (Array U32) = value\n  return @usage.share owner\n", .type_mismatch);
    try law("const read: unique U32 -> shared U32 = fn owner => @usage.share owner\nconst size: shared (Array U32) -> U32 = fn values => @usage.length values\n", null);
    try law("const read = fn (owner: unique U32) => do:\n  let shared = @usage.share owner\n  return @u32.add (@usage.read shared) (@usage.read shared)\n", null);
    try law("const read = fn (owner: unique (Array U32)) => do:\n  let shared = @usage.share owner\n  return (@usage.length shared, @usage.length shared)\n", null);
    try law("const read = fn (owner: unique (List F32)) => do:\n  let shared = @usage.share owner\n  return (@usage.length shared, @usage.length shared)\n", null);
    try law("const reused = fn (owner: unique U32) => (@usage.share owner, owner)\n", .use_after_move);
    try law("const reused = fn (owner: unique U32) => (@usage.share owner, @usage.share owner)\n", .use_after_move);
    try law("const bad = fn (owner: shared U32) => @usage.share owner\n", .usage_evidence_mismatch);
    try law("const bad = fn (owner: U32) => @usage.share owner\n", .usage_evidence_mismatch);
    try law("const bad = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.share loan)\n", .usage_evidence_mismatch);
    try law("const bad = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.share owner)\n", .borrow_conflict);
}

fn sharingArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "const read = fn (owner: unique (Array U32)) => do:\n  let shared = @usage.share owner\n  return (shared, shared)\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(a, &module, .{});
    if (!corrupt) return;
    var sharing: u32 = 0;
    var result: u32 = 0;
    for (module.nodes, 0..) |node, index| {
        if (node.tag == .usage_share) sharing = @intCast(index);
        if (node.tag == .product) result = @intCast(index);
    }
    try std.testing.expect(sharing != 0 and result != 0);
    const original = module.nodes[sharing];
    module.nodes[sharing].ty = module.typeOf(original.a);
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
    module.nodes[sharing] = original;
    module.nodes[sharing].c = 1;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
    module.nodes[sharing] = original;
    // Same independently valid shared result type, but a second conversion
    // reaches the already consumed owner through a different executable edge.
    const second = module.children(result)[1];
    const saved = module.nodes[second];
    module.nodes[second] = original;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
    module.nodes[second] = saved;
    try validation.validate(a, &module, .{});
}

test "usage sharing reconstructs portable consumption and rejects owning result forgeries" {
    try sharingArtifact(std.testing.allocator, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharingArtifact, .{false});
}

test "usage qualified returned callbacks preserve lambda and declaration header capture boundaries" {
    const a = std.testing.allocator;
    const source =
        \\const local = fn (owner: unique U32) -> once (Unit -> unique U32) => fn () => owner
        \\const declared: unique U32 -> once (Unit -> unique U32) = fn owner => fn () => owner
        \\const flat: U32 -> Unit -> U32 = fn owner => fn () => owner
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    var tested: usize = 0;
    for (module.bodies) |body| {
        if (body.root == 0) continue;
        const summary = module.binding(body.binding).capability_parameters;
        if (module.node(body.root).tag == .closure) {
            try std.testing.expectEqual(@as(u32, 1), body.parameters.len);
            try std.testing.expectEqual(@import("capability_flow.zig").ParameterResult.product, summary.kind);
        } else {
            try std.testing.expectEqual(@as(u32, 2), body.parameters.len);
            try std.testing.expectEqual(@import("capability_flow.zig").ParameterResult.captured_unit, summary.kind);
        }
        try std.testing.expectEqual(@as(u16, 1), summary.result());
        tested += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), tested);
}

test "resource transferred owners preserve explicit contracts and reject captured loan cleanup authority" {
    try law("const make = fn () -> unique U32 ! {Foreign} => @resource.acquire (fn () => 9) (fn owner => ())\nconst forward = fn (owner: unique U32) => owner\nconst drop = fn (owner: unique U32) => @resource.release owner\n", null);
    try law("const bad = fn (owner: unique U32) => @usage.borrow owner (fn loan => @resource.acquire (fn () => 9) (fn resource => do:\n  let read = @usage.read loan\n  return ()))\n", .cleanup_not_safe);
    try law("const bad = fn (owner: shared U32) => @resource.release owner\n", .cleanup_not_safe);
    try law("const bad = fn () => @resource.acquire (fn () => 9) (fn owner => @resource.release owner)\n", .cleanup_not_safe);
}

test "resource transferred owners cannot enter persistent module startup storage" {
    try law("const owner = @resource.acquire (fn () => 9) (fn owner => ())\n", .const_effect);
    try law("let owner = @resource.acquire (fn () => 9) (fn owner => ())\nentry const read = fn () => @usage.borrow owner (fn loan => @usage.read loan)\n", .initializer_effect);
    try law("let owner = do:\n  use resource <- @resource.acquire (fn () => 9) (fn owner => ())\n  return @usage.share resource\nentry const read = fn () => @usage.read owner\n", .initializer_effect);
    try law("let stored = do:\n  use resource <- @resource.acquire (fn () => 9) (fn owner => ())\n  let owner = @usage.share resource\n  return fn () => @usage.read owner\nentry const read = fn () => stored ()\n", .initializer_effect);
}

fn transferredArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "const make = fn () => @resource.acquire (fn () => #[1, 2]) (fn owner => ())\nconst drop = fn (owner: unique (Array U32)) => @resource.release owner\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.checkModule(a, &tree, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    if (!corrupt) return;
    var observed: usize = 0;
    for (module.nodes) |node| if (node.tag == .resource_acquire or node.tag == .resource_release) {
        const binding = for (module.bodies) |body| {
            if (body.root != 0 and module.node(body.root).tag == node.tag) break body.binding;
        } else return error.TestUnexpectedResult;
        const header = module.bindings[binding].ty;
        const saved = module.types.nodes[header];
        try std.testing.expectEqual(T.Tag.function, saved.tag);
        module.types.nodes[header].c = 0;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.types.nodes[header] = saved;
        observed += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), observed);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
}

test "resource transfer publication reconstructs owned effects and releases every allocation failure" {
    try transferredArtifact(std.testing.allocator, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, transferredArtifact, .{false});
}

test "resource cleanup exact range recipes check nested work and reject unknown bounds" {
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => do:\n  for index in 0..3:\n    for inner in 0..4:\n      let value = @u32.add index inner\n  return ()) (fn loan => @usage.read loan)\n", null);
    try law("const run = fn () => @resource.acquire (fn () => 9) (fn owner => do:\n  for index in 4..2:\n    let value = index\n  return ())\n", null);
    try law("const run = fn (bound: U32) => @resource.scope (fn () => 9) (fn owner => do:\n  for index in 0..bound:\n    let value = index\n  return ()) (fn loan => ())\n", .cleanup_not_safe);
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => do:\n  for index in 0..1000:\n    for inner in 0..1000:\n      let value = index\n  return ()) (fn loan => ())\n", .cleanup_not_safe);
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => do:\n  for index in 0..0:\n    let value = (fn () => ()) ()\n  return ()) (fn loan => ())\n", .cleanup_not_safe);
    try law("const run = fn () => @resource.scope (fn () => 9) (fn owner => do:\n  for ever:\n    let value = 9\n  return ()) (fn loan => ())\n", .cleanup_not_safe);
}

fn finiteCleanupArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "const run = fn () => @resource.scope (fn () => 9) (fn owner => do:\n  for index in 0..3:\n    for inner in 1..4:\n      let value = @u32.add index inner\n  return ()) (fn loan => @usage.read loan)\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(a, &module, .{});
    if (!corrupt) return;
    try std.testing.expectEqual(@as(usize, 2), module.loops.len);
    const saved = module.loops[0];
    module.loops[0].kind = .forever;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.loops[0] = saved;
    const end = module.nodes[saved.end];
    module.nodes[saved.end].a = 1_000_000;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
    module.nodes[saved.end] = end;
    module.nodes[saved.end].ty = T.f32_type;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.nodes[saved.end] = end;
    module.loops[0].end = 0;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.loops[0] = saved;
    module.loops[0].body = 0;
    module.nodes[saved.end].a = 1_000_000;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.nodes[saved.end] = end;
    module.loops[0].body = @intCast(module.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.loops[0] = saved;
    for ([_]T.Id{ saved.first, saved.end }) |bound| {
        const original = module.nodes[bound];
        module.nodes[bound].b = 1;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.nodes[bound] = original;
        module.nodes[bound].c = 1;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.nodes[bound] = original;
        module.nodes[bound].op = .add;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.nodes[bound] = original;
    }
    module.loops[0].body = for (module.nodes, 0..) |node, id| {
        if (node.tag == .loop and node.a == 0) break @intCast(id);
    } else return error.TestUnexpectedResult;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.loops[0] = saved;
    try validation.validate(a, &module, .{});
}
test "resource cleanup immutable range receipts reconstruct bounds and reject forged recursive work" {
    try finiteCleanupArtifact(std.testing.allocator, true);
}
test "resource cleanup finite range publication releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, finiteCleanupArtifact, .{false});
}

test "resource request cancellation admits invocation owners without closing unrelated effects" {
    const source =
        \\type Ask is effect = {ask: Unit -> U32}
        \\entry const run = fn () => do:
        \\  let computation = @computation (fn () => do:
        \\    use owner <- @resource.acquire (fn () => 9) (fn resource => ())
        \\    use value <- Ask.ask ()
        \\    return @usage.borrow owner (fn loan => @u32.add value (@usage.read loan))
        \\  )
        \\  for request in @requests computation:
        \\    case request of
        \\      effect Ask.ask () =>
        \\        return 42
        \\      complete value =>
        \\        return value
    ;
    try law(source, null);
    try portableControl(source, .none);
}

fn resourceRequestArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source =
        \\type Ask is effect = {ask: Unit -> U32}
        \\const keep = fn ~value => fn () => @force value
        \\entry const run = fn () => do:
        \\  let delayed = keep (do:
        \\    use owner <- @resource.acquire (fn () => 9) (fn resource => ())
        \\    use value <- Ask.ask ()
        \\    return @usage.borrow owner (fn loan => @u32.add value (@usage.read loan))
        \\  )
        \\  let computation = @computation (fn () => delayed ())
        \\  use first <- do:
        \\    for request in @requests computation:
        \\      case request of
        \\        effect Ask.ask () =>
        \\          return 40
        \\        complete value =>
        \\          return value
        \\  use second <- do:
        \\    for request in @requests computation:
        \\      case request of
        \\        effect Ask.ask () =>
        \\          yield 33
        \\        complete value =>
        \\          return value
        \\  return @u32.add first second
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(a, &module, .{});
    if (!corrupt) return;
    var found = false;
    for (module.nodes) |*node| {
        if (node.tag == .operation_value) {
            const original = node.*;
            node.a = @intCast(module.operation_values.len);
            try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
            node.* = original;
        }
        if (node.tag == .suspend_) {
            found = true;
            const original_type = node.ty;
            node.ty = @intCast(module.types.nodes.len);
            try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
            node.ty = original_type;
            const original_function = module.closures[node.a].function_type;
            module.closures[node.a].function_type = @intCast(module.types.nodes.len);
            try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
            module.closures[node.a].function_type = original_function;
            const index = module.closures[node.a].function_type;
            const header = module.types.nodes[index];
            module.types.nodes[index].a = T.u32_type;
            try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
            module.types.nodes[index] = header;
            module.types.nodes[index].c = 0;
            try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
            module.types.nodes[index] = header;
        }
    }
    try std.testing.expect(found);
    try std.testing.expect(module.request_loops.len != 0);
    const loop = module.request_loops[0];
    module.request_loops[0].completion_body = 0;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.request_loops[0] = loop;
    module.request_loops[0].arms.len = @intCast(module.request_arms.len + 1);
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.request_loops[0] = loop;
    try validation.validate(a, &module, .{});
}
test "resource request cancellation rebuilds suspension and protocol contracts independently" {
    try resourceRequestArtifact(std.testing.allocator, true);
}
test "resource request cancellation publication releases every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, resourceRequestArtifact, .{false});
}

test "resource retry demands reject consuming captured owners while creating fresh owners" {
    try law("const keep = fn ~value => fn () => @force value\nconst bad = fn (owner: unique U32) => keep owner\n", .duplicate_owner);
    try law("const keep = fn ~value => fn () => @force value\nconst bad = fn (owner: unique U32) => keep (@usage.share owner)\n", .duplicate_owner);
}

test "usage nominal payload affinity follows closed owning fields and nested families" {
    try law("type Box is data = #Box (unique U32)\nconst move = fn (owner: Box) => owner\n", null);
    try law("type Box is data = #Box (unique U32)\nconst duplicate = fn (owner: Box) => (owner, owner)\n", .use_after_move);
    try law("type Box is data = #Box (unique U32)\ntype Outer is data = #Outer Box\nconst duplicate = fn (owner: Outer) => (owner, owner)\n", .use_after_move);
    try law("type Box is data = #Box (unique U32)\nconst bad = fn (owner: shared Box) => owner\n", .usage_evidence_mismatch);
    try law("opaque type Box = unique U32\nconst move = fn (owner: Box) => owner\n", null);
}

test "usage nominal Core independently reconstructs hidden affinity before allowing moves" {
    try portableControl("type Box is data = #Box (unique U32)\nconst move = fn (owner: Box) => owner\n", .none);
    try portableControl("opaque type Box = unique U32\nconst move = fn (owner: Box) => owner\n", .none);
}

fn nominalOwnershipArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "type Box is data = #Box (unique U32)\nopaque type Secret = unique U32\nconst move = fn (owner: Box) => owner\nconst secret = fn (owner: Secret) => owner\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validation = @import("frozen_core_validation.zig");
    try validation.validate(a, &module, .{});
    if (!corrupt) return;
    var found: usize = 0;
    for (module.nominals) |*nominal| if (nominal.affine) {
        found += 1;
        nominal.affine = false;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
        nominal.affine = true;
    };
    try std.testing.expectEqual(@as(usize, 2), found);
    const payload = module.constructors[0].payload;
    module.constructors[0].payload = @intCast(module.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.constructors[0].payload = payload;
    const prior = module.types.nodes[payload];
    for ([_]T.Node{
        .{ .tag = .product, .a = @intCast(module.types.extra.len), .b = 2 },
        .{ .tag = .record, .b = std.math.maxInt(u32) },
        .{ .tag = .nominal, .c = @intCast(module.types.extra.len) },
        .{ .tag = .usage, .a = @intCast(module.types.nodes.len), .b = @backingInt(T.UsageKind.unique) },
    }) |mutant| {
        module.types.nodes[payload] = mutant;
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    }
    module.types.nodes[payload] = prior;
    module.has_usage_contracts = false;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
    module.has_usage_contracts = true;
    try validation.validate(a, &module, .{});
}
test "usage nominal owned graphs reject erased hidden affinity and release every failed publication" {
    try nominalOwnershipArtifact(std.testing.allocator, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, nominalOwnershipArtifact, .{false});
}

test "resource host cleanup accepts exact synchronous descriptor roles and excludes ordinary callbacks" {
    try portableControl("const run = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.scope (fn () => 9) (fn owner => do:\n  for index in 0..3:\n    let value = index\n  return drop owner) (fn loan => @usage.read loan)\n", .none);
    try portableControl("const run = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.scope (fn () => 9) drop (fn loan => @usage.read loan)\n", .none);
    try portableControl("const run = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => do:\n  use owner <- @resource.acquire (fn () => 9) drop\n  return @usage.borrow owner (fn loan => @usage.read loan)\n", .none);
    try law("const run = fn (drop: (unique U32) -> Unit ! {Foreign}) => @resource.scope (fn () => 9) drop (fn loan => @usage.read loan)\n", .cleanup_not_safe);
    try law("const run = fn (drop: cleanup ((unique U32) -> Unit)) => @resource.scope (fn () => 9) drop (fn loan => ())\n", .cleanup_not_safe);
}

test "usage nominal DAG scans consume one shared work budget" {
    var store = try T.Store.init(std.testing.allocator);
    defer store.deinit();
    const leaf = try store.product(&.{ T.u32_type, T.u32_type });
    const dag = try store.product(&.{ leaf, leaf });
    var work: @import("usage_check.zig").Work = .{ .remaining = 32 };
    const nominals: []const @import("core.zig").Nominal = &.{};
    try std.testing.expect(!try @import("usage_check.zig").affineNominalWork(&store, nominals, dag, &work));
    const remaining = work.remaining;
    try std.testing.expect(remaining < 32);
    var exhausted = false;
    for (0..33) |_| {
        const before = work.remaining;
        const found = @import("usage_check.zig").affineNominalWork(&store, nominals, dag, &work) catch |err| {
            try std.testing.expectEqual(error.TypeLimit, err);
            exhausted = true;
            break;
        };
        try std.testing.expect(!found);
        try std.testing.expect(work.remaining < before);
    }
    try std.testing.expect(exhausted);
    try std.testing.expect(work.remaining < remaining);
}

fn hostCleanupArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "const run = fn (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => @resource.scope (fn () => 9) drop (fn loan => @usage.read loan)\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validation = @import("frozen_core_validation.zig");
    const usage = @import("usage_core.zig");
    try validation.validate(a, &module, .{});
    if (!corrupt) return;
    const release = for (module.nodes) |node| {
        if (node.tag == .resource_scope) break node.b;
    } else return error.TestUnexpectedResult;
    const reference = module.nodes[release];
    const target = module.references[reference.a];
    module.references[reference.a].binding = 0;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.references[reference.a] = target;
    const binding = module.bindings[target.binding];
    module.bindings[target.binding].kind = .local;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.bindings[target.binding] = binding;
    const wrapper = module.types.nodes[reference.ty];
    module.types.nodes[reference.ty].a = @intCast(module.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.nodes[reference.ty] = wrapper;
    const arrow = module.types.nodes[wrapper.a];
    module.types.nodes[wrapper.a].c = @intCast(module.types.effects.rows.len);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.nodes[wrapper.a] = arrow;
    module.types.nodes[wrapper.a].c = 0;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.nodes[wrapper.a] = arrow;
    module.nodes[release].ty = wrapper.a;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.nodes[release] = reference;
    try validation.validate(a, &module, .{});
}
test "resource host cleanup immutable role rejects metadata promotion before indexed reads" {
    try hostCleanupArtifact(std.testing.allocator, true);
}
test "resource host cleanup publication releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, hostCleanupArtifact, .{false});
}

test "resource standalone explicit pure cleanup literals require finite source receipts" {
    try portableControl("const drop: cleanup ((unique U32) -> Unit) = fn owner => do:\n  for index in 0..3:\n    let value = index\n  return ()\n", .none);
    try portableControl("const run = fn () => do:\n  let drop: cleanup ((unique U32) -> Unit) = fn owner => ()\n  return ()\n", .none);
    try law("const drop: cleanup ((unique U32) -> Unit) = fn owner => drop owner\n", .type_mismatch);
    try law("const helper = fn () => ()\nconst drop: cleanup ((unique U32) -> Unit) = fn owner => helper ()\n", .cleanup_not_safe);
    try law("const drop: cleanup ((unique U32) -> Unit) = fn owner => do:\n  for ever:\n    let value = 9\n  return ()\n", .cleanup_not_safe);
}

fn pureCleanupArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "const drop: cleanup ((unique U32) -> Unit) = fn owner => do:\n  for index in 0..3:\n    let value = index\n  return ()\nconst run = fn () => do:\n  let adapter: cleanup ((unique U32) -> Unit) = fn owner => ()\n  return ()\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validator = @import("frozen_core_validation.zig");
    const usage = @import("usage_core.zig");
    try validator.validate(a, &module, .{});
    if (!corrupt) return;
    const body_id = for (module.bodies, 0..) |body, index| {
        if (body.binding != 0 and @import("cleanup_contracts.zig").pureType(&module.types, module.bindings[body.binding].ty)) break index;
    } else return error.TestUnexpectedResult;
    const body = module.bodies[body_id];
    module.bodies[body_id].parameters.len = 0;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.bodies[body_id] = body;
    module.bodies[body_id].root = 0;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.bodies[body_id] = body;
    const parameter = module.parameters[body.parameters.start];
    module.parameters[body.parameters.start].ty = @intCast(module.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.parameters[body.parameters.start] = parameter;
    module.bodies[body_id].scheme.root = @intCast(module.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.bodies[body_id] = body;
    const binding_scheme = module.bindings[body.binding].scheme;
    module.bindings[body.binding].scheme.root = @intCast(module.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.bindings[body.binding].scheme = binding_scheme;
    module.bindings[body.binding].body_id = 0;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.bindings[body.binding].body_id = @intCast(body_id);
    const loop_node = for (module.nodes, 0..) |node, index| {
        if (node.tag == .loop) break index;
    } else return error.TestUnexpectedResult;
    const loop = module.loops[module.nodes[loop_node].a];
    module.loops[module.nodes[loop_node].a].kind = .forever;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.loops[module.nodes[loop_node].a] = loop;
    try validator.validate(a, &module, .{});
}
test "resource standalone pure cleanup immutable receipts reject erasure and release every publication failure" {
    try pureCleanupArtifact(std.testing.allocator, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, pureCleanupArtifact, .{false});
}

fn phantomAffinePackage(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "type Box is data = #Box (unique U32)\nconst package = pack [U32] () as exists [a] => Unit\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validator = @import("frozen_core_validation.zig");
    const usage = @import("usage_core.zig");
    try validator.validate(a, &module, .{});
    if (!corrupt) return;
    const box: T.Id = found: {
        for (module.types.nodes, 0..) |node, id| {
            if (node.tag != .nominal) continue;
            for (module.nominals) |nominal| if (nominal.affine and nominal.identity.unit == node.a and nominal.identity.decl == node.b) break :found @intCast(id);
        }
        return error.TestUnexpectedResult;
    };
    const pack = for (module.nodes) |node| {
        if (node.tag == .package_pack) break node;
    } else return error.TestUnexpectedResult;
    const prior = module.types.extra[pack.b];
    module.types.extra[pack.b] = box;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.extra[pack.b] = @intCast(module.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.extra[pack.b] = prior;
    try validator.validate(a, &module, .{});
}
test "usage nominal phantom package witnesses cannot erase affinity before payload traversal" {
    try phantomAffinePackage(std.testing.allocator, true);
}
test "usage nominal affinity cannot be lifted across a stage through an opaque payload" {
    try law("type Box is data = #Box (unique U32)\nconst make = fn (value: Box) => @code.quote (@code.lift value)\n", .cross_stage_authority);
    try law("opaque type Box = unique U32\nconst make = fn (value: Box) => @code.quote (@code.lift value)\n", .cross_stage_authority);
}

test "resource closed aggregate payloads preserve fresh ownership and reject hidden authority" {
    try portableControl("const run = fn (value: U32) => @resource.scope (fn () => {left: value, right: #[value]}) (fn owner => @panic \"failure\") (fn loan => 42)\n", .none);
    try portableControl("const run = fn () => @resource.scope (fn () => (7, #[1, 2])) (fn owner => ()) (fn loan => 42)\n", .none);
    try portableControl("const run = fn () => @resource.scope (fn () => {left: 7, right: #[1, 2]}) (fn owner => ()) (fn loan => 42)\n", .none);
    try portableControl("const run = fn () => @resource.scope (fn () => #[#[1, 2], #[3]]) (fn owner => ()) (fn loan => @usage.length loan)\n", .none);
    try law("const run = fn () => @resource.scope (fn () => (7, fn () => 8)) (fn owner => ()) (fn loan => ())\n", .cleanup_not_safe);
    try law("const run = fn (value: (U32, Array U32)) => @resource.scope (fn () => value) (fn owner => ()) (fn loan => ())\n", .type_mismatch);
}

fn aggregateResourceArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "const run = fn () => @resource.scope (fn () => {left: 7, right: #[#[1, 2], #[3]]}) (fn owner => @panic \"failure\") (fn loan => 42)\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validator = @import("frozen_core_validation.zig");
    const usage = @import("usage_core.zig");
    try validator.validate(a, &module, .{});
    if (!corrupt) return;
    const record_id = for (module.types.nodes, 0..) |node, index| {
        if (node.tag == .record) break index;
    } else return error.TestUnexpectedResult;
    const record = module.types.nodes[record_id];
    module.types.nodes[record_id].a = @intCast(module.types.extra.len + 1);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.nodes[record_id] = record;
    module.types.nodes[record_id].b = @intCast(module.types.extra.len + 1);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.nodes[record_id] = record;
    module.types.nodes[record_id].c = 1;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.nodes[record_id] = record;
    const record_node = for (module.nodes, 0..) |node, index| {
        if (node.tag == .record) break index;
    } else return error.TestUnexpectedResult;
    const child_id = module.extra[module.nodes[record_node].a];
    const child_type = module.nodes[child_id].ty;
    module.nodes[child_id].ty = T.boolean;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.nodes[child_id].ty = child_type;
    const destination = module.extra[module.nodes[record_node].c + 1];
    module.extra[module.nodes[record_node].c + 1] = module.extra[module.nodes[record_node].c];
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.extra[module.nodes[record_node].c + 1] = destination;
    const field = module.types.extra[record.a + 1];
    module.types.extra[record.a + 1] = @intCast(module.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.extra[record.a + 1] = field;
    module.types.nodes[record_id].tag = .function;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.nodes[record_id] = record;
    try validator.validate(a, &module, .{});
}
test "resource closed aggregate immutable receipts reject malformed shapes and release every publication failure" {
    try aggregateResourceArtifact(std.testing.allocator, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, aggregateResourceArtifact, .{false});
}

test "resource closed aggregate shape walks charge repeated DAG edges to one budget" {
    var store = try T.Store.init(std.testing.allocator);
    defer store.deinit();
    var shape = T.u32_type;
    for (0..8) |_| shape = try store.product(&.{ shape, shape });
    try std.testing.expect(@import("cleanup_contracts.zig").payload(&store, shape));
    for (0..9) |_| shape = try store.product(&.{ shape, shape });
    try std.testing.expect(!@import("cleanup_contracts.zig").payload(&store, shape));
}

test "usage nominal repeatable owners still carry lifetime authority across lift and package boundaries" {
    try law("opaque type Box = shared U32\nconst make = fn (value: Box) => @code.quote (@code.lift value)\n", .cross_stage_authority);
    try law("type Box is data = #Box (shared U32)\ntype Outer is data = #Outer Box\nconst make = fn (value: Outer) => @code.quote (@code.lift value)\n", .cross_stage_authority);
    try law("opaque type Box = shared U32\nconst hide = fn (value: Box) => pack [Box] value as exists [a] => a\n", .usage_evidence_mismatch);
    try portableControl("opaque type Box = shared U32\nconst duplicate = fn (value: Box) => (value, value)\n", .none);
}

fn repeatableNominalArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "type Box is data = #Box (shared U32)\nopaque type Hidden = shared U32\nconst phantom = pack [U32] () as exists [a] => Unit\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const validator = @import("frozen_core_validation.zig");
    const usage = @import("usage_core.zig");
    try usage.validate(&module);
    try validator.validate(a, &module, .{});
    if (!corrupt) return;
    for (module.nominals) |*nominal| {
        if (!nominal.has_usage) continue;
        try std.testing.expect(!nominal.affine);
        nominal.has_usage = false;
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        nominal.has_usage = true;
    }
    module.has_usage_contracts = false;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.has_usage_contracts = true;
    const witness: T.Id = found: {
        for (module.types.nodes, 0..) |node, index| {
            if (node.tag != .nominal) continue;
            for (module.nominals) |nominal| if (nominal.has_usage and nominal.identity.unit == node.a and nominal.identity.decl == node.b) break :found @intCast(index);
        }
        return error.TestUnexpectedResult;
    };
    const pack = for (module.nodes) |node| {
        if (node.tag == .package_pack) break node;
    } else return error.TestUnexpectedResult;
    const old = module.types.extra[pack.b];
    module.types.extra[pack.b] = witness;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.types.extra[pack.b] = old;
    try validator.validate(a, &module, .{});
}
test "usage nominal repeatable lifetime metadata independently rejects erasure and releases failed publication" {
    try repeatableNominalArtifact(std.testing.allocator, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, repeatableNominalArtifact, .{false});
}

test "resource nominal closed storage owns fresh constructor payloads without hidden authority" {
    try portableControl("type Box[a] is data = #Box a\nconst run = fn () => @resource.scope (fn () => #Box 7) (fn owner => ()) (fn loan => 42)\n", .none);
    try portableControl("opaque type Box = {left: U32, right: Array U32}\nconst run = fn () => @resource.scope (fn () => #Box {left: 7, right: #[1, 2]}) (fn owner => ()) (fn loan => 42)\n", .none);
    try law("opaque type Box = Unit -> U32\nconst run = fn () => @resource.scope (fn () => #Box (fn () => 7)) (fn owner => ()) (fn loan => ())\n", .cleanup_not_safe);
    try portableControl("type Tree a is data = #Leaf a | #Branch (Tree a, Tree a)\nconst run = fn () => @resource.scope (fn () => #Branch (#Leaf 7, #Leaf 9)) (fn owner => ()) (fn loan => 42)\n", .none);
    try portableControl("const run = fn () => do:\n  let owner: unique {left: U32, right: Array U32} = {right: #[1, 2], left: 7}\n  return @usage.borrow owner (fn loan => 42)\n", .none);
}

fn closedNominalArtifact(a: std.mem.Allocator, corrupt: bool) !void {
    const source = "type Box[a] is data = #Box a\nopaque type Secret = {left: U32, right: Array U32}\nconst run = fn () => @resource.scope (fn () => #Box 7) (fn owner => ()) (fn loan => 42)\nconst secret = fn () => @resource.scope (fn () => #Secret {right: #[1, 2], left: 7}) (fn owner => ()) (fn loan => 42)\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    const usage = @import("usage_core.zig");
    const validator = @import("frozen_core_validation.zig");
    try usage.validate(&module);
    try validator.validate(a, &module, .{});
    if (!corrupt) return;
    module.nominals[0].closed_storage = true;
    try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
    module.nominals[0].closed_storage = false;
    var tiny: @import("usage_check.zig").Work = .{ .remaining = 1 };
    var scratch: [3]@import("core.zig").Nominal = undefined;
    try std.testing.expectEqual(scratch.len, module.nominals.len);
    @memcpy(&scratch, module.nominals);
    try std.testing.expectError(error.TypeLimit, @import("closed_nominal_storage.zig").facts(&module.types, &scratch, module.constructors, module.unit, &tiny));
    try std.testing.expectEqual(@as(usize, 0), tiny.remaining);
    for (module.nominals, 0..) |*nominal, ni| {
        if (ni == 0) continue;
        try std.testing.expect(nominal.closed_storage);
        nominal.has_usage = true;
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        nominal.has_usage = false;
        const variables = nominal.variables;
        nominal.variables.start = @intCast(module.types.extra.len);
        nominal.variables.len = 1;
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        nominal.variables = variables;
        if (nominal.is_opaque) {
            const role = nominal.storage;
            try std.testing.expectEqual(.reference, role.kind);
            nominal.storage = .{ .kind = .f32 };
            try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
            try std.testing.expectError(error.InvalidArtifact, validator.validate(a, &module, .{}));
            nominal.storage = role;
        }
    }
    for (module.nodes) |*node| {
        if (node.tag != .construct) continue;
        const prior = node.*;
        node.a = 0;
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        node.* = prior;
        node.a = @intCast(module.constructors.len);
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        node.* = prior;
        node.b = @intCast(module.nodes.len);
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        node.* = prior;
        node.c = 2;
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        node.* = prior;
        if (!module.nominals[module.constructors[node.a].nominal].is_opaque) {
            const child = &module.nodes[node.b];
            const ty = child.ty;
            child.ty = T.f32_type;
            try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
            child.ty = ty;
        } else {
            node.c = 1;
            try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
            node.* = prior;
        }
    }
    for (module.constructors) |*constructor| {
        if (constructor.payload == 0) continue;
        const payload = constructor.payload;
        constructor.payload = @intCast(module.types.nodes.len);
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        constructor.payload = payload;
        const prior = module.types.nodes[payload];
        module.types.nodes[payload] = .{ .tag = .function, .a = T.unit, .b = T.u32_type };
        try std.testing.expectError(error.InvalidArtifact, usage.validate(&module));
        module.types.nodes[payload] = prior;
    }
    try validator.validate(a, &module, .{});
}
test "resource nominal closed storage independently rejects forged roles and constructor publication" {
    try closedNominalArtifact(std.testing.allocator, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, closedNominalArtifact, .{false});
}

fn usageQueryMemoScenario(a: std.mem.Allocator) !void {
    const usage = @import("usage_check.zig");
    var store = try T.Store.init(a);
    defer store.deinit();
    var memo: usage.Memo = .{ .allocator = a };
    defer memo.deinit();
    var nominals = [_]struct { identity: T.NominalIdentity, has_usage: bool, affine: bool }{.{ .identity = .{ .unit = 7, .decl = 9 }, .has_usage = false, .affine = false }};
    var root: T.Id = T.u32_type;
    for (0..64) |_| root = try store.product(&.{ root, root });
    var work: usage.Work = .{};
    const initial = work.remaining;
    try std.testing.expect(!try usage.containsNominalMemoWork(&store, nominals[0..], root, &work, &memo));
    const after = work.remaining;
    try std.testing.expect(initial - after < 4096);
    try std.testing.expect(!try usage.containsNominalMemoWork(&store, nominals[0..], root, &work, &memo));
    try std.testing.expect(work.remaining < after);
    try std.testing.expect(after - work.remaining < initial - after);
    const variable = try store.fresh();
    const holder = try store.product(&.{ variable, variable });
    try std.testing.expect(!try usage.containsNominalMemoWork(&store, nominals[0..], holder, &work, &memo));
    const owner = try store.usage(T.u32_type, .unique, 0);
    try store.unify(variable, owner);
    try std.testing.expect(try usage.containsNominalMemoWork(&store, nominals[0..], holder, &work, &memo));
    const nominal = try store.nominal(nominals[0].identity, &.{});
    try std.testing.expect(!try usage.containsNominalMemoWork(&store, nominals[0..], nominal, &work, &memo));
    nominals[0].has_usage = true;
    try std.testing.expect(try usage.containsNominalMemoWork(&store, nominals[0..], nominal, &work, &memo));
    var exhausted: usage.Work = .{ .remaining = 0 };
    try std.testing.expectError(error.TypeLimit, usage.containsNominalMemoWork(&store, nominals[0..], root, &exhausted, &memo));
    const rewritten = try store.product(&.{ T.u32_type, T.u32_type });
    try std.testing.expect(!try usage.containsNominalMemoWork(&store, nominals[0..], rewritten, &work, &memo));
    const node = store.node(rewritten);
    store.replaceListItem(.{ .start = node.a, .len = node.b }, 0, owner);
    try std.testing.expect(try usage.containsNominalMemoWork(&store, nominals[0..], rewritten, &work, &memo));
}
test "usage query memo shares completed DAG work and rejects later binding catalog and storage owners through OOM" {
    try usageQueryMemoScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, usageQueryMemoScenario, .{});
}

test "usage distinct-node cap remains bounded while repeated wide edges retain exact shape checks" {
    const usage = @import("usage_check.zig");
    var store = try T.Store.init(std.testing.allocator);
    defer store.deinit();
    var ids: [4097]T.Id = undefined;
    @memset(&ids, T.u32_type);
    const repeated = try store.product(&ids);
    const nominals: []const @import("core.zig").Nominal = &.{};
    try std.testing.expect(!try usage.containsNominal(&store, nominals, repeated));
    for (&ids) |*id| id.* = try store.fresh();
    const distinct = try store.product(&ids);
    try std.testing.expectError(error.TypeLimit, usage.containsNominal(&store, nominals, distinct));
    const prior = store.nodes.items[repeated];
    store.nodes.items[repeated].a = std.math.maxInt(u32);
    defer store.nodes.items[repeated] = prior;
    try std.testing.expectError(error.TypeLimit, usage.containsNominal(&store, nominals, repeated));
}
