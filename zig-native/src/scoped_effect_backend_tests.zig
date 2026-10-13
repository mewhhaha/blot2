const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const validation = @import("frozen_core_validation.zig");
const a = std.testing.allocator;
const T = @import("types.zig");
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
    if (result.diagnostic) |item| std.debug.print("scoped emission diagnostic {s} at {d}\n", .{ @tagName(item.code), item.span.start });
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    // Creation occurs only when the generated guest runs. No live authority
    // exists in evaluator values, snapshots or a successful constant receipt.
    if (result.constant_steps != 0) std.debug.print("scoped emission constant steps {d}\n", .{result.constant_steps});
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

const flow_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const identity = fn value => value
    \\const invoke = fn callback => callback ()
    \\entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
    \\  let capability = identity s
    \\  let (state, result) = do (@effect.state capability.get capability.set 7):
    \\    return invoke (identity capability.get)
    \\  return result
    \\)
;
fn lowerFlowAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, flow_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect public flow contracts validate bodies and release failed allocations" {
    var module = try lowerText(a, flow_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var identity_count: usize = 0;
    var invoke_count: usize = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_flow == .unknown) continue;
        const original = binding.capability_flow;
        switch (original) {
            .identity => {
                identity_count += 1;
                binding.capability_flow = .invoke_unit;
            },
            .invoke_unit => {
                invoke_count += 1;
                binding.capability_flow = .identity;
            },
            .unknown, .member_unit, .invoke_with_capability, .member_first_unit, .member_second_unit => unreachable,
        }
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_flow = original;
    }
    try std.testing.expectEqual(1, identity_count);
    try std.testing.expectEqual(1, invoke_count);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerFlowAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const parameter_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const read = fn (s: State a) -> a ! {s.get} => s.get ()
    \\entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
    \\  let (state, result) = do (@effect.state s.get s.set 7):
    \\    return read s
    \\  return result
    \\)
;
fn lowerParameterAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, parameter_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect capability parameters preserve owned binders through lowering emission and OOM" {
    var module = try lowerText(a, parameter_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerParameterAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

test "scoped effect frozen capability parameters reject substituted binder edges and body claims" {
    var module = try lowerText(a, parameter_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var tested = false;
    for (module.types.nodes) |*node| {
        if (node.tag != .scoped or node.b != 0) continue;
        const identity = node.c;
        node.c = T.u32_type;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        node.c = identity;
        tested = true;
        break;
    }
    try std.testing.expect(tested);
    for (module.bindings) |*binding| {
        if (binding.capability_flow != .member_unit) continue;
        binding.capability_flow = .invoke_unit;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_flow = .member_unit;
        try validation.validate(a, &module, .{ .units = &.{&module} });
        return;
    }
    return error.ExpectedParameterFlow;
}

const curried_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const apply = fn (s: State a) => fn (callback: Unit -> a ! {s.get | e}) => callback ()
    \\entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
    \\  let (state, result) = do (@effect.state s.get s.set 7):
    \\    return apply s (fn () => s.get ())
    \\  return result
    \\)
;
fn lowerCurriedAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, curried_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect curried capability callback contracts survive lowering emission and OOM" {
    var module = try lowerText(a, curried_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    for (module.bindings) |*binding| {
        if (binding.capability_flow != .invoke_with_capability) continue;
        binding.capability_flow = .invoke_unit;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_flow = .invoke_with_capability;
    }
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerCurriedAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerLocalStoreAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").local_store_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect local State storage releases capture roots on failed lowering and emission" {
    var module = try lowerText(a, @import("check_effect_tests.zig").local_store_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerLocalStoreAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerDependentArrowAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").dependent_arrow_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect complete arrow binders survive owned lowering emission and OOM" {
    var module = try lowerText(a, @import("check_effect_tests.zig").dependent_arrow_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerDependentArrowAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerPairAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").pair_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect paired input identities survive owned lowering emission and OOM" {
    var module = try lowerText(a, @import("check_effect_tests.zig").pair_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    for (module.bindings) |*binding| {
        if (binding.capability_flow != .member_second_unit) continue;
        binding.capability_flow = .member_first_unit;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_flow = .member_second_unit;
    }
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerPairAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerSelectionAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").selection_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect selection terms survive owned lowering emission and OOM" {
    var module = try lowerText(a, @import("check_effect_tests.zig").selection_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerSelectionAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerParameterFootprintsAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").parameter_footprint_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect pure product input footprints validate exact bodies and release OOM" {
    var module = try lowerText(a, @import("check_effect_tests.zig").parameter_footprint_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var contracts: usize = 0;
    for (module.bindings) |*binding| {
        if (!binding.capability_parameters.present()) continue;
        contracts += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters = .init(original.arity(), 1);
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_parameters = original;
        binding.capability_parameters = .init(17, original.result());
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), contracts);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerParameterFootprintsAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerParameterInvocationAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").parameter_invocation_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect multiple input invocation claims validate callback ordinals and OOM" {
    var module = try lowerText(a, @import("check_effect_tests.zig").parameter_invocation_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var contracts: usize = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_parameters.kind != .invoke_unit) continue;
        contracts += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters.mask = 1;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_parameters = original;
        binding.capability_parameters.kind = .product;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), contracts);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerParameterInvocationAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerRecordFootprintsAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").record_footprint_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect record constructors validate exact retained fields and release OOM" {
    var module = try lowerText(a, @import("check_effect_tests.zig").record_footprint_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var contracts: usize = 0;
    for (module.bindings) |*binding| {
        if (!binding.capability_parameters.present()) continue;
        contracts += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters.mask = 1;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), contracts);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lowerRecordFootprintsAndRelease, .{});
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}
