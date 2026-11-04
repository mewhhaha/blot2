const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("core_backend.zig");
const types = @import("../check/types.zig");
const a = std.testing.allocator;

test "saturated scalar primitive aliases retain checked direct calls without curried storage" {
    const prelude_source =
        \\const U32.add = @u32.add
        \\const U32.div = @u32.div
        \\const negate = @f32.neg
        \\const convert = @u32.to_f32
    ;
    const source =
        \\entry const integer = func (value: U32): U32 => return @type.call "add" (@type.call "div" value 2) 7
        \\entry const floating = func (value: F32): F32 => return negate value
        \\entry const converted = func (value: U32): F32 => return convert value
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "prelude.blot", .data = prelude_source });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = source });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    const prelude_path = try tmp.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
    defer a.free(prelude_path);
    var loaded = try @import("../reuse/project.zig").load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try @import("../reuse/project_check.zig").checkProject(a, &loaded);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try @import("../reuse/alias_project_pipeline.zig").lowerChecked(a, &loaded, &checked);
    defer frozen.deinit(a);
    var result = try backend.compileWithOptions(a, frozen.units, frozen.entry, .{ .inline_named = false, .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    var module = try result.capture.?.emission.materialize(a);
    defer module.deinit();
    const ir = @import("runtime_ir.zig");
    const Case = struct { op: ir.Op, parameters: []const ir.ValueType, result: ir.ValueType };
    const cases = [_]Case{
        .{ .op = .i32_add, .parameters = &.{ .i32, .i32, .i32 }, .result = .i32 },
        .{ .op = .i32_div_u, .parameters = &.{ .i32, .i32, .i32 }, .result = .i32 },
        .{ .op = .f32_neg, .parameters = &.{ .f32, .i32 }, .result = .f32 },
        .{ .op = .f32_convert_i32_u, .parameters = &.{ .i32, .i32 }, .result = .f32 },
    };
    for (cases) |case| {
        var found = false;
        for (module.functions.items, 0..) |function, index| {
            if (module.runtimeHelper(index) or function.entry or function.locals.items.len != 0) continue;
            if (!std.mem.eql(ir.ValueType, function.parameters, case.parameters) or function.result != case.result or function.result_role != .scalar) continue;
            const operands = case.parameters.len - 1;
            if (function.provider_parameter != operands or function.parameterRole(operands) != .reference) continue;
            const instructions = function.instructions.items;
            if (instructions.len != operands + 1 or instructions[operands].op != case.op) continue;
            var direct = true;
            for (instructions[0..operands], 0..) |inst, operand| {
                if (inst.op != .local_get or inst.operand != operand or function.parameterRole(operand) != .scalar) direct = false;
            }
            found = found or direct;
        }
        if (!found) std.debug.print("missing direct primitive alias {s}\n", .{@tagName(case.op)});
        try std.testing.expect(found);
    }
}

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
    \\const reader = @effect.provider Read (func () => return 1.75)
    \\const state = @effect.state (State.get F32) (State.set F32) 1.75
    \\entry const folded = do reader:
    \\  break Read ()
    \\entry const callback = func () => return do reader:
    \\  break Read ()
    \\entry const answer = func (value: F32) => return do:
    \\  let dynamic = @effect.provider Read (func () => return value)
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
        \\const read = func () => return 42
        \\const requirements = @effect.of read
        \\const count = func effects => return @effect.count effects
        \\entry const run = func () => return count requirements
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
        \\const read = func () => return do:
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
        \\const bump = func (value: U32) => return @u32.add value 1
        \\entry const answer = func (value: U32) => return do:
        \\  let row = { value, flag: true }
        \\  let read = func () => return bump row.value
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
        \\entry const answer = func (value: U32) => return do:
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
        \\entry const answer = func (value: U32) => return do:
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
        \\entry const float_answer = func (value: F32) => return do:
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
    \\const make = func (seed: Array U32) => return func (value: U32) => return @array.get seed value
    \\const saved = make #[7, 42]
    \\entry const run = func (value: U32) => return saved value
    \\entry const pressure = func (count: U32) => return @array.fill count 0
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
        \\entry const run = func (seed: U32) => return do:
        \\  let local = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[seed]
        \\  let (_, result) = do local:
        \\    break State.get (Array U32) ()
        \\  break result[0]
    );
    defer module.deinit(a);
    try providerConstruction(a, &module, true);
}
test "private provider flow covers captured request cancellation and callback source cycle bodies" {
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
        try std.testing.expectEqual(@as(u32, 8), fact.bytes);
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
test "callable construction edges rederive exact closure environments without granting later immutability" {
    const ir = @import("runtime_ir.zig");
    const origins = @import("callable_origins.zig");
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    var module = try built.capture.?.emission.materialize(a);
    defer module.deinit();
    var closure_edge = false;
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
            .zero => continue,
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
    try std.testing.expect(closure_edge);
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

fn callbackActivationGraph(allocator: std.mem.Allocator, journal: *const @import("../reuse/artifact_emitter.zig").Recorder) !void {
    const flow = @import("activation_graph.zig");
    var module = try journal.materialize(allocator);
    defer module.deinit();
    var checked: usize = 0;
    for (module.functions.items, 0..) |_, id| {
        if (module.runtimeHelper(id)) continue;
        var graph = try flow.analyze(allocator, &module, @intCast(id));
        defer graph.deinit(allocator);
        try std.testing.expect(graph.complete or graph.blocker != .none);
        for (graph.stores) |store| {
            try std.testing.expect(store.context < graph.contexts.len);
            try std.testing.expectEqual(store.function, graph.contexts[store.context].function);
        }
        var cohort = try flow.cohort(allocator, &module, @intCast(id));
        defer if (cohort) |*owned| owned.deinit(allocator);
        try std.testing.expect(cohort == null);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}
test "callback activation graphs retain bounded observations and decline invented cycles" {
    var source = try lowerCatalog(a, @import("fixtures").source("provider-fixtures/lifetime-cost.blot"), true);
    defer source.deinit(a);
    var built = try backend.compileWithOptions(a, &.{source}, 1, .{ .inline_named = false, .retain_artifacts = true });
    defer built.deinit(a);
    try callbackActivationGraph(a, &built.capture.?.emission);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, callbackActivationGraph, .{&built.capture.?.emission});
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
        value.table_kind = .unknown;
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
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\const render: forall [a] where { Render a } => a -> U32 = func value => return Render.show value
        \\const forward: forall [a] where { Render a } => a -> U32 = func value => return render value
        \\const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
        \\entry const answer: Unit -> U32 = func () => return both forward
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
        \\impl Number : Render U32 = { const show = func value => return value }
        \\type Item = exists [a] where { Render a } => (Array a, a)
        \\const item: Item = pack [U32] (#[20, 22], 42) as Item
        \\const read = func (value: Item) => return unpack value as [a] payload in Render.show (@product.get payload 1)
        \\entry const answer = func () => return read item
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
        \\impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
        \\impl Flag : Source Bool = { type Item = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
        \\type Package = exists [a] where { Source a } => a
        \\const make = func (flag: Bool) => return if flag then pack [U32] 42 as Package else pack [Bool] true as Package
        \\const seal: forall [a] where { Source a } => a -> Package = func value => return pack [a] value as Package
        \\const read = func (item: Package) => return unpack item as [a] value in Source.show value (Source.get value)
        \\entry const answer = func (flag: Bool) => return read (seal flag)
    );
    defer module.deinit(a);
    try @import("../check/frozen_core_validation.zig").validate(a, &module, .{});
    try emitStaticPackages(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitStaticPackages, .{&module});
}

test "static associated dictionary carriers preserve exact owner emission replay through complete OOM" {
    var module = try lower(a,
        \\type Source a is contract = { type Item, const get: a -> (Source.Item a), const show: a -> (Source.Item a) -> U32 }
        \\impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
        \\impl Flag : Source Bool = { type Item = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
        \\type Package = exists [a] where { Source a } => a
        \\const make = func (flag: Bool) => return if flag then pack [U32] 42 as Package else pack [Bool] true as Package
        \\const read = func (item: Package) => return unpack item as [a] value in Source.show value (Source.get value)
        \\const item: Package = pack [U32] 42 as Package
        \\entry const answer = func () => return read item
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
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\const helper = func value => return Render.show value
        \\const apply = func callback => return func value => return callback value
        \\const sum = func left => return func right => return @u32.add (helper left) (helper right)
        \\const render: forall [a] where { Render a } => a -> a -> U32 = func left => return func right => return apply (sum left) right
        \\const both: (forall [a] where { Render a } => a -> a -> U32) -> U32 = func callback => return @u32.add (callback 20 22) (callback true false)
        \\entry const answer: Unit -> U32 = func () => return both render
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
        \\impl Number : Source U32 = { type Item = U32, const get = func value => return value, const show = func owner => return func value => return value }
        \\impl Flag : Source Bool = { type Item = Bool, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
        \\const helper = func value => return Source.show value (Source.get value)
        \\const render: forall [a] where { Source a } => a -> U32 = func value => return helper value
        \\const both: (forall [a] where { Source a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
        \\entry const answer: Unit -> U32 = func () => return both render
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
        \\const helper: forall [a] where { Tag a } => Unit -> U32 = func unit => return Tag.read unit
        \\entry const answer: Unit -> U32 = func unit => return 42
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
        \\impl Number : Render U32 = { const show = func value => return value }
        \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
        \\const helper = Render.show
        \\const render: forall [a] where { Render a } => a -> U32 = func value => return helper value
        \\const both: (forall [a] where { Render a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
        \\entry const answer: Unit -> U32 = func () => return both render
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
        \\entry const answer: Unit -> U32 = func unit => return 42
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
        "type Hidden is data = $Hidden (unique U32)\ntype Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = Hidden }\n",
        "opaque type Hidden = shared U32\ntype Source a is contract = { type Item }\nimpl Number : Source U32 = { type Item = Hidden }\n",
        "type Hidden is data = $Hidden (shared U32)\ntype Source a is contract = { type Item = Hidden }\n",
        "type Source a is contract = { type Item }\nimpl All a : Source a = { type Item = a }\nconst keep: unique U32 -> (Source.Item (unique U32)) = func value => return value\n",
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
        \\type Hidden is data = $Hidden (shared U32)
        \\opaque type Sealed = shared U32
        \\type Source a is contract = { type Item }
        \\impl Number : Source U32 = { type Item = U32 }
        \\type Fixed a is contract = { type Item = U32 }
        \\const keep = func (owner: unique U32) => return owner
        \\entry const answer: Unit -> U32 = func unit => return 42
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
        \\type Hidden is data = $Hidden (shared U32)
        \\type Source a is contract = { type Item }
        \\impl All a : Source a = { type Item = a }
        \\type Fixed a is contract = { type Item = a }
        \\const keep = func (owner: unique U32) => return owner
        \\entry const answer: Unit -> U32 = func unit => return 42
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
        \\impl Number : Source U32 = { type Item = U32, type Other = Bool, const get = func value => return value, const show = func owner => return func value => return value }
        \\impl Flag : Source Bool = { type Item = Bool, type Other = U32, const get = func value => return value, const show = func owner => return func value => return if value then 7 else 9 }
        \\const helper = Source.get
        \\const render: forall [a] where { Source a } => a -> U32 = func value => return Source.show value (helper value)
        \\const both: (forall [a] where { Source a } => a -> U32) -> U32 = func callback => return @u32.add (callback 42) (callback true)
        \\entry const answer: Unit -> U32 = func () => return both render
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
    const source = try std.mem.replaceOwned(u8, a, @import("fixtures").source("request-fixtures/effectful-dictionary-closure.blot"), "const helper = func value => return Render.show value", "const helper = Render.show");
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
        \\const apply = func (callback: U32 -> U32) => return func (value: U32) => return callback value
        \\const increment = func (value: U32) => return @u32.add value 2
        \\entry const answer = func (value: U32) => return apply increment value
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

test "cohort owner transfer protocol keeps the member outside the allocation journal" {
    var module = try @import("../runtime/cohort_fixture.zig").build(a);
    defer module.deinit();
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer a.free(bytes);
}

fn regionPublicationFixture(allocator: std.mem.Allocator) !void {
    var module = try @import("../runtime/region_fixture.zig").build(allocator);
    defer module.deinit();
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer allocator.free(bytes);
}
test "region owner publication prepares reference endpoints through OOM" {
    var module = try @import("../runtime/region_fixture.zig").build(a);
    defer module.deinit();
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer a.free(bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, regionPublicationFixture, .{});
}

test "region publication declines overlapping owned fields" {
    const region = @import("../runtime/region_runtime.zig");
    const fixture = @import("../runtime/region_fixture.zig");
    var module = @import("wasm.zig").Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    var invalid = fixture.plan;
    invalid.mask |= @as(u32, 1) << 5;
    try std.testing.expectError(error.InvalidRegion, region.install(&module, invalid));
    invalid = fixture.plan;
    invalid.members = &.{ .{ .offset = 20, .bytes = 16 }, .{ .offset = 32, .bytes = 20 } };
    try std.testing.expectError(error.InvalidRegion, region.install(&module, invalid));
    _ = try region.install(&module, fixture.plan);
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

test "selected associated callback annotation retains current concrete method result" {
    var module = try lower(a,
        \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
        \\impl ArraySource a : Source (Array a) = { type Item = a, const first = func values => return @array.get values 0 }
        \\entry const answer = func (value: U32) => return do:
        \\  let selected: (Array U32) -> U32 = Source.first
        \\  break selected #[value]
    );
    defer module.deinit(a);
    try emitInferredDictionary(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitInferredDictionary, .{&module});
    var changed = false;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .reference or module.span(@intCast(id)).start != 282) continue;
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
