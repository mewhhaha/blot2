const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const archive = @import("backend_checkpoint.zig");
const a = std.testing.allocator;
const source =
    \\const delay = fn ~value => value
    \\const pending = delay (@array.fill 3 40)
    \\let saved = @array.fill 3 40
    \\entry const run = fn (index: U32) => do:
    \\  let cached = @force pending
    \\  return @u32.add saved[index] cached[index]
;
const Fixture = struct {
    units: [1]core.Module,
    names: identity.Metadata,
    fn init() !Fixture {
        return initSource(source);
    }
    fn initSource(input: []const u8) !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tokens = try lexer.lex(a, input);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, input, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var module = try core.lower(a, &tree, &pool, &checked);
        errdefer module.deinit(a);
        module.unit = 1;
        return .{ .units = .{module}, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/roots/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        self.names.deinit(a);
    }
    fn emit(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const @import("artifact_capture.zig").Capture, checkpoint: ?*const archive.Checkpoint) !backend.Result {
        return backend.compileWithOptions(allocator, &self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous, .checkpoint = checkpoint });
    }
};

test "cycle zero-child source proof preserves retained checkpoint replay and OOM Wasm" {
    var fixture = try Fixture.initSource(
        \\entry const run = fn (index: U32) => #[41, 42, 43][index]
    );
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    const emission = &first.capture.?.emission;
    try std.testing.expectEqual(@as(u32, 0), emission.functions[emission.arena.?.cycle_collect].instructions.len);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(34);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "strong cycle source owns full helper bodies across retained checkpoint replay and OOM" {
    var fixture = try Fixture.initSource(
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\type Node is data = #End | #Next (Unit -> Node ! {State.get Node})
        \\const keep = fn ~value => fn () => @demand value
        \\const get = fn (witness: Unit -> a) -> a => State.get ()
        \\entry const run = fn (seed: U32) => do:
        \\  let (_, result) = @effect.run State.get State.set #End (fn () => do:
        \\    let delayed = keep (get (fn () => #End))
        \\    use State.set (#Next delayed)
        \\    use first <- delayed ()
        \\    use State.set #End
        \\    use cached <- delayed ()
        \\    return case cached of
        \\      #End => @panic "the demand lost its memoized cycle"
        \\      #Next same => do:
        \\        use again <- same ()
        \\        return case again of
        \\          #End => @panic "the retained closure lost its memo"
        \\          #Next _ => seed
        \\  )
        \\  return result
    );
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    const emission = &first.capture.?.emission;
    try std.testing.expect(emission.functions[emission.arena.?.cycle_collect].instructions.len != 0);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(34);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "persistent List rotations keep borrowed pivots through source preparation and OOM" {
    var fixture = try Fixture.initSource(
        \\entry const forward = fn (count: U32) => do:
        \\  let values: List U32 = []
        \\  for index in 0..count:
        \\    values := [...self, index]
        \\  return @array.from_list values
        \\entry const backward = fn (count: U32) => do:
        \\  let values: List U32 = []
        \\  for index in 0..count:
        \\    values := [index, ...self]
        \\  return @array.from_list values
    );
    defer fixture.deinit();
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
}
fn ownership(bytes: []const u8) !void {
    const index = std.mem.findLast(u8, bytes, "blot:ownership") orelse return error.TestExpectedOwnership;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, bytes[index + "blot:ownership".len ..][0..3]);
}
fn emitScenario(allocator: std.mem.Allocator, fixture: *const Fixture, previous: ?*const @import("artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try fixture.emit(allocator, previous, null);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try ownership(result.bytes);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}
test "persistent source roots preserve fresh retained and portable checkpoint Wasm" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .retain_artifacts = true, .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expect(replayed.diagnostic == null);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try std.testing.expect(retained.reuse.reused_named + retained.reuse.reused_closures > 0);
    const compiler: [32]u8 = @splat(32);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    try ownership(portable.bytes);
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}
test "persistent source root preparation owns all fresh and retained OOM paths" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
}
test "static field ownership rejects misalignment bounds and conflicting roles before publication" {
    var module = @import("wasm.zig").Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const address = try module.dataWords(&.{0});
    try module.staticField(address, .reference);
    try module.staticField(address, .reference);
    try std.testing.expectEqual(@as(usize, 1), module.static_fields.items.len);
    try std.testing.expectError(error.InvalidGlobalReference, module.staticField(address, .scalar));
    try std.testing.expectError(error.InvalidGlobalReference, module.staticField(address + 1, .scalar));
    try std.testing.expectError(error.InvalidGlobalReference, module.staticField(address + 4, .scalar));
    try std.testing.expectEqual(@as(usize, 1), module.static_fields.items.len);
}

test "portable demand receipts reject mismatched callable kinds" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    const semantic = @import("semantic_archive.zig");
    const format = @import("dependency_format.zig");
    const compiler: [32]u8 = @splat(32);
    const bytes = (try semantic.encode(a, compiler, &first.capture.?)).?;
    defer a.free(bytes);
    var snapshot = try format.decode(semantic.Snapshot, a, bytes, semantic.wireKey(compiler));
    defer format.deinit(a, &snapshot);
    try semantic.validate(a, &snapshot);
    var found = false;
    for (snapshot.queries.records) |*record| {
        if (snapshot.evaluator.values[record.key.input].kind != .suspension) continue;
        found = true;
        const before = record.*;
        defer record.* = before;
        for (snapshot.evaluator.evidence.nodes, 0..) |node, index| {
            if (node.tag != .function) continue;
            record.key.expected = @intCast(index);
            try std.testing.expectError(error.InvalidArtifact, semantic.validate(a, &snapshot));
            record.* = before;
            break;
        } else return error.TestExpectedFunctionEvidence;
        const kind = snapshot.evaluator.values[before.key.input].kind;
        snapshot.evaluator.values[before.key.input].kind = .closure;
        defer snapshot.evaluator.values[before.key.input].kind = kind;
        try std.testing.expectError(error.InvalidArtifact, semantic.validate(a, &snapshot));
    }
    try std.testing.expect(found);
}

test "optimizer root context rejects changed static owner-table geometry" {
    const w = @import("wasm.zig");
    const bodies = @import("optimized_bodies.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const address = try module.dataWords(&.{0});
    try module.staticField(address, .scalar);
    try module.finishStaticFields();
    const start = try module.addTypedFunction(&.{}, .none, .scalar);
    try module.setStart(start);
    var before: bodies.Capture = .{ .allocator = a };
    defer before.deinit();
    const initial = try module.assembleWithOptions(.{ .current = &before });
    defer a.free(initial);
    try ownership(initial);
    const extra = try module.dataWords(&.{0});
    try module.staticField(extra, .reference);
    try module.finishStaticFields();
    var after: bodies.Capture = .{ .allocator = a };
    defer after.deinit();
    var stats: bodies.Stats = .{};
    const retained = try module.assembleWithOptions(.{ .previous = &before, .current = &after, .stats = &stats });
    defer a.free(retained);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqual(before.root_slots + 1, after.root_slots);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
    try std.testing.expectEqualSlices(u8, fresh, retained);
}

test "retained caller cleanup rejects changed checked callee result roles" {
    const w = @import("wasm.zig");
    const bodies = @import("optimized_bodies.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const child = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emitSlice(child, &.{
        .{ .op = .i32_const, .operand = 4 },               .{ .op = .i32_const },
        .{ .op = .call, .operand = arena.allocate_typed },
    });
    const caller = try module.addTypedFunction(&.{}, .i32, .scalar);
    try module.emitSlice(caller, &.{
        .{ .op = .call, .operand = child }, .{ .op = .drop }, .{ .op = .i32_const },
    });
    var before: bodies.Capture = .{ .allocator = a };
    defer before.deinit();
    const initial = try module.assembleWithOptions(.{ .current = &before });
    defer a.free(initial);
    try ownership(initial);
    module.functions.items[child].result_role = .scalar;
    var after: bodies.Capture = .{ .allocator = a };
    defer after.deinit();
    const retained = try module.assembleWithOptions(.{ .previous = &before, .current = &after });
    defer a.free(retained);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, retained);
    try std.testing.expect(!std.mem.eql(u8, initial, retained));
    var matcher = try bodies.Matcher.init(a, &before, &after);
    defer matcher.deinit();
    try std.testing.expect(!matcher.matches(child));
    try std.testing.expect(!matcher.matches(caller));
}

test "unchanged variant descriptors preserve erased types through fresh retained checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\type Choice [a, b] is data = #Left a | #Right b
        \\const map = fn transform => fn candidate => case candidate of
        \\  #Left value => #Left (transform value)
        \\  #Right error => #Right error
        \\entry const run = fn (value: U32) => do:
        \\  let candidate = #Left #[value, @u32.add value 1]
        \\  let mapped = map (fn array => array) candidate
        \\  return case mapped of
        \\    #Left array => array[0]
        \\    #Right _ => 0
    );
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(35);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "complete allocation-free modules omit frames without granting raw graphs admission" {
    const w = @import("wasm.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const function = try module.addTypedFunction(&.{}, .i32, .scalar);
    try module.emit(function, .{ .op = .i32_const, .operand = 42 });
    try module.exportFunction(function, "run", .unit, .u32);
    var session = try @import("runtime_pipeline.zig").Session.init(a, &module);
    defer session.deinit();
    try std.testing.expect(session.roots);
    try std.testing.expect(!session.needs_roots);
    var output = try session.optimize(&module.functions.items[function]);
    defer if (output) |*body| body.deinit(a);
    try std.testing.expect(output == null);
    const bytes = try module.assemble();
    defer a.free(bytes);
    try ownership(bytes);
    try module.exportFunction(module.arena.?.allocate_typed, "raw", .unit, .u32);
    var partial = try @import("runtime_pipeline.zig").Session.init(a, &module);
    defer partial.deinit();
    try std.testing.expect(!partial.roots);
}

test "root frame demand changes reject retained rootless bodies and portable candidates" {
    const w = @import("wasm.zig");
    const bodies = @import("optimized_bodies.zig");
    const portable = @import("optimized_archive.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const borrowed = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(borrowed, @import("runtime_ir.zig").packParameterRoles(&.{.reference}));
    try module.emit(borrowed, .{ .op = .local_get });
    var before: bodies.Capture = .{ .allocator = a };
    defer before.deinit();
    const original = try module.assembleWithOptions(.{ .current = &before });
    defer a.free(original);
    try std.testing.expect(before.roots);
    try std.testing.expect(!before.needs_roots);
    try std.testing.expect(before.entries.items[borrowed].output == null);
    const compiler: [32]u8 = @splat(35);
    const archived = try portable.encode(a, compiler, &before);
    defer a.free(archived);
    var checkpoint = try portable.decode(a, compiler, archived);
    defer checkpoint.deinit();
    const owning = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emitSlice(owning, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .call, .operand = arena.allocate_scalar } });
    const fresh = try module.assemble();
    defer a.free(fresh);
    for ([_]*const bodies.Capture{ &before, &checkpoint }) |previous| {
        var current: bodies.Capture = .{ .allocator = a };
        defer current.deinit();
        const retained = try module.assembleWithOptions(.{ .previous = previous, .current = &current });
        defer a.free(retained);
        try std.testing.expectEqualSlices(u8, fresh, retained);
        try std.testing.expect(current.roots);
        try std.testing.expect(current.needs_roots);
        try std.testing.expect(current.entries.items[borrowed].output != null);
        var matcher = try bodies.Matcher.init(a, previous, &current);
        defer matcher.deinit();
        try std.testing.expect(!matcher.matches(borrowed));
    }
}
