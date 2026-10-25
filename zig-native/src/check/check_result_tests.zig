const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const ast = @import("../parse/ast.zig");
const check = @import("check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const source =
    \\type Box value is data = #Box value
    \\const Box.from = fn value => #Box value
    \\const from = fn value => @type.result "from" value
    \\const alias = from
    \\entry const integer = fn () => do:
    \\  let #Box value:Box U32 = alias 42
    \\  break value
    \\entry const floating = fn () => do:
    \\  let #Box value:Box F32 = alias 1.25
    \\  break value
;
const Fixture = struct {
    pool: symbols.Pool = .{},
    tree: ast.Tree,
    checked: check.Checked,
    fn init(allocator: std.mem.Allocator, text: []const u8) !Fixture {
        var tokens = try lexer.lex(allocator, text);
        defer tokens.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(allocator);
        var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
        errdefer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const checked = try check.check(allocator, &tree, &pool);
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
test "result directed schemes retain input and expected output across aliases and nominal arguments" {
    var f = try Fixture.init(a, source);
    defer f.deinit(a);
    try f.valid();
    var signatures: usize = 0;
    for (f.checked.bindings[1..]) |binding| {
        if (binding.kind != .global) continue;
        const name = f.pool.get(binding.name);
        if (std.mem.eql(u8, name, "from") or std.mem.eql(u8, name, "alias")) {
            try std.testing.expectEqual(@as(u32, 2), binding.scheme.variables.len);
            try std.testing.expectEqual(@as(u32, 1), binding.scheme.obligations.len);
            const predicate = f.checked.obligations[binding.scheme.obligations.start];
            if (std.mem.eql(u8, name, "from")) {
                try std.testing.expectEqual(T.ObligationKind.result_dispatch, predicate.kind);
                try std.testing.expectEqualStrings("from", f.pool.get(predicate.name));
            } else {
                try std.testing.expectEqual(T.ObligationKind.callee_use, predicate.kind);
                const original = f.checked.bindings[predicate.identity.decl];
                try std.testing.expectEqualStrings("from", f.pool.get(original.name));
                const requirement = f.checked.obligations[original.scheme.obligations.start];
                try std.testing.expectEqual(T.ObligationKind.result_dispatch, requirement.kind);
                const product = f.checked.types.node(predicate.ty);
                const arguments = f.checked.types.list(.{ .start = product.a, .len = product.b });
                const arrow = f.checked.types.node(binding.scheme.root);
                try std.testing.expect(std.mem.findScalar(T.Id, arguments, arrow.a) != null);
                try std.testing.expect(std.mem.findScalar(T.Id, arguments, arrow.b) != null);
            }
        }
        if (std.mem.eql(u8, name, "integer") or std.mem.eql(u8, name, "floating")) {
            try std.testing.expectEqual(if (std.mem.eql(u8, name, "integer")) T.u32_type else T.f32_type, f.checked.types.node(binding.scheme.root).b);
            signatures += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), signatures);
}
test "result selection uses only the destination owner and retains missing unused requirements" {
    var f = try Fixture.init(a,
        \\type Source is data = #Source U32
        \\type Target is data = #Target U32
        \\type Missing is data = #Missing U32
        \\const Source.from = fn value => @panic "input owner was selected"
        \\const Target.from = fn (source:Source) => do:
        \\  let #Source value=source
        \\  break #Target value
        \\const unused = fn (value:U32) -> Missing => @type.result "from" value
        \\entry const answer = fn () => do:
        \\  let #Target value:Target = @type.result "from" (#Source 42)
        \\  break value
    );
    defer f.deinit(a);
    try f.valid();
    var selected = false;
    var latent = false;
    for (f.tree.nodes.items, 0..) |node, index| {
        if (node.tag != .apply or f.checked.resolved[index] == 0) continue;
        const target = f.checked.bindings[f.checked.resolved[index]];
        if (std.mem.eql(u8, f.pool.get(target.name), "Target.from")) selected = true;
    }
    for (f.checked.bindings[1..]) |binding| if (std.mem.eql(u8, f.pool.get(binding.name), "unused")) {
        try std.testing.expectEqual(@as(u32, 1), binding.scheme.obligations.len);
        latent = f.checked.obligations[binding.scheme.obligations.start].kind == .result_dispatch;
    };
    try std.testing.expect(selected and latent);
}
test "a selected result method cannot fall back after input or output mismatch" {
    const cases = [_][]const u8{
        "type Target is data = #Target U32\nconst Target.from = fn (value:F32) => #Target 42\nentry const answer:Target = @type.result \"from\" 1\n",
        "type Target is data = #Target U32\nconst Target.from = fn value => 42\nentry const answer:Target = @type.result \"from\" 1\n",
    };
    for (cases) |text| {
        var f = try Fixture.init(a, text);
        defer f.deinit(a);
        var found = false;
        for (f.checked.diagnostics) |d| found = found or d.code == .type_mismatch;
        try std.testing.expect(found);
    }
    const invalid = [_]struct { text: []const u8, code: check.Code }{
        .{ .text = "const partial=@type.result \"from\"\n", .code = .call_arity },
        .{ .text = "const name=42\nconst bad=@type.result name 42\n", .code = .literal_required },
    };
    for (invalid) |item| {
        var f = try Fixture.init(a, item.text);
        defer f.deinit(a);
        try std.testing.expectEqual(item.code, f.checked.diagnostics[0].code);
    }
}
fn failures(allocator: std.mem.Allocator) !void {
    var f = try Fixture.init(allocator, source);
    defer f.deinit(allocator);
    try f.valid();
}
test "result scheme selection and principal publication release every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, failures, .{});
}

fn writtenResults(allocator: std.mem.Allocator) !void {
    const text =
        \\type Box a is data = #Box a
        \\const Box.from = fn value => #Box value
        \\type Convert (a, b) is contract = { result "from" a b }
        \\const from: a -> b where { result "from" a b } = fn value => @type.result "from" value
        \\const alias: a -> b where { Convert (a, b) } = from
        \\entry const answer = fn () => do:
        \\  let local: a -> b where { result "from" a b ! {} } = alias
        \\  let #Box first: Box U32 = local 42
        \\  let #Box second: Box F32 = local 1.25
        \\  break (first, second)
    ;
    var f = try Fixture.init(allocator, text);
    defer f.deinit(allocator);
    try f.valid();
    var interfaces: usize = 0;
    for (f.checked.bindings[1..]) |binding| {
        const name = f.pool.get(binding.name);
        if (!std.mem.eql(u8, name, "from") and !std.mem.eql(u8, name, "alias") and !std.mem.eql(u8, name, "local")) continue;
        interfaces += 1;
        try std.testing.expectEqual(@as(u32, 2), binding.scheme.variables.len);
        try std.testing.expectEqual(@as(u32, 1), binding.scheme.obligations.len);
        const goal = f.checked.obligations[binding.scheme.obligations.start];
        try std.testing.expectEqual(T.ObligationKind.result_dispatch, goal.kind);
        try std.testing.expect(goal.explicit);
        const arrow = f.checked.types.node(binding.scheme.root);
        try std.testing.expectEqual(arrow.a, goal.ty);
        try std.testing.expectEqual(arrow.b, goal.result);
        const row = f.checked.types.row(f.checked.types.node(goal.signature).c);
        try std.testing.expect(row.tail == .closed and row.labels.len == 0);
    }
    try std.testing.expectEqual(@as(usize, 3), interfaces);
    // A covered goal is absent from the exported inferred requirements, but
    // its concrete invocation signature must still reach immutable Core.
    for (f.tree.nodes.items, 0..) |node, index| {
        if (node.tag != .apply) continue;
        const inner = f.tree.node(node.a);
        if (inner.tag != .apply) continue;
        const head = f.tree.node(inner.a);
        if (head.tag != .intrinsic or !std.mem.eql(u8, f.pool.get(head.a), "@type.result")) continue;
        const signature = f.checked.dispatch_signatures[index];
        try std.testing.expect(signature != 0);
        const arrow = f.checked.types.node(signature);
        try std.testing.expectEqual(T.Tag.function, arrow.tag);
        try std.testing.expectEqual(f.checked.expr_types[node.b], arrow.a);
        try std.testing.expectEqual(f.checked.expr_types[index], arrow.b);
    }
}

test "written result requirements preserve destination input aliases contracts and local polymorphism through OOM" {
    try writtenResults(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, writtenResults, .{});
}

fn invalidWrittenResults(allocator: std.mem.Allocator) !void {
    const cases = [_]struct { clause: []const u8, code: check.Code }{
        .{ .clause = "", .code = .missing_predicate },
        .{ .clause = "result \"other\" a b", .code = .missing_predicate },
        .{ .clause = "result a b", .code = .invalid_constraint },
        .{ .clause = "result \"from\" a", .code = .invalid_constraint },
        .{ .clause = "result \"from\" a b a", .code = .invalid_constraint },
        .{ .clause = "result \"from\" a b ! {Foreign}", .code = .missing_predicate },
    };
    for (cases) |item| {
        const text = try allocator.print("const from: a -> b where {{ {s} }} = fn value => @type.result \"from\" value\n", .{item.clause});
        defer allocator.free(text);
        var f = try Fixture.init(allocator, text);
        defer f.deinit(allocator);
        try std.testing.expect(f.checked.diagnostics.len != 0);
        try std.testing.expectEqual(item.code, f.checked.diagnostics[0].code);
    }
}

test "written result requirements reject missing coverage wrong members malformed arity and incompatible rows through OOM" {
    try invalidWrittenResults(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, invalidWrittenResults, .{});
}
