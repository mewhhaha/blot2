const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool = .{},
    fn init() !Fixture {
        return .{ .tree = try ast.Tree.init(a) };
    }
    fn deinit(self: *Fixture) void {
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn symbol(self: *Fixture, value: []const u8) !symbols.Symbol {
        return self.pool.intern(a, value);
    }
    fn add(self: *Fixture, node: ast.Node) !ast.Id {
        const id: ast.Id = @intCast(self.tree.nodes.items.len);
        try self.tree.nodes.append(a, node);
        try self.tree.spans.append(a, .{ .start = id * 2, .end = id * 2 + 1 });
        return id;
    }
    fn extra(self: *Fixture, values: []const u32) !u32 {
        const at: u32 = @intCast(self.tree.extra.items.len);
        try self.tree.extra.appendSlice(a, values);
        return at;
    }
    fn name(self: *Fixture, text: []const u8) !ast.Id {
        return self.add(.{ .tag = .name, .a = try self.symbol(text) });
    }
    fn integer(self: *Fixture, bits: u32) !ast.Id {
        return self.add(.{ .tag = .integer, .a = bits });
    }
    fn float(self: *Fixture, value: f32) !ast.Id {
        return self.add(.{ .tag = .float, .a = @bitCast(value) });
    }
    fn binary(self: *Fixture, operator: []const u8, left: ast.Id, right: ast.Id) !ast.Id {
        return self.add(.{ .tag = .binary, .a = try self.symbol(operator), .b = left, .c = right });
    }
    // Operator laws assemble an explicit ordinary source declaration, as a
    // parsed module would. No undeclared binary node receives default fixity.
    fn operatorDeclaration(self: *Fixture, comptime operator: []const u8, comptime member: []const u8, precedence: u32, association: u32) !void {
        const target_name = "_fixity_" ++ member;
        const primitive = try self.add(.{ .tag = .intrinsic, .a = try self.symbol("@type.call") });
        const field = try self.add(.{ .tag = .string, .a = try self.symbol(member) });
        const call = try self.apply(try self.apply(try self.apply(primitive, field), try self.name("left")), try self.name("right"));
        _ = try self.declaration(target_name, try self.lambda("left", try self.lambda("right", call, 0), 0));
        const fixity = try self.add(.{ .tag = .fixity_decl, .a = try self.symbol(operator), .b = try self.symbol(target_name), .c = try self.extra(&.{ precedence, association, 0, 0, 0 }) });
        try self.tree.roots.insert(a, 0, fixity);
    }
    fn scalarOperator(self: *Fixture, comptime operator: []const u8, comptime member: []const u8, precedence: u32, association: u32) !void {
        const target_name = "_scalar_" ++ member;
        const primitive = try self.add(.{ .tag = .intrinsic, .a = try self.symbol("@u32." ++ member) });
        const call = try self.apply(try self.apply(primitive, try self.name("left")), try self.name("right"));
        _ = try self.declaration(target_name, try self.lambda("left", try self.lambda("right", call, 0), 0));
        const fixity = try self.add(.{ .tag = .fixity_decl, .a = try self.symbol(operator), .b = try self.symbol(target_name), .c = try self.extra(&.{ precedence, association, 0, 0, 0 }) });
        try self.tree.roots.insert(a, 0, fixity);
    }
    fn returning(self: *Fixture, body: ast.Id, type_name: []const u8) !ast.Id {
        const function = try self.lambda("", body, 0);
        const result_type = try self.add(.{ .tag = .type_name, .a = try self.symbol(type_name) });
        self.tree.nodes.items[function].c = result_type;
        return function;
    }
    fn apply(self: *Fixture, callee: ast.Id, argument: ast.Id) !ast.Id {
        return self.add(.{ .tag = .apply, .a = callee, .b = argument });
    }
    fn lambda(self: *Fixture, parameter_name: []const u8, body: ast.Id, annotation: ast.Id) !ast.Id {
        const unit = parameter_name.len == 0;
        const parameter = try self.add(.{ .tag = .parameter, .a = if (unit) 0 else try self.symbol(parameter_name), .b = annotation, .c = try self.extra(&.{ if (unit) 2 else 0, 0, 0, 0 }) });
        return self.add(.{ .tag = .lambda, .a = parameter, .b = body });
    }
    fn declaration(self: *Fixture, declaration_name: []const u8, body: ast.Id) !ast.Id {
        const id = try self.add(.{ .tag = .value_decl, .a = try self.symbol(declaration_name), .b = body, .c = try self.extra(&.{ 0, 0, 0, 0, 0, 0, 0, 0, 0 }) });
        try self.tree.roots.append(a, id);
        return id;
    }
    fn block(self: *Fixture, statements: []const ast.Id) !ast.Id {
        return self.add(.{ .tag = .block, .a = try self.extra(statements), .b = @intCast(statements.len) });
    }
    fn bind(self: *Fixture, binding_name: []const u8, value: ast.Id) !ast.Id {
        const pattern = try self.add(.{ .tag = .pattern_name, .a = try self.symbol(binding_name) });
        return self.add(.{ .tag = .let_stmt, .a = pattern, .b = value, .c = try self.extra(&.{ 0, 0, 0, 0, 0 }) });
    }
    fn result(self: *Fixture, value: ast.Id) !ast.Id {
        return self.add(.{ .tag = .return_stmt, .a = value });
    }
};

test "one principal overloaded body has independent U32 and F32 uses" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.operatorDeclaration("+", "add", 60, 0);
    const sum = try fixture.binary("+", try fixture.name("x"), try fixture.name("x"));
    const declaration = try fixture.declaration("twice", try fixture.lambda("x", sum, 0));
    const integer_call = try fixture.apply(try fixture.name("twice"), try fixture.integer(3));
    _ = try fixture.declaration("integer_use", try fixture.returning(integer_call, "U32"));
    const float_call = try fixture.apply(try fixture.name("twice"), try fixture.float(1.5));
    _ = try fixture.declaration("float_use", try fixture.returning(float_call, "F32"));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const binding = checked.bindings[checked.resolved[declaration]];
    try std.testing.expectEqual(@as(u32, 2), binding.scheme.variables.len);
    try std.testing.expectEqual(@as(u32, 1), binding.scheme.obligations.len);
    try std.testing.expectEqual(types.u32_type, checked.expr_types[integer_call]);
    try std.testing.expectEqual(types.f32_type, checked.expr_types[float_call]);
    try std.testing.expectEqual(types.Tag.variable, checked.types.node(checked.types.node(binding.scheme.root).a).tag);
}
test "unused declarations fail and rejected constraints do not poison valid declarations" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const recursive_value = try fixture.apply(try fixture.name("x"), try fixture.name("x"));
    _ = try fixture.declaration("bad", try fixture.lambda("x", recursive_value, 0));
    const good = try fixture.declaration("good", try fixture.lambda("x", try fixture.name("x"), 0));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(check.Code.infinite_type, checked.diagnostics[0].code);
    const scheme = checked.bindings[checked.resolved[good]].scheme;
    try std.testing.expectEqual(@as(u32, 1), scheme.variables.len);
}
test "local let generalizes and rebinding retains old identities and self" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.scalarOperator("+", "add", 60, 0);
    const identity = try fixture.bind("identity", try fixture.lambda("value", try fixture.name("value"), 0));
    const integer_call = try fixture.apply(try fixture.name("identity"), try fixture.integer(4));
    const float_call = try fixture.apply(try fixture.name("identity"), try fixture.float(2));
    const old = try fixture.bind("value", integer_call);
    const self_reference = try fixture.name("self");
    const rebind = try fixture.add(.{ .tag = .rebind_stmt, .a = try fixture.name("value"), .b = try fixture.binary("+", self_reference, try fixture.integer(2)) });
    const body = try fixture.block(&.{ identity, old, rebind, float_call, try fixture.result(try fixture.name("value")) });
    _ = try fixture.declaration("test", try fixture.lambda("", body, 0));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(types.f32_type, checked.expr_types[float_call]);
    try std.testing.expectEqual(checked.resolved[old], checked.resolved[self_reference]);
    try std.testing.expect(checked.resolved[old] != checked.resolved[rebind]);
    try std.testing.expectEqual(types.u32_type, checked.expr_types[body]);
}
test "recursive function checks once and conditional return belongs to enclosing block" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.operatorDeclaration("*", "mul", 70, 0);
    try fixture.operatorDeclaration("-", "sub", 60, 0);
    try fixture.operatorDeclaration("<=", "le", 30, 2);
    const condition = try fixture.binary("<=", try fixture.name("n"), try fixture.integer(1));
    const branch = try fixture.block(&.{try fixture.result(try fixture.integer(1))});
    const conditional = try fixture.add(.{ .tag = .if_stmt, .a = condition, .b = branch });
    const recurse = try fixture.apply(try fixture.name("factorial"), try fixture.binary("-", try fixture.name("n"), try fixture.integer(1)));
    const body = try fixture.block(&.{ conditional, try fixture.result(try fixture.binary("*", try fixture.name("n"), recurse)) });
    const declaration = try fixture.declaration("factorial", try fixture.lambda("n", body, try fixture.add(.{ .tag = .type_name, .a = try fixture.symbol("U32") })));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const root = checked.types.node(checked.bindings[checked.resolved[declaration]].scheme.root);
    try std.testing.expectEqual(types.u32_type, root.a);
    try std.testing.expectEqual(types.u32_type, root.b);
}
test "branch rebindings merge only existing names and preserve lexical scope" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const before = try fixture.bind("value", try fixture.integer(1));
    const rebind = try fixture.add(.{ .tag = .rebind_stmt, .a = try fixture.name("value"), .b = try fixture.integer(2) });
    const private = try fixture.bind("branch_local", try fixture.integer(99));
    const conditional = try fixture.add(.{ .tag = .if_stmt, .a = try fixture.add(.{ .tag = .boolean, .a = 1 }), .b = try fixture.block(&.{ rebind, private }) });
    const reference = try fixture.name("value");
    _ = try fixture.declaration("test", try fixture.lambda("", try fixture.block(&.{ before, conditional, try fixture.result(reference) }), 0));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), checked.merges.len);
    try std.testing.expectEqual(checked.merges[0].result, checked.resolved[reference]);
    try std.testing.expectEqual(checked.resolved[before], checked.merges[0].else_binding);
    try std.testing.expectEqual(checked.resolved[rebind], checked.merges[0].then_binding);
}

test "custom and named fixity resolve their declared target rather than numeric defaults" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const target = try fixture.declaration("second", try fixture.lambda("left", try fixture.lambda("right", try fixture.name("right"), 0), 0));
    const fixity = try fixture.add(.{ .tag = .fixity_decl, .a = try fixture.symbol("+"), .b = try fixture.symbol("second"), .c = try fixture.extra(&.{ 60, 0, 0, 0, 0 }) });
    try fixture.tree.roots.insert(a, 0, fixity);
    const call = try fixture.binary("+", try fixture.integer(2), try fixture.add(.{ .tag = .boolean, .a = 1 }));
    _ = try fixture.declaration("answer", try fixture.lambda("", call, 0));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(types.boolean, checked.expr_types[call]);
    try std.testing.expectEqual(checked.resolved[target], checked.resolved[call]);
    try std.testing.expectEqual(@as(usize, 2), checked.body_elaborations);
}
test "explicit scalar operator producers reject Bool arithmetic and F32 remainder" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.scalarOperator("+", "add", 60, 0);
    try fixture.scalarOperator("%", "rem", 70, 0);
    const sum = try fixture.binary("+", try fixture.name("x"), try fixture.name("x"));
    _ = try fixture.declaration("twice", try fixture.lambda("x", sum, 0));
    _ = try fixture.declaration("bad", try fixture.lambda("", try fixture.apply(try fixture.name("twice"), try fixture.add(.{ .tag = .boolean, .a = 1 })), 0));
    _ = try fixture.declaration("bad_remainder", try fixture.lambda("", try fixture.binary("%", try fixture.float(2.5), try fixture.float(1)), 0));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), checked.diagnostics.len);
    for (checked.diagnostics) |diagnostic| try std.testing.expectEqual(check.Code.type_mismatch, diagnostic.code);
}

test "source admits only F32 prefix negation and authoritative primitive names" {
    var prefix_fixture = try Fixture.init();
    defer prefix_fixture.deinit();
    const unsupported_prefix = try prefix_fixture.add(.{ .tag = .unary, .a = try prefix_fixture.symbol("!"), .b = try prefix_fixture.add(.{ .tag = .boolean, .a = 1 }) });
    _ = try prefix_fixture.declaration("prefix", try prefix_fixture.lambda("", unsupported_prefix, 0));
    var prefix_checked = try check.check(a, &prefix_fixture.tree, &prefix_fixture.pool);
    defer prefix_checked.deinit(a);
    try std.testing.expectEqual(check.Code.unsupported_prefix, prefix_checked.diagnostics[0].code);
    var fake = try Fixture.init();
    defer fake.deinit();
    _ = try fake.declaration("fake_intrinsic", try fake.add(.{ .tag = .intrinsic, .a = try fake.symbol("@u32.ne") }));
    var fake_checked = try check.check(a, &fake.tree, &fake.pool);
    defer fake_checked.deinit(a);
    try std.testing.expectEqual(check.Code.unknown_intrinsic, fake_checked.diagnostics[0].code);
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const primitive = try fixture.add(.{ .tag = .intrinsic, .a = try fixture.symbol("@u32.rem") });
    const call = try fixture.apply(try fixture.apply(primitive, try fixture.integer(5)), try fixture.integer(2));
    _ = try fixture.declaration("remainder", try fixture.lambda("", call, 0));
    var checked = try check.check(a, &fixture.tree, &fixture.pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(types.u32_type, checked.expr_types[call]);
}

test "owned checker tables grow with declarations and uses without rechecking shared bodies" {
    const Memory = @import("memory.zig");
    for ([_]usize{ 16, 64, 256 }) |count| {
        for (0..3) |shape| {
            var fixture = try Fixture.init();
            defer fixture.deinit();
            if (shape == 1) {
                try fixture.operatorDeclaration("+", "add", 60, 0);
                _ = try fixture.declaration("twice", try fixture.lambda("x", try fixture.binary("+", try fixture.name("x"), try fixture.name("x")), 0));
                var calls: std.ArrayList(ast.Id) = .empty;
                defer calls.deinit(a);
                for (0..count) |_| try calls.append(a, try fixture.apply(try fixture.name("twice"), try fixture.integer(1)));
                try calls.append(a, try fixture.result(try fixture.integer(1)));
                _ = try fixture.declaration("driver", try fixture.lambda("", try fixture.block(calls.items), 0));
            } else {
                for (0..count) |i| {
                    var buffer: [40]u8 = undefined;
                    const name = try std.mem.print(&buffer, "function_{d}", .{i});
                    const symbol = try fixture.symbol(name);
                    var body = try fixture.name("value");
                    if (shape == 2) {
                        var next_buffer: [40]u8 = undefined;
                        const next = try std.mem.print(&next_buffer, "function_{d}", .{(i + 1) % count});
                        body = try fixture.apply(try fixture.name(next), body);
                    }
                    const declaration = try fixture.add(.{ .tag = .value_decl, .a = symbol, .b = try fixture.lambda("value", body, 0), .c = try fixture.extra(&.{ 0, 0, 0, 0, 0, 0, 0, 0, 0 }) });
                    try fixture.tree.roots.append(a, declaration);
                }
            }
            var memory: Memory.TrackedAllocator = .{ .backing = a };
            var checked = try check.check(memory.allocator(), &fixture.tree, &fixture.pool);
            var released = false;
            defer if (!released) checked.deinit(memory.allocator());
            const nodes = checked.types.nodes.items.len;
            const versions = checked.types.versions.items.len;
            try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
            try std.testing.expectEqual(if (shape == 1) @as(usize, 3) else count, checked.body_elaborations);
            try std.testing.expect(nodes < 40 * count + 100);
            try std.testing.expect(versions < 10 * count + 100);
            std.debug.print("SEMANTIC_SCALING shape={d} N={d} bodies={d} nodes={d} versions={d} peak_requested={d} live={d}\n", .{ shape, count, checked.body_elaborations, nodes, versions, memory.counts.peak_bytes, memory.counts.live_bytes });
            checked.deinit(memory.allocator());
            released = true;
            try std.testing.expectEqual(@as(usize, 0), memory.counts.live_bytes);
        }
    }
}

test "wide scalar let bindings avoid quadratic generalization allocations" {
    const Memory = @import("memory.zig");
    for ([_]usize{ 32, 128, 512, 1024 }) |count| {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        try fixture.scalarOperator("+", "add", 60, 0);
        _ = try fixture.declaration("twice", try fixture.lambda("x", try fixture.binary("+", try fixture.name("x"), try fixture.name("x")), 0));
        var statements: std.ArrayList(ast.Id) = .empty;
        defer statements.deinit(a);
        for (0..count) |i| {
            var buffer: [32]u8 = undefined;
            const name = try std.mem.print(&buffer, "value_{d}", .{i});
            const call = try fixture.apply(try fixture.name("twice"), try fixture.integer(2));
            try statements.append(a, try fixture.bind(name, call));
        }
        try statements.append(a, try fixture.result(try fixture.integer(0)));
        _ = try fixture.declaration("driver", try fixture.lambda("", try fixture.block(statements.items), 0));
        var memory: Memory.TrackedAllocator = .{ .backing = a };
        var checked = try check.check(memory.allocator(), &fixture.tree, &fixture.pool);
        defer checked.deinit(memory.allocator());
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        try std.testing.expectEqual(@as(usize, 3), checked.body_elaborations);
        try std.testing.expect(memory.counts.allocations < count * 32 + 100);
        try std.testing.expect(memory.counts.allocated_bytes < count * 3000 + 65536);
        std.debug.print("SCALAR_LET_SCALING N={d} allocations={d} cumulative={d} peak={d}\n", .{ count, memory.counts.allocations, memory.counts.allocated_bytes, memory.counts.peak_bytes });
    }
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    _ = try fixture.declaration("identity", try fixture.lambda("x", try fixture.name("x"), 0));
    var checked = try check.check(allocator, &fixture.tree, &fixture.pool);
    defer checked.deinit(allocator);
}
test "checker releases all owned tables on allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{});
}
