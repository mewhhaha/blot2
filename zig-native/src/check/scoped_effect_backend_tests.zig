const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("../backend/core_backend.zig");
const validation = @import("frozen_core_validation.zig");
const a = std.testing.allocator;
const T = @import("types.zig");
const source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
    \\  let (state, result) = do (@effect.state s.get s.set 7):
    \\    break s.get ()
    \\  break result
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

test "scoped effect maximum member closure ordinal survives owned lowering and emission" {
    var module = try lowerText(a, @import("check_effect_tests.zig").maximum_member_closure_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var tested: usize = 0;
    for (module.bindings) |binding| {
        if (binding.capability_parameters.kind != .member_closure_unit) continue;
        tested += 1;
        try std.testing.expectEqual(@as(u8, 15), binding.capability_parameters.arity());
        try std.testing.expectEqual(@as(u16, 0x4000), binding.capability_parameters.result());
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try emit(a, &module);
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
    \\    break @u32.add a b
    \\  )
    \\  for request in @requests computation:
    \\    case request of
    \\      effect left.get () =>
    \\        yield 11
    \\      effect right_read () =>
    \\        yield 102
    \\      complete value =>
    \\        break value
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerRequestAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    \\    break s.get ()
    \\  break result
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerGenericAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const outer_result_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = fn () => @effect.scope (fn (left: State U32) => do:
    \\  let longer = @effect.scope (fn (right: State U32) => {saved: left})
    \\  let read = longer.saved.get
    \\  let (state, result) = do (@effect.state longer.saved.get longer.saved.set 7):
    \\    break read ()
    \\  break result
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerOuterResultAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const closure_result_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = fn (value: U32) => do:
    \\  let callback = @effect.scope (fn (s: State U32) => fn () => @u32.add value 1)
    \\  break callback ()
;
fn lowerClosureResultAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, closure_result_source);
    defer module.deinit(allocator);
}
test "scoped effect closure footprint survives lowering emission and failed allocations" {
    var module = try lowerText(a, closure_result_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module}, .source_length = closure_result_source.len });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerClosureResultAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const flow_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const identity = fn value => value
    \\const invoke = fn callback => callback ()
    \\entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
    \\  let capability = identity s
    \\  let (state, result) = do (@effect.state capability.get capability.set 7):
    \\    break invoke (identity capability.get)
    \\  break result
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
            .unknown, .member_unit, .invoke_with_capability, .member_first_unit, .member_second_unit, .input_shape, .consume_task => unreachable,
        }
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_flow = original;
    }
    try std.testing.expectEqual(1, identity_count);
    try std.testing.expectEqual(1, invoke_count);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerFlowAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const task_join_wrapper_source =
    \\const await = fn source => |source|
    \\entry const answer = fn () => @task.scope (fn group => do:
    \\  let pending = @task.spawn group (fn () => 42)
    \\  return await pending)
;
test "task join wrapper contract requires the exact checked join body" {
    var module = try lowerText(a, task_join_wrapper_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var found: usize = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_flow != .consume_task) continue;
        found += 1;
        const original = binding.capability_flow;
        binding.capability_flow = .identity;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_flow = original;
        const root = module.bodies[binding.body_id].root;
        const task = module.nodes[root];
        module.nodes[root].c = @backingInt(@import("task_types.zig").Op.cancel);
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        module.nodes[root] = task;
    }
    try std.testing.expectEqual(@as(usize, 1), found);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    try emit(a, &module);
}

const parameter_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const read = fn (s: State a) -> a ! {s.get} => s.get ()
    \\entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
    \\  let (state, result) = do (@effect.state s.get s.set 7):
    \\    break read s
    \\  break result
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerParameterAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    \\    break apply s (fn () => s.get ())
    \\  break result
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerCurriedAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerLocalStoreAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerDependentArrowAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerPairAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerSelectionAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerParameterFootprintsAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerParameterInvocationAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerRecordFootprintsAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerMemberClosureAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").member_closure_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "scoped effect member closure recipes validate captured ordinals and release OOM" {
    var module = try lowerText(a, @import("check_effect_tests.zig").member_closure_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{ .units = &.{&module} });
    var contracts: usize = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_parameters.kind != .member_closure_unit) continue;
        contracts += 1;
        const original = binding.capability_parameters;
        binding.capability_parameters.mask = 1;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_parameters = original;
        binding.capability_parameters.kind = .invoke_unit;
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{ .units = &.{&module} }));
        binding.capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), contracts);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerMemberClosureAndRelease, .{});
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

const multi_input_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const apply2 = fn callback => fn left => fn right => callback left right
    \\const read2 = fn (left: State U32) => fn (right: State U32) => do:
    \\  use x <- left.get ()
    \\  use y <- right.get ()
    \\  break @u32.add x y
    \\entry const answer = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
    \\  use outer <- do (@effect.state left.get left.set 7):
    \\    use inner <- do (@effect.state right.get right.set 9):
    \\      break apply2 read2 left right
    \\    let (state, result) = inner
    \\    break result
    \\  let (state, result) = outer
    \\  break result
    \\))
;
test "multi input invocation reconstructs ordered owners and named callback no store" {
    var module = try lowerText(a, multi_input_source);
    defer module.deinit(a);
    try validation.validate(a, &module, .{});
    const flow = @import("capability_flow.zig");
    var tested: usize = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_parameters.kind != .invoke_inputs) continue;
        tested += 1;
        const original = binding.capability_parameters;
        const body = module.bodies[binding.body_id];
        try std.testing.expect(flow.parameterCore(&module, body, original));
        binding.capability_parameters.invocation_arguments = 0x12;
        try std.testing.expect(binding.capability_parameters.valid());
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
        binding.capability_parameters.invocation_arguments = 0x11;
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        binding.capability_parameters = original;
        binding.capability_parameters.mask = 2;
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        binding.capability_parameters = original;
        binding.capability_parameters.invocation_count = 17;
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        binding.capability_parameters = original;
        var forged = body;
        forged.parameters.start = std.math.maxInt(u32);
        try std.testing.expect(!flow.parameterCore(&module, forged, original));
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    tested = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_flow != .input_shape or binding.capability_parameters.arity() != 2) continue;
        tested += 1;
        const body = module.bodies[binding.body_id];
        const original = binding.capability_parameters;
        try std.testing.expect(@import("capability_contract_core.zig").inputBody(&module, body, original));
        binding.capability_parameters.mask = 1;
        try std.testing.expect(!@import("capability_contract_core.zig").inputBody(&module, body, binding.capability_parameters));
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
        binding.capability_parameters = original;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    var result = try backend.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerMultiInput, .{});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn lowerMultiInput(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, multi_input_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{});
}

test "captured scalar call receipts require primitive roles pure rows and owned certificates" {
    var module = try lowerText(a,
        \\const add = fn (left: U32) => fn (right: U32) => @u32.add left right
        \\const make = fn (seed: U32) => fn () => #[@u32.add seed 1]
    );
    defer module.deinit(a);
    const terms = @import("capability_contracts.zig");
    const receipts = @import("capability_contract_core.zig");
    const body = module.body(2).?.*;
    const array = module.node(body.root);
    const child = module.extra[array.a];
    const scalar = module.node(child);
    try std.testing.expectEqual(core.Tag.scalar, scalar.tag);
    const type_start: u32 = @intCast(module.types.nodes.len);
    module.types.nodes = try a.realloc(module.types.nodes, module.types.nodes.len + 2);
    module.types.nodes[type_start] = .{ .tag = .function, .a = T.u32_type, .b = T.u32_type };
    module.types.nodes[type_start + 1] = .{ .tag = .function, .a = T.u32_type, .b = type_start };
    const call_index: u32 = @intCast(module.calls.len);
    module.calls = try a.realloc(module.calls, module.calls.len + 1);
    module.calls[call_index] = .{ .target = .{ .unit = 1, .binding = 1 }, .callee_type = type_start + 1 };
    const arguments: u32 = @intCast(module.extra.len);
    module.extra = try a.realloc(module.extra, module.extra.len + 2);
    module.extra[arguments] = scalar.a;
    module.extra[arguments + 1] = scalar.b;
    module.nodes[child] = .{ .tag = .call, .ty = T.u32_type, .a = call_index, .b = arguments, .c = 2 };
    const summary = module.bindings[2].capability_parameters;
    var store: terms.Store = .{};
    defer store.deinit(a);
    try std.testing.expect((try receipts.derive(a, &store, &module, body, summary)) != null);
    store.deinit(a);
    store = .{};
    const row_index: u32 = @intCast(module.types.effects.rows.len);
    module.types.effects.rows = try a.realloc(module.types.effects.rows, module.types.effects.rows.len + 2);
    const label: u32 = @intCast(module.types.effects.labels.len);
    module.types.effects.labels = try a.realloc(module.types.effects.labels, module.types.effects.labels.len + 1);
    module.types.effects.labels[label] = T.foreign_operation;
    module.types.effects.rows[row_index] = .{ .labels = .{ .start = label, .len = 1 } };
    module.types.nodes[type_start + 1].c = row_index;
    try std.testing.expectEqual(@as(?terms.Id, null), try receipts.derive(a, &store, &module, body, summary));
    module.types.effects.rows[row_index + 1] = .{ .tail = .{ .variable = 0 } };
    module.types.nodes[type_start + 1].c = row_index + 1;
    var uncertified = body;
    uncertified.closed_rows = .{};
    try std.testing.expectEqual(@as(?terms.Id, null), try receipts.derive(a, &store, &module, uncertified, summary));
    const certificate: u32 = @intCast(module.types.extra.len);
    module.types.extra = try a.realloc(module.types.extra, module.types.extra.len + 1);
    module.types.extra[certificate] = 0;
    uncertified.closed_rows = .{ .start = certificate, .len = 1 };
    try std.testing.expect((try receipts.derive(a, &store, &module, uncertified, summary)) != null);
    store.deinit(a);
    store = .{};
    module.nodes[scalar.a].ty = T.boolean;
    try std.testing.expectEqual(@as(?terms.Id, null), try receipts.derive(a, &store, &module, uncertified, summary));
    module.nodes[scalar.a].ty = T.u32_type;
    var budget: usize = 0;
    try std.testing.expectEqual(@as(?[]const u32, null), @import("capability_flow.zig").scalarCallOperands(&module, child, uncertified.closed_rows, &budget));
}

fn forwardingSource(allocator: std.mem.Allocator) ![]u8 {
    return std.mem.replaceOwned(u8, allocator, "const forward2 = fn callback => fn left => fn right => apply2 callback left right\n" ++ multi_input_source, "break apply2 read2 left right", "break forward2 read2 left right");
}
fn lowerForwarding(allocator: std.mem.Allocator) !void {
    const text = try forwardingSource(allocator);
    defer allocator.free(text);
    var module = try lowerText(allocator, text);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{});
}
test "forwarding invocation reconstructs producer bodies and rejects cycles missing owners and order forgery" {
    const text = try forwardingSource(a);
    defer a.free(text);
    var module = try lowerText(a, text);
    defer module.deinit(a);
    try validation.validate(a, &module, .{});
    const flow = @import("capability_flow.zig");
    var tested: usize = 0;
    for (module.bindings) |binding| {
        if (!binding.capability_parameters.inputInvokes()) continue;
        const body = module.bodies[binding.body_id];
        const node = module.node(body.root);
        if (node.tag != .call) continue;
        tested += 1;
        try std.testing.expect(flow.parameterCore(&module, body, binding.capability_parameters));
        var remaining: usize = 0;
        try std.testing.expectEqual(@as(?flow.Parameters, null), flow.invocationCore(&module, body, &.{}, &remaining));
        remaining = 4096;
        try std.testing.expectEqualDeep(binding.capability_parameters, flow.invocationCore(&module, body, &.{}, &remaining).?);
        try std.testing.expect(remaining < 4096);
        const first = module.extra[node.b + 1];
        const second = module.extra[node.b + 2];
        module.extra[node.b + 1] = second;
        module.extra[node.b + 2] = first;
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        try std.testing.expectError(error.InvalidArtifact, validation.validate(a, &module, .{}));
        module.extra[node.b + 1] = first;
        module.extra[node.b + 2] = second;
        const target = module.calls[node.a].target;
        module.calls[node.a].target = .{ .binding = body.binding, .unit = module.unit };
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        module.calls[node.a].target = .{ .binding = target.binding, .unit = 99 };
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        module.calls[node.a].target = target;
        const producer_body = module.bindings[target.binding].body_id;
        const root = module.bodies[producer_body].root;
        module.bodies[producer_body].root = 0;
        try std.testing.expect(!flow.parameterCore(&module, body, binding.capability_parameters));
        module.bodies[producer_body].root = root;
    }
    try std.testing.expectEqual(@as(usize, 1), tested);
    try emit(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerForwarding, .{});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
}

fn projectedSource(allocator: std.mem.Allocator) ![]u8 {
    const wrapped = try std.mem.replaceOwned(u8, allocator, multi_input_source, "entry const answer", "const keep = fn callback => {callback}\nconst make = fn () => keep read2\nentry const answer");
    defer allocator.free(wrapped);
    return std.mem.replaceOwned(u8, allocator, wrapped, "break apply2 read2 left right", "let holder = make ()\n      break apply2 holder.callback left right");
}
fn emitProjected(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
fn lowerProjected(allocator: std.mem.Allocator) !void {
    const text = try projectedSource(allocator);
    defer allocator.free(text);
    var module = try lowerText(allocator, text);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
test "projected callable provenance owns producer bodies receiver binders and closed constructor execution" {
    const text = try projectedSource(a);
    defer a.free(text);
    var module = try lowerText(a, text);
    defer module.deinit(a);
    const context: validation.Context = .{ .units = &.{&module} };
    try validation.validateBounds(&module, context);
    try @import("capability_invocations.zig").validate(a, &module, context.units);
    try validation.validate(a, &module, context);
    var callbacks: usize = 0;
    for (module.bindings) |binding| {
        if (binding.capability_flow != .input_shape or binding.capability_parameters.arity() != 2) continue;
        callbacks += 1;
        const body = &module.bodies[binding.body_id];
        const original = body.root;
        const parameter = module.parameters[body.parameters.start].binding;
        for (module.nodes, 0..) |node, id| {
            if (node.tag != .reference) continue;
            const reference = module.reference(@intCast(id));
            if ((reference.unit != 0 and reference.unit != module.unit) or reference.binding != parameter) continue;
            body.root = @intCast(id);
            break;
        }
        try std.testing.expect(body.root != original);
        try std.testing.expectError(error.InvalidArtifact, @import("capability_invocations.zig").validate(a, &module, context.units));
        body.root = original;
        var tested_reference = false;
        for (module.nodes, 0..) |node, id| {
            if (node.tag != .reference) continue;
            const reference = module.reference(@intCast(id));
            if (reference.binding != body.binding or (reference.unit != 0 and reference.unit != module.unit)) continue;
            tested_reference = true;
            module.nodes[id].ty = T.u32_type;
            try std.testing.expectError(error.InvalidArtifact, @import("capability_invocations.zig").validate(a, &module, context.units));
            module.nodes[id].ty = node.ty;
            const type_id: u32 = @intCast(module.types.nodes.len);
            module.types.nodes = try a.realloc(module.types.nodes, module.types.nodes.len + 2);
            const row: u32 = @intCast(module.types.effects.rows.len);
            const label: u32 = @intCast(module.types.effects.labels.len);
            module.types.effects.rows = try a.realloc(module.types.effects.rows, module.types.effects.rows.len + 1);
            module.types.effects.labels = try a.realloc(module.types.effects.labels, module.types.effects.labels.len + 1);
            module.types.effects.labels[label] = T.foreign_operation;
            module.types.effects.rows[row] = .{ .labels = .{ .start = label, .len = 1 } };
            module.types.nodes[type_id] = module.types.node(node.ty);
            const inner = module.types.node(module.types.nodes[type_id].b);
            try std.testing.expectEqual(T.Tag.function, inner.tag);
            module.types.nodes[type_id + 1] = inner;
            module.types.nodes[type_id + 1].c = row;
            module.types.nodes[type_id].b = type_id + 1;
            module.nodes[id].ty = type_id;
            try std.testing.expectError(error.InvalidArtifact, @import("capability_invocations.zig").validate(a, &module, context.units));
            module.nodes[id].ty = node.ty;
            break;
        }
        try std.testing.expect(tested_reference);
    }
    try std.testing.expectEqual(@as(usize, 1), callbacks);
    var factories: usize = 0;
    for (module.bindings) |*binding| {
        if (binding.capability_flow != .input_shape or binding.capability_parameters.arity() != 1 or binding.scheme.variables.len == 0) continue;
        const body = module.bodies[binding.body_id];
        if (module.parameters[body.parameters.start].ty != T.unit) continue;
        factories += 1;
        const original = binding.scheme.variables;
        binding.scheme.variables = .{};
        try std.testing.expectError(error.InvalidArtifact, validation.validateBounds(&module, context));
        binding.scheme.variables = original;
    }
    try std.testing.expectEqual(@as(usize, 1), factories);
    try emitProjected(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, lowerProjected, .{});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitProjected, .{&module});
}
