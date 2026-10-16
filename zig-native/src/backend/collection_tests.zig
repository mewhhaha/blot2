const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const ownership = @import("owned_arrays.zig");
const wasm = @import("wasm.zig");

fn lower(a: std.mem.Allocator, source: []const u8) !core.Module {
    return lowerWithCatalog(a, source, false);
}
fn lowerWithCatalog(a: std.mem.Allocator, source: []const u8, builtin_catalog: bool) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = blk: {
        if (builtin_catalog) break :blk try check.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true, .prelude_unit = 1 });
        break :blk try check.check(a, &tree, &names);
    };
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, frontendFailures, .{});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, runtimeFailures, .{});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
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
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    try packedEmissionFailures(a, &units);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
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
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    try packedEmissionFailures(a, &units);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
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
        const before = @import("../check/core_snapshot_tests.zig").stamp(module);
        const units = [_]core.Module{module};
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
        try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
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
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
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
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
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
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
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
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

fn privateCursorEmission(a: std.mem.Allocator, units: []const core.Module, previous: ?*const @import("../reuse/artifact_capture.zig").Capture, expected: []const u8) !void {
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, &first.capture.?, first.bytes });
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
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, privateCursorEmission, .{ &units, &first.capture.?, first.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

fn literalEmission(a: std.mem.Allocator, units: []const core.Module) !void {
    var result = try @import("core_backend.zig").compileWithOptions(a, units, 1, .{ .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    const marker = std.mem.findLast(u8, result.bytes, "blot:ownership").? + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, result.bytes[marker..][0..3]);
}
test "checked List literal publications retain exact leaf roles under every emission failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (value: U32) => do:
        \\  let child = #[value, @u32.add value 1]
        \\  let rows = [child, child]
        \\  let copied = @array.from_list rows
        \\  return @array.get (@array.get copied 1) 0
        \\entry const floating = fn (value: F32) => @array.from_list [value, -0.0]
    );
    defer module.deinit(a);
    const units = [_]core.Module{module};
    try literalEmission(a, &units);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, literalEmission, .{&units});
}

fn bottomEmission(a: std.mem.Allocator, units: []const core.Module, previous: ?*const @import("../reuse/artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try @import("core_backend.zig").compileWithOptions(a, units, 1, .{ .previous = previous, .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    const marker = std.mem.findLast(u8, result.bytes, "blot:ownership").? + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, result.bytes[marker..][0..3]);
}
test "bottom completion representations preserve cancellation fresh retained replay and OOM ownership" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\type Outer is effect = { check: U32 -> U32 }
        \\type Inner is effect = { read: Unit -> U32 }
        \\const make = fn action => @computation action
        \\const inner = fn computation => do:
        \\  for request in @requests computation:
        \\    case request of
        \\      effect Inner.read () =>
        \\        use value <- Outer.check 0
        \\        yield value
        \\      complete value =>
        \\        return value
        \\const outer = fn computation => do:
        \\  for request in @requests computation:
        \\    case request of
        \\      effect Outer.check value =>
        \\        return 42
        \\      complete value =>
        \\        return value
        \\entry const answer = fn () => outer (@computation (fn () => do:
        \\  use inner (make (fn () => do:
        \\    use Inner.read ()
        \\    return @panic "cancelled inner suffix"
        \\  ))
        \\  return @panic "cancelled outer suffix"
        \\))
    );
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try bottomEmission(a, &units, null, first.bytes);
    try bottomEmission(a, &units, &first.capture.?, first.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, bottomEmission, .{ &units, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, bottomEmission, .{ &units, &first.capture.?, first.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}
test "bottom result proof declines normal returns outward branch and loop control" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const trapped = fn () => @panic "trap"
        \\const bottom = fn () => do:
        \\  let value = 7
        \\  return trapped ()
        \\const ordinary = fn (flag: Bool) => do:
        \\  if flag:
        \\    return 7
        \\  return @panic "suffix"
        \\const looping = fn () => do:
        \\  for i in 0..1:
        \\    return 7
        \\  return @panic "suffix"
        \\entry const answer = fn (flag: Bool) => ordinary flag
    );
    defer module.deinit(a);
    const proof = @import("bottom_result.zig");
    try std.testing.expect(proof.proves(&.{module}, 1, module.bodies[1].root));
    try std.testing.expect(proof.proves(&.{module}, 1, module.bodies[2].root));
    try std.testing.expect(!proof.proves(&.{module}, 1, module.bodies[3].root));
    try std.testing.expect(!proof.proves(&.{module}, 1, module.bodies[4].root));
    try std.testing.expect(!proof.proves(&.{module}, 1, module.bodies[5].root));
    try std.testing.expect(!proof.proves(&.{module}, 0, 1));
}

fn collectionIterationEmission(a: std.mem.Allocator, units: []const core.Module, previous: ?*const @import("../reuse/artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try @import("core_backend.zig").compileWithOptions(a, units, 1, .{ .previous = previous, .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}
test "resolved collection iteration preserves frozen Core retained replay and complete OOM ownership" {
    const a = std.testing.allocator;
    var module = try lowerWithCatalog(a,
        \\data Maybe a = #Some a | #Nothing
        \\const List.iter = fn (values: List a) => @list.cursor values
        \\const Cursor.next = fn (cursor: Cursor collection) =>
        \\  if @cursor.has cursor
        \\  then #Some (@cursor.value cursor, @cursor.advance cursor)
        \\  else #Nothing
        \\const fold = fn reduce => fn initial => fn values => do:
        \\  let state = initial
        \\  for value in values:
        \\    use next <- reduce state value
        \\    state := next
        \\  return state
        \\entry const run = fn (count: U32) => fold (fn left => fn right => @u32.add left right) 0 (@list.generate count (fn index => index))
    , true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try collectionIterationEmission(a, &units, null, first.bytes);
    try collectionIterationEmission(a, &units, &first.capture.?, first.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, &first.capture.?, first.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "empty ordinary cursor producer preserves partial layout Core replay and complete OOM" {
    const a = std.testing.allocator;
    var module = try lowerWithCatalog(a,
        \\data Maybe a = #Some a | #Nothing
        \\const List.iter = fn (values: List a) => @list.cursor values
        \\const Array.iter = fn (values: Array a) => @array.cursor values
        \\const Cursor.next = fn (cursor: Cursor collection) =>
        \\  if @cursor.has cursor
        \\  then #Some (@cursor.value cursor, @cursor.advance cursor)
        \\  else #Nothing
        \\entry const list = fn () => case [].iter.next of
        \\  #Nothing => 42
        \\  #Some (_, _) => 0
        \\entry const array = fn () => case #[].iter.next of
        \\  #Nothing => 42
        \\  #Some (_, _) => 0
    , true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try collectionIterationEmission(a, &units, null, first.bytes);
    try collectionIterationEmission(a, &units, &first.capture.?, first.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, &first.capture.?, first.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "leaf List traversal keeps reference carries outside its private root scope through emission failures" {
    const a = std.testing.allocator;
    var module = try lowerWithCatalog(a,
        \\data Maybe a = #Some a | #Nothing
        \\const List.iter = fn (values: List a) => @list.cursor values
        \\const Cursor.next = fn (cursor: Cursor collection) =>
        \\  if @cursor.has cursor
        \\  then #Some (@cursor.value cursor, @cursor.advance cursor)
        \\  else #Nothing
        \\entry const run = fn (count: U32) => do:
        \\  let values = @list.generate count (fn index => index)
        \\  let carried = @array.fill 1 count
        \\  for value in values:
        \\    carried := @array.fill 1 value
        \\  return @array.get carried 0
    , true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try collectionIterationEmission(a, &units, &first.capture.?, first.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, first.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "chunk scalar publications retain complete ownership through static chains" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const frozen = @list.generate 513 (fn index => index)
        \\const first = fn values => (@array.from_list values)[0]
        \\const read = fn (seed: U32) => do:
        \\  let values = @array.from_list [seed, ...[2, 3], 4]
        \\  values[1] := (@array.from_list frozen)[512]
        \\  let array = @array.from_list [value | value <- values, @u32.lt 0 value]
        \\  return first (@list.from_array array)
        \\entry const answer = fn () => @u32.add (read 40) 2
    );
    defer module.deinit(a);
    var result = try @import("core_backend.zig").compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?@import("core_backend.zig").Diagnostic, null), result.diagnostic);
}

test "checked scalar builder publications preserve Core replay and every emission allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (value: U32) => @array.from_list [@u32.add value index | index <- #[1, 2]]
    );
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try collectionIterationEmission(a, &units, &first.capture.?, first.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, first.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

const immediateStepSource =
    \\data Maybe a = #Some a | #Nothing
    \\const Cursor.next = fn (cursor: Cursor collection) =>
    \\  if @cursor.has cursor
    \\  then #Some (@cursor.value cursor, @cursor.advance cursor)
    \\  else #Nothing
    \\entry const run = fn (values: Array U32) => do:
    \\  use step <- (@array.cursor values).next
    \\  let #Some (value, rest) = step else:
    \\    return 0
    \\  return @u32.add value (@u32.add (@cursor.value rest) (@cursor.value (@array.cursor values)))
;

test "immediate collection step requires exact producer constructor and a single adjacent sink" {
    const a = std.testing.allocator;
    const proof = @import("collection_iteration.zig");
    var module = try lowerWithCatalog(a, immediateStepSource, true);
    defer module.deinit(a);
    var step: core.Id = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .bind and proof.stepSink(&module, @intCast(id)) != null) {
        try std.testing.expectEqual(@as(core.Id, 0), step);
        step = @intCast(id);
    };
    try std.testing.expect(step != 0);
    const sink = proof.stepSink(&module, step).?;
    const producer = &module.bodies[1];
    try std.testing.expect(proof.cursorNext(&module, producer.binding, &module, sink.constructor));
    const root = module.node(producer.root);
    const before = module.nodes[root.a];
    module.nodes[root.a].c = @backingInt(core.ArrayOp.cursor_value);
    try std.testing.expect(!proof.cursorNext(&module, producer.binding, &module, sink.constructor));
    module.nodes[root.a] = before;
    try std.testing.expect(!proof.cursorNext(&module, producer.binding, &module, module.node(root.c).a));
    const some = module.nodes[root.b];
    module.nodes[root.b].a = module.node(root.c).a;
    try std.testing.expect(!proof.cursorNext(&module, producer.binding, &module, sink.constructor));
    module.nodes[root.b] = some;
    try std.testing.expect(proof.cursorNext(&module, producer.binding, &module, sink.constructor));
    const pattern = module.nodes[sink.pattern];
    module.nodes[sink.pattern].tag = .bind;
    try std.testing.expect(proof.stepSink(&module, step) == null);
    module.nodes[sink.pattern] = pattern;
    for ([_][]const u8{
        "  let #Some (again, _) = step else:\n    return 0\n  return again\n",
        "  let read = fn () => step\n  let #Some (again, _) = read () else:\n    return 0\n  return again\n",
    }) |tail| {
        const text = try std.mem.concat(a, u8, &.{ immediateStepSource[0..std.mem.find(u8, immediateStepSource, "  return @u32.add").?], tail });
        defer a.free(text);
        var retained = try lowerWithCatalog(a, text, true);
        defer retained.deinit(a);
        for (retained.nodes, 0..) |node, id| if (node.tag == .bind) {
            try std.testing.expect(proof.stepSink(&retained, @intCast(id)) == null);
        };
    }
}

test "immediate collection step emits original cursor operations without transient result cells" {
    const a = std.testing.allocator;
    var module = try lowerWithCatalog(a, immediateStepSource, true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var result = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    var allocations: usize = 0;
    var advances: usize = 0;
    for (result.capture.?.emission.records.items) |record| if (record.event == .semantic_site and record.event.semantic_site.kind == .allocation) {
        const site = record.event.semantic_site;
        try std.testing.expectEqual(@as(u32, 1), site.unit);
        const node = module.node(site.node);
        try std.testing.expect(node.tag != .product and node.tag != .construct);
        allocations += 1;
        if (node.tag == .array_op and module.arrayOperation(site.node) == .cursor_advance) advances += 1;
    };
    try std.testing.expect(allocations > 0);
    try std.testing.expectEqual(@as(usize, 1), advances);
    try collectionIterationEmission(a, &units, &result.capture.?, result.bytes);
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "immediate collection step releases every emission allocation failure" {
    const a = std.testing.allocator;
    var module = try lowerWithCatalog(a, immediateStepSource, true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var result = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, result.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

const localCursorSource =
    \\data Maybe a = #Some a | #Nothing
    \\const Cursor.next = fn (cursor: Cursor collection) =>
    \\  if @cursor.has cursor
    \\  then #Some (@cursor.value cursor, @cursor.advance cursor)
    \\  else #Nothing
    \\const progress = fn (values: Array U32) => do:
    \\  let original = @array.cursor values
    \\  let cursor = original
    \\  let total = 0
    \\  for ever:
    \\    if @u32.lt 10000 total:
    \\      break
    \\    use step <- cursor.next
    \\    let #Some (value, rest) = step else:
    \\      break
    \\    total := @u32.add self value
    \\    cursor := rest
    \\  return cursor
    \\entry const run = fn (values: Array U32) => @cursor.has (progress values)
;
fn localCursorStep(module: *const core.Module) !@import("private_cursor.zig").Step {
    const proof = @import("collection_iteration.zig");
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .bind) continue;
        const sink = proof.stepSink(module, @intCast(id)) orelse continue;
        const initializer = module.node(node.b);
        try std.testing.expectEqual(core.Tag.project, initializer.tag);
        const input = module.reference(initializer.a);
        const pattern = module.node(sink.pattern);
        const fields = module.patternChildren(module.pattern(pattern.a).b);
        return .{ .node = node.b, .pattern = sink.pattern, .input = input.binding, .rest = module.pattern(fields[1]).a };
    }
    return error.TestExpectedEqual;
}
test "private cursor successors require a closed lexical family and reject calls captures and merges" {
    const a = std.testing.allocator;
    const proof = @import("private_cursor.zig");
    var module = try lowerWithCatalog(a, localCursorSource, true);
    defer module.deinit(a);
    const step = try localCursorStep(&module);
    const root = module.bodies[2].root;
    try std.testing.expect(!proof.check(&module, root, step.input));
    const family = proof.checkSteps(&module, root, step.input, &.{step}).?;
    try std.testing.expect(std.mem.findScalar(core.BindingId, family.bindings[0..family.len], step.rest) != null);
    const position = std.mem.find(u8, localCursorSource, "  return cursor").?;
    for ([_][]const u8{
        "  let read = fn () => @cursor.has cursor\n  return cursor\n",
        "  let read = fn cursor => @cursor.has cursor\n  use ignored <- read cursor\n  return cursor\n",
        "  if @cursor.has cursor:\n    cursor := @array.cursor values\n  return cursor\n",
    }) |tail| {
        const text = try std.mem.concat(a, u8, &.{ localCursorSource[0..position], tail });
        defer a.free(text);
        var changed = try lowerWithCatalog(a, text, true);
        defer changed.deinit(a);
        const selected = try localCursorStep(&changed);
        try std.testing.expect(proof.checkSteps(&changed, changed.bodies[2].root, selected.input, &.{selected}) == null);
    }
}
test "private cursor successors publish only the returned immutable header and preserve replay" {
    const a = std.testing.allocator;
    var module = try lowerWithCatalog(a, localCursorSource, true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var result = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    var headers: usize = 0;
    for (result.capture.?.emission.records.items) |record| if (record.event == .semantic_site and record.event.semantic_site.kind == .allocation) {
        const node = module.node(record.event.semantic_site.node);
        try std.testing.expect(node.tag != .product and node.tag != .construct);
        if (node.tag == .array_op) try std.testing.expect(module.arrayOperation(record.event.semantic_site.node) != .cursor and module.arrayOperation(record.event.semantic_site.node) != .cursor_advance);
        if (node.tag == .reference) headers += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), headers);
    try collectionIterationEmission(a, &units, &result.capture.?, result.bytes);
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}
test "private cursor successors release all family and materialization allocations through complete OOM" {
    const a = std.testing.allocator;
    var module = try lowerWithCatalog(a, localCursorSource, true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var result = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, result.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "finite cursor carry owners cover duplicate row publications and preserve replay" {
    const a = std.testing.allocator;
    const text = try std.mem.replaceOwned(u8, a, localCursorSource, "  return cursor\nentry const run = fn (values: Array U32) => @cursor.has (progress values)", "  return total\nentry const run = fn (values: Array U32) => progress values");
    defer a.free(text);
    const finite = try std.mem.replaceOwned(u8, a, text, "for ever:", "for unused in values:");
    defer a.free(finite);
    var module = try lowerWithCatalog(a, finite, true);
    defer module.deinit(a);
    const units = [_]core.Module{module};
    var result = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    var dummy = wasm.Module.init(a);
    defer dummy.deinit();
    var removed: usize = 0;
    for (result.capture.?.optimized.?.entries.items) |*entry| {
        if (try @import("root_borrows.zig").run(a, &dummy, &entry.source)) |body| {
            var owned = body;
            defer owned.deinit(a);
            const difference = entry.source.instructions.items.len - body.instructions.items.len;
            removed += difference;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), removed);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, result.bytes });
}

test "persistent List snapshots lazily freeze the descriptor and preserve complete replay through OOM" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (seed: U32) => do:
        \\  let values = [seed, @u32.add seed 1, @u32.add seed 2]
        \\  let left = @list.cursor values
        \\  let right = @list.cursor values
        \\  return @u32.add (@cursor.value left) (@cursor.value (@cursor.advance right))
    );
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    const units = [_]core.Module{module};
    var first = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    const runtime = first.capture.?.emission.lists.?;
    const snapshot = runtime.snapshot.?;
    try std.testing.expectEqual(@import("../reuse/artifact_emitter.zig").FunctionRole.list_snapshot, first.capture.?.emission.functions[snapshot].role);
    try collectionIterationEmission(a, &units, null, first.bytes);
    try collectionIterationEmission(a, &units, &first.capture.?, first.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, first.bytes });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, &first.capture.?, first.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}

test "direct collection patterns eliminate transient cells with immutable Core replay and complete OOM" {
    const a = std.testing.allocator;
    const text = try std.mem.replaceOwned(u8, a, immediateStepSource, "  use step <- (@array.cursor values).next\n  let #Some (value, rest) = step", "  let #Some (value, rest) = (@array.cursor values).next");
    defer a.free(text);
    var module = try lowerWithCatalog(a, text, true);
    defer module.deinit(a);
    const before = @import("../check/core_snapshot_tests.zig").stamp(module);
    var direct: usize = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .pattern_bind) {
        if (@import("collection_iteration.zig").stepSink(&module, @intCast(id))) |_| direct += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), direct);
    const units = [_]core.Module{module};
    var result = try @import("core_backend.zig").compileWithOptions(a, &units, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    var advances: usize = 0;
    for (result.capture.?.emission.records.items) |record| if (record.event == .semantic_site and record.event.semantic_site.kind == .allocation) {
        const site = record.event.semantic_site;
        const node = module.node(site.node);
        try std.testing.expect(node.tag != .product and node.tag != .construct);
        if (node.tag == .array_op and module.arrayOperation(site.node) == .cursor_advance) advances += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), advances);
    try collectionIterationEmission(a, &units, &result.capture.?, result.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, collectionIterationEmission, .{ &units, null, result.bytes });
    try std.testing.expectEqual(before, @import("../check/core_snapshot_tests.zig").stamp(module));
}
