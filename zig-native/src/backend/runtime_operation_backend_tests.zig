const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("core_backend.zig");
const types = @import("../check/types.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    return lowerCatalog(allocator, source, false);
}
fn lowerCatalog(allocator: std.mem.Allocator, source: []const u8, builtin_catalog: bool) !core.Module {
    return lowerCatalogIdentity(allocator, source, builtin_catalog, null);
}
fn lowerCatalogIdentity(allocator: std.mem.Allocator, source: []const u8, builtin_catalog: bool, names: ?*?@import("runtime_identity.zig").Metadata) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = builtin_catalog });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    if (names) |owned| owned.* = try @import("runtime_identity.zig").Metadata.capture(allocator, &pool, &.{.{ .unit = 1, .path = "/semantic-emission/main.blot" }}, 1);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

const provider_source =
    \\effect Read: Unit -> F32
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\const reader = @effect.provider Read (fn () => 1.75)
    \\const state = @effect.state (State.get F32) (State.set F32) 1.75
    \\entry const folded = do reader:
    \\  break Read ()
    \\entry const callback = fn () => do reader:
    \\  break Read ()
    \\entry const answer = fn (value: F32) => do:
    \\  let dynamic = @effect.provider Read (fn () => value)
    \\  let local = @effect.state (State.get F32) (State.set F32) value
    \\  let (next, old) = do state:
    \\    use old <- State.get F32 ()
    \\    use State.set F32 (@f32.add old value)
    \\    break old
    \\  let (_, selected) = do local:
    \\    break State.get F32 ()
    \\  let read = do dynamic:
    \\    break Read ()
    \\  break @f32.add (@f32.add next old) (@f32.add selected read)
;

fn emit(allocator: std.mem.Allocator, module: *const core.Module, noisy: bool) !void {
    var result = try backend.compileWithEvidenceNoise(allocator, &.{module.*}, 1, noisy);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

test "provider State Requests Foreign captures and suspended runtime paths ignore unrelated semantic labels after frontend teardown" {
    const sources = [_][]const u8{
        provider_source,
        @import("fixtures").source("request-fixtures/f32-foreign-nested.blot"),
        @import("fixtures").source("request-fixtures/suspended.blot"),
        @import("fixtures").source("request-fixtures/nested-owner.blot"),
        @import("fixtures").source("request-fixtures/template-wrapped-reuse.blot"),
    };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const types_before = try a.dupe(types.Node, module.types.nodes);
        defer a.free(types_before);
        const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
        defer a.free(rows);
        const labels = try a.dupe(types.Effects.Label, module.types.effects.labels);
        defer a.free(labels);
        var plain = try backend.compile(a, &.{module}, 1);
        defer plain.deinit(a);
        var noisy = try backend.compileWithEvidenceNoise(a, &.{module}, 1, true);
        defer noisy.deinit(a);
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), plain.diagnostic);
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), noisy.diagnostic);
        try std.testing.expectEqualSlices(u8, plain.bytes, noisy.bytes);
        try std.testing.expectEqual(plain.constant_steps, noisy.constant_steps);
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(types_before, module.types.nodes);
        try std.testing.expectEqualDeep(rows, module.types.effects.rows);
        try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
    }
}

test "runtime operation instruction and constant-provider relocation release every failed allocation without changing frozen Core" {
    var module = try lower(a, provider_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const extra = try a.dupe(types.Id, module.types.extra);
    defer a.free(extra);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    const labels = try a.dupe(types.Effects.Label, module.types.effects.labels);
    defer a.free(labels);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, true });
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
    try std.testing.expectEqualDeep(rows, module.types.effects.rows);
    try std.testing.expectEqualSlices(types.Effects.Label, labels, module.types.effects.labels);
}

test "runtime operation separation preserves opaque effect reflection as a compile-only capability" {
    const source =
        \\const read = fn () => 42
        \\const requirements = @effect.of read
        \\const count = fn effects => @effect.count effects
        \\entry const run = fn () => count requirements
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    var plain = try backend.compile(a, &.{module}, 1);
    defer plain.deinit(a);
    var noisy = try backend.compileWithEvidenceNoise(a, &.{module}, 1, true);
    defer noisy.deinit(a);
    try std.testing.expectEqual(backend.Code.backend_const_only, plain.diagnostic.?.code);
    try std.testing.expectEqualDeep(plain.diagnostic, noisy.diagnostic);
    try std.testing.expectEqual(@as(usize, 0), plain.bytes.len);
    try std.testing.expectEqual(@as(usize, 0), noisy.bytes.len);
}

test "runtime operation relocation preserves supported semantic reflection membership and descriptor equality" {
    const source =
        \\type Signal a is effect = { ping: Unit -> U32 }
        \\const read = fn () => do:
        \\  use Signal.ping U32 ()
        \\  use Signal.ping U32 ()
        \\  break Signal.ping F32 ()
        \\const effects = @effect.of read
        \\entry const total = @effect.count effects
        \\entry const present = @effect.has effects (Signal.ping F32)
        \\entry const absent = @effect.has effects (Signal.ping Bool)
        \\entry const same = @effect.same (@effect.descriptor (Signal.ping U32)) (@effect.descriptor (Signal.ping U32))
        \\entry const different = @effect.same (@effect.descriptor (Signal.ping U32)) (@effect.descriptor (Signal.ping F32))
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    var plain = try backend.compile(a, &.{module}, 1);
    defer plain.deinit(a);
    var noisy = try backend.compileWithEvidenceNoise(a, &.{module}, 1, true);
    defer noisy.deinit(a);
    try std.testing.expect(plain.diagnostic == null and noisy.diagnostic == null);
    try std.testing.expectEqualSlices(u8, plain.bytes, noisy.bytes);
    try std.testing.expectEqual(plain.constant_steps, noisy.constant_steps);
}

fn emitProject(allocator: std.mem.Allocator, module: *const core.Module, names: @import("runtime_identity.zig").View) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .identity = names, .evidence_noise = true });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null and result.bytes.len > 8);
}

test "project emission requires complete actual owners and independently solves noisy evidence without changing frozen Core" {
    var module = try lower(a, provider_source);
    defer module.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var names = try @import("runtime_identity.zig").Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/provider.blot" }}, 1);
    defer names.deinit(a);
    var plain = try backend.compileWithIdentity(a, &.{module}, 1, names.view());
    defer plain.deinit(a);
    var noisy = try backend.compileWithOptions(a, &.{module}, 1, .{ .identity = names.view(), .evidence_noise = true });
    defer noisy.deinit(a);
    try std.testing.expect(plain.diagnostic == null and noisy.diagnostic == null);
    try std.testing.expectEqualSlices(u8, plain.bytes, noisy.bytes);
    try std.testing.expectEqual(plain.constant_steps, noisy.constant_steps);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const extra = try a.dupe(types.Id, module.types.extra);
    defer a.free(extra);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitProject, .{ &module, names.view() });
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
    try std.testing.expectEqualDeep(rows, module.types.effects.rows);
    var unowned = module;
    unowned.unit = 0;
    try std.testing.expectError(error.InvalidFunctionReference, backend.compileWithIdentity(a, &.{unowned}, 1, names.view()));
    try std.testing.expectError(error.InvalidFunctionReference, backend.compileWithIdentity(a, &.{ module, module }, 1, names.view()));
}

test "resolved bodies prepare calls fields evidence closures and exits without mutating frozen Core" {
    const source =
        \\const bump = fn (value: U32) => @u32.add value 1
        \\entry const answer = fn (value: U32) => do:
        \\  let row = { value, flag: #True }
        \\  let read = fn () => bump row.value
        \\  let count = 0
        \\  for index in 0..value:
        \\    count := @u32.add self 1
        \\  if @type.same 0 1:
        \\    break read ()
        \\  break count
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitResolvedBody, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
}
fn emitResolvedBody(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.counters.resolved_bodies > 0);
    try std.testing.expect(result.counters.resolved_plan_entries > 0);
    try std.testing.expect(result.counters.resolved_plan_reads > 0);
    try std.testing.expect(result.bytes.len > 8);
}

test "shared RC source collection construction and publication preserve frozen Core through every allocation failure" {
    const source =
        \\entry const answer = fn (value: U32) => do:
        \\  let child = #[value, @u32.add value 1]
        \\  let values = @list.fill 500 child
        \\  let before = values
        \\  values := [child, ...self]
        \\  let copied = @array.from_list values
        \\  let old = @array.from_list before
        \\  copied[0] := #[value, value]
        \\  break @u32.add (@array.get (@array.get old 0) 1) (@array.get (@array.get copied 500) 0)
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitTypedCollections, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
}
fn emitTypedCollections(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    const marker = "blot:ownership";
    const offset = std.mem.findLast(u8, result.bytes, marker) orelse return error.TestExpectedOwnershipManifest;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, result.bytes[offset + marker.len ..][0..3]);
}

// Packed traversal publishes a scalar leaf directory owned by its exact tree.
test "packed List directory emission preserves frozen Core through every allocation failure" {
    const source =
        \\const static = [{ a: 1, b: 2, c: 3 }, { a: 4, b: 5, c: 6 }]
        \\entry const answer = fn (value: U32) => do:
        \\  let rows = @list.fill 600 { a: value, b: value, c: value }
        \\  let saved = rows
        \\  rows := [ { a: value, b: value, c: value }, ...self ]
        \\  let total = 0
        \\  for row in static:
        \\    total := @u32.add (@u32.add (@u32.add self row.a) row.b) row.c
        \\  for row in saved:
        \\    total := @u32.add (@u32.add (@u32.add self row.a) row.b) row.c
        \\  for row in rows:
        \\    total := @u32.add (@u32.add (@u32.add self row.a) row.b) row.c
        \\  break total
        \\entry const float_answer = fn (value: F32) => do:
        \\  let rows = @list.fill 601 { a: value, b: value, c: value, d: value }
        \\  let total = 0.0
        \\  for row in rows:
        \\    total := @f32.add (@f32.add (@f32.add (@f32.add self row.a) row.b) row.c) row.d
        \\  break total
    ;
    var module = try lower(a, source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitResolvedBody, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
}

const constant_getter_source =
    \\const make = fn (seed: Array U32) => fn (value: U32) => @array.get seed value
    \\const saved = make #[7, 42]
    \\entry const run = fn (value: U32) => saved value
    \\entry const pressure = fn (count: U32) => @array.fill count 0
;
fn constantGetter(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    const capture = &result.capture.?;
    var adapters: usize = 0;
    for (capture.metadata.jobs.items) |job| {
        if (job.request != .callable or job.function == null) continue;
        const body = module.body(job.request.callable.target.binding) orelse continue;
        if (body.parameters.len != 0 or body.runtime) continue;
        const function = capture.emission.functions[job.function.?];
        const instructions = capture.emission.instructions[function.instructions.start..][0..function.instructions.len];
        var direct: usize = 0;
        for (instructions) |inst| {
            try std.testing.expect(inst.op != .call_indirect);
            if (inst.op == .call and inst.operand.role == .function) direct += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), direct);
        adapters += 1;
    }
    try std.testing.expect(adapters > 0);
    var replay = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .inline_named = false, .retain_artifacts = true, .previous = capture });
    defer replay.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), replay.diagnostic);
    try std.testing.expectEqualSlices(u8, result.bytes, replay.bytes);
}
test "checked constant callable adapters preserve exact source callee roles and owned replay through OOM" {
    var module = try lower(a, constant_getter_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    try constantGetter(a, &module);
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, constantGetter, .{&module});
}

const retained_demand_source =
    \\const keep = fn ~value => fn () => @demand value
    \\entry const run = fn (host: U32 -> Array U32 ! {Foreign}) => do:
    \\  let delayed = keep (host 41)
    \\  use first <- delayed ()
    \\  use second <- delayed ()
    \\  break @u32.add (@array.get first 0) (@array.get second 0)
;
fn retainedDemand(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    const capture = &result.capture.?;
    const pools = capture.metadata.pools.?;
    var producers: usize = 0;
    for (pools.captures) |template| if (template.demand_cell) {
        try std.testing.expect(template.has_environment and !template.computation);
        try std.testing.expectEqual(core.Tag.suspend_, module.node(template.node).tag);
        producers += 1;
    };
    try std.testing.expect(producers > 0);
    var consumers: usize = 0;
    for (capture.metadata.jobs.items) |job| {
        if (job.request != .named or job.request.named.templates == 0 or job.function == null) continue;
        const function = capture.emission.functions[job.function.?];
        const instructions = capture.emission.instructions[function.instructions.start..][0..function.instructions.len];
        var direct: usize = 0;
        for (instructions) |inst| {
            try std.testing.expect(inst.op != .call_indirect);
            if (inst.op == .call and inst.operand.role == .function) direct += 1;
        }
        try std.testing.expect(direct > 0);
        consumers += 1;
    }
    try std.testing.expect(consumers > 0);
    var replay = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .inline_named = false, .retain_artifacts = true, .previous = capture });
    defer replay.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), replay.diagnostic);
    try std.testing.expectEqualSlices(u8, result.bytes, replay.bytes);
}
test "checked retained demand producer descriptors preserve the same memo cell and exact owned replay through OOM" {
    var module = try lower(a, retained_demand_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    try retainedDemand(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, retainedDemand, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
}

fn checkProviderFlow(allocator: std.mem.Allocator, module: *const @import("wasm.zig").Module) !void {
    try std.testing.expect(try @import("provider_flow.zig").complete(allocator, module));
}
fn providerMutants(module: *@import("wasm.zig").Module) !void {
    const ir = @import("runtime_ir.zig");
    const flow = @import("provider_flow.zig");
    const origins = @import("provider_origins.zig");
    var changed_interface = false;
    var changed_read = false;
    var changed_guard = false;
    var changed_constructor = false;
    for (module.functions.items, 0..) |*body, function_id| {
        if (module.runtimeHelper(function_id)) continue;
        if (!changed_interface and body.provider_parameter == 2 and body.parameters.len == 3 and body.parameterRole(0) == .reference) {
            body.provider_parameter = 0;
            try std.testing.expect(!try flow.complete(a, module));
            body.provider_parameter = 2;
            changed_interface = true;
        }
        for (body.instructions.items, 0..) |*inst, at| {
            if (!changed_read and body.provider_parameter == 2 and inst.op == .i32_load and inst.operand == 12) {
                inst.operand = 20;
                try std.testing.expect(!try flow.complete(a, module));
                inst.operand = 12;
                changed_read = true;
            }
            if (!changed_guard and inst.op == .unreachable_ and at >= 3 and at + 1 < body.instructions.items.len) {
                const guard = body.instructions.items[at - 3 .. at + 2];
                if (guard[0].op == .local_get and guard[1].op == .i32_eqz and guard[2].op == .if_ and guard[2].operand == 0 and guard[4].op == .end) {
                    inst.op = .nop;
                    try std.testing.expect(!try flow.complete(a, module));
                    inst.op = .unreachable_;
                    changed_guard = true;
                }
            }
            if (changed_constructor or inst.op != .ownership) continue;
            const marker: ir.Ownership = @bitCast(inst.operand);
            if (marker.kind != .rest or marker.chunk != origins.begin_chunk) continue;
            const fact = origins.constructor(module, body, at).?;
            if (fact.kind != 4) continue;
            const place = fact.end + 1;
            try body.instructions.insertSlice(a, place, &.{ .{ .op = .local_get, .operand = fact.local }, .{ .op = .i32_const }, .{ .op = .i32_store, .operand = 12 } });
            try std.testing.expect(!try flow.complete(a, module));
            std.mem.copyForwards(ir.Instruction, body.instructions.items[place..], body.instructions.items[place + 3 ..]);
            body.instructions.shrinkRetainingCapacity(body.instructions.items.len - 3);
            const forged_address = [_]ir.Instruction{ .{ .op = .i32_const, .operand = 160 }, .{ .op = .i32_const }, .{ .op = .i32_store, .operand = 12 } };
            try body.instructions.insertSlice(a, place, &forged_address);
            try std.testing.expect(!try flow.complete(a, module));
            std.mem.copyForwards(ir.Instruction, body.instructions.items[place..], body.instructions.items[place + forged_address.len ..]);
            body.instructions.shrinkRetainingCapacity(body.instructions.items.len - forged_address.len);
            // The mutable value field remains legal; an escaped head in an
            // ordinary source graph cannot gain provider-head authority.
            try body.instructions.insertSlice(a, place, &.{ .{ .op = .local_get, .operand = fact.local }, .{ .op = .i32_const }, .{ .op = .i32_store, .operand = 4 } });
            try checkProviderFlow(a, module);
            std.mem.copyForwards(ir.Instruction, body.instructions.items[place..], body.instructions.items[place + 3 ..]);
            body.instructions.shrinkRetainingCapacity(body.instructions.items.len - 3);
            const graph: u32 = @intCast(body.parameters.len + body.locals.items.len);
            try body.locals.append(a, .i32);
            const escaped = [_]ir.Instruction{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .call, .operand = module.arena.?.allocate }, .{ .op = .local_set, .operand = graph }, .{ .op = .local_get, .operand = graph }, .{ .op = .local_get, .operand = fact.local }, .{ .op = .i32_store } };
            try body.instructions.insertSlice(a, place, &escaped);
            try std.testing.expect(!try flow.complete(a, module));
            std.mem.copyForwards(ir.Instruction, body.instructions.items[place..], body.instructions.items[place + escaped.len ..]);
            body.instructions.shrinkRetainingCapacity(body.instructions.items.len - escaped.len);
            body.locals.shrinkRetainingCapacity(body.locals.items.len - 1);
            changed_constructor = true;
            break;
        }
    }
    try std.testing.expect(changed_interface and changed_read and changed_guard and changed_constructor);
    var rejected_borrowed_release = false;
    for (module.functions.items, 0..) |*body, id| {
        if (module.runtimeHelper(id) or body.provider_parameter == ir.unknown_provider or body.provider_parameter == ir.no_provider) continue;
        try body.instructions.insertSlice(a, 0, &.{
            .{ .op = .local_get, .operand = body.provider_parameter },
            .{ .op = .call, .operand = module.arena.?.release },
        });
        const rejected = !try flow.complete(a, module);
        _ = body.instructions.orderedRemove(0);
        _ = body.instructions.orderedRemove(0);
        try std.testing.expect(rejected);
        try body.instructions.insert(a, 0, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 6, .roles = body.provider_parameter }) });
        const rejected_force = !try flow.complete(a, module);
        _ = body.instructions.orderedRemove(0);
        try std.testing.expect(rejected_force);
        rejected_borrowed_release = true;
        break;
    }
    try std.testing.expect(rejected_borrowed_release);
    try checkProviderFlow(a, module);
}
fn providerConstruction(allocator: std.mem.Allocator, source: *const core.Module, expect_flow: bool) !void {
    const origins = @import("provider_origins.zig");
    var result = try backend.compileWithOptions(allocator, &.{source.*}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    const capture = &result.capture.?;
    var module = try capture.emission.materialize(allocator);
    defer module.deinit();
    if (expect_flow) {
        try checkProviderFlow(allocator, &module);
        try providerMutants(&module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, checkProviderFlow, .{&module});
    }
    var count: usize = 0;
    for (module.functions.items) |*body| {
        try std.testing.expect(body.validProviderParameter());
        for (body.instructions.items, 0..) |inst, at| {
            if (inst.op != .ownership) continue;
            const marker: @import("runtime_ir.zig").Ownership = @bitCast(inst.operand);
            if (marker.kind != .rest or marker.chunk != origins.begin_chunk) continue;
            try std.testing.expect(origins.constructor(&module, body, at) != null);
            count += 1;
        }
    }
    try std.testing.expect(count > 0);
    var replay = try backend.compileWithOptions(allocator, &.{source.*}, 1, .{ .inline_named = false, .retain_artifacts = true, .previous = capture });
    defer replay.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), replay.diagnostic);
    try std.testing.expectEqualSlices(u8, result.bytes, replay.bytes);
}
test "symbolic provider constructors rederive physical State callback and Request initializers through owned replay" {
    const sources = [_][]const u8{ provider_source, @import("fixtures").source("request-fixtures/f32-foreign-nested.blot") };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try providerConstruction(a, &module, false);
    }
}
test "private State provider heads stay outside source Array graphs across direct and checked table callees" {
    var module = try lower(a,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\entry const run = fn (seed: U32) => do:
        \\  let local = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[seed]
        \\  let (_, result) = do local:
        \\    break State.get (Array U32) ()
        \\  break result[0]
    );
    defer module.deinit(a);
    try providerConstruction(a, &module, true);
}
test "private provider flow covers captured request cancellation and memoized source cycle bodies" {
    var module = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer module.deinit(a);
    try providerConstruction(a, &module, true);
}

fn checkProviderModes(allocator: std.mem.Allocator, module: *const @import("wasm.zig").Module) !void {
    const modes = @import("provider_modes.zig");
    var catalog = try modes.Catalog.init(allocator, module);
    defer catalog.deinit(allocator);
    var reads: usize = 0;
    var writes: usize = 0;
    for (catalog.entries.items) |mode| {
        reads += @intFromBool(mode.access == .read);
        writes += @intFromBool(mode.access == .write);
    }
    try std.testing.expect(reads > 0 and writes > 0);
    var getters: usize = 0;
    for (module.functions.items) |*body| {
        const mode = modes.readOperation(&catalog, body) orelse continue;
        var projection = (try modes.specialize(allocator, &catalog, body)).?;
        defer projection.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 49), projection.instructions.items.len);
        var view = body.*;
        view.locals = projection.locals;
        view.instructions = projection.instructions;
        var rooted = (try @import("root_lowering.zig").runBorrowed(allocator, module, &view, true, false, false, true)).?;
        defer rooted.deinit(allocator);
        const arena = module.arena.?;
        var publication: ?usize = null;
        var safe: ?usize = null;
        for (rooted.instructions.items, 0..) |inst, at| {
            if (inst.op != .call) continue;
            try std.testing.expect(inst.operand != arena.root_open and inst.operand != arena.root_close);
            if (inst.operand == arena.root_store) publication = at;
            if (inst.operand == arena.cycle_safe) safe = at;
        }
        try std.testing.expect(safe != null);
        if (mode.role == .reference) try std.testing.expect(publication != null and publication.? < safe.?) else try std.testing.expect(publication == null);
        for (catalog.entries.items) |*item| if (item.operation == mode.operation) {
            const saved = item.*;
            item.access = .unsupported;
            try std.testing.expect(modes.readOperation(&catalog, body) == null);
            item.* = saved;
        };
        var poison = body.*;
        var instructions = try allocator.dupe(@import("runtime_ir.zig").Instruction, body.instructions.items);
        defer allocator.free(instructions);
        poison.instructions = .fromOwnedSlice(instructions);
        instructions[42].operand = 12;
        try std.testing.expect(modes.readOperation(&catalog, &poison) == null);
        instructions[42].operand = 4;
        instructions[7].op = .nop;
        try std.testing.expect(modes.readOperation(&catalog, &poison) == null);
        getters += 1;
    }
    try std.testing.expect(getters > 0);
}

test "State-only operation modes preserve result publication before collector safepoints and reject field or guard forgeries through OOM" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var result = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    var module = try result.capture.?.emission.materialize(a);
    defer module.deinit();
    try checkProviderModes(a, &module);
    var session = try @import("runtime_pipeline.zig").Session.init(a, &module);
    defer session.deinit();
    for (module.functions.items, 0..) |*body, id| {
        if (@import("provider_modes.zig").readOperation(&session.providers, body) == null) continue;
        const summary = session.summaries.functions[id];
        try std.testing.expect(!summary.invalidates);
        try std.testing.expect(!summary.parameters[body.provider_parameter].escapes);
        try std.testing.expectEqual(@as(u32, 20), summary.parameters[body.provider_parameter].bytes);
    }
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkProviderModes, .{&module});
    const archive = @import("../reuse/optimized_archive.zig");
    const captured = &result.capture.?.optimized.?;
    const bytes = try archive.encode(a, @splat(35), captured);
    defer a.free(bytes);
    var loaded = try archive.decode(a, @splat(35), bytes);
    defer loaded.deinit();
    try std.testing.expectEqualDeep(captured.providers.items, loaded.providers.items);
    try std.testing.expect(loaded.providers.items.len > 0);
    var changed_mode = false;
    for (loaded.providers.items) |*mode| if (mode.access == .read) {
        mode.access = .unsupported;
        changed_mode = true;
        break;
    };
    try std.testing.expect(changed_mode);
    var matcher = try @import("optimized_bodies.zig").Matcher.init(a, &loaded, captured);
    defer matcher.deinit();
    for (captured.entries.items, 0..) |_, id| try std.testing.expect(!matcher.matches(id));
}

fn stateWriteMutants(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder, machine: @import("runtime_ir.zig").ValueType) !void {
    const modes = @import("provider_modes.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var catalog = try modes.Catalog.init(allocator, &module);
    defer catalog.deinit(allocator);
    var matched = false;
    for (module.functions.items) |*body| {
        const mode = modes.writeOperation(&module, &catalog, body) orelse continue;
        try std.testing.expectEqual(machine, mode.machine);
        const original = body.instructions;
        var changed = try original.clone(allocator);
        defer changed.deinit(allocator);
        body.instructions = changed;
        defer body.instructions = original;
        for ([_]struct { at: usize, operand: u32 }{
            .{ .at = 15, .operand = 8 }, // exact kind guard
            .{ .at = 26, .operand = 4 }, // lookup must traverse next, not value
            .{ .at = 44, .operand = 2 }, // owning store uses selected frame
            .{ .at = 45, .operand = 8 }, // exact value slot
            .{ .at = 47, .operand = 0 }, // actual argument, not closure env
        }) |mutation| {
            changed.items[mutation.at].operand = mutation.operand;
            try std.testing.expect(modes.writeOperation(&module, &catalog, body) == null);
            changed.items[mutation.at] = original.items[mutation.at];
        }
        var publication: usize = 48;
        if (mode.machine == .f32) {
            changed.items[48].op = .nop;
            try std.testing.expect(modes.writeOperation(&module, &catalog, body) == null);
            changed.items[48] = original.items[48];
            publication += 1;
        }
        changed.items[publication].operand = module.arena.?.copy_words;
        try std.testing.expect(modes.writeOperation(&module, &catalog, body) == null);
        changed.items[publication] = original.items[publication];
        for (catalog.entries.items) |*entry| {
            if (entry.operation != mode.operation) continue;
            const saved = entry.*;
            entry.access = .unsupported;
            try std.testing.expect(modes.writeOperation(&module, &catalog, body) == null);
            entry.* = saved;
            entry.role = .unknown;
            try std.testing.expect(modes.writeOperation(&module, &catalog, body) == null);
            entry.* = saved;
        }
        try std.testing.expectEqualDeep(mode, modes.writeOperation(&module, &catalog, body).?);
        matched = true;
    }
    try std.testing.expect(matched);
}
test "State write graph edges require exact receiver slot input type and owning publication through OOM" {
    for ([_][]const u8{ @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), provider_source }, [_]@import("runtime_ir.zig").ValueType{ .i32, .f32 }) |text, machine| {
        var source = try lowerCatalog(a, text, true);
        defer source.deinit(a);
        var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
        defer built.deinit(a);
        try stateWriteMutants(a, &built.capture.?.emission, machine);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stateWriteMutants, .{ &built.capture.?.emission, machine });
    }
}

fn callableReplay(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var constructions: usize = 0;
    for (module.table_origins.items) |origin| {
        if (origin.kind == .unknown) continue;
        const fact = @import("callable_origins.zig").construction(&module, origin).?;
        try std.testing.expectEqual(origin.target, fact.target);
        try std.testing.expectEqual(@import("callable_origins.zig").constructionLayout(&module, origin).?, fact.layout);
        try std.testing.expectEqual(@as(u32, if (origin.kind == .callable) 8 else 16), fact.bytes);
        if (origin.function) |id| {
            try std.testing.expect(fact.local != null and fact.allocation != null);
            try std.testing.expect(fact.end <= module.functions.items[id].instructions.items.len);
            try std.testing.expect(fact.allocation.? < origin.place and origin.place < fact.end);
        } else {
            try std.testing.expect(fact.local == null and fact.allocation == null);
            try std.testing.expectEqual(origin.place + 4, fact.environment.data_word);
        }
        constructions += 1;
    }
    try std.testing.expect(constructions > 0);
}
test "callable construction edges rederive exact Memo closure environments without granting later immutability" {
    const ir = @import("runtime_ir.zig");
    const origins = @import("callable_origins.zig");
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    var module = try built.capture.?.emission.materialize(a);
    defer module.deinit();
    var closure_edge = false;
    var memo_edge = false;
    for (module.table_origins.items) |origin| {
        if (origin.kind == .unknown or origin.function == null) continue;
        const fact = origins.construction(&module, origin).?;
        const body = &module.functions.items[origin.function.?];
        const before = try a.dupe(ir.Instruction, body.instructions.items);
        defer a.free(before);
        const environment_at = origin.place + 3;
        switch (fact.environment) {
            .local => |local| {
                if (origin.kind != .callable or local >= body.parameters.len) continue;
                try std.testing.expectEqual(ir.Role.reference, body.parameterRole(local));
                try std.testing.expectEqual(ir.Op.local_get, before[environment_at].op);
                try std.testing.expectEqual(local, before[environment_at].operand);
                // Same i32 machine word, different checked parameter role.
                {
                    const original = body.parameter_roles;
                    defer body.parameter_roles = original;
                    const shift: u6 = @intCast(local * 2);
                    body.parameter_roles = (original & ~(@as(u64, 3) << shift)) | (@as(u64, @backingInt(ir.Role.scalar)) << shift);
                    try std.testing.expect(origins.construction(&module, origin) == null);
                }
                body.instructions.items[environment_at].operand = fact.local.?;
                try std.testing.expect(origins.construction(&module, origin) == null);
                body.instructions.items[environment_at] = before[environment_at];
                closure_edge = true;
            },
            .zero => {
                if (origin.kind != .demand) continue;
                try std.testing.expectEqual(@as(u32, 16), fact.bytes);
                body.instructions.items[environment_at].operand = 1;
                try std.testing.expect(origins.construction(&module, origin) == null);
                body.instructions.items[environment_at] = before[environment_at];
                // Status and cached-result words are creation-time zeros.
                for ([_]usize{ environment_at + 3, environment_at + 6 }) |at| {
                    body.instructions.items[at].operand = 1;
                    try std.testing.expect(origins.construction(&module, origin) == null);
                    body.instructions.items[at] = before[at];
                }
                memo_edge = true;
            },
            .data_word => return error.UnexpectedDynamicDataWord,
        }
        body.instructions.items[origin.place].operand ^= 1;
        try std.testing.expect(origins.construction(&module, origin) == null);
        body.instructions.items[origin.place] = before[origin.place];
        body.instructions.items[environment_at + 1].operand = 0;
        try std.testing.expect(origins.construction(&module, origin) == null);
        body.instructions.items[environment_at + 1] = before[environment_at + 1];
        try std.testing.expectEqualSlices(ir.Instruction, before, body.instructions.items);
        // An initial edge is still only an initial edge. A later code write
        // must be seen by the future heap-flow proof, not hidden in this fact.
        var changed: std.ArrayList(ir.Instruction) = .empty;
        defer changed.deinit(a);
        try changed.appendSlice(a, before);
        try changed.appendSlice(a, &.{ .{ .op = .local_get, .operand = fact.local.? }, .{ .op = .i32_const }, .{ .op = .i32_store } });
        {
            const original = body.instructions;
            body.instructions = changed;
            defer body.instructions = original;
            try std.testing.expectEqualDeep(fact, origins.construction(&module, origin).?);
        }
    }
    try std.testing.expect(closure_edge and memo_edge);
    try callableReplay(a, &built.capture.?.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, callableReplay, .{&built.capture.?.emission});
}
fn callableResultMutants(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    const origins = @import("callable_origins.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var matched = false;
    for (module.functions.items, 0..) |*body, id| {
        const fact = origins.resultConstruction(&module, @intCast(id)) orelse continue;
        if (fact.kind != .callable or fact.environment != .local) continue;
        try std.testing.expect(fact.environment.local < body.parameters.len);
        try std.testing.expectEqual(@as(u32, 1), fact.environment.local);
        {
            const machine = &body.locals.items[fact.local.? - body.parameters.len];
            const saved = machine.*;
            defer machine.* = saved;
            machine.* = .f32;
            try std.testing.expect(origins.resultConstruction(&module, @intCast(id)) == null);
        }
        const original = body.instructions;
        defer body.instructions = original;
        var changed = try original.clone(allocator);
        defer changed.deinit(allocator);
        body.instructions = changed;
        // Returning the capture rather than the new closure is a different
        // owner/result relationship despite the same reference machine type.
        changed.items[fact.end].operand = fact.environment.local;
        try std.testing.expect(origins.resultConstruction(&module, @intCast(id)) == null);
        changed.items[fact.end] = original.items[fact.end];
        // A later mutable field or opaque call cannot disappear from the
        // result graph simply because the first initializer was recognized.
        for ([_]@import("runtime_ir.zig").Instruction{
            .{ .op = .i32_store },
            .{ .op = .call_import },
            .{ .op = .global_set },
            .{ .op = .return_ },
        }) |extra| {
            try changed.append(allocator, extra);
            body.instructions = changed;
            if (extra.op == .return_) {
                try std.testing.expectEqualDeep(fact, origins.resultConstruction(&module, @intCast(id)).?);
                try changed.append(allocator, .{ .op = .nop });
                body.instructions = changed;
            }
            try std.testing.expect(origins.resultConstruction(&module, @intCast(id)) == null);
            changed.shrinkRetainingCapacity(original.items.len);
            body.instructions = changed;
        }
        try std.testing.expectEqualDeep(fact, origins.resultConstruction(&module, @intCast(id)).?);
        matched = true;
    }
    try std.testing.expect(matched);
}
test "callable result ownership edges reject changed returns later stores and opaque sinks through OOM" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    try callableResultMutants(a, &built.capture.?.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, callableResultMutants, .{&built.capture.?.emission});
}
fn demandOutcomeMutants(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder, guarded: bool) !void {
    const origins = @import("../eval/demand_origins.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var matched = false;
    for (module.functions.items, 0..) |*body, id| {
        const fact = origins.force(&module, @intCast(id)) orelse continue;
        try std.testing.expectEqual(guarded, fact.guard_global != null);
        try std.testing.expectEqual(@as(u32, 0), fact.cell_parameter);
        try std.testing.expectEqual(@as(u32, 2), fact.provider_parameter);
        try std.testing.expect(fact.producer_call < fact.cache_publication and fact.cache_publication < fact.ready_publication);
        var constructed = false;
        for (module.table_origins.items) |origin| {
            if (origin.kind != .demand or origin.target != fact.producer) continue;
            try std.testing.expect(@import("callable_origins.zig").construction(&module, origin) != null);
            constructed = true;
        }
        try std.testing.expect(constructed);
        const original = body.instructions;
        defer body.instructions = original;
        var changed = try original.clone(allocator);
        defer changed.deinit(allocator);
        body.instructions = changed;
        const mutations = [_]struct { at: usize, operand: u32 }{
            .{ .at = 4, .operand = 3 }, // terminal must never become ready
            .{ .at = 16, .operand = 0 }, // force owner before evaluation
            .{ .at = 26, .operand = 0 }, // actual provider argument
            .{ .at = fact.cache_publication - 3, .operand = 4 }, // cache field
            .{ .at = fact.cache_publication - 1, .operand = 3 }, // result owner
            .{ .at = fact.ready_publication - 1, .operand = 1 }, // publication state
            .{ .at = original.items.len - 1, .operand = 3 }, // final cached return
        };
        for (mutations) |mutation| {
            changed.items[mutation.at].operand = mutation.operand;
            try std.testing.expect(origins.force(&module, @intCast(id)) == null);
            changed.items[mutation.at] = original.items[mutation.at];
        }
        if (fact.guard_global) |global| {
            changed.items[35].operand = 2;
            try std.testing.expect(origins.force(&module, @intCast(id)) == null);
            changed.items[35] = original.items[35];
            const mutable = module.globals.items[global].mutable;
            module.globals.items[global].mutable = false;
            const rejected = origins.force(&module, @intCast(id)) == null;
            module.globals.items[global].mutable = mutable;
            try std.testing.expect(rejected);
        }
        {
            const producer = &module.functions.items[fact.producer];
            const role = producer.result_role;
            producer.result_role = .scalar;
            const rejected = origins.force(&module, @intCast(id)) == null;
            producer.result_role = role;
            try std.testing.expect(rejected);
        }
        // A valid producer edit updates the executable edge; no stale table
        // descriptor or equal machine ABI can preserve the previous target.
        var edited = false;
        for (module.functions.items, 0..) |candidate, target| {
            if (target == fact.producer or target == id or module.runtimeHelper(target) or candidate.entry or candidate.result != body.result or candidate.result_role != body.result_role or candidate.provider_parameter != 2 or candidate.parameter_roles != body.parameter_roles or !std.mem.eql(@import("runtime_ir.zig").ValueType, candidate.parameters, body.parameters)) continue;
            changed.items[fact.producer_call].operand = @intCast(target);
            try std.testing.expectEqual(@as(u32, @intCast(target)), origins.force(&module, @intCast(id)).?.producer);
            changed.items[fact.producer_call] = original.items[fact.producer_call];
            edited = true;
            break;
        }
        try std.testing.expect(edited);
        try std.testing.expectEqualDeep(fact, origins.force(&module, @intCast(id)).?);
        matched = true;
    }
    try std.testing.expect(matched);
}
test "stored Memo outcome edges rederive cache readiness producer and cancellation ordering through OOM" {
    const full = @import("fixtures").source("provider-fixtures/lifetime-cost.blot");
    const state_start = std.mem.find(u8, full, "type State").?;
    for ([_][]const u8{ full, full[state_start..] }, [_]bool{ true, false }) |text, guarded| {
        var source = try lowerCatalog(a, text, true);
        defer source.deinit(a);
        var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
        defer built.deinit(a);
        try demandOutcomeMutants(a, &built.capture.?.emission, guarded);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, demandOutcomeMutants, .{ &built.capture.?.emission, guarded });
    }
}
fn activationReach(sites: []const @import("activation_graph.zig").Site, initial: u64) u64 {
    var seen = initial;
    for (0..64) |_| {
        var next = seen;
        var pending = seen;
        while (pending != 0) {
            const id: usize = @intCast(@ctz(pending));
            pending &= pending - 1;
            next |= sites[id].children;
        }
        if (next == seen) return seen;
        seen = next;
    }
    return seen;
}
fn closedCycleGraph(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    const flow = @import("activation_graph.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var matched = false;
    var outer_epoch = false;
    for (module.functions.items, 0..) |body, id| {
        if (body.entry or body.provider_parameter != 1 or body.result_role != .scalar or body.parameter_roles != @import("runtime_ir.zig").packParameterRoles(&.{ .scalar, .reference })) continue;
        var graph = try flow.analyze(allocator, &module, @intCast(id));
        defer graph.deinit(allocator);
        if (!graph.complete) {
            outer_epoch = outer_epoch or graph.blocker == .epoch;
            continue;
        }
        var memo: usize = 0;
        var closures: usize = 0;
        for (graph.sites, 0..) |site, at| {
            memo += @intFromBool(site.kind == .memo);
            closures += @intFromBool(site.kind == .closure);
            if (site.kind != .memo) continue;
            const bit = @as(u64, 1) << @intCast(at);
            var reachable = activationReach(graph.sites, bit);
            var members: u64 = 0;
            var bytes: u32 = 0;
            while (reachable != 0) {
                const child: u6 = @intCast(@ctz(reachable));
                reachable &= reachable - 1;
                if (activationReach(graph.sites, @as(u64, 1) << child) & bit == 0) continue;
                members |= @as(u64, 1) << child;
                bytes += graph.sites[child].bytes;
            }
            try std.testing.expectEqual(@as(u32, 3), @popCount(members));
            try std.testing.expectEqual(@as(u32, 32), bytes);
            var member_bits = members;
            var owner: ?u64 = null;
            while (member_bits != 0) {
                const member: u6 = @intCast(@ctz(member_bits));
                member_bits &= member_bits - 1;
                const provider = graph.sites[member].provider;
                try std.testing.expectEqual(@as(u32, 1), @popCount(provider));
                try std.testing.expectEqual(flow.Kind.frame, graph.sites[@intCast(@ctz(provider))].kind);
                if (owner) |expected| try std.testing.expectEqual(expected, provider) else owner = provider;
            }
            var cache_store = false;
            var installed_store = false;
            for (graph.stores) |store| {
                try std.testing.expect(store.context < graph.contexts.len);
                try std.testing.expectEqual(store.function, graph.contexts[store.context].function);
                cache_store = cache_store or (store.owners & bit != 0 and store.offset == 12 and store.values & members != 0);
                installed_store = installed_store or (store.owners & owner.? != 0 and store.offset == 4 and store.values & members != 0);
            }
            try std.testing.expect(cache_store and installed_store);
            // Current State contents differ from retained write history. The
            // post-run tuple may carry End, never the old cyclic Node.
            for (graph.stores) |store| {
                if (store.owners & (members | owner.?) != 0) continue;
                try std.testing.expectEqual(@as(u64, 0), store.values & members);
            }
        }
        try std.testing.expect(memo > 0 and closures > 0);
        var cohort = (try flow.cohort(allocator, &module, @intCast(id))).?;
        defer cohort.deinit(allocator);
        try std.testing.expectEqual(@as(u32, 3), @popCount(cohort.members));
        matched = true;
    }
    try std.testing.expect(matched and outer_epoch);
}
test "closed cycle activation graph composes executable constructors State cache and finite callees" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    try closedCycleGraph(a, &built.capture.?.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, closedCycleGraph, .{&built.capture.?.emission});
}
fn activationRejects(allocator: std.mem.Allocator, module: *const @import("wasm.zig").Module, boundary: u32, reason: @import("activation_graph.zig").Blocker) !void {
    var graph = try @import("activation_graph.zig").analyze(allocator, module, boundary);
    defer graph.deinit(allocator);
    try std.testing.expect(!graph.complete);
    try std.testing.expectEqual(reason, graph.blocker);
}
fn activationMutants(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    const ir = @import("runtime_ir.zig");
    const flow = @import("activation_graph.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var boundary: ?u32 = null;
    var memo_site: ?flow.Site = null;
    var factory: ?u32 = null;
    var witness: ?u32 = null;
    for (module.functions.items, 0..) |body, id| {
        if (body.entry or body.provider_parameter != 1 or body.result_role != .scalar or body.parameter_roles != ir.packParameterRoles(&.{ .scalar, .reference })) continue;
        var graph = try flow.analyze(allocator, &module, @intCast(id));
        defer graph.deinit(allocator);
        if (!graph.complete) continue;
        boundary = @intCast(id);
        for (graph.sites) |site| if (site.kind == .memo) {
            memo_site = site;
        };
        for (graph.sites) |site| if (site.kind == .closure and @import("callable_origins.zig").resultConstruction(&module, site.function) != null) {
            factory = site.function;
        };
        for (module.table_origins.items) |origin| {
            if (origin.function != null or module.functions.items[origin.target].parameters.len != 3) continue;
            var used = false;
            for (graph.calls) |call| used = used or call.target == origin.target;
            if (!used) witness = origin.target;
        }
    }
    try std.testing.expect(boundary != null and memo_site != null and factory != null and witness != null);
    const body = &module.functions.items[boundary.?];
    // The machine result and declared scalar role cannot hide a heap pointer.
    var changed_return = false;
    var at = body.instructions.items.len;
    while (at != 0) {
        at -= 1;
        if (body.instructions.items[at].op != .i32_load) continue;
        const original = body.instructions.items[at];
        body.instructions.items[at].operand = 0;
        try activationRejects(allocator, &module, boundary.?, .escape);
        body.instructions.items[at] = original;
        changed_return = true;
        break;
    }
    try std.testing.expect(changed_return);
    // Scalar allocation cannot conceal reference layout slots.
    const allocation = &module.functions.items[memo_site.?.function].instructions.items[memo_site.?.at];
    const original_allocation = allocation.*;
    allocation.operand = module.arena.?.allocate_scalar;
    try activationRejects(allocator, &module, boundary.?, .instruction);
    allocation.* = original_allocation;
    // An executable Foreign sink remains a blocker even for a scalar boundary.
    var foreign = false;
    for (module.functions.items, 0..) |_, id| {
        const force = @import("../eval/demand_origins.zig").force(&module, @intCast(id)) orelse continue;
        const producer = &module.functions.items[force.producer];
        for (producer.instructions.items) |*inst| {
            if (inst.op != .call) continue;
            const original = inst.*;
            inst.op = .call_import;
            inst.operand = 0;
            try activationRejects(allocator, &module, boundary.?, .boundary);
            inst.* = original;
            foreign = true;
            break;
        }
        if (foreign) break;
    }
    try std.testing.expect(foreign);
    // A factory used outside the activation cannot share raw grouped stores.
    const outside = &module.functions.items[witness.?];
    const original = outside.instructions;
    defer outside.instructions = original;
    var replacement: std.ArrayList(ir.Instruction) = .empty;
    defer replacement.deinit(allocator);
    try replacement.appendSlice(allocator, &.{ .{ .op = .local_get }, .{ .op = .i32_const }, .{ .op = .local_get, .operand = 2 }, .{ .op = .call, .operand = factory.? }, .{ .op = .drop }, .{ .op = .i32_const } });
    outside.instructions = replacement;
    try activationRejects(allocator, &module, boundary.?, .caller);
}
test "closed activation graph rejects disguised result owners scalar allocation Foreign sinks and outside factory callers" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    try activationMutants(a, &built.capture.?.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, activationMutants, .{&built.capture.?.emission});
}
fn cohortLifetimeMutants(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    const flow = @import("activation_graph.zig");
    const ir = @import("runtime_ir.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var checked = false;
    for (module.functions.items, 0..) |body, boundary| {
        if (body.entry or body.provider_parameter != 1 or body.result_role != .scalar or body.parameter_roles != ir.packParameterRoles(&.{ .scalar, .reference })) continue;
        var cohort = (try flow.cohort(allocator, &module, @intCast(boundary))) orelse continue;
        defer cohort.deinit(allocator);
        var node: ?flow.Site = null;
        for (cohort.graph.sites, 0..) |site, id| if (cohort.members & (@as(u64, 1) << @intCast(id)) != 0 and site.kind == .ordinary) {
            node = site;
        };
        const site = node.?;
        const callback = &module.functions.items[site.function];
        const assigned = callback.instructions.items[site.at + 1];
        try std.testing.expectEqual(ir.Op.local_set, assigned.op);
        var changed = false;
        for (callback.instructions.items, 0..) |*inst, at| {
            if (inst.op != .i32_const or (!ir.hasImmortalReference(callback.instructions.items, at) and ir.staticConstructor(callback.instructions.items, at) == null)) continue;
            const original = inst.*;
            // Retaining Node in State carries a member into the boundary's
            // older post-run tuple, even though the eventual result is scalar.
            inst.* = .{ .op = .local_get, .operand = assigned.operand };
            var report = try flow.analyze(allocator, &module, @intCast(boundary));
            defer report.deinit(allocator);
            try std.testing.expect(report.complete);
            var rejected = try flow.cohort(allocator, &module, @intCast(boundary));
            defer if (rejected) |*owned| owned.deinit(allocator);
            try std.testing.expect(rejected == null);
            inst.* = original;
            changed = true;
            break;
        }
        try std.testing.expect(changed);
        checked = true;
    }
    try std.testing.expect(checked);
}
test "cohort owner ordering rejects retained member result roots after State clear edits" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    try cohortLifetimeMutants(a, &built.capture.?.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, cohortLifetimeMutants, .{&built.capture.?.emission});
}
fn cohortAssembly(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder, model: @import("activation_intersection.zig").Model) !void {
    const ir = @import("runtime_ir.zig");
    var source = try journal.materialize(allocator);
    defer source.deinit();
    var matched = false;
    for (source.functions.items, 0..) |body, boundary| {
        if (body.entry or body.provider_parameter != 1 or body.result_role != .scalar or body.parameter_roles != ir.packParameterRoles(&.{ .scalar, .reference })) continue;
        var candidate = (try @import("cohort_candidate.zig").checked(allocator, &source, model, @intCast(boundary))) orelse continue;
        defer candidate.deinit();
        try std.testing.expect(try @import("provider_flow.zig").complete(allocator, &candidate.module));
        try std.testing.expect(try @import("provider_flow.zig").protectedActivations(allocator, &candidate.module));
        var rejection: @import("wasm.zig").OwnershipFailure = .{};
        const bytes = try candidate.module.assembleCheckedWithOptions(.{ .rejection = &rejection });
        defer allocator.free(bytes);
        try std.testing.expect(bytes.len != 0);
        const ordinary = try source.assembleCheckedWithOptions(.{});
        defer allocator.free(ordinary);
        try std.testing.expectEqual(@import("wasm.zig").OwnershipFallback.none, rejection.fallback);
        try std.testing.expect(source.cohorts == null and source.functions.items.len + 3 == candidate.module.functions.items.len);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, cohortConstruction, .{ &source, @as(u32, @intCast(boundary)) });
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, cohortPreparation, .{ &candidate.module, @as(u32, @intCast(boundary)) });
        for (candidate.owned, 0..) |owned, id| {
            if (!owned or id == boundary or candidate.module.runtimeHelper(id)) continue;
            try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, cohortPreparation, .{ &candidate.module, @as(u32, @intCast(id)) });
        }
        matched = true;
    }
    try std.testing.expect(matched);
}
fn cohortPreparation(allocator: std.mem.Allocator, module: *const @import("wasm.zig").Module, function: u32) !void {
    var pipeline = try @import("runtime_pipeline.zig").Session.init(allocator, module);
    defer pipeline.deinit();
    var result = try pipeline.optimize(&module.functions.items[function]);
    defer if (result) |*owned| owned.deinit(allocator);
}
fn cohortConstruction(allocator: std.mem.Allocator, source: *const @import("wasm.zig").Module, boundary: u32) !void {
    var candidate = (try @import("cohort_candidate.zig").extensionForTest(allocator, source, boundary)).?;
    defer candidate.deinit();
    try std.testing.expect(candidate.module.artifacts == null);
    try std.testing.expect(source.cohorts == null and source.functions.items.len + 3 == candidate.module.functions.items.len);
}
test "private cohort Source view preserves complete root RC admission without changing original bodies" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    const pools = &built.capture.?.metadata.pools.?;
    try cohortAssembly(a, &built.capture.?.emission, .{ .units = &.{source}, .functions = pools.functions, .evidence = pools.evaluator.evidence.view(), .rows = pools.rows, .templates = pools.templates, .captures = pools.captures, .operations = pools.operations });
}
fn cohortDetachedTables(allocator: std.mem.Allocator) !void {
    var source = @import("wasm.zig").Module.init(allocator);
    defer source.deinit();
    _ = try source.ensureArena();
    for (source.signatures.items) |signature| try std.testing.expect(signature.result != .f32 or !std.mem.eql(@import("runtime_ir.zig").ValueType, signature.parameters, &.{ .f32, .f32, .f32 }));
    const before_functions = source.functions.items.len;
    const before_signatures = source.signatures.items.len;
    var view = try @import("cohort_candidate.zig").detached(allocator, &source);
    defer view.deinit();
    _ = try @import("../runtime/cohort_runtime.zig").install(&view.module);
    const added = try view.module.addTypedFunction(&.{ .f32, .f32, .f32 }, .f32, .scalar);
    try view.module.emit(added, .{ .op = .f32_const });
    try std.testing.expect(view.module.signatures.items.len > before_signatures);
    try std.testing.expectEqual(before_signatures, source.signatures.items.len);
    try std.testing.expectEqual(before_functions, source.functions.items.len);
    try std.testing.expect(source.cohorts == null);
}
test "late cohort view owns missing helper signatures and functions through all allocation failures" {
    try cohortDetachedTables(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, cohortDetachedTables, .{});
}
fn semanticSiteReplay(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    var original = try journal.materialize(allocator);
    defer original.deinit();
    var shifted = @import("wasm.zig").Module.init(allocator);
    defer shifted.deinit();
    _ = try shifted.addTypedFunction(&.{.f32}, .f32, .scalar);
    try journal.replayInto(&shifted);
    try std.testing.expect(original.semantic_sites.items.len > 0);
    try std.testing.expectEqual(original.semantic_sites.items.len, shifted.semantic_sites.items.len);
    for (original.semantic_sites.items, shifted.semantic_sites.items) |before, after| {
        var relocated = before;
        relocated.function += 1;
        try std.testing.expectEqualDeep(relocated, after);
    }
}
const SemanticImportGenerator = struct {
    representations: @import("backend_representations.zig").State,
    planning: @import("backend_plan.zig").State,
    allocator: std.mem.Allocator,
    evaluator: @import("../eval/core_eval.zig").Session,
    fn init(allocator: std.mem.Allocator, units: []const core.Module, names: @import("runtime_identity.zig").View) !@This() {
        var evaluator = try @import("../eval/core_eval.zig").Session.init(allocator, units);
        errdefer evaluator.deinit();
        return .{ .allocator = allocator, .evaluator = evaluator, .representations = .fromStore(allocator, try @import("layout.zig").Store.init(allocator)), .planning = .{ .runtime_operations = .initProject(allocator, names) } };
    }
    fn deinit(self: *@This()) void {
        self.planning.deinit(self.allocator);
        self.representations.deinit(self.allocator);
        self.evaluator.deinit();
    }
};
fn semanticSiteImport(allocator: std.mem.Allocator, capture: *const @import("../reuse/artifact_capture.zig").Capture, units: []const core.Module, names: @import("runtime_identity.zig").View) !void {
    var importer = try @import("../reuse/artifact_import.zig").Importer.init(allocator, &capture.metadata.pools.?, units, names, units.len);
    defer importer.deinit();
    var generator = try SemanticImportGenerator.init(allocator, units, names);
    defer generator.deinit();
    var sites: usize = 0;
    for (capture.emission.records.items) |record| {
        if (record.event != .semantic_site) continue;
        const site = record.event.semantic_site;
        const imported = (try importer.importSemanticSite(&generator, site)).?;
        try std.testing.expectEqual(site.unit, imported.unit);
        try std.testing.expectEqual(site.root, imported.root);
        try std.testing.expectEqual(site.node, imported.node);
        try std.testing.expectEqual(site.place, imported.place);
        var wrong = site;
        wrong.node = 0;
        try std.testing.expect(try importer.importSemanticSite(&generator, wrong) == null);
        wrong = site;
        wrong.unit = @intCast(units.len + 1);
        try std.testing.expect(try importer.importSemanticSite(&generator, wrong) == null);
        wrong = site;
        wrong.mappings = @intCast(capture.metadata.pools.?.evaluator.evidence.nodes.len);
        try std.testing.expect(try importer.importSemanticSite(&generator, wrong) == null);
        sites += 1;
    }
    try std.testing.expect(sites > 0);
}
test "typed semantic emission sites preserve exact owned Core coordinates through replay import and OOM" {
    var names: ?@import("runtime_identity.zig").Metadata = null;
    defer if (names) |*owned| owned.deinit(a);
    var source = try lowerCatalogIdentity(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true, &names);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true, .identity = names.?.view(), .artifact_replay = true });
    defer built.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), built.diagnostic);
    const capture = &built.capture.?;
    try semanticSiteReplay(a, &capture.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, semanticSiteReplay, .{&capture.emission});
    try semanticSiteImport(a, capture, &.{source}, names.?.view());
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, semanticSiteImport, .{ capture, &[_]core.Module{source}, names.?.view() });
    var malformed = false;
    for (capture.emission.records.items) |*record| {
        if (record.event != .semantic_site) continue;
        const original = record.event.semantic_site;
        record.event.semantic_site.place += 1;
        try std.testing.expectError(error.InvalidArtifact, capture.emission.materialize(a));
        record.event.semantic_site = original;
        malformed = true;
        break;
    }
    try std.testing.expect(malformed);
    var retained = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true, .identity = names.?.view(), .previous = capture, .cached_units = 1 });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expect(retained.reuse.reused_named > 0);
    try std.testing.expectEqualSlices(u8, built.bytes, retained.bytes);
    try semanticSiteImport(a, &retained.capture.?, &.{source}, names.?.view());
}
test "checked callable layout endpoints distinguish source types through physical constructors replay mismatches and OOM" {
    const ir = @import("runtime_ir.zig");
    const origins = @import("callable_origins.zig");
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var result = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    const captured = &result.capture.?;
    var module = try captured.emission.materialize(a);
    defer module.deinit();
    var constructed: usize = 0;
    var different_type = false;
    var changed_field = false;
    for (module.table_origins.items) |origin| {
        if (origin.kind == .unknown) continue;
        const ty = origins.constructionLayout(&module, origin).?;
        try std.testing.expect(ty < captured.metadata.pools.?.layouts.nodes.len);
        try std.testing.expectEqual(@import("layout.zig").Tag.function, captured.metadata.pools.?.layouts.nodes[ty].tag);
        constructed += 1;
        for (module.table_origins.items) |other| {
            if (other.kind == .unknown or other.target == origin.target) continue;
            const left = module.functions.items[origin.target];
            const right = module.functions.items[other.target];
            if (left.signature == right.signature and left.parameter_roles == right.parameter_roles and left.result_role == right.result_role and left.callable_layout != right.callable_layout) different_type = true;
        }
        if (origin.kind != .callable or origin.function == null or changed_field) continue;
        const field = &module.functions.items[origin.function.?].instructions.items[origin.place + 1];
        field.operand = 4;
        try std.testing.expect(origins.constructionLayout(&module, origin) == null);
        field.operand = 0;
        const endpoint = &module.functions.items[origin.target].callable_layout;
        endpoint.* = 0;
        try std.testing.expect(origins.constructionLayout(&module, origin) == null);
        endpoint.* = ty;
        const value = &module.functions.items[origin.function.?].instructions.items[origin.place];
        value.table_kind = .demand;
        try std.testing.expect(origins.constructionLayout(&module, origin) == null);
        value.table_kind = .callable;
        changed_field = true;
    }
    try std.testing.expect(constructed > 0 and different_type and changed_field);
    var reads: usize = 0;
    for (module.functions.items) |*function| for (function.instructions.items, 0..) |inst, at| {
        if (inst.op != .i32_load) continue;
        const ty = ir.callableCodeLayout(function.instructions.items, at) orelse continue;
        try std.testing.expect(ty < captured.metadata.pools.?.layouts.nodes.len);
        try std.testing.expectEqual(@import("layout.zig").Tag.function, captured.metadata.pools.?.layouts.nodes[ty].tag);
        const saved = function.instructions.items[at - 1];
        function.instructions.items[at - 1] = ir.callableCodeRead(0);
        try std.testing.expect(ir.callableCodeLayout(function.instructions.items, at) == null);
        function.instructions.items[at - 1] = saved;
        reads += 1;
    };
    try std.testing.expect(reads > 0);
    try callableReplay(a, &captured.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, callableReplay, .{&captured.emission});
    var replay = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true, .previous = captured });
    defer replay.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), replay.diagnostic);
    try std.testing.expectEqualSlices(u8, result.bytes, replay.bytes);
}

fn emitUniversalDictionary(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithEvidenceNoise(allocator, &.{module.*}, 1, false);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "universal dictionary forwarding keeps exact lexical evidence through every backend allocation failure" {
    var module = try lower(a,
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
        \\const render: forall [a] where { Render a } => a -> U32 = fn value => Render.show value
        \\const forward: forall [a] where { Render a } => a -> U32 = fn value => render value
        \\const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
        \\entry const answer: Unit -> U32 = fn () => both forward
    );
    defer module.deinit(a);
    try @import("../check/frozen_core_validation.zig").validate(a, &module, .{});
    try emitUniversalDictionary(a, &module);
    try emit(a, &module, true);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitUniversalDictionary, .{&module});
}

fn emitStaticPackages(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .retain_artifacts = true });
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
    var replay = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .retain_artifacts = true, .previous = &result.capture.? });
    defer replay.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), replay.diagnostic);
    try std.testing.expectEqualSlices(u8, result.bytes, replay.bytes);
}
test "static package carriers and stored methods preserve owned emission replay through every allocation failure" {
    var module = try lower(a,
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\type Item = exists [a] where { Render a } => (Array a, a)
        \\const item: Item = pack [U32] (#[20, 22], 42) as Item
        \\const read = fn (value: Item) => unpack value as [a] payload in Render.show (@product.get payload 1)
        \\entry const answer = fn () => read item
    );
    defer module.deinit(a);
    try @import("../check/frozen_core_validation.zig").validate(a, &module, .{});
    try emitStaticPackages(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitStaticPackages, .{&module});
}

fn stackProviderProof(allocator: std.mem.Allocator, module: *const @import("wasm.zig").Module) !void {
    try std.testing.expect(try @import("provider_flow.zig").protectedActivations(allocator, module));
    var ordinary = try @import("provider_modes.zig").Catalog.init(allocator, module);
    defer ordinary.deinit(allocator);
    var protected = (try @import("provider_modes.zig").Catalog.initProtected(allocator, module)).?;
    defer protected.deinit(allocator);
    try std.testing.expectEqualDeep(ordinary.entries.items, protected.entries.items);
    try std.testing.expectEqual(ordinary.saturated, protected.saturated);
}
fn rejectStackMutation(module: *const @import("wasm.zig").Module, body: *@import("runtime_ir.zig").Function, changed: *const std.ArrayList(@import("runtime_ir.zig").Instruction)) !void {
    const original = body.instructions;
    body.instructions = changed.*;
    defer body.instructions = original;
    try std.testing.expect(try @import("provider_flow.zig").complete(a, module));
    try std.testing.expect(!try @import("provider_flow.zig").protectedActivations(a, module));
    try std.testing.expectEqual(@as(?@import("provider_modes.zig").Catalog, null), try @import("provider_modes.zig").Catalog.initProtected(a, module));
}
test "provider activation storage requires live borrowers and tracks owned outer links and rejects retired aliases through OOM" {
    const ir = @import("runtime_ir.zig");
    const flow = @import("provider_flow.zig");
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    var module = try built.capture.?.emission.materialize(a);
    defer module.deinit();
    try std.testing.expect(try flow.complete(a, &module));
    try stackProviderProof(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stackProviderProof, .{&module});
    var checked = false;
    for (module.functions.items) |*body| {
        var constructor: ?@import("provider_origins.zig").Fact = null;
        for (body.instructions.items, 0..) |inst, at| if (inst.op == .ownership) {
            const mark: ir.Ownership = @bitCast(inst.operand);
            if (mark.kind == .rest and mark.chunk == 8) if (@import("provider_origins.zig").constructor(&module, body, at)) |fact| {
                if (fact.kind == 4) constructor = fact;
            };
        };
        const fact = constructor orelse continue;
        var retirement: ?usize = null;
        for (body.instructions.items, 0..) |inst, at| if (inst.op == .call and (inst.operand == module.arena.?.release or inst.operand == module.arena.?.free or inst.operand == module.arena.?.recycle) and at > fact.end) {
            retirement = at;
        };
        const at = retirement orelse continue;
        const original = body.instructions;
        var changed: std.ArrayList(ir.Instruction) = .empty;
        defer changed.deinit(a);
        try changed.appendSlice(a, original.items[0 .. at + 1]);
        try changed.appendSlice(a, &.{ .{ .op = .local_get, .operand = fact.local }, .{ .op = .drop } });
        try changed.appendSlice(a, original.items[at + 1 ..]);
        try rejectStackMutation(&module, body, &changed);
        changed.clearRetainingCapacity();
        try changed.appendSlice(a, original.items[0 .. at + 1]);
        try changed.appendSlice(a, &.{ .{ .op = .local_get, .operand = fact.local }, .{ .op = .call, .operand = original.items[at].operand } });
        try changed.appendSlice(a, original.items[at + 1 ..]);
        try rejectStackMutation(&module, body, &changed);
        const local_count = body.locals.items.len;
        const alias: u32 = @intCast(body.parameters.len + local_count);
        try body.locals.append(a, .i32);
        defer body.locals.shrinkRetainingCapacity(local_count);
        changed.clearRetainingCapacity();
        try changed.appendSlice(a, original.items[0 .. at - 1]);
        try changed.appendSlice(a, &.{ .{ .op = .local_get, .operand = fact.local }, .{ .op = .local_set, .operand = alias } });
        try changed.appendSlice(a, original.items[at - 1 .. at + 1]);
        try changed.appendSlice(a, &.{ .{ .op = .local_get, .operand = alias }, .{ .op = .drop } });
        try changed.appendSlice(a, original.items[at + 1 ..]);
        try rejectStackMutation(&module, body, &changed);
        changed.clearRetainingCapacity();
        try changed.append(a, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope }) });
        try changed.appendSlice(a, original.items[0 .. fact.end + 1]);
        try changed.append(a, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 1 }) });
        try changed.appendSlice(a, original.items[fact.end + 1 ..]);
        try rejectStackMutation(&module, body, &changed);
        changed.clearRetainingCapacity();
        try changed.appendSlice(a, original.items[0 .. fact.end + 1]);
        try changed.appendSlice(a, &.{ .{ .op = .local_get, .operand = fact.local }, .{ .op = .call, .operand = module.arena.?.retain } });
        try changed.appendSlice(a, original.items[fact.end + 1 ..]);
        try rejectStackMutation(&module, body, &changed);
        const old_entry = body.entry;
        body.entry = true;
        try std.testing.expect(!try flow.protectedActivations(a, &module));
        body.entry = old_entry;
        checked = true;
        break;
    }
    try std.testing.expect(checked);
}

test "runtime associated dictionary carriers preserve exact owner emission replay through complete OOM" {
    var module = try lower(a,
        \\type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
        \\impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
        \\impl Flag : Source Bool = { type Item = Bool, const get = fn value => value, const show = fn owner => fn value => if value then 7 else 9 }
        \\type Package = exists [a] where { Source a } => a
        \\const make = fn (flag: Bool) => if flag then pack [U32] 42 as Package else pack [Bool] #True as Package
        \\const seal: forall [a] where { Source a } => a -> Package = fn value => pack [a] value as Package
        \\const read = fn (item: Package) => unpack item as [a] value in Source.show value (Source.get value)
        \\entry const answer = fn (flag: Bool) => read (seal flag)
    );
    defer module.deinit(a);
    try @import("../check/frozen_core_validation.zig").validate(a, &module, .{});
    try emitStaticPackages(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitStaticPackages, .{&module});
}

test "static associated dictionary carriers preserve exact owner emission replay through complete OOM" {
    var module = try lower(a,
        \\type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
        \\impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
        \\impl Flag : Source Bool = { type Item = Bool, const get = fn value => value, const show = fn owner => fn value => if value then 7 else 9 }
        \\type Package = exists [a] where { Source a } => a
        \\const make = fn (flag: Bool) => if flag then pack [U32] 42 as Package else pack [Bool] #True as Package
        \\const read = fn (item: Package) => unpack item as [a] value in Source.show value (Source.get value)
        \\const item: Package = pack [U32] 42 as Package
        \\entry const answer = fn () => read item
    );
    defer module.deinit(a);
    try @import("../check/frozen_core_validation.zig").validate(a, &module, .{});
    try emitStaticPackages(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitStaticPackages, .{&module});
}

fn emitInferredDictionary(allocator: std.mem.Allocator, module: *const core.Module) !void {
    try @import("../check/frozen_core_validation.zig").validate(allocator, module, .{});
    try emitStaticPackages(allocator, module);
}
test "inferred dictionary principals retain stored member ownership through backend replay and complete OOM" {
    var module = try lower(a,
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
        \\const helper = fn value => Render.show value
        \\const apply = fn callback => fn value => callback value
        \\const sum = fn left => fn right => @u32.add (helper left) (helper right)
        \\const render: forall [a] where { Render a } => a -> a -> U32 = fn left => fn right => apply (sum left) right
        \\const both: (forall [a] where { Render a } => a -> a -> U32) -> U32 = fn callback => @u32.add (callback 20 22) (callback #True #False)
        \\entry const answer: Unit -> U32 = fn () => both render
    );
    defer module.deinit(a);
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
    var changed = false;
    for (module.bodies) |body| {
        if (!body.is_function or module.types.node(body.scheme.root).tag != .function or body.scheme.variables.len == 0 or body.scheme.obligations.len == 0) continue;
        var remaining: usize = 65_536;
        try @import("../check/package_core.zig").parametricBody(&module, body.binding, .{ .units = &.{} }, &remaining);
        const original = module.obligations[body.scheme.obligations.start];
        module.obligations[body.scheme.obligations.start].identity.decl += 1;
        remaining = 65_536;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/package_core.zig").parametricBody(&module, body.binding, .{ .units = &.{} }, &remaining));
        try std.testing.expectError(error.InvalidArtifact, @import("../check/frozen_core_validation.zig").validate(a, &module, .{}));
        module.obligations[body.scheme.obligations.start] = original;
        remaining = 0;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/package_core.zig").parametricBody(&module, body.binding, .{ .units = &.{} }, &remaining));
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    var stolen = false;
    for (module.calls) |*call| {
        const template = for (module.member_templates) |candidate| {
            if (candidate.binding == call.target.binding) break candidate;
        } else continue;
        _ = template;
        const original = call.target;
        for (module.bodies) |body| {
            const signature = module.types.node(body.scheme.root);
            if (!body.is_function or signature.tag != .function or signature.a != types.u32_type) continue;
            call.target = .{ .unit = module.unit, .binding = body.binding };
            try std.testing.expectError(error.InvalidArtifact, @import("../check/frozen_core_validation.zig").validate(a, &module, .{}));
            call.target = original;
            stolen = true;
            break;
        }
        if (stolen) break;
    }
    try std.testing.expect(stolen);
}

test "inferred dictionary associated helper retains immutable scheme authority" {
    var module = try lower(a,
        \\type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
        \\impl Number : Source U32 = { type Item = U32, const get = fn value => value, const show = fn owner => fn value => value }
        \\impl Flag : Source Bool = { type Item = Bool, const get = fn value => value, const show = fn owner => fn value => if value then 7 else 9 }
        \\const helper = fn value => Source.show value (Source.get value)
        \\const render: forall [a] where { Source a } => a -> U32 = fn value => helper value
        \\const both: (forall [a] where { Source a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
        \\entry const answer: Unit -> U32 = fn () => both render
    );
    defer module.deinit(a);
    try @import("../check/frozen_core_validation.zig").validate(a, &module, .{});
    for (module.bodies) |body| {
        if (!body.is_function or @import("../check/dictionary_owner.zig").Owner.forBinding(&module, body.binding) == null) continue;
        var remaining: usize = 65_536;
        try @import("../check/package_core.zig").parametricBody(&module, body.binding, .{ .units = &.{} }, &remaining);
    }
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
}

fn phantomDictionaryHeader(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator,
        \\type Tag a is contract = { const read: Unit -> U32 }
        \\const helper: forall [a] where { Tag a } => Unit -> U32 = fn unit => Tag.read unit
        \\entry const answer: Unit -> U32 = fn unit => 42
    );
    defer module.deinit(allocator);
    try @import("../check/frozen_core_validation.zig").validate(allocator, &module, .{});
    var found = false;
    for (module.bodies) |body| {
        const owner = @import("../check/dictionary_owner.zig").Owner.forBinding(&module, body.binding) orelse continue;
        const principal = module.types.node(body.scheme.root);
        if (principal.tag != .forall) continue;
        var remaining: usize = 65_536;
        var scopes: @import("../check/package_contracts.zig").Context = .{ .types = &module.types, .remaining = &remaining };
        try scopes.initialize();
        try scopes.enter(body.scheme.root);
        var proof: @import("../check/package_contracts.zig").Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
        try std.testing.expectError(error.InvalidArtifact, owner.instantiate(&module, &proof, principal.a));
        found = true;
    }
    try std.testing.expect(found);
}
test "dictionary forwarding rejects header-free phantom witnesses through complete OOM" {
    try phantomDictionaryHeader(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, phantomDictionaryHeader, .{});
}

test "interface member aliases preserve immutable unary dictionary abstractions through complete OOM" {
    var module = try lower(a,
        \\type Render a is contract = { const show: a -> U32 }
        \\impl Number : Render U32 = { const show = fn value => value }
        \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
        \\const helper = Render.show
        \\const render: forall [a] where { Render a } => a -> U32 = fn value => helper value
        \\const both: (forall [a] where { Render a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
        \\entry const answer: Unit -> U32 = fn () => both render
    );
    defer module.deinit(a);
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
    var changed = false;
    for (module.bodies) |*body| {
        if (module.node(body.root).tag != .call or body.scheme.obligations.len == 0) continue;
        const saved = body.*;
        body.is_function = false;
        body.parameters.len = 0;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/frozen_core_validation.zig").validate(a, &module, .{}));
        body.* = saved;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
}

test "interface alias lowering preserves action boundaries and ordinary operation values" {
    var module = try lower(a,
        \\effect Read: Unit -> U32
        \\type Render a is contract = { const show: a -> (Unit -> U32) ! {Read} }
        \\const helper = Render.show
        \\const operation = Read
        \\entry const answer: Unit -> U32 = fn unit => 42
    );
    defer module.deinit(a);
    try @import("../check/frozen_core_validation.zig").validate(a, &module, .{});
    var method = false;
    var operation = false;
    for (module.bodies) |body| {
        const root = module.node(body.root);
        if (root.tag == .operation_value) {
            try std.testing.expect(!body.is_function and body.parameters.len == 0);
            operation = true;
        }
        if (root.tag != .call or body.scheme.obligations.len == 0) continue;
        try std.testing.expect(body.is_function);
        try std.testing.expectEqual(@as(u32, 1), body.parameters.len);
        try std.testing.expectEqual(@as(usize, 1), module.call(body.root).arguments.len);
        const arrow = module.types.node(body.scheme.root);
        try std.testing.expectEqual(types.Tag.function, arrow.tag);
        try std.testing.expect(module.types.effects.rows[arrow.c].labels.len != 0);
        const applied = module.types.node(module.call(body.root).callee_type);
        try std.testing.expectEqual(applied.b, root.ty);
        try std.testing.expect(module.types.effects.rows[applied.c].labels.len != 0);
        try std.testing.expectEqual(types.Tag.function, module.types.node(root.ty).tag);
        method = true;
    }
    try std.testing.expect(method and operation);
}

fn rejectsAssociatedUsage(allocator: std.mem.Allocator, source: []const u8) !void {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| if (diagnostic.code == .usage_evidence_mismatch) return;
    for (checked.diagnostics) |diagnostic| std.debug.print("associated usage {s}\n", .{@tagName(diagnostic.code)});
    return error.TestUnexpectedResult;
}

test "unrestricted associated equations reject direct and hidden lifetime authority at source publication" {
    const sources = [_][]const u8{
        "type Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = unique U32 }\n",
        "type Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = shared U32 }\n",
        "type Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = once (Unit -> U32) }\n",
        "type Source a is contract = { type Item = shared U32 }\n",
        "type Hidden is data = #Hidden (unique U32)\ntype Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = Hidden }\n",
        "opaque type Hidden = shared U32\ntype Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = Hidden }\n",
        "type Hidden is data = #Hidden (shared U32)\ntype Source a is contract = { type Item = Hidden }\n",
        "type Source a is contract = { type Item }\nimpl All a : Source a = { type Item = a }\nconst keep: unique U32 -> (Source.Item (unique U32)) = fn value => value\n",
    };
    for (sources) |source| try rejectsAssociatedUsage(a, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectsAssociatedUsage, .{sources[5]});
}

fn expectAssociatedError(expected: anyerror, result: anytype) !void {
    _ = result catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try std.testing.expectEqual(expected, err);
        return;
    };
    return error.TestUnexpectedResult;
}

fn associatedUsageReader(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator,
        \\type Hidden is data = #Hidden (shared U32)
        \\opaque type Sealed = shared U32
        \\type Source a is contract = { type Item }
        \\impl Number : Source U32 = { type Item = U32 }
        \\type Fixed a is contract = { type Item = U32 }
        \\const keep = fn (owner: unique U32) => owner
        \\entry const answer: Unit -> U32 = fn unit => 42
    );
    defer module.deinit(allocator);
    const validation = @import("../check/frozen_core_validation.zig");
    const admission = @import("../eval/implementation_admission.zig");
    try validation.validate(allocator, &module, .{});
    var direct = false;
    var hidden = false;
    for (module.types.nodes, 0..) |node, index| {
        if (node.tag != .usage and node.tag != .nominal) continue;
        if (node.tag == .nominal) {
            const nominal = for (module.nominals) |candidate| {
                if (candidate.identity.unit == node.a and candidate.identity.decl == node.b) break candidate;
            } else continue;
            if (!nominal.has_usage) continue;
            hidden = true;
        } else direct = true;
        for (module.implementation_members) |*member| {
            if (member.kind != .type_) continue;
            const saved = member.root;
            member.root = @intCast(index);
            var remaining: usize = 65_536;
            try expectAssociatedError(error.InvalidArtifact, admission.scopes(allocator, &module.types, &module, module.obligations, &remaining));
            try expectAssociatedError(error.InvalidArtifact, validation.validate(allocator, &module, .{}));
            member.root = saved;
        }
        for (module.contract_members) |*member| {
            if (member.kind != .defined_type) continue;
            const saved = member.root;
            member.root = @intCast(index);
            var remaining: usize = 65_536;
            try expectAssociatedError(error.InvalidArtifact, admission.scopes(allocator, &module.types, &module, module.obligations, &remaining));
            try expectAssociatedError(error.InvalidArtifact, validation.validate(allocator, &module, .{}));
            member.root = saved;
        }
    }
    try std.testing.expect(direct and hidden);
}

test "unrestricted associated immutable equations reject erased lifetimes through complete OOM" {
    try associatedUsageReader(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, associatedUsageReader, .{});
}

const AssociatedUsageHost = struct {
    units: []const core.Module,
    evidence: @import("../eval/type_evidence.zig").Store,
    associated_remaining: usize = 65_536,
    pub fn evidenceStore(self: *@This()) *@import("../eval/type_evidence.zig").Store {
        return &self.evidence;
    }
    pub fn implementationRead(_: *@This(), _: u32, _: types.NominalIdentity) std.mem.Allocator.Error!void {}
    pub fn implementationLegacyPredicate(_: *@This(), _: u32, _: core.Obligation, _: [4]@import("../eval/type_evidence.zig").Id, _: @import("../eval/type_evidence.zig").ProjectionResolver) @import("../eval/type_evidence.zig").Error!?@import("../eval/implementation_evidence.zig").LegacyChoice {
        return null;
    }
};
fn associatedUsageSelection(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator,
        \\type Hidden is data = #Hidden (shared U32)
        \\type Source a is contract = { type Item }
        \\impl All a : Source a = { type Item = a }
        \\type Fixed a is contract = { type Item = a }
        \\const keep = fn (owner: unique U32) => owner
        \\entry const answer: Unit -> U32 = fn unit => 42
    );
    defer module.deinit(allocator);
    try @import("../check/frozen_core_validation.zig").validate(allocator, &module, .{});
    var host: AssociatedUsageHost = .{ .units = &.{module}, .evidence = try @import("../eval/type_evidence.zig").Store.init(allocator) };
    defer host.evidence.deinit();
    var proofs: @import("../eval/implementation_evidence.zig").Store = .{ .allocator = allocator };
    defer proofs.deinit();
    const contract = module.implementations[0].contract;
    _ = try proofs.resolve(&host, 1, contract, &.{types.u32_type});
    var checked: usize = 0;
    for (module.types.nodes, 0..) |node, index| {
        if (node.tag != .usage and node.tag != .nominal) continue;
        if (node.tag == .nominal) {
            const nominal = for (module.nominals) |candidate| {
                if (candidate.identity.unit == node.a and candidate.identity.decl == node.b) break candidate;
            } else continue;
            if (!nominal.has_usage) continue;
        }
        const actual = try host.evidence.projectWithBudget(&module.types, @intCast(index), &.{}, &.{}, &host.associated_remaining);
        try expectAssociatedError(error.TypeMismatch, proofs.resolve(&host, 1, contract, &.{actual}));
        // Defined equations must repeat the check after substituting arguments.
        for (module.contract_members) |descriptor| {
            if (descriptor.kind != .defined_type) continue;
            try expectAssociatedError(error.TypeMismatch, proofs.projection(&host, 1, descriptor.contract, descriptor.name, &.{actual}));
        }
        // Failed selection cannot publish a partially checked member or proof.
        try std.testing.expectEqual(@as(usize, 1), proofs.proofs.items.len);
        try std.testing.expectEqual(@as(usize, 1), proofs.members.items.len);
        checked += 1;
    }
    try std.testing.expect(checked >= 2);
    host.associated_remaining = 0;
    try expectAssociatedError(error.AssociatedLimit, proofs.resolve(&host, 1, contract, &.{types.boolean}));
}

test "instantiated associated equations cannot erase generic or nominal lifetime arguments through complete OOM" {
    try associatedUsageSelection(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, associatedUsageSelection, .{});
}

test "associated member aliases retain exact goal and member authority through emission and complete OOM" {
    var module = try lower(a,
        \\type Source a is contract = { type Item, type Other, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
        \\impl Number : Source U32 = { type Item = U32, type Other = Bool, const get = fn value => value, const show = fn owner => fn value => value }
        \\impl Flag : Source Bool = { type Item = Bool, type Other = U32, const get = fn value => value, const show = fn owner => fn value => if value then 7 else 9 }
        \\const helper = Source.get
        \\const render: forall [a] where { Source a } => a -> U32 = fn value => Source.show value (helper value)
        \\const both: (forall [a] where { Source a } => a -> U32) -> U32 = fn callback => @u32.add (callback 42) (callback #True)
        \\entry const answer: Unit -> U32 = fn () => both render
    );
    defer module.deinit(a);
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
    var changed = false;
    for (module.bodies) |body| {
        const header = module.types.node(body.scheme.root);
        if (header.tag != .function or module.types.node(header.b).tag != .projection or module.node(body.root).tag != .call or body.scheme.obligations.len == 0) continue;
        const projection = module.types.node(header.b);
        const original = module.types.projectionMember(projection);
        const other = for (module.contract_members) |member| {
            if (member.kind == .abstract_type and member.name != original) break member.name;
        } else return error.TestUnexpectedResult;
        const slot = projection.c + 1 + module.types.extra[projection.c];
        module.types.extra[slot] = other;
        var remaining: usize = 65_536;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/package_core.zig").parametricBody(&module, body.binding, .{ .units = &.{} }, &remaining));
        try std.testing.expectError(error.InvalidArtifact, @import("../check/frozen_core_validation.zig").validate(a, &module, .{}));
        module.types.extra[slot] = original;
        const goal = body.scheme.obligations.start;
        const identity = module.obligations[goal].identity;
        module.obligations[goal].identity.decl += 1;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/frozen_core_validation.zig").validate(a, &module, .{}));
        module.obligations[goal].identity = identity;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
}

test "effectful dictionary methods return owned closures under conservative result rows through complete OOM" {
    var module = try lower(a, @import("fixtures").source("request-fixtures/effectful-dictionary-closure.blot"));
    defer module.deinit(a);
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
    var erased = false;
    for (module.implementation_members) |member| {
        if (member.kind != .value) continue;
        const arrow = &module.types.nodes[member.root];
        if (arrow.tag != .function or module.types.rowLabels(arrow.c).len == 0) continue;
        const row = arrow.c;
        arrow.c = 0;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/frozen_core_validation.zig").validate(a, &module, .{}));
        arrow.c = row;
        erased = true;
        break;
    }
    try std.testing.expect(erased);
    var stolen = false;
    for (module.closures) |closure| {
        if (closure.captures.len < 2) continue;
        const captures = module.extra[closure.captures.start..][0..closure.captures.len];
        const prior = captures[1];
        captures[1] = captures[0];
        try std.testing.expectError(error.InvalidArtifact, @import("../check/frozen_core_validation.zig").validate(a, &module, .{}));
        captures[1] = prior;
        stolen = true;
        break;
    }
    try std.testing.expect(stolen);
}

test "effectful member aliases retain owned returned closures through complete OOM" {
    const source = try std.mem.replaceOwned(u8, a, @import("fixtures").source("request-fixtures/effectful-dictionary-closure.blot"), "const helper = fn value => Render.show value", "const helper = Render.show");
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
}

fn nestedCallableReuse(allocator: std.mem.Allocator) !void {
    var names: ?@import("runtime_identity.zig").Metadata = null;
    defer if (names) |*owned| owned.deinit(allocator);
    var module = try lowerCatalogIdentity(allocator,
        \\const apply = fn (callback: U32 -> U32) => fn (value: U32) => callback value
        \\const increment = fn (value: U32) => @u32.add value 2
        \\entry const answer = fn (value: U32) => apply increment value
    , false, &names);
    defer module.deinit(allocator);
    var first = try backend.compileWithOptions(allocator, &.{module}, 1, .{ .inline_named = false, .retain_artifacts = true, .identity = names.?.view() });
    defer first.deinit(allocator);
    try std.testing.expect(first.diagnostic == null);
    var retained = try backend.compileWithOptions(allocator, &.{module}, 1, .{ .inline_named = false, .retain_artifacts = true, .identity = names.?.view(), .previous = &first.capture.?, .cached_units = 1 });
    defer retained.deinit(allocator);
    try std.testing.expect(retained.diagnostic == null);
    try std.testing.expectEqual(first.reuse.fresh_named, retained.reuse.reused_named);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    var tested = false;
    for (first.capture.?.emission.records.items) |*record| {
        if (record.event != .callable_layout) continue;
        const owner = record.owner;
        const layout_before = record.event.callable_layout.layout;
        defer record.owner = owner;
        defer record.event.callable_layout.layout = layout_before;
        for (0..3) |mutation| {
            record.owner = owner;
            record.event.callable_layout.layout = layout_before;
            switch (mutation) {
                0 => record.owner = 0,
                1 => record.owner = @intCast(first.capture.?.metadata.jobs.items.len + 1),
                2 => record.event.callable_layout.layout = types.boolean,
                else => unreachable,
            }
            var declined = try backend.compileWithOptions(allocator, &.{module}, 1, .{ .inline_named = false, .retain_artifacts = true, .identity = names.?.view(), .previous = &first.capture.?, .cached_units = 1 });
            defer declined.deinit(allocator);
            try std.testing.expect(declined.diagnostic == null);
            try std.testing.expect(declined.reuse.reused_named < first.reuse.fresh_named);
            try std.testing.expectEqualSlices(u8, first.bytes, declined.bytes);
        }
        tested = true;
        break;
    }
    try std.testing.expect(tested);
}
test "nested callable fragment records retain their own checked job layout through complete OOM" {
    try nestedCallableReuse(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nestedCallableReuse, .{});
}

fn activationCorrespondenceOom(allocator: std.mem.Allocator, source: *const @import("wasm.zig").Module, model: @import("activation_intersection.zig").Model, runtime: *const @import("activation_graph.zig").Cohort, semantic: *const @import("../check/capability_lifetimes.zig").Report, boundary: core.BindingRef) !void {
    const mapped = try @import("activation_intersection.zig").correspondence(allocator, source, model, runtime, semantic, boundary);
    defer mapped.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 14), mapped.contexts.len);
}
fn activationIntersectionRejects(module: *const @import("wasm.zig").Module, model: @import("activation_intersection.zig").Model, boundary: u32) !void {
    var result = try @import("activation_intersection.zig").analyze(a, module, model, boundary);
    defer if (result) |*owned| owned.deinit(a);
    try std.testing.expect(result == null);
}
fn activationIntersectionMutants(module: *@import("wasm.zig").Module, model: @import("activation_intersection.zig").Model, boundary: u32, proof: *const @import("activation_intersection.zig").Intersection) !void {
    var checked: usize = 0;
    for (module.semantic_sites.items) |*site| {
        var used = false;
        for (proof.runtime.graph.contexts[1..]) |context| used = used or (proof.runtime.graph.contexts[context.parent].function == site.function and context.at == site.place);
        for (proof.runtime.graph.sites, 0..) |allocation, id| if (id == proof.runtime.owner or proof.runtime.members & (@as(u64, 1) << @intCast(id)) != 0) {
            used = used or (allocation.function == site.function and allocation.at == site.place);
        };
        if (!used) continue;
        const original = site.*;
        site.node = 0;
        try activationIntersectionRejects(module, model, boundary);
        site.* = original;
        site.root = 0;
        try activationIntersectionRejects(module, model, boundary);
        site.* = original;
        site.unit = @intCast(model.units.len + 1);
        try activationIntersectionRejects(module, model, boundary);
        site.* = original;
        site.place += 1;
        try activationIntersectionRejects(module, model, boundary);
        site.* = original;
        site.mappings = @intCast(model.evidence.nodes.len);
        try activationIntersectionRejects(module, model, boundary);
        site.* = original;
        checked += 1;
    }
    try std.testing.expect(checked >= 10);
    var capture_mutant = false;
    for (@constCast(model.captures)) |*capture| {
        if (!capture.demand_cell) continue;
        capture.demand_cell = false;
        try activationIntersectionRejects(module, model, boundary);
        capture.demand_cell = true;
        const original = capture.node;
        capture.node = 0;
        try activationIntersectionRejects(module, model, boundary);
        capture.node = original;
        capture_mutant = true;
    }
    try std.testing.expect(capture_mutant);
    var producer_mutant = false;
    for (@constCast(model.functions)) |*entry| {
        if (entry.request != .closure or entry.request.closure.catalog == 0) continue;
        var used = false;
        for (proof.runtime.graph.contexts) |context| used = used or context.function == entry.function;
        if (!used) continue;
        const original = entry.request.closure.catalog;
        entry.request.closure.catalog = 0;
        try activationIntersectionRejects(module, model, boundary);
        entry.request.closure.catalog = original;
        producer_mutant = true;
    }
    try std.testing.expect(producer_mutant);
    var row_mutant = false;
    for (module.semantic_sites.items) |*site| {
        const source_request = for (model.functions) |entry| {
            if (entry.function == site.function) break entry.request;
        } else continue;
        if (source_request != .named or source_request.named.templates == 0) continue;
        const producer = &model.units[source_request.named.target.unit - 1];
        const body = producer.body(source_request.named.target.binding).?;
        const parameter = producer.bodyParameters(body)[0];
        const demand = producer.types.node(parameter.ty);
        if (demand.tag != .demand or producer.types.row(demand.c).tail != .variable) continue;
        const entries = try a.alloc(@import("../reuse/substitution_keys.zig").Entry, model.rows.entries.len + 1);
        defer a.free(entries);
        @memcpy(entries[0..model.rows.entries.len], model.rows.entries);
        entries[model.rows.entries.len] = .{ .variable = producer.types.row(demand.c).tail.variable, .value = 0 };
        const spans = try a.alloc(@import("../reuse/code_artifacts.zig").Span, model.rows.spans.len + 1);
        defer a.free(spans);
        @memcpy(spans[0..model.rows.spans.len], model.rows.spans);
        spans[model.rows.spans.len] = .{ .start = @intCast(model.rows.entries.len), .len = 1 };
        var wrong = model;
        wrong.rows = .{ .entries = entries, .spans = spans };
        const old_rows = site.rows;
        site.rows = @intCast(spans.len);
        try activationIntersectionRejects(module, wrong, boundary);
        site.rows = old_rows;
        row_mutant = true;
        break;
    }
    try std.testing.expect(row_mutant);
    var field_mutant = false;
    for (proof.runtime.graph.sites, 0..) |site, id| {
        if (site.kind != .ordinary or proof.runtime.members & (@as(u64, 1) << @intCast(id)) == 0) continue;
        const body = &module.functions.items[site.function];
        const annotations = @import("runtime_ir.zig").allocationAnnotations(body.instructions.items, site.at);
        for (@constCast(annotations)) |*instruction| {
            var marker: @import("runtime_ir.zig").Ownership = @bitCast(instruction.operand);
            if (marker.kind != .words or marker.chunk != 0) continue;
            const original = instruction.*;
            marker.roles = (marker.roles & ~@as(u26, 12)) | (@as(u26, @backingInt(@import("runtime_ir.zig").Role.scalar)) << 2);
            instruction.operand = @bitCast(marker);
            try activationIntersectionRejects(module, model, boundary);
            instruction.* = original;
            field_mutant = true;
            break;
        }
    }
    try std.testing.expect(field_mutant);
    const full = @import("fixtures").source("provider-fixtures/lifetime-cost.blot");
    const changed = try std.mem.replaceOwned(u8, a, full, "get (fn () => #End)", "#End");
    defer a.free(changed);
    var changed_source = try lowerCatalog(a, changed, true);
    defer changed_source.deinit(a);
    var wrong_producer = model;
    wrong_producer.units = &.{changed_source};
    try activationIntersectionRejects(module, wrong_producer, boundary);
}

test "private semantic activation intersection contracts exact owned callable invocation contexts" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    const pools = &built.capture.?.metadata.pools.?;
    var module = try built.capture.?.emission.materialize(a);
    defer module.deinit();
    var found = false;
    for (pools.functions) |entry| {
        if (entry.request != .named) continue;
        var cohort = (try @import("activation_graph.zig").cohort(a, &module, entry.function)) orelse continue;
        defer cohort.deinit(a);
        const model: @import("activation_intersection.zig").Model = .{ .units = &.{source}, .functions = pools.functions, .evidence = pools.evaluator.evidence.view(), .rows = pools.rows, .templates = pools.templates, .captures = pools.captures, .operations = pools.operations };
        var intersection = (try @import("activation_intersection.zig").analyze(a, &module, model, entry.function)).?;
        defer intersection.deinit(a);
        try std.testing.expectEqual(@as(u32, 3), @popCount(intersection.runtime.members));
        try activationIntersectionMutants(&module, model, entry.function, &intersection);
        try activationCorrespondenceOom(a, &module, model, &intersection.runtime, &intersection.semantic, entry.request.named.target);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, activationCorrespondenceOom, .{ &module, model, &intersection.runtime, &intersection.semantic, entry.request.named.target });
        found = true;
    }
    try std.testing.expect(found);
}

test "cohort owner transfer protocol keeps the member outside the allocation journal" {
    var module = try @import("../runtime/cohort_fixture.zig").build(a);
    defer module.deinit();
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer a.free(bytes);
}

fn closedOutgoingMutants(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    const flow = @import("activation_graph.zig");
    const ir = @import("runtime_ir.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var matched = false;
    for (module.functions.items, 0..) |body, boundary| {
        if (body.entry or body.provider_parameter != 1 or body.result_role != .scalar or body.parameter_roles != ir.packParameterRoles(&.{ .scalar, .reference })) continue;
        var proof = (try flow.cohort(allocator, &module, @intCast(boundary))) orelse continue;
        defer proof.deinit(allocator);
        for (proof.graph.sites, 0..) |site, id| {
            if (proof.members & (@as(u64, 1) << @intCast(id)) == 0 or site.kind != .memo) continue;
            const producer = &module.functions.items[site.function];
            const assigned = producer.instructions.items[site.at + 1];
            try std.testing.expectEqual(ir.Op.local_set, assigned.op);
            const original = producer.instructions;
            defer producer.instructions = original;
            var origin: ?@import("wasm.zig").Module.TableOrigin = null;
            var end: ?usize = null;
            for (module.table_origins.items) |entry| {
                if (entry.function != site.function) continue;
                const creation = @import("callable_origins.zig").construction(&module, entry) orelse continue;
                if (creation.allocation != site.at) continue;
                origin = entry;
                end = creation.end;
            }
            try std.testing.expect(origin != null and end != null);
            // The borrowed outer provider remains live beyond this activation.
            // Even a later overwrite cannot erase this outgoing store history.
            for ([_]bool{ false, true }) |resource| {
                var changed: std.ArrayList(ir.Instruction) = .empty;
                defer changed.deinit(allocator);
                try changed.appendSlice(allocator, original.items[0..end.?]);
                if (resource) {
                    try changed.append(allocator, .{ .op = .resource_retire, .operand = assigned.operand });
                } else {
                    try changed.appendSlice(allocator, &.{ .{ .op = .local_get, .operand = assigned.operand }, .{ .op = .local_get, .operand = producer.provider_parameter }, .{ .op = .i32_load, .operand = @offsetOf(@import("../runtime/runtime_layout.zig").StateFrame, "outer") }, .{ .op = .i32_store, .operand = 4 } });
                }
                try changed.appendSlice(allocator, original.items[end.?..]);
                producer.instructions = changed;
                try std.testing.expect(@import("callable_origins.zig").construction(&module, origin.?) != null);
                var rejected = try flow.cohort(allocator, &module, @intCast(boundary));
                defer if (rejected) |*owned| owned.deinit(allocator);
                try std.testing.expect(rejected == null);
                producer.instructions = original;
            }
            matched = true;
        }
    }
    try std.testing.expect(matched);
}
test "closed cohort destruction rejects outgoing provider history and resource obligations" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    try closedOutgoingMutants(a, &built.capture.?.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, closedOutgoingMutants, .{&built.capture.?.emission});
}

fn regionPublicationFixture(allocator: std.mem.Allocator) !void {
    var module = try @import("../runtime/region_fixture.zig").build(allocator);
    defer module.deinit();
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer allocator.free(bytes);
}
test "region owner publication prepares reference endpoints and exceptional force records through OOM" {
    var module = try @import("../runtime/region_fixture.zig").build(a);
    defer module.deinit();
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer a.free(bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, regionPublicationFixture, .{});
}

test "region publication declines overlapping owned fields and changed force cleanup bodies" {
    const region = @import("../runtime/region_runtime.zig");
    const fixture = @import("../runtime/region_fixture.zig");
    var module = @import("wasm.zig").Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    var invalid = fixture.plan;
    invalid.mask |= @as(u32, 1) << 5;
    try std.testing.expectError(error.InvalidRegion, region.install(&module, invalid));
    invalid = fixture.plan;
    invalid.members = &.{ .{ .offset = 20, .bytes = 16, .demand = true }, .{ .offset = 32, .bytes = 20 } };
    try std.testing.expectError(error.InvalidRegion, region.install(&module, invalid));
    const runtime = try region.install(&module, fixture.plan);
    const body = &module.functions.items[arena.root_pop];
    var changed = false;
    for (body.instructions.items, 0..) |*inst, at| {
        if (inst.op != .i32_load or inst.operand != @offsetOf(@import("../runtime/runtime_layout.zig").Demand, "status") or at + 1 == body.instructions.items.len) continue;
        const next = body.instructions.items[at + 1];
        if (next.op != .i32_const or next.operand != @backingInt(@import("../runtime/runtime_layout.zig").DemandStatus.evaluating)) continue;
        inst.operand = 12;
        try std.testing.expectError(error.UnsupportedRootPop, region.forcePop(a, &module, runtime));
        inst.operand = @offsetOf(@import("../runtime/runtime_layout.zig").Demand, "status");
        changed = true;
        break;
    }
    try std.testing.expect(changed);
}

fn uniqueRegionAssembly(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder, model: @import("activation_intersection.zig").Model) !void {
    var source = try journal.materialize(allocator);
    defer source.deinit();
    var candidate = (try @import("region_candidate.zig").prepare(allocator, &source, model)) orelse return error.TestExpectedRegion;
    defer candidate.deinit();
    try std.testing.expect(try @import("provider_flow.zig").complete(allocator, &candidate.view.module));
    try std.testing.expect(try @import("provider_flow.zig").protectedActivations(allocator, &candidate.view.module));
    const bytes = try candidate.view.module.assembleCheckedWithOptions(.{});
    defer allocator.free(bytes);
    // Mismatched providers and logical roles cannot acquire interior authority
    // merely because their machine signatures are still i32-compatible.
    const scoped = &candidate.scopes[0];
    const original_scope = scoped.*;
    scoped.parameter = 0;
    if (original_scope.parameter == 0) scoped.parameter = 1;
    var invalid = try @import("runtime_pipeline.zig").Session.init(allocator, &candidate.view.module);
    defer invalid.deinit();
    try std.testing.expect(!invalid.roots);
    scoped.* = original_scope;
    const member_at = &candidate.view.module.functions.items[candidate.view.module.regions.?.runtime.member_at];
    member_at.result_role = .scalar;
    var wrong_role = try @import("runtime_pipeline.zig").Session.init(allocator, &candidate.view.module);
    defer wrong_role.deinit();
    try std.testing.expect(!wrong_role.roots);
    member_at.result_role = .reference;
    // An offset outside the owned member catalog cannot become a typed loan.
    var changed = false;
    for (candidate.view.module.functions.items) |*function| {
        if (changed) break;
        for (function.instructions.items, 0..) |instruction, at| {
            if (instruction.op != .call or instruction.operand != candidate.view.module.regions.?.runtime.member_at or at == 0) continue;
            const offset = &function.instructions.items[at - 1];
            try std.testing.expect(offset.op == .i32_const);
            const saved = offset.*;
            offset.operand = 4;
            try std.testing.expectError(error.IncompleteOwnership, candidate.view.module.assembleCheckedWithOptions(.{}));
            offset.* = saved;
            changed = true;
            break;
        }
    }
    try std.testing.expect(changed);
}
test "unique region storage consumes exact invocation owners before physical preparation" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    const pools = &built.capture.?.metadata.pools.?;
    try uniqueRegionAssembly(a, &built.capture.?.emission, .{ .units = &.{source}, .functions = pools.functions, .evidence = pools.evaluator.evidence.view(), .rows = pools.rows, .templates = pools.templates, .captures = pools.captures, .operations = pools.operations });
}

fn regionConstruction(allocator: std.mem.Allocator, source: *const @import("wasm.zig").Module, proof: *const @import("activation_intersection.zig").Intersection) !void {
    var candidate = try @import("region_candidate.zig").extensionForTest(allocator, source, proof);
    defer candidate.deinit();
    try std.testing.expect(candidate.view.module.regions.?.valid(&candidate.view.module));
    try std.testing.expect(source.regions == null and source.cohorts == null);
}
fn regionPreparation(allocator: std.mem.Allocator, module: *const @import("wasm.zig").Module, function: u32) !void {
    var session = try @import("runtime_pipeline.zig").Session.init(allocator, module);
    defer session.deinit();
    try std.testing.expect(session.roots);
    var result = try session.optimize(&module.functions.items[function]);
    defer if (result) |*owned| owned.deinit(allocator);
}
test "unique region constructor and owner-aware callers release every failed preparation allocation" {
    var unit = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer unit.deinit(a);
    var built = try backend.compileWithOptions(a, &.{unit}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    var source = try built.capture.?.emission.materialize(a);
    defer source.deinit();
    const pools = &built.capture.?.metadata.pools.?;
    const model: @import("activation_intersection.zig").Model = .{ .units = &.{unit}, .functions = pools.functions, .evidence = pools.evaluator.evidence.view(), .rows = pools.rows, .templates = pools.templates, .captures = pools.captures, .operations = pools.operations };
    var candidate = (try @import("region_candidate.zig").prepare(a, &source, model)).?;
    defer candidate.deinit();
    var proof = (try @import("activation_intersection.zig").analyze(a, &source, model, candidate.boundary)).?;
    defer proof.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, regionConstruction, .{ &source, &proof });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, regionPreparation, .{ &candidate.view.module, candidate.boundary });
    for (candidate.scopes) |entry| try @import("../allocation_failures.zig").checkAllAllocationFailures(a, regionPreparation, .{ &candidate.view.module, entry.function });
}

test "public static host entry requires exact logical code reads and rejects captured or opaque receivers" {
    const ir = @import("runtime_ir.zig");
    const host = @import("host_entry.zig");
    var unit = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer unit.deinit(a);
    var built = try backend.compileWithOptions(a, &.{unit}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    var source = try built.capture.?.emission.materialize(a);
    defer source.deinit();
    var selected: ?u32 = null;
    var stub: u32 = undefined;
    var ty: u32 = undefined;
    for (built.capture.?.metadata.pools.?.functions) |entry| {
        if (entry.request != .host) continue;
        for (source.functions.items, 0..) |_, id| if (host.confined(&source, @intCast(id), entry.function, entry.request.host.ty, 0)) {
            selected = @intCast(id);
            stub = entry.function;
            ty = entry.request.host.ty;
            break;
        };
        if (selected != null) break;
    }
    const target = selected orelse return error.TestExpectedStaticHost;
    try source.exportGlobal(source.arena.?.root_top, "probe_top");
    try source.exportGlobal(source.arena.?.root_frame, "probe_frame");
    try source.exportGlobal(source.host_references.?.cursor, "probe_refs");
    const fixture = try source.assembleCheckedWithOptions(.{});
    defer a.free(fixture);
    const stub_guard = &source.functions.items[stub].instructions.items[2];
    const original_guard = stub_guard.*;
    stub_guard.operand += 1;
    try std.testing.expect(!host.confined(&source, target, stub, ty, 0));
    stub_guard.* = original_guard;
    var projected: ?usize = null;
    for (source.functions.items[target].instructions.items, 0..) |_, at| if (ir.callableCodeLayout(source.functions.items[target].instructions.items, at) != null) {
        projected = at;
        break;
    };
    const at = projected orelse return error.TestExpectedHostProjection;
    const code = source.functions.items[target].instructions.items;
    const annotation = code[at - 1];
    code[at - 1] = ir.callableCodeRead(ty + 1);
    try std.testing.expect(!host.confined(&source, target, stub, ty, 0));
    code[at - 1] = annotation;
    code[at].operand = 8;
    try std.testing.expect(!host.confined(&source, target, stub, ty, 0));
    code[at].operand = 0;
    try std.testing.expect(!host.confined(&source, target, stub, ty, null));
    const sink = try source.addGlobal(.pointer, 0, true);
    try source.functions.items[target].instructions.insertSlice(a, 1, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .global_set, .operand = sink } });
    try std.testing.expect(!host.confined(&source, target, stub, ty, 0));
    source.functions.items[target].instructions.replaceRangeAssumeCapacity(1, 2, &.{});
    const unknown_callee = try source.addTypedFunction(&.{.i32}, .none, .scalar);
    source.functions.items[unknown_callee].parameter_roles = ir.packParameterRoles(&.{.reference});
    try source.functions.items[target].instructions.insertSlice(a, 1, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .call, .operand = unknown_callee } });
    try std.testing.expect(!host.confined(&source, target, stub, ty, 0));
    source.functions.items[target].instructions.replaceRangeAssumeCapacity(1, 2, &.{});
    try std.testing.expect(host.confined(&source, target, stub, ty, 0));
}

fn ownedRegionContext(allocator: std.mem.Allocator, context: @import("../runtime/region_runtime.zig").Prepared) !void {
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = allocator };
    defer capture.deinit();
    try capture.captureRegions(context);
    try std.testing.expect(capture.regions.?.plan.members.ptr != context.plan.members.ptr);
    try std.testing.expect(capture.regions.?.scopes.ptr != context.scopes.ptr);
    try std.testing.expectEqualDeep(context.plan.members, capture.regions.?.plan.members);
    try std.testing.expectEqualDeep(context.scopes, capture.regions.?.scopes);
}
fn regionContextWire(allocator: std.mem.Allocator, context: @import("../runtime/region_runtime.zig").Prepared) !void {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(35), .settings = @splat(36), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try format.encode(allocator, key, context);
    defer allocator.free(bytes);
    var loaded = try format.decode(@import("../runtime/region_runtime.zig").Prepared, allocator, bytes, key);
    defer format.deinit(allocator, &loaded);
    try std.testing.expectEqualDeep(context, loaded);
}
fn validateRegionSnapshot(allocator: std.mem.Allocator, snapshot: *const @import("../reuse/optimized_archive.zig").Snapshot) !void {
    try @import("../reuse/optimized_archive.zig").validateRegions(allocator, snapshot);
}
test "single region pipeline owns exact optimizer context and invalidates missing changed or forged portable facts through OOM" {
    const bodies = @import("optimized_bodies.zig");
    const archive = @import("../reuse/optimized_archive.zig");
    const format = @import("../reuse/dependency_format.zig");
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true, .artifact_replay = true });
    defer built.deinit(a);
    try std.testing.expect(built.diagnostic == null);
    const captured = &built.capture.?.optimized.?;
    const original = captured.regions orelse return error.TestExpectedRegionContext;
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, ownedRegionContext, .{original});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, regionContextWire, .{original});
    const bytes = try archive.encode(a, @splat(35), captured);
    defer a.free(bytes);
    var loaded = try archive.decode(a, @splat(35), bytes);
    defer loaded.deinit();
    try std.testing.expectEqualDeep(original, loaded.regions.?);
    {
        var same = try bodies.Matcher.init(a, &loaded, captured);
        defer same.deinit();
        for (captured.entries.items, 0..) |_, id| try std.testing.expect(same.matches(id));
    }
    const loaded_context = loaded.regions.?;
    defer loaded.regions = loaded_context;
    for (0..5) |mutation| {
        loaded.regions = loaded_context;
        const members = @constCast(loaded_context.plan.members);
        const scopes = @constCast(loaded_context.scopes);
        const first_member = members[0];
        const first_scope = scopes[0];
        defer members[0] = first_member;
        defer scopes[0] = first_scope;
        switch (mutation) {
            0 => loaded.regions = null,
            1 => loaded.regions.?.plan.mask ^= 1,
            2 => members[0].offset += 4,
            3 => scopes[0].parameter +%= 1,
            4 => loaded.regions.?.runtime.store = loaded.regions.?.runtime.close,
            else => unreachable,
        }
        var mismatch = try bodies.Matcher.init(a, &loaded, captured);
        defer mismatch.deinit();
        for (captured.entries.items, 0..) |_, id| try std.testing.expect(!mismatch.matches(id));
    }
    loaded.regions = loaded_context;
    var snapshot = try format.decode(archive.Snapshot, a, bytes, archive.wireKey(@splat(35)));
    defer format.deinit(a, &snapshot);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, validateRegionSnapshot, .{&snapshot});
    const saved = snapshot.regions.?;
    snapshot.regions.?.runtime.store = saved.runtime.close;
    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
    snapshot.regions = saved;
    snapshot.regions.?.plan.bytes += 4;
    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
    snapshot.regions = saved;
    const scopes = @constCast(snapshot.regions.?.scopes);
    const scope = scopes[0];
    scopes[0].parameter +%= 1;
    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
    scopes[0] = scope;
}

test "selected associated callback annotation retains current concrete method result" {
    var module = try lower(a,
        \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
        \\impl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }
        \\entry const answer = fn (value: U32) => do:
        \\  let selected: (Array U32) -> U32 = Source.first
        \\  break selected #[value]
    );
    defer module.deinit(a);
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
    var changed = false;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .reference or module.span(@intCast(id)).start != 264) continue;
        const arrow = &module.types.nodes[node.ty];
        try std.testing.expect(arrow.tag == .function);
        const saved = arrow.b;
        arrow.b = types.boolean;
        defer arrow.b = saved;
        var invalid = try backend.compile(a, &.{module}, 1);
        defer invalid.deinit(a);
        try std.testing.expect(invalid.diagnostic != null);
        try std.testing.expectEqual(backend.Code.type_mismatch, invalid.diagnostic.?.code);
        changed = true;
        break;
    }
    try std.testing.expect(changed);
}
