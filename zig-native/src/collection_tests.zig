const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const ownership = @import("owned_arrays.zig");
const wasm = @import("wasm.zig");

fn lower(a: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(a, &tree, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
test "collection builders consume a private accumulator across guarded loop carries" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const compact = fn (values: Array U32) =>
        \\  #[@u32.add i 1 | i <- values, @u32.lt 0 i]
    );
    defer module.deinit(a);
    var proof = try ownership.Proof.init(a, &.{module}, 1);
    defer proof.deinit(a);
    var admitted: usize = 0;
    for (module.nodes, 0..) |node, index| if (node.tag == .array_op and module.arrayOperation(@intCast(index)) == .append) {
        admitted += @intFromBool(proof.admits(@intCast(index)));
    };
    try std.testing.expectEqual(@as(usize, 1), admitted);
}

fn frontendFailures(a: std.mem.Allocator) !void {
    var module = try lower(a,
        \\entry const build = fn (values: Array U32) =>
        \\  #[@u32.add i offset | i <- values, @u32.lt 0 i, let offset = 2]
        \\entry const append = fn (value: U32) => do:
        \\  let xs = @array.from_list [value, ...[1, 2], 3]
        \\  xs[0] := 42
        \\  return xs[0]
    );
    defer module.deinit(a);
    var proof = try ownership.Proof.init(a, &.{module}, 1);
    defer proof.deinit(a);
}
test "collection desugaring checking and owned publication release every allocation failure" {
    try frontendFailures(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, frontendFailures, .{});
}
fn runtimeFailures(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const first = try module.ensureLists();
    const count = module.functions.items.len;
    try std.testing.expectEqual(first, try module.ensureLists());
    try std.testing.expectEqual(count, module.functions.items.len);
}
test "Chunk list runtime publication releases every allocation failure" {
    try runtimeFailures(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, runtimeFailures, .{});
}

fn packedEmissionFailures(a: std.mem.Allocator, units: []const core.Module) !void {
    var result = try @import("core_backend.zig").compileWithOptions(a, units, 1, .{ .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "packed array constants and runtime copies release every emission allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const saved = [(3, 7)]
        \\entry const run = fn (value: U32) => do:
        \\  let rows = @array.fill 2 (value, value)
        \\  let copied = @array.from_list (@list.concat (@list.from_array rows) saved)
        \\  let row = @array.get copied 2
        \\  let (left, right) = row
        \\  return @u32.add left right
    );
    defer module.deinit(a);
    const units = [_]core.Module{module};
    try packedEmissionFailures(a, &units);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
}

test "collection ownership rejects an old value observed after an update and on either branch" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (flag: Bool) => do:
        \\  let xs = [1, 2]
        \\  let old = xs
        \\  if flag:
        \\    xs := @list.append xs 3
        \\  else:
        \\    xs := @list.prepend xs 4
        \\  return @u32.add (@list.length old) (@list.length xs)
    );
    defer module.deinit(a);
    var proof = try ownership.Proof.init(a, &.{module}, 1);
    defer proof.deinit(a);
    for (module.nodes, 0..) |node, index| if (node.tag == .array_op) {
        const op = module.arrayOperation(@intCast(index));
        if (op == .append or op == .prepend) try std.testing.expect(!proof.admits(@intCast(index)));
    };
}

test "packed List span emission preserves immutable Core under allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (count: U32) => do:
        \\  let values = @list.generate count (fn (i: U32) => (i, i, i))
        \\  let total = 0
        \\  for pass in 0..2:
        \\    for (x, y, z) in values:
        \\      for (first, _, _) in values:
        \\        total := @u32.add total first
        \\        break
        \\      total := @u32.add total (@u32.add x (@u32.add y z))
        \\  return total
    );
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    try packedEmissionFailures(a, &units);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "packed List borrowed row emission preserves immutable Core under allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (count: U32) => do:
        \\  let values = @list.generate count (fn (i: U32) => {a: i, b: i, c: i})
        \\  let total = 0
        \\  for pass in 0..2:
        \\    for row in values:
        \\      for first in values:
        \\        total := @u32.add total first.a
        \\        break
        \\      total := @u32.add total (@u32.add row.a row.c)
        \\  return total
    );
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    try packedEmissionFailures(a, &units);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "ordinary checked row consumers remove per-row scalar boxes" {
    const a = std.testing.allocator;
    for ([_][]const u8{ "array", "list" }) |collection| {
        const text = try a.print(
            \\const seed = {{a: 1, b: 2, c: 3}}
            \\const consume = fn row => @u32.add (@u32.add row.a row.b) row.c
            \\entry const run = fn (count: U32) => do:
            \\  let values = @{s}.fill count seed
            \\  let total = 0
            \\  for row in values:
            \\    total := @u32.add total (consume row)
            \\  return total
            \\
        , .{collection});
        defer a.free(text);
        var module = try lower(a, text);
        defer module.deinit(a);
        var result = try @import("core_backend.zig").compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true });
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        const capture = &result.capture.?;
        const optimized = &capture.optimized.?;
        var found = false;
        for (capture.metadata.pools.?.functions) |function| {
            if (function.request != .named or function.request.named.target.binding != module.bodies[module.bodies.len - 1].binding) continue;
            found = true;
            const entry_ = &optimized.entries.items[function.function];
            var instructions = entry_.source.instructions.items;
            if (entry_.output) |body| instructions = body.instructions.items;
            for (instructions) |inst| {
                // List directory scratch has a mixed role and remains owned.
                // A temporary flat row always uses the checked scalar allocator.
                if (inst.op == .call) try std.testing.expect(inst.operand != optimized.arena.?.allocate_scalar);
            }
        }
        if (!found) std.debug.print("row fusion {s} missed source binding {d}\n", .{ collection, module.bodies[module.bodies.len - 1].binding });
        try std.testing.expect(found);
        const before = @import("core_snapshot_tests.zig").stamp(module);
        const units = [_]core.Module{module};
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
        try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
    }
}

test "ordinary numeric scope helpers lower to vector stores with immutable Core" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const calculate = fn (index: U32) => do:
        \\  let shifted = @u32.add index 17
        \\  let wrapped = @u32.mul shifted 4294967295
        \\  return @u32.add wrapped 1
        \\entry const run = fn (count: U32) => @array.generate count calculate
    );
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var result = try @import("core_backend.zig").compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    var vector_stores: usize = 0;
    const capture = &result.capture.?;
    for (capture.metadata.pools.?.functions) |function| {
        if (function.request != .named or function.request.named.target.binding != module.bodies[module.bodies.len - 1].binding) continue;
        const entry_ = &capture.optimized.?.entries.items[function.function];
        if (entry_.output) |body| for (body.instructions.items) |inst| {
            if (inst.op == .v128_store) vector_stores += 1;
        };
    }
    try std.testing.expect(vector_stores != 0);
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "ordinary checked row products lower to SIMD without reordering scalar additions" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const seed = {a: 1.0, b: 2.0, c: 3.0, d: 4.0}
        \\const consume = fn row => @f32.add (@f32.add (@f32.add (@f32.mul row.a 1.25) (@f32.mul row.b 1.25)) (@f32.mul row.c 1.25)) (@f32.mul row.d 1.25)
        \\entry const run = fn (count: U32) => do:
        \\  let rows = @array.fill count seed
        \\  let total = 0.0
        \\  for row in rows:
        \\    total := @f32.add total (consume row)
        \\  return total
    );
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var result = try @import("core_backend.zig").compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    const capture = &result.capture.?;
    var vector_products: usize = 0;
    for (capture.metadata.pools.?.functions) |function| {
        if (function.request != .named or function.request.named.target.binding != module.bodies[module.bodies.len - 1].binding) continue;
        const entry_ = &capture.optimized.?.entries.items[function.function];
        if (entry_.output) |body| for (body.instructions.items) |inst| {
            if (inst.op == .f32x4_mul) vector_products += 1;
        };
    }
    try std.testing.expect(vector_products != 0);
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

fn privateCursorEmission(a: std.mem.Allocator, units: []const core.Module, previous: ?*const @import("artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try @import("core_backend.zig").compileWithOptions(a, units, 1, .{ .retain_artifacts = true, .previous = previous });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}
test "private cursor versions keep immutable Core replay and emission OOM ownership" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const make = fn values => @list.cursor values
        \\entry const run = fn (count: U32) => do:
        \\  let values = @list.fill count {x: 41, y: 8192}
        \\  let cursor = make values
        \\  let original = cursor
        \\  let sum = 0
        \\  for i in 0..count:
        \\    let row = @cursor.value cursor
        \\    sum := @u32.add self row.x
        \\    cursor := @cursor.advance self
        \\  return @u32.add sum (@cursor.value original).y
    );
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try privateCursorEmission(a, &units, &first.capture.?, first.bytes);
    var replay = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .artifact_replay = true });
    defer replay.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replay.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, null, first.bytes });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, &first.capture.?, first.bytes });
    try std.testing.expectEqualDeep(nodes, module.nodes);
}
test "eager tuple reductions keep immutable Core fresh retained replay and emission OOM ownership" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\infixl 60 (+) = add
        \\const primitive = fn (left: U32) => fn (right: U32) => @u32.add left right
        \\const add = fn (left: U32) => fn (right: U32) => primitive left right
        \\entry const run = fn (count: U32) => do:
        \\  let values = @list.fill count (1, 2, 3, 4, 5, 6, 7, 8, 9)
        \\  let cursor = @list.cursor values
        \\  let total = 0
        \\  for index in 0..count:
        \\    let (a, b, c, d, e, f, g, h, i) = @cursor.value cursor
        \\    total := self + a + b + c + d + e + f + g + h + i
        \\    cursor := @cursor.advance self
        \\  return total
    );
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    var vectors: usize = 0;
    for (first.capture.?.optimized.?.entries.items) |entry| {
        if (entry.output) |body| for (body.instructions.items) |inst| {
            if (inst.op == .v128_load) vectors += 1;
        };
    }
    try std.testing.expectEqual(@as(usize, 2), vectors);
    try privateCursorEmission(a, &units, &first.capture.?, first.bytes);
    var replay = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .artifact_replay = true });
    defer replay.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, replay.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, null, first.bytes });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, &first.capture.?, first.bytes });
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}
