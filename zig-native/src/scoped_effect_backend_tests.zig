const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const validation = @import("frozen_core_validation.zig");
const a = std.testing.allocator;
const source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
    \\  let (state, result) = do (@effect.state s.get s.set 7):
    \\    return s.get ()
    \\  return result
    \\)
;

fn lower(allocator: std.mem.Allocator) !core.Module {
    return lowerText(allocator, source);
}
fn lowerText(allocator: std.mem.Allocator, text: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(0, checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    try std.testing.expectEqual(0, module.diagnostics.len);
    return module;
}
fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    // Creation occurs only when the generated guest runs. No live authority
    // exists in evaluator values, snapshots or a successful constant receipt.
    try std.testing.expectEqual(0, result.constant_steps);
}
test "scoped effect lowering and guest emission release every failed allocation" {
    var module = try lower(a);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module}, .source_length = source.len });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
fn lowerAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator);
    defer module.deinit(allocator);
}
test "scoped effect frozen evidence rejects missing and substituted scope binders" {
    var module = try lower(a);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    for (module.operation_values) |*operation| {
        if (operation.instance.decl == 0) continue;
        const original = operation.*;
        operation.capability = 0;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        operation.* = original;
        operation.instance.decl += 1;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        operation.* = original;
        return;
    }
    return error.ExpectedScopedOperation;
}

const request_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
    \\  let right_read = right.get
    \\  let computation = @computation (fn () => do:
    \\    use a <- left.get ()
    \\    use b <- right_read ()
    \\    return @u32.add a b
    \\  )
    \\  for request in @requests computation:
    \\    case request of
    \\      effect left.get () =>
    \\        yield 11
    \\      effect right_read () =>
    \\        yield 102
    \\      complete value =>
    \\        return value
    \\))
;
fn lowerRequestAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, request_source);
    defer module.deinit(allocator);
}
test "scoped effect request selectors survive lowering emission and failed allocations" {
    var module = try lowerText(a, request_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module}, .source_length = request_source.len });
    try std.testing.expectEqual(2, module.request_arms.len);
    try std.testing.expect(module.request_arms[0].selector != 0);
    try std.testing.expect(module.request_arms[1].selector != 0);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerRequestAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
test "scoped effect request evidence rejects missing and foreign-owner selectors" {
    var module = try lowerText(a, request_source);
    defer module.deinit(a);
    const original = module.request_arms[0];
    module.request_arms[0].selector = 0;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
    module.request_arms[0] = original;
    module.request_arms[0].selector = module.request_arms[1].selector;
    try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
    module.request_arms[0] = original;
    try validation.validate(a, &module, .{ .units = &.{&module} });
}

const generic_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const local = fn (value: a) => @effect.scope (fn (s: State a) => do:
    \\  let (state, result) = do (@effect.state s.get s.set value):
    \\    return s.get ()
    \\  return result
    \\)
    \\entry const integer = fn () => local 7
    \\entry const fraction = fn () => local 1.5
;
fn lowerGenericAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, generic_source);
    defer module.deinit(allocator);
}
test "scoped effect symbolic factories survive lowering emission and failed allocations" {
    var module = try lowerText(a, generic_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module}, .source_length = generic_source.len });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerGenericAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const outer_result_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = fn () => @effect.scope (fn (left: State U32) => do:
    \\  let longer = @effect.scope (fn (right: State U32) => {saved: left})
    \\  let read = longer.saved.get
    \\  let (state, result) = do (@effect.state longer.saved.get longer.saved.set 7):
    \\    return read ()
    \\  return result
    \\)
;
fn lowerOuterResultAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, outer_result_source);
    defer module.deinit(allocator);
}
test "scoped effect outer authority projection survives lowering emission and failed allocations" {
    var module = try lowerText(a, outer_result_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module}, .source_length = outer_result_source.len });
    var projected_owners: usize = 0;
    for (module.operation_values) |operation| {
        if (operation.capability == 0) continue;
        if (module.node(operation.capability).tag == .project) projected_owners += 1;
    }
    try std.testing.expect(projected_owners > 0);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerOuterResultAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const closure_result_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = fn (value: U32) => do:
    \\  let callback = @effect.scope (fn (s: State U32) => fn () => @u32.add value 1)
    \\  return callback ()
;
fn lowerClosureResultAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, closure_result_source);
    defer module.deinit(allocator);
}
test "scoped effect closure footprint survives lowering emission and failed allocations" {
    var module = try lowerText(a, closure_result_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module}, .source_length = closure_result_source.len });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerClosureResultAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
