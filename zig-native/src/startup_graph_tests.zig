const std = @import("std");
const graph = @import("startup_graph.zig");
const core = @import("core.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const a = std.testing.allocator;
fn target(binding: u32) core.BindingRef {
    return .{ .unit = 1, .binding = binding };
}
fn expectCycle(declarations: []const graph.Declaration, expected: ?core.BindingRef) !void {
    var g = try graph.Graph.init(a, declarations);
    defer g.deinit(a);
    const reached = try g.select(a, 1);
    defer a.free(reached);
    var plan = try g.plan(a, reached);
    defer plan.deinit(a);
    try std.testing.expectEqual(expected, plan.cycle);
}
test "component order reports the last source cell in the last disconnected reached cycle" {
    const declarations = [_]graph.Declaration{
        .{ .target = target(1), .references = &.{target(2)}, .runtime = true },
        .{ .target = target(2), .references = &.{target(1)}, .runtime = true },
        .{ .target = target(3), .references = &.{target(4)}, .runtime = true },
        .{ .target = target(4), .references = &.{target(3)}, .runtime = true },
        .{ .target = target(5), .references = &.{ target(1), target(3) }, .exported = true },
    };
    try expectCycle(&declarations, target(4));
    var reversed = declarations;
    reversed[4].references = &.{ target(3), target(1) };
    try expectCycle(&reversed, target(4));
    // A disconnected dead component does not enter startup planning.
    reversed[4].references = &.{target(1)};
    try expectCycle(&reversed, target(2));
}
test "recursive named functions are not runtime cells but mixed function-cell SCC rejects" {
    const functions = [_]graph.Declaration{
        .{ .target = target(1), .references = &.{target(2)}, .is_function = true, .runtime = true },
        .{ .target = target(2), .references = &.{target(1)}, .is_function = true, .runtime = true },
        .{ .target = target(3), .references = &.{target(1)}, .is_function = true, .exported = true },
    };
    try expectCycle(&functions, null);
    var mixed = functions;
    mixed[1].is_function = false;
    try expectCycle(&mixed, target(2));
    mixed[1].references = &.{target(2)};
    try expectCycle(&mixed, target(2));
}
test "candidate selection edges never become initializer calls" {
    const declarations = [_]graph.Declaration{
        .{ .target = target(1), .references = &.{}, .candidates = &.{target(2)}, .runtime = true },
        .{ .target = target(2), .references = &.{target(1)}, .is_function = true },
        .{ .target = target(3), .references = &.{target(1)}, .exported = true },
    };
    var g = try graph.Graph.init(a, &declarations);
    defer g.deinit(a);
    const selected = try g.select(a, 1);
    defer a.free(selected);
    try std.testing.expect(selected[1]);
    var plan = try g.plan(a, selected);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(?core.BindingRef, null), plan.cycle);
    try std.testing.expectEqualSlices(core.BindingRef, &.{target(1)}, plan.initializers);
}
fn checkPlan(allocator: std.mem.Allocator, declarations: []const graph.Declaration) !void {
    var g = try graph.Graph.init(allocator, declarations);
    defer g.deinit(allocator);
    const selected = try g.select(allocator, 1);
    defer allocator.free(selected);
    var plan = try g.plan(allocator, selected);
    defer plan.deinit(allocator);
    try std.testing.expectEqualSlices(core.BindingRef, &.{ target(1), target(2), target(3) }, plan.initializers);
}
test "ordered acyclic initialization releases every graph and SCC allocation failure" {
    const declarations = [_]graph.Declaration{
        .{ .target = target(1), .references = &.{}, .runtime = true },
        .{ .target = target(2), .references = &.{target(1)}, .runtime = true },
        .{ .target = target(3), .references = &.{target(2)}, .runtime = true, .exported = true },
    };
    try checkPlan(a, &declarations);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, checkPlan, .{&declarations});
    try std.testing.expectError(error.InvalidDependencyGraph, graph.Graph.init(a, &.{.{ .target = target(1), .references = &.{target(2)} }}));
    try std.testing.expectError(error.InvalidDependencyGraph, graph.Graph.init(a, &.{ .{ .target = target(1), .references = &.{} }, .{ .target = target(1), .references = &.{} } }));
}
test "long chains and large legal function components use iterative work and preserve source order" {
    const count = 10000;
    const declarations = try a.alloc(graph.Declaration, count);
    defer a.free(declarations);
    const references = try a.alloc(core.BindingRef, count);
    defer a.free(references);
    for (declarations, 0..) |*d, i| {
        references[i] = target(if (i == 0) count else @intCast(i));
        d.* = .{ .target = target(@intCast(i + 1)), .references = references[i..][0..1], .is_function = true, .exported = i == count - 1 };
    }
    try expectCycle(declarations, null);
    declarations[1234].runtime = true;
    declarations[1234].is_function = false;
    try expectCycle(declarations, target(1235));
}
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("check {s} {d}..{d}: {s}\n", .{ @tagName(d.code), d.span.start, d.span.end, d.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

const backend = @import("core_backend.zig");
const Control = struct { source: []const u8, code: ?backend.Code, point: ?u32 = null, message: ?[]const u8 = null };
const controls = [_]Control{
    .{ .source = "let base = 1\nconst saved = 41\nconst delay = fn ~value => value\nentry const answer = fn () => @u32.add base (@force (delay saved))\n", .code = null },
    .{ .source = "let first: U32 = second\nlet second = first\nentry const answer = if #True then 42 else first\n", .code = .initialization_cycle, .point = 28 },
    .{ .source = "let first: U32 = second\nlet second = first\nentry const answer: Unit -> U32 = fn () => first\nentry const bad: U32 = @panic \"later\"\n", .code = .const_panic, .point = 0, .message = "later" },
    .{ .source = "let first: U32 = second\nlet second = first\nlet saved = 42\nentry const answer: Unit -> U32 = fn () => first\nentry const bad = saved\n", .code = .const_runtime_dependency, .point = 0 },
    .{ .source = "let first: U32 = second\nlet second = first\nentry const answer = 42\n", .code = null },
    .{ .source = "let first: U32 = second\nlet second = first\nconst read: Unit -> U32 = fn () => first\nentry const answer = @effect.count (@effect.of read)\n", .code = .initialization_cycle, .point = 28 },
    .{ .source = "const read: Unit -> U32 = fn () => first\nlet first = read ()\nentry const answer = fn () => first\n", .code = .initialization_cycle, .point = 45 },
};
fn emitControl(allocator: std.mem.Allocator, module: *const core.Module, control: Control) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(control.code, if (result.diagnostic) |diagnostic| diagnostic.code else null);
    if (control.point) |point| {
        try std.testing.expectEqual(point, result.diagnostic.?.span.start);
        try std.testing.expectEqual(point, result.diagnostic.?.span.end);
    }
    if (control.message) |message| try std.testing.expectEqualStrings(message, result.diagnostic.?.message());
    if (control.code == null) try std.testing.expect(result.bytes.len > 8) else try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}
fn sourceOwnership(allocator: std.mem.Allocator, source: []const u8) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    try std.testing.expectEqual(module.bodies.len, module.declaration_dependencies.len);
    try std.testing.expectEqual(@as(usize, 1), module.erased_declaration_references.len);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    var declarations = try graph.fromCore(allocator, &.{module}, &.{1});
    defer declarations.deinit(allocator);
    const selected = try declarations.select(allocator, 1);
    defer allocator.free(selected);
    for (selected) |chosen| try std.testing.expect(chosen);
}
test "startup ownership preserves original branches and erased metadata after frontend teardown and OOM" {
    const source = controls[5].source;
    try sourceOwnership(a, source);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, sourceOwnership, .{source});
}
test "all entry constant demands precede owned startup cycle planning under OOM without mutating frozen Core" {
    for (controls) |control| {
        var module = try lower(a, control.source);
        defer module.deinit(a);
        const references = try a.dupe(core.BindingRef, module.dependency_references);
        defer a.free(references);
        const dependencies = try a.dupe(core.DeclarationDependencies, module.declaration_dependencies);
        defer a.free(dependencies);
        const erased = try a.dupe(core.ErasedDeclarationReference, module.erased_declaration_references);
        defer a.free(erased);
        try emitControl(a, &module, control);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitControl, .{ &module, control });
        try std.testing.expectEqualSlices(core.BindingRef, references, module.dependency_references);
        try std.testing.expectEqualSlices(core.DeclarationDependencies, dependencies, module.declaration_dependencies);
        try std.testing.expectEqualSlices(core.ErasedDeclarationReference, erased, module.erased_declaration_references);
    }
}

test "frozen startup dependency tables reject omitted or out of range recipes before indexed reads" {
    var module = try lower(a, controls[5].source);
    defer module.deinit(a);
    const V = @import("frozen_core_validation.zig");
    try V.validateBounds(&module, .{});
    const recipes = module.declaration_dependencies;
    module.declaration_dependencies = &.{};
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&module, .{}));
    module.declaration_dependencies = recipes;
    const first = module.declaration_dependencies[1];
    module.declaration_dependencies[1].references.start = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&module, .{}));
    module.declaration_dependencies[1] = first;
    const reference = module.dependency_references[0];
    module.dependency_references[0].binding = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&module, .{}));
    module.dependency_references[0] = reference;
    const erased = module.erased_declaration_references[0];
    module.erased_declaration_references[0].node = 0;
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&module, .{}));
    module.erased_declaration_references[0] = erased;
    module.declaration_dependencies[1].runtime_metadata = module.bodies[1].root;
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&module, .{}));
    module.declaration_dependencies[1] = first;
    try V.validateBounds(&module, .{});
}
