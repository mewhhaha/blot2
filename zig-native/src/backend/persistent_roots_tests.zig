const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
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
    \\  break @u32.add saved[index] cached[index]
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
    fn emit(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const @import("../reuse/artifact_capture.zig").Capture, checkpoint: ?*const archive.Checkpoint) !backend.Result {
        return backend.compileWithOptions(allocator, &self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous, .checkpoint = checkpoint });
    }
};

test "single-reference named environments preserve static captures replay changed roles and OOM" {
    var fixture = try Fixture.initSource(
        \\const read = fn (values: Array U32) => fn (index: U32) => values[index]
        \\const add = fn (values: Array U32) => fn (bias: U32) => fn (index: U32) => @u32.add values[index] bias
        \\const selected = read #[41, 8192]
        \\entry const run = fn (seed: U32) => do:
        \\  let values = @array.fill 3 seed
        \\  let partial = add values
        \\  let biased = partial 8192
        \\  let choices = #[selected, read values]
        \\  let chosen = choices[@u32.rem seed 2]
        \\  break @u32.add (biased 1) (chosen 0)
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
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    var changed_fixture = try Fixture.initSource(
        \\const read = fn (value: U32) => fn (index: U32) => value
        \\const add = fn (value: U32) => fn (bias: U32) => fn (index: U32) => @u32.add value bias
        \\const selected = read 8192
        \\entry const run = fn (seed: U32) => do:
        \\  let partial = add seed
        \\  let biased = partial 8192
        \\  let choices = #[selected, read seed]
        \\  let chosen = choices[@u32.rem seed 2]
        \\  break @u32.add (biased 1) (chosen 0)
    );
    defer changed_fixture.deinit();
    var changed = try changed_fixture.emit(a, &first.capture.?, null);
    defer changed.deinit(a);
    var fresh = try changed_fixture.emit(a, null, null);
    defer fresh.deinit(a);
    var changed_portable = try changed_fixture.emit(a, null, &checkpoint);
    defer changed_portable.deinit(a);
    try ownership(changed.bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed.bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed_portable.bytes);
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "immutable algebraic shapes keep acyclic claims through replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\type Link a is data = #End | #Next (Link a, a)
        \\const grow = fn (count: U32) => do:
        \\  let root: Link U32 = #End
        \\  for index in 0..count:
        \\    root := #Next (self, index)
        \\  break root
        \\entry const run = fn (count: U32) => do:
        \\  let root = grow count
        \\  break count
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
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    const changed_source =
        \\type Link a is data = #End | #Next (Link a, a) | #Later (Unit -> a)
        \\const grow = fn (count: U32) => do:
        \\  let root: Link U32 = #End
        \\  for index in 0..count:
        \\    root := #Next (self, index)
        \\  break root
        \\entry const run = fn (count: U32) => do:
        \\  let root = grow count
        \\  break count
    ;
    var changed_fixture = try Fixture.initSource(changed_source);
    defer changed_fixture.deinit();
    var changed = try changed_fixture.emit(a, &first.capture.?, null);
    defer changed.deinit(a);
    var fresh = try changed_fixture.emit(a, null, null);
    defer fresh.deinit(a);
    var changed_portable = try changed_fixture.emit(a, null, &checkpoint);
    defer changed_portable.deinit(a);
    try ownership(changed.bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed.bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed_portable.bytes);
    try std.testing.expect(acyclicClaims(&first) != 0);
    try std.testing.expectEqual(@as(usize, 0), acyclicClaims(&changed));
    try std.testing.expectEqual(@as(usize, 0), acyclicClaims(&changed_portable));
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "single-use generic local storage keeps exact private roles through replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\type Box f is data = #Box f
        \\const box = fn value => #Box value
        \\entry const run = fn (seed: U32) => do:
        \\  let stored = box (fn value => {item: value})
        \\  let #Box mapper = stored
        \\  break @u32.add (mapper seed).item 1
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
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    var reference_fixture = try Fixture.initSource(
        \\type Box f is data = #Box f
        \\const box = fn value => #Box value
        \\entry const run = fn (seed: Array U32) => do:
        \\  let stored = box (fn value => {item: value})
        \\  let #Box mapper = stored
        \\  break @array.length (mapper seed).item
    );
    defer reference_fixture.deinit();
    var changed = try reference_fixture.emit(a, &first.capture.?, null);
    defer changed.deinit(a);
    var fresh = try reference_fixture.emit(a, null, null);
    defer fresh.deinit(a);
    try ownership(changed.bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed.bytes);
    try std.testing.expect(!std.mem.eql(u8, first.bytes, changed.bytes));
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "dynamic Array copies admit exact owners through replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\entry const run = fn (count: U32) => do:
        \\  let left = @array.fill count 41
        \\  let right = @array.fill count 42
        \\  let joined = @array.concat left right
        \\  break @array.length (@array.slice joined 0 count)
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
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "immutable nullary constructor cells preserve changed tags replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\type Token is data = #Left | #Right
        \\entry const run = fn (value: U32) => do:
        \\  let token = if @u32.eq value 0 then #Left else #Right
        \\  break case token of
        \\    #Left => 11
        \\    #Right => 22
    );
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), first.counters.allocation_role_runs);
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
    var replayed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replayed.bytes);
    var changed = try Fixture.initSource(
        \\type Token is data = #Right | #Left
        \\entry const run = fn (value: U32) => do:
        \\  let token = if @u32.eq value 0 then #Left else #Right
        \\  break case token of
        \\    #Left => 11
        \\    #Right => 22
    );
    defer changed.deinit();
    var fresh = try changed.emit(a, null, null);
    defer fresh.deinit(a);
    var edited = try changed.emit(a, &first.capture.?, &checkpoint);
    defer edited.deinit(a);
    try std.testing.expect(fresh.diagnostic == null and edited.diagnostic == null);
    try std.testing.expect(!std.mem.eql(u8, first.bytes, fresh.bytes));
    try std.testing.expectEqualSlices(u8, fresh.bytes, edited.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "capture-free descriptor addresses relocate through retained portable replay and OOM" {
    var fixture = try Fixture.initSource(
        \\const make = fn (value: U32) => { value, apply: fn (input: U32) => @u32.add input 1 }
        \\entry const run = fn (value: U32) => do:
        \\  let holder = make value
        \\  break holder.apply holder.value
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
    try std.testing.expect(retained.reuse.reused_named + retained.reuse.reused_closures > 0);
    const compiler: [32]u8 = @splat(35);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "changed State value roles preserve retained artifact and checkpoint roots through OOM" {
    const definitions =
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\const stable = fn (value: U32) => @u32.add value 1
    ;
    var first = try Fixture.initSource(definitions ++ "\n" ++
        \\const shape = fn (value: U32) => @effect.run State.get State.set #[value] (fn () => do:
        \\  use current <- State.get ()
        \\  break current[0]
        \\)
        \\entry const run = fn (value: U32) => do:
        \\  let (_, result) = shape value
        \\  break stable result
    );
    defer first.deinit();
    var changed = try Fixture.initSource(definitions ++ "\n" ++
        \\const shape = fn (value: U32) => @effect.run State.get State.set value (fn () => do:
        \\  use current <- State.get ()
        \\  break current
        \\)
        \\entry const run = fn (value: U32) => do:
        \\  let (_, result) = shape value
        \\  break stable result
    );
    defer changed.deinit();
    const nodes = try a.dupe(core.Node, changed.units[0].nodes);
    defer a.free(nodes);
    var before = try first.emit(a, null, null);
    defer before.deinit(a);
    var fresh = try changed.emit(a, null, null);
    defer fresh.deinit(a);
    try std.testing.expect(before.diagnostic == null and fresh.diagnostic == null);
    try ownership(before.bytes);
    try ownership(fresh.bytes);
    try std.testing.expect(!std.mem.eql(u8, before.bytes, fresh.bytes));
    var retained = try changed.emit(a, &before.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(35);
    const saved = try archive.encode(a, compiler, &before.capture.?);
    defer a.free(saved);
    var checkpoint = try archive.decode(a, compiler, saved);
    defer checkpoint.deinit();
    var restarted = try changed.emit(a, null, &checkpoint);
    defer restarted.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, restarted.bytes);
    var replayed = try backend.compileWithOptions(a, &changed.units, 1, .{ .identity = changed.names.view(), .artifact_replay = true });
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, replayed.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &changed, &before.capture.?, fresh.bytes });
    try std.testing.expectEqualDeep(nodes, changed.units[0].nodes);
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
        \\    break case cached of
        \\      #End => @panic "the demand lost its memoized cycle"
        \\      #Next same => do:
        \\        use again <- same ()
        \\        break case again of
        \\          #End => @panic "the retained closure lost its memo"
        \\          #Next _ => seed
        \\  )
        \\  break result
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "persistent List rotations keep borrowed pivots through source preparation and OOM" {
    var fixture = try Fixture.initSource(
        \\entry const forward = fn (count: U32) => do:
        \\  let values: List U32 = []
        \\  for index in 0..count:
        \\    values := [...self, index]
        \\  break @array.from_list values
        \\entry const backward = fn (count: U32) => do:
        \\  let values: List U32 = []
        \\  for index in 0..count:
        \\    values := [index, ...self]
        \\  break @array.from_list values
    );
    defer fixture.deinit();
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
}
fn ownership(bytes: []const u8) !void {
    const index = std.mem.findLast(u8, bytes, "blot:ownership") orelse return error.TestExpectedOwnership;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, bytes[index + "blot:ownership".len ..][0..3]);
}
fn emitScenario(allocator: std.mem.Allocator, fixture: *const Fixture, previous: ?*const @import("../reuse/artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try fixture.emit(allocator, previous, null);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try ownership(result.bytes);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}

const static_capture_source =
    \\type Pack [unused, selected] is data = #Pack {unused: unused, selected: selected}
    \\const identity = fn value => value
    \\const packed = #Pack {unused: identity, selected: fn (value: U32) => @u32.add value 1}
    \\const invoke = fn callback => callback 1
    \\const capture = fn packed => fn (value: U32) => invoke (fn extra => do:
    \\  let #Pack {selected} = packed
    \\  break selected (@u32.add value extra))
    \\const work = fn (value: U32) => do:
    \\  let total = 0
    \\  let index = 0
    \\  for ever:
    \\    if @u32.eq index value:
    \\      break
    \\    total := @u32.add self (capture packed index)
    \\    index := @u32.add self 1
    \\  break total
    \\const offset = 10
    \\entry const answer = fn (value: U32) => @u32.add (work value) offset
;
fn staticCaptureReplay(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const @import("../reuse/artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try fixture.emit(allocator, previous, null);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expect(result.reuse.reused_named > 0);
    try std.testing.expectEqual(@as(usize, 0), result.reuse.fresh_closures);
}
test "static captured value graphs admit executable closure replay independently of principal mappings" {
    var before = try Fixture.initSource(static_capture_source);
    defer before.deinit();
    var first = try before.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    var static_jobs: usize = 0;
    for (first.capture.?.metadata.jobs.items) |job| if (job.request == .closure and job.request.closure.static_values != 0) {
        static_jobs += 1;
        try std.testing.expect(job.reusable);
        // Executable graph admission must not publish a solved principal
        // receipt from a generalized static field's erased layout.
        try std.testing.expect(!job.solved);
    };
    try std.testing.expect(static_jobs != 0);
    const edited = try std.mem.replaceOwned(u8, a, static_capture_source, "offset = 10", "offset = 11");
    defer a.free(edited);
    var after = try Fixture.initSource(edited);
    defer after.deinit();
    var fresh = try after.emit(a, null, null);
    defer fresh.deinit(a);
    try std.testing.expect(fresh.diagnostic == null);
    try staticCaptureReplay(a, &after, &first.capture.?, fresh.bytes);
    const original = @import("../reuse/code_artifacts.zig").stamp(first.capture.?.metadata.pools.?.evaluator.values);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, staticCaptureReplay, .{ &after, &first.capture.?, fresh.bytes });
    try std.testing.expectEqual(original, @import("../reuse/code_artifacts.zig").stamp(first.capture.?.metadata.pools.?.evaluator.values));
}

test "promoted generalized local initializers retain fresh code and exact wrapper body dependencies" {
    var fixture = try Fixture.initSource(
        \\type Box f is data = #Box f
        \\const box = fn value => #Box value
        \\const get = fn (#Box mapper) => mapper
        \\entry const run = fn (seed: U32) => do:
        \\  let stored = box (fn value => {item: value})
        \\  let read = fn (value: U32) => (get stored value).item
        \\  break read seed
    );
    defer fixture.deinit();
    var result = try fixture.emit(a, null, null);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    const module = &fixture.units[0];
    const run = for (module.bodies) |body| {
        if (body.exported and std.mem.eql(u8, module.name(body.export_name), "run")) break core.BindingRef{ .unit = 1, .binding = body.binding };
    } else return error.MissingRun;
    var wrapper = for (module.nodes) |node| {
        if (node.tag == .bind and module.node(node.b).tag == .call) break module.call(node.b).target;
    } else return error.MissingInitializer;
    if (wrapper.unit == 0) wrapper.unit = 1;
    try std.testing.expectEqual(core.Tag.construct, module.node(module.body(wrapper.binding).?.root).tag);
    const owner = for (result.capture.?.metadata.jobs.items) |*job| {
        if (job.request == .named and std.meta.eql(job.request.named.target, run)) break job;
    } else return error.MissingRunOwner;
    try std.testing.expect(!owner.reusable);
    const reads_wrapper = for (owner.inline_bodies.items) |read| {
        if (std.meta.eql(read, wrapper)) break true;
    } else false;
    try std.testing.expect(reads_wrapper);
}

test "generalized runtime locals used at different layouts evaluate one checked instance per layout through replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\const pair = fn a => fn b => (a, b)
        \\entry const run = fn (seed: U32) => do:
        \\  let k = pair (@array.fill 2 seed)
        \\  let alias = k
        \\  let (whole, _) = alias seed
        \\  let (_, half) = k 1.5
        \\  let (_, next) = alias (@u32.add seed 1)
        \\  break @u32.add (@u32.add whole[0] next) (@f32.to_u32 half)
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
    const compiler: [32]u8 = @splat(36);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

// Issue #10 (Ink app-hooks): `play` leaves the curried callback's rows open,
// so serializing it infers each of its own arrows; the rebound link reads the
// promoted `empty ()` value and is promoted too.
test "promoted generalized builder chains serialize curried callbacks through replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\type App [world, scope, render] is data = #App { initial: world, scope: world -> scope, render: render }
        \\type Trace is data = #Trace (Array U32)
        \\const empty = fn () => do:
        \\  let scope = fn world => fn action => do:
        \\    use outcome <- @effect.run State.get State.set world action
        \\    break outcome
        \\  break #App { initial: #Trace #[], scope, render: fn (frame: U32) => frame }
        \\const note = fn (value: U32) => do:
        \\  use current <- State.get ()
        \\  let #Trace values = current
        \\  break State.set (#Trace #[...values, value])
        \\const with_render = fn render => fn app => do:
        \\  let #App { initial, scope } = app
        \\  break #App { initial, scope, render }
        \\const initial = fn app => do:
        \\  let #App { initial } = app
        \\  break initial
        \\const play = fn app => fn world => fn action => do:
        \\  let #App { scope } = app
        \\  break scope world action
        \\const draw = fn app => fn frame => do:
        \\  let #App { render } = app
        \\  break render 2 frame
        \\entry const run = fn (seed: U32) => do:
        \\  let app = empty ()
        \\  app := with_render (fn (scale: U32) => fn (frame: U32) => do:
        \\    use note frame
        \\    break @u32.mul frame scale) self
        \\  let (trace, doubled) = play app (initial app) (fn () => draw app seed)
        \\  let #Trace values = trace
        \\  break @u32.add doubled (@array.length values)
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
    const compiler: [32]u8 = @splat(37);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

// Issue #10 (Ink effect repro c1): `@array.length boxed` leaves the scope's
// action result open, and `create` serializes the systems whole while no use
// applies the route. Those variables and the route's row are ambiguous, so
// the body stores them as a word and a pure row; `boxed`'s own quantified
// hole still takes one instance per layout.
test "ambiguous holes at generalized local uses take word storage through replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(
        \\type B [w, s] is data = #B { initial: w, s: w -> s }
        \\type System [route, start] is data = #Route route | #Start start
        \\type App [engine, system] is data = #App { engine: engine, systems: Array system }
        \\const empty = fn () => do:
        \\  let scope = fn world => fn action => do:
        \\    use result <- action ()
        \\    break (world, result)
        \\  break #B { initial: (), s: scope }
        \\const enter = fn b => fn action => do:
        \\  let #B { initial, s } = b
        \\  break s initial action
        \\const new_with = fn route => #App { engine: empty (), systems: #[#Route route, #Start (fn () => ())] }
        \\const create = fn app => fn () => do:
        \\  let #App { engine, systems } = app
        \\  let (world, _) = enter engine (fn () => @array.length systems)
        \\  break world
        \\entry const run = fn (seed: U32) => do:
        \\  let b = empty ()
        \\  let (_, first) = enter b (fn () => seed)
        \\  let boxed = #[b, b]
        \\  let (_, values) = enter (@array.get boxed 1) (fn () => @array.fill 2 seed)
        \\  let app = new_with (fn (e: u) => e)
        \\  let world = create app ()
        \\  break @u32.add (@u32.add first (@array.get values 0)) (@array.length boxed)
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
    const compiler: [32]u8 = @splat(38);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
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
    const semantic = @import("../reuse/semantic_archive.zig");
    const format = @import("../reuse/dependency_format.zig");
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
        \\  #Right error => do:
        \\    break #Right error
        \\entry const run = fn (value: U32) => do:
        \\  let candidate = #Left #[value, @u32.add value 1]
        \\  let mapped = map (fn array => array) candidate
        \\  break case mapped of
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
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

fn genericWordEmission(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var result = try backend.compileWithOptions(allocator, &fixture.units, 1, .{ .identity = fixture.names.view() });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try ownership(result.bytes);
}

test "unobserved generic identities keep complete ownership through replay and allocation failure" {
    var fixture = try Fixture.initSource(
        \\const holder = fn () => #{ f0: fn x => x, f1: fn x => x, g: 4 }
        \\const s0 = fn () => (holder ()).g
        \\const s1 = fn () => @u32.add (holder ()).g (s0 ())
        \\entry const run = fn () => s1 ()
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, genericWordEmission, .{&fixture});
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "root frame demand changes reject retained rootless bodies and portable candidates" {
    const w = @import("wasm.zig");
    const bodies = @import("optimized_bodies.zig");
    const portable = @import("../reuse/optimized_archive.zig");
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

fn acyclicClaims(result: *const backend.Result) usize {
    const emission = &result.capture.?.emission;
    var count: usize = 0;
    for (emission.instructions) |instruction| if (instruction.op == .call and instruction.operand.value == emission.arena.?.mark_acyclic) {
        count += 1;
    };
    return count;
}

fn ownedFieldAdmission(allocator: std.mem.Allocator, conflict: bool) !void {
    const w = @import("wasm.zig");
    const ir = @import("runtime_ir.zig");
    const bodies = @import("optimized_bodies.zig");
    const portable = @import("../reuse/optimized_archive.zig");
    var module = w.Module.init(allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.setParameterRoles(function, ir.packParameterRoles(&.{.reference}));
    const object = try module.addLocal(function, .i32);
    const alias = try module.addLocal(function, .i32);
    var buffer: [ir.max_annotations]ir.Instruction = undefined;
    try module.emit(function, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 0 }) });
    try module.emitSlice(function, ir.annotations(&.{ .reference, .scalar }, .scalar, &buffer));
    try module.emitSlice(function, &.{
        .{ .op = .i32_const, .operand = 8 },      .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        .{ .op = .local_get, .operand = object }, .{ .op = .local_get },                       .{ .op = .i32_store },
        .{ .op = .local_get, .operand = object }, .{ .op = .i32_const, .operand = 8192 },      .{ .op = .i32_store, .operand = 4 },
        .{ .op = .local_get, .operand = object }, .{ .op = .local_set, .operand = alias },
    });
    try module.emit(function, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 2, .roles = @intCast(alias) }) });
    try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = alias }, .{ .op = .i32_load }, .{ .op = .i32_load, .operand = 4 } });
    const original = try allocator.dupe(ir.Instruction, module.functions.items[function].instructions.items);
    defer allocator.free(original);
    var before: bodies.Capture = .{ .allocator = allocator };
    defer before.deinit();
    const initial = try module.assembleWithOptions(.{ .current = &before });
    defer allocator.free(initial);
    try ownership(initial);
    const compiler: [32]u8 = @splat(47);
    const encoded = try portable.encode(allocator, compiler, &before);
    defer allocator.free(encoded);
    var checkpoint = try portable.decode(allocator, compiler, encoded);
    defer checkpoint.deinit();
    var exposed: bodies.Capture = .{ .allocator = allocator };
    defer exposed.deinit();
    const exported = try module.assembleWithOptions(.{ .previous = &before, .current = &exposed, .export_function_table = true });
    defer allocator.free(exported);
    const exported_fresh = try module.assembleWithOptions(.{ .export_function_table = true });
    defer allocator.free(exported_fresh);
    try std.testing.expectEqualSlices(u8, exported_fresh, exported);
    try std.testing.expect(!exposed.roots);
    var exported_matcher = try bodies.Matcher.init(allocator, &before, &exposed);
    defer exported_matcher.deinit();
    try std.testing.expect(!exported_matcher.matches(function));
    if (conflict) {
        // A private scalar slot storing another allocation's address creates
        // a source role conflict, independently of the owning cursor above.
        const other = try module.addTypedFunction(&.{}, .i32, .scalar);
        const child = try module.addLocal(other, .i32);
        const parent = try module.addLocal(other, .i32);
        try module.emitSlice(other, ir.annotations(&.{.scalar}, .scalar, &buffer));
        try module.emitSlice(other, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = child } });
        try module.emitSlice(other, ir.annotations(&.{.scalar}, .scalar, &buffer));
        try module.emitSlice(other, &.{
            .{ .op = .i32_const, .operand = 4 },      .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = parent },
            .{ .op = .local_get, .operand = parent }, .{ .op = .local_get, .operand = child },     .{ .op = .i32_store },
            .{ .op = .i32_const, .operand = 42 },
        });
        var summaries = try @import("wasm_lifetimes.zig").Summaries.init(allocator, &module);
        defer summaries.deinit();
        try summaries.prepare();
        try std.testing.expect(summaries.role_conflicts != 0);
    }
    // An unrelated dynamic raw allocation declines only the final RC proof.
    const unproven = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.emitSlice(unproven, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = arena.allocate } });
    const fresh = try module.assemble();
    defer allocator.free(fresh);
    for ([_]*const bodies.Capture{ &before, &checkpoint }) |previous| {
        var current: bodies.Capture = .{ .allocator = allocator };
        defer current.deinit();
        const retained = try module.assembleWithOptions(.{ .previous = previous, .current = &current });
        defer allocator.free(retained);
        try std.testing.expectEqualSlices(u8, fresh, retained);
        try std.testing.expect(!current.roots);
        var matcher = try bodies.Matcher.init(allocator, previous, &current);
        defer matcher.deinit();
        try std.testing.expect(!matcher.matches(function));
        const output = current.output(function).?;
        var allocations: usize = 0;
        for (output.instructions.items) |instruction| if (instruction.op == .call and instruction.operand == arena.allocate_typed) {
            allocations += 1;
        };
        try std.testing.expectEqual(@as(usize, 1), allocations);
    }
    try std.testing.expectEqualSlices(ir.Instruction, original, module.functions.items[function].instructions.items);
}

test "single-use selected member storage retains private checked fields through replay and OOM" {
    var fixture = try Fixture.initSource(
        \\type Box f is data = #Box f
        \\type Factory a is data = #Factory a
        \\const Factory.boxed = fn (factory: Factory a) => #Box (fn value => {item: value, factory: factory})
        \\entry const run = fn (seed: U32) => do:
        \\  let factory = #Factory seed
        \\  let stored = factory.boxed
        \\  let #Box mapper = stored
        \\  break @u32.add (mapper seed).item 1
    );
    defer fixture.deinit();
    const stamp = @import("../check/core_snapshot_tests.zig").stamp(fixture.units[0]);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    try emitScenario(a, &fixture, &first.capture.?, first.bytes);
    const compiler: [32]u8 = @splat(35);
    const encoded = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(encoded);
    var checkpoint = try archive.decode(a, compiler, encoded);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try std.testing.expectEqual(stamp, @import("../check/core_snapshot_tests.zig").stamp(fixture.units[0]));
}

test "late module ownership failure restores owning field objects through retained portable and OOM" {
    for ([_]bool{ false, true }) |conflict| {
        try ownedFieldAdmission(a, conflict);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, ownedFieldAdmission, .{conflict});
    }
}

test "private cursor constructor body reads invalidate retained and portable admission" {
    const input =
        \\const make = fn values => @list.cursor values
        \\entry const run = fn (count: U32) => do:
        \\  let values = @list.fill count {x: 41, y: 8192}
        \\  let cursor = make values
        \\  let sum = 0
        \\  for index in 0..count:
        \\    let row = @cursor.value cursor
        \\    sum := @u32.add self row.x
        \\    cursor := @cursor.advance self
        \\  break sum
    ;
    var fixture = try Fixture.initSource(input);
    defer fixture.deinit();
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(47);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    var portable = try fixture.emit(a, null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, portable.bytes);
    var changed_fixture = try Fixture.initSource(
        \\const make = fn values => do:
        \\  let copy = @array.from_list values
        \\  break @list.cursor (@list.from_array copy)
        \\entry const run = fn (count: U32) => do:
        \\  let values = @list.fill count {x: 41, y: 8192}
        \\  let cursor = make values
        \\  let sum = 0
        \\  for index in 0..count:
        \\    let row = @cursor.value cursor
        \\    sum := @u32.add self row.x
        \\    cursor := @cursor.advance self
        \\  break sum
    );
    defer changed_fixture.deinit();
    var changed = try changed_fixture.emit(a, &first.capture.?, null);
    defer changed.deinit(a);
    var fresh = try changed_fixture.emit(a, null, null);
    defer fresh.deinit(a);
    var changed_portable = try changed_fixture.emit(a, null, &checkpoint);
    defer changed_portable.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed.bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed_portable.bytes);
    try std.testing.expect(!std.mem.eql(u8, first.bytes, fresh.bytes));
}

test "scalar closure environments preserve snapshots physical roles replay checkpoints and complete OOM" {
    var fixture = try Fixture.initSource(
        \\entry const run = fn (seed: U32) => do:
        \\  let value = seed
        \\  let callback = fn (index: U32) => do:
        \\    let total = value
        \\    for i in 0..index:
        \\      total := @u32.add self i
        \\    break total
        \\  value := @u32.add self 1
        \\  let choices = #[callback, fn (index: U32) => @u32.add value index]
        \\  break (choices[@u32.rem seed 2]) 3
    );
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    var scalar: usize = 0;
    for (first.capture.?.metadata.jobs.items) |job| if (job.request == .closure and job.request.closure.scalar_environment) {
        const function = job.function orelse return error.TestExpectedEqual;
        var role: ?u64 = null;
        for (first.capture.?.emission.records.items) |record| if (record.event == .parameter_roles and record.event.parameter_roles.function == function) {
            role = record.event.parameter_roles.roles;
        };
        try std.testing.expectEqual(@as(u64, @backingInt(@import("runtime_ir.zig").Role.scalar)), role.? & 3);
        scalar += 1;
    };
    try std.testing.expect(scalar != 0);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(47);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

// An Array-returning insertion sort with breaks: both carried numeric Arrays
// are edited in place, so every iteration journal operation is a duplicate.
const in_place_sort_source =
    \\const sort = fn (count: U32) -> Array U32 => do:
    \\  let keys = @array.generate count (fn (i: U32) => @u32.sub count i)
    \\  let ids = @array.generate count (fn (i: U32) => i)
    \\  for i in 1..count:
    \\    let j = i
    \\    for 0..i:
    \\      if @u32.eq j 0:
    \\        break
    \\      let previous = keys[@u32.sub j 1]
    \\      let current = keys[j]
    \\      if @u32.lt previous (@u32.add current 1):
    \\        break
    \\      keys[j] := previous
    \\      keys[@u32.sub j 1] := current
    \\      let previous_id = ids[@u32.sub j 1]
    \\      let current_id = ids[j]
    \\      ids[j] := previous_id
    \\      ids[@u32.sub j 1] := current_id
    \\      j := @u32.sub j 1
    \\  break ids
    \\entry const run = fn (count: U32) => (sort count)[0]
;
const LoopJournal = struct { loops: usize = 0, calls: usize = 0, opens: usize = 0 };
/// Root journal helper calls executed inside loops of the prepared bodies.
fn loopJournal(result: *const backend.Result) LoopJournal {
    const optimized = &result.capture.?.optimized.?;
    const arena = optimized.arena.?;
    var total: LoopJournal = .{};
    for (optimized.entries.items) |entry| {
        const body = entry.output orelse continue;
        var loops: [256]bool = undefined;
        var depth: usize = 0;
        var inside: usize = 0;
        for (body.instructions.items) |inst| switch (inst.op) {
            .block, .loop, .if_ => {
                loops[depth] = inst.op == .loop;
                depth += 1;
                if (inst.op == .loop) {
                    inside += 1;
                    total.loops += 1;
                }
            },
            .end => {
                depth -= 1;
                if (loops[depth]) inside -= 1;
            },
            .call => if (inside != 0) {
                if (inst.operand == arena.root_open) total.opens += 1;
                if (inst.operand == arena.root_open or inst.operand == arena.root_reserve or inst.operand == arena.root_store or inst.operand == arena.root_close) total.calls += 1;
            },
            else => {},
        };
    }
    return total;
}
fn inPlaceLoopScenario(allocator: std.mem.Allocator, fixture: *const Fixture, previous: ?*const @import("../reuse/artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try fixture.emit(allocator, previous, null);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try ownership(result.bytes);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    const journal = loopJournal(&result);
    try std.testing.expect(journal.loops >= 2);
    try std.testing.expectEqual(@as(usize, 0), journal.calls);
}

test "in-place Array-returning loops emit no per-iteration journal operations through replay checkpoint and OOM" {
    var fixture = try Fixture.initSource(in_place_sort_source);
    defer fixture.deinit();
    const nodes = try a.dupe(core.Node, fixture.units[0].nodes);
    defer a.free(nodes);
    var first = try fixture.emit(a, null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try ownership(first.bytes);
    // Both carried Arrays keep one stable slot and its first strong store
    // outside the loops; no iteration opens, reserves, stores or closes.
    const journal = loopJournal(&first);
    try std.testing.expect(journal.loops >= 2);
    try std.testing.expectEqual(@as(usize, 0), journal.calls);
    var developed = try backend.compileWithOptions(a, &fixture.units, 1, .{ .identity = fixture.names.view(), .retain_artifacts = true, .policy = .{ .codegen_tier = .development } });
    defer developed.deinit(a);
    try std.testing.expect(developed.diagnostic == null);
    try ownership(developed.bytes);
    try std.testing.expectEqual(@as(usize, 0), loopJournal(&developed).calls);
    var retained = try fixture.emit(a, &first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(36);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, inPlaceLoopScenario, .{ &fixture, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, inPlaceLoopScenario, .{ &fixture, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, fixture.units[0].nodes);
}

test "shared carries, fresh replacements and owning element stores keep their loop journal operations" {
    for ([_][]const u8{
        // A live alias makes every edit copy: the slot store is real and the
        // iteration keeps owning its incoming version.
        \\entry const run = fn (count: U32) => do:
        \\  let values = @array.fill count 0
        \\  let before = values
        \\  for i in 0..count:
        \\    values[i] := i
        \\  break @u32.add before[0] values[@u32.sub count 1]
        ,
        // A fresh replacement each iteration is a real new owner.
        \\entry const run = fn (count: U32) => do:
        \\  let values = @array.fill 2 0
        \\  for i in 0..count:
        \\    values := @array.fill 2 i
        \\  break values[1]
        ,
        // Owning element stores publish a counted edge per iteration.
        \\entry const run = fn (count: U32) => do:
        \\  let rows = @array.fill count (@array.fill 1 0)
        \\  for i in 0..count:
        \\    rows[i] := @array.fill 1 i
        \\  break rows[0][0]
        ,
    }) |text| {
        var fixture = try Fixture.initSource(text);
        defer fixture.deinit();
        var result = try fixture.emit(a, null, null);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        try ownership(result.bytes);
        const journal = loopJournal(&result);
        try std.testing.expect(journal.calls != 0);
        try std.testing.expect(journal.opens != 0);
    }
}
