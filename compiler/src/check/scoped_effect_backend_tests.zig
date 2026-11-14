const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const validation = @import("frozen_core_validation.zig");
const a = std.testing.allocator;
const T = @import("types.zig");
const source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
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
    \\entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  let right_read = right.get
    \\  let computation = @computation (func () => return do:
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
    \\const local = func (value: a) => return @effect.scope (func (s: State a) => return do:
    \\  let (state, result) = do (@effect.state s.get s.set value):
    \\    break s.get ()
    \\  break result
    \\)
    \\entry const integer = func () => return local 7
    \\entry const fraction = func () => return local 1.5
;
fn lowerGenericAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, generic_source);
    defer module.deinit(allocator);
}
const outer_result_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = func () => return @effect.scope (func (left: State U32) => return do:
    \\  let longer = @effect.scope (func (right: State U32) => return {saved: left})
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
const closure_result_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\entry const answer = func (value: U32) => return do:
    \\  let callback = @effect.scope (func (s: State U32) => return func () => return @u32.add value 1)
    \\  break callback ()
;
fn lowerClosureResultAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, closure_result_source);
    defer module.deinit(allocator);
}
const flow_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const identity = func value => return value
    \\const invoke = func callback => return callback ()
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
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
const task_join_wrapper_source =
    \\const await = func source => return |source|
    \\entry const answer = func () => return @task.scope (func group => return do:
    \\  let pending = @task.spawn group (func () => return 42)
    \\  return await pending)
;
const parameter_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const read = func (s: State a) : a ! {s.get} => return s.get ()
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
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
    \\const apply = func (s: State a) => return func (callback: Unit -> a ! {s.get | e}) => return callback ()
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let (state, result) = do (@effect.state s.get s.set 7):
    \\    break apply s (func () => return s.get ())
    \\  break result
    \\)
;
fn lowerCurriedAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, curried_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerLocalStoreAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").local_store_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerDependentArrowAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").dependent_arrow_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerPairAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").pair_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerSelectionAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").selection_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerParameterFootprintsAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").parameter_footprint_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerParameterInvocationAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").parameter_invocation_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerRecordFootprintsAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").record_footprint_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
fn lowerMemberClosureAndRelease(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, @import("check_effect_tests.zig").member_closure_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
const multi_input_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const apply2 = func callback => return func left => return func right => return callback left right
    \\const read2 = func (left: State U32) => return func (right: State U32) => return do:
    \\  use x <- left.get ()
    \\  use y <- right.get ()
    \\  break @u32.add x y
    \\entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  use outer <- do (@effect.state left.get left.set 7):
    \\    use inner <- do (@effect.state right.get right.set 9):
    \\      break apply2 read2 left right
    \\    let (state, result) = inner
    \\    break result
    \\  let (state, result) = outer
    \\  break result
    \\))
;
fn lowerMultiInput(allocator: std.mem.Allocator) !void {
    var module = try lowerText(allocator, multi_input_source);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{});
}

test "captured scalar call receipts require primitive roles pure rows and owned certificates" {
    var module = try lowerText(a,
        \\const add = func (left: U32) => return func (right: U32) => return @u32.add left right
        \\const make = func (seed: U32) => return func () => return #[@u32.add seed 1]
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
    return std.mem.replaceOwned(u8, allocator, "const forward2 = func callback => return func left => return func right => return apply2 callback left right\n" ++ multi_input_source, "break apply2 read2 left right", "break forward2 read2 left right");
}
fn lowerForwarding(allocator: std.mem.Allocator) !void {
    const text = try forwardingSource(allocator);
    defer allocator.free(text);
    var module = try lowerText(allocator, text);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{});
}
fn projectedSource(allocator: std.mem.Allocator) ![]u8 {
    const wrapped = try std.mem.replaceOwned(u8, allocator, multi_input_source, "entry const answer", "const keep = func callback => return {callback}\nconst make = func () => return keep read2\nentry const answer");
    defer allocator.free(wrapped);
    return std.mem.replaceOwned(u8, allocator, wrapped, "break apply2 read2 left right", "let holder = make ()\n      break apply2 holder.callback left right");
}
fn lowerProjected(allocator: std.mem.Allocator) !void {
    const text = try projectedSource(allocator);
    defer allocator.free(text);
    var module = try lowerText(allocator, text);
    defer module.deinit(allocator);
    try validation.validate(allocator, &module, .{ .units = &.{&module} });
}
