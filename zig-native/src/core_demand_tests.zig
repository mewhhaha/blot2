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
    \\const keep = fn ~(value: U32) => fn () => @force value
    \\const ignore = fn ~(value: U32) => 42
    \\entry const snapshot = fn (start: U32) -> U32 => do:
    \\  let saved = start
    \\  let read = keep saved
    \\  saved := 0
    \\  return read ()
    \\entry const skipped = ignore (@panic "unused demand")
;

const Fixture = struct {
    tree: ast.Tree,
    names: symbols.Pool,
    checked: check.Checked,
    fn init() !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var names: symbols.Pool = .{};
        errdefer names.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &names);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &names);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |item| std.debug.print("demand {d}: {s}\n", .{ item.span.start, item.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .tree = tree, .names = names, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.names.deinit(a);
    }
    fn lower(self: *const Fixture, allocator: std.mem.Allocator) !core.Module {
        return core.lower(allocator, &self.tree, &self.names, &self.checked);
    }
};

fn verify(module: *const core.Module) !void {
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var suspensions: usize = 0;
    var forces: usize = 0;
    var captured: core.BindingId = 0;
    for (module.nodes, 0..) |value, index| switch (value.tag) {
        .suspend_ => {
            suspensions += 1;
            const id: core.Id = @intCast(index);
            const info = module.suspension(id);
            try std.testing.expectEqual(@as(core.BindingId, 0), info.parameter.binding);
            try std.testing.expectEqual(T.unit, info.parameter.ty);
            const ty = module.types.node(value.ty);
            try std.testing.expectEqual(T.Tag.demand, ty.tag);
            // An ignored panic remains Never in the suspension body while the
            // context supplies Demand(U32), rather than manufacturing Demand(Never).
            try std.testing.expectEqual(T.Tag.u32, module.types.node(ty.a).tag);
            const captures = module.suspensionCaptures(id);
            if (module.node(info.body).tag == .panic) {
                try std.testing.expectEqual(@as(usize, 0), captures.len);
                try std.testing.expectEqualStrings("unused demand", module.panicMessage(info.body));
                try std.testing.expectEqual(T.Tag.never, module.types.node(module.node(info.body).ty).tag);
            } else {
                try std.testing.expectEqual(core.Tag.reference, module.node(info.body).tag);
                captured = module.reference(info.body).binding;
                try std.testing.expectEqualSlices(core.BindingId, &.{captured}, captures);
            }
        },
        .force => {
            forces += 1;
            try std.testing.expectEqual(T.Tag.demand, module.types.node(module.node(value.a).ty).tag);
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 2), suspensions);
    try std.testing.expectEqual(@as(usize, 1), forces);
    try std.testing.expect(captured != 0);
    for (module.bodies) |body| {
        if (!std.mem.eql(u8, module.name(body.export_name), "snapshot")) continue;
        const statements = module.children(body.root);
        try std.testing.expectEqual(captured, module.node(statements[0]).a);
        try std.testing.expect(captured != module.node(statements[2]).a);
        return;
    }
    return error.TestExpectedEqual;
}

test "suspensions own lexical versions and contextual result types after frontend teardown" {
    var fixture = try Fixture.init();
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try verify(&module);
}

fn allocationFailure(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try verify(&module);
}

test "every demanded closure and capture allocation failure releases owned state" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{&fixture});
}
