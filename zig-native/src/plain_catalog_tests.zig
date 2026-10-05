const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const plain = @import("plain_catalog.zig");

fn fixture(a: std.mem.Allocator, text: []const u8) !core.Module {
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &pool, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

test "positive catalog proofs cover List Array generic and nested data but decline callables cycles unknown owners and depth exhaustion" {
    const a = std.testing.allocator;
    var module = try fixture(a,
        \\type Payload a is data = #Payload { xs: List a, ys: Array a }
        \\type Acyclic is data = #Acyclic (Payload U32)
        \\type Callback is data = #Callback (U32 -> U32)
        \\type Recursive is data = #Recursive (List Recursive)
        \\type NestedCallback is data = #NestedCallback (Payload (U32 -> U32))
        \\type Empty is data = #Empty
        \\entry const run = 0
    );
    defer module.deinit(a);
    var verified: usize = 0;
    for (module.nominals[1..]) |nominal| {
        const name = module.name(nominal.diagnostic_name);
        const expected = std.mem.eql(u8, name, "Payload") or std.mem.eql(u8, name, "Acyclic") or std.mem.eql(u8, name, "Empty");
        try std.testing.expectEqual(expected, plain.prove(&.{module}, 1, nominal.identity.decl, 256));
        try std.testing.expect(!plain.prove(&.{module}, 1, nominal.identity.decl, 0));
        try std.testing.expect(!plain.prove(&.{module}, 2, nominal.identity.decl, 256));
        verified += 1;
    }
    try std.testing.expectEqual(@as(usize, 6), verified);
    try std.testing.expect(!plain.prove(&.{module}, 1, std.math.maxInt(u32), 256));
    module.unit = 0;
    for (module.nominals[1..]) |nominal| {
        const name = module.name(nominal.diagnostic_name);
        const expected = std.mem.eql(u8, name, "Payload") or std.mem.eql(u8, name, "Acyclic") or std.mem.eql(u8, name, "Empty");
        try std.testing.expectEqual(expected, plain.prove(&.{module}, 1, nominal.identity.decl, 256));
    }
}

test "a changed constructor payload is revalidated independently of prior positive answers" {
    const a = std.testing.allocator;
    var module = try fixture(a,
        \\type Value is data = #Value U32
        \\type Callback is data = #Callback (U32 -> U32)
        \\entry const run = 0
    );
    defer module.deinit(a);
    const value = for (module.nominals) |item| {
        if (std.mem.eql(u8, module.name(item.diagnostic_name), "Value")) break item;
    } else return error.MissingValue;
    const callback = for (module.nominals) |item| {
        if (std.mem.eql(u8, module.name(item.diagnostic_name), "Callback")) break item;
    } else return error.MissingCallback;
    const constructor = module.extra[value.constructors.start];
    const replacement = module.constructor(module.extra[callback.constructors.start]).payload;
    try std.testing.expect(plain.prove(&.{module}, 1, value.identity.decl, 256));
    const original = module.constructors[constructor].payload;
    @constCast(module.constructors)[constructor].payload = replacement;
    try std.testing.expect(!plain.prove(&.{module}, 1, value.identity.decl, 256));
    @constCast(module.constructors)[constructor].payload = original;
    try std.testing.expect(plain.prove(&.{module}, 1, value.identity.decl, 256));
}
