const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
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
    \\  return value
    \\entry const floating = fn () => do:
    \\  let #Box value:Box F32 = alias 1.25
    \\  return value
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
        \\  return #Target value
        \\const unused = fn (value:U32) -> Missing => @type.result "from" value
        \\entry const answer = fn () => do:
        \\  let #Target value:Target = @type.result "from" (#Source 42)
        \\  return value
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, failures, .{});
}
