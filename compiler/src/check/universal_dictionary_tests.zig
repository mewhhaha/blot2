const std = @import("std");
const symbols = @import("../parse/symbols.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const check = @import("check.zig");
const A = std.mem.Allocator;
const source =
    \\type Render a is contract = { const show: a -> U32 }
    \\const render: forall [a] where { Render a } => a -> U32 = func value => return Render.show value
;
fn checkIntroduction(a: A) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), checked.dictionary_uses.len);
    const use = checked.dictionary_uses[0];
    try std.testing.expect(use.introduction != 0 and use.opening == 0);
    try std.testing.expectEqual(@as(u32, 0), use.goal);
    try std.testing.expectEqual(@as(u32, 0), use.member);
    try std.testing.expectEqual(@as(usize, 1), checked.types.quantifierGoals(use.quantifier).len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const original = module.dictionary_uses[0];
    module.dictionary_uses[0].introduction = 0;
    try rejected(a, &module);
    module.dictionary_uses[0] = original;
    module.dictionary_uses[0].introduction = original.node;
    try rejected(a, &module);
    module.dictionary_uses[0] = original;
    module.dictionary_uses[0].goal = 1;
    try rejected(a, &module);
    module.dictionary_uses[0] = original;
    module.dictionary_uses[0].member = 1;
    try rejected(a, &module);
    module.dictionary_uses[0] = original;
}
fn rejected(a: A, module: *const @import("core.zig").Module) !void {
    @import("frozen_core_validation.zig").validate(a, module, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
        return;
    };
    return error.TestUnexpectedResult;
}
test "universal predicate introductions own lexical method givens through complete allocation failures" {
    try checkIntroduction(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, checkIntroduction, .{});
}

fn checkCalls(a: A) !void {
    const text =
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = func value => return value }
        \\const render: forall [a] where { Render a } => a -> U32 = func value => return Render.show value
        \\entry const answer: U32 -> U32 = func value => return render value
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(checked.selected_proofs.len != 0);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
}
test "universal predicate eliminations independently discharge caller evidence through complete allocation failures" {
    try checkCalls(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, checkCalls, .{});
}

fn checkImplementationGivens(a: A) !void {
    const text =
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\const render: forall [a] where { Render a } => a -> U32 = func value => return Render.show value
        \\const forward: forall [a] where { Render a } => a -> U32 = func value => return render value
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try @import("core.zig").lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.selected_proofs.len);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const implementation = module.implementations[0];
    const member = module.implementation_members[implementation.members.start];
    const body = module.body(member.target.binding).?;
    try std.testing.expect(body.scheme.obligations.len != 0);
    var remaining: usize = 65_536;
    var scopes: @import("package_contracts.zig").Context = .{ .types = &module.types, .remaining = &remaining };
    try scopes.initialize();
    const dictionaries = @import("dictionary_contracts.zig");
    try dictionaries.requirements(&module, body.scheme.obligations, &scopes, body.binding);
    try std.testing.expectError(error.InvalidArtifact, dictionaries.requirements(&module, body.scheme.obligations, &scopes, 0));
    const other = module.implementation_members[module.implementations[1].members.start];
    try std.testing.expectError(error.InvalidArtifact, dictionaries.requirements(&module, body.scheme.obligations, &scopes, other.target.binding));
}
test "universal library implementation givens require the exact owning method and head through full OOM" {
    try checkImplementationGivens(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, checkImplementationGivens, .{});
}
